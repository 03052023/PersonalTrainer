import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Contrato V2-FINAL §2.3: `CoachService` sobre doubles de `SessionPlanning` e
/// `ProgramRepositoring`, `FakeCoachLogStore`, `FakeNotificationScheduler`, relógio controlado e
/// `UserDefaults` descartável. Cobre a montagem do `CoachInput` (C1 com `since` estável, C2 com a
/// revisão guardada, C4, C5, C6, C7, C8), os efeitos de cada resposta, o destaque na abertura e o
/// aviso da véspera (permissão só por ação da pessoa, AGENTS §7).
@MainActor
final class CoachServiceTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -3 * 3_600)!
        return calendar
    }()

    /// Quinta-feira, 24/09/2026, 12:00 em UTC−3 (semana ISO 2026-W39).
    private var now: Date { date(2026, 9, 24) }

    // MARK: - Feed vazio e C4 / destaque

    func testRefresh_withoutAnyData_hasNoMessagesAndNoHighlight() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        XCTAssertEqual(fixture.service.messages, [])
        XCTAssertNil(fixture.service.highlight)
        XCTAssertNil(fixture.service.errorMessage)
    }

    func testRefresh_expiryInTwoDays_showsC4AsHighlight() throws {
        let expiry = date(2026, 9, 26, hour: 21)
        let fixture = try makeFixture(expiry: expiry)
        defer { fixture.cleanUp() }

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        XCTAssertEqual(fixture.service.provisioningExpiry, expiry)
        let message = try XCTUnwrap(fixture.service.messages.first)
        XCTAssertEqual(message.rule, .installExpiry)
        XCTAssertEqual(fixture.service.highlight?.id, message.id, "C4 destaca na abertura")
    }

    func testHighlight_eachMessageIsHighlightedOnlyOnce() throws {
        let fixture = try makeFixture(expiry: date(2026, 9, 26, hour: 21))
        defer { fixture.cleanUp() }

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let highlighted = try XCTUnwrap(fixture.service.highlight)
        fixture.service.dismissHighlight()
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        XCTAssertNil(fixture.service.highlight, "Fechar sem responder não reabre a folha a cada refresh")
        XCTAssertTrue(fixture.service.messages.contains { $0.id == highlighted.id }, "A mensagem continua no feed")
    }

    func testHandle_onHighlight_defersNavigationUntilSheetCloses() throws {
        let fixture = try makeFixture(expiry: date(2026, 9, 26, hour: 21))
        defer { fixture.cleanUp() }
        var renewalRequests = 0
        fixture.service.onRenewalHelpRequested = { renewalRequests += 1 }

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.highlight)
        fixture.service.handle(.howToRenew, on: message)

        XCTAssertNil(fixture.service.highlight, "Responder fecha o destaque")
        XCTAssertEqual(renewalRequests, 0, "Duas folhas ao mesmo tempo não abrem: espera o destaque fechar")
        fixture.service.highlightDidDismiss()
        XCTAssertEqual(renewalRequests, 1)
        XCTAssertFalse(fixture.service.messages.contains { $0.id == message.id })
        XCTAssertEqual(fixture.logStore.log.entries.last?.action, .howToRenew)
        XCTAssertEqual(fixture.logStore.log.entries.last?.messageID, message.id)
    }

    // MARK: - C7 Backup

    func testHandle_backupNow_outsideHighlight_navigatesAtOnce() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.sessionsToReturn = recentSessions(count: 5)
        var backupRequests = 0
        fixture.service.onBackupRequested = { backupRequests += 1 }

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .backup })
        XCTAssertNil(fixture.service.highlight, "C7 não destaca na abertura")
        fixture.service.handle(.backupNow, on: message)

        XCTAssertEqual(backupRequests, 1)
        XCTAssertFalse(fixture.service.messages.contains { $0.rule == .backup })
    }

    func testRefresh_readsLastBackupAtFromDefaults() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.sessionsToReturn = recentSessions(count: 5)

        fixture.defaults.set(date(2026, 9, 23).timeIntervalSince1970, forKey: CoachService.DefaultsKey.lastBackupAt)
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        XCTAssertFalse(fixture.service.messages.contains { $0.rule == .backup }, "Backup de ontem: nada a lembrar")

        fixture.defaults.set(date(2026, 9, 1).timeIntervalSince1970, forKey: CoachService.DefaultsKey.lastBackupAt)
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        XCTAssertTrue(fixture.service.messages.contains { $0.rule == .backup }, "Backup de 23 dias atrás: lembrete")
    }

    // MARK: - C1 Semana leve

    func testRefresh_pendingDeload_keepsSinceStableUntilItEnds() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.deloadStatusToReturn = .pending(trigger: .scheduled)

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .deload })
        XCTAssertEqual(message.id, "deload:2026-09-24")
        XCTAssertEqual(
            fixture.defaults.double(forKey: CoachService.DefaultsKey.pendingDeloadSince),
            now.timeIntervalSince1970
        )

        fixture.service.handle(.ok, on: message)
        fixture.clock.now = date(2026, 9, 26)
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        XCTAssertFalse(
            fixture.service.messages.contains { $0.rule == .deload },
            "Com o since estável, a mensagem respondida não volta nos dias seguintes"
        )

        fixture.planner.deloadStatusToReturn = .active(start: date(2026, 9, 26, hour: 8))
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        XCTAssertNil(fixture.defaults.object(forKey: CoachService.DefaultsKey.pendingDeloadSince))
    }

    func testRefresh_pendingThatBecomesManual_startsANewPeriod() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.deloadStatusToReturn = .pending(trigger: .manyDecreases)
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        fixture.clock.now = date(2026, 9, 25)
        fixture.planner.deloadStatusToReturn = .pending(trigger: .manual)
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .deload })
        XCTAssertEqual(message.id, "deload:2026-09-25", "Contrato: no manual, since = instante do pedido")
        XCTAssertEqual(message.itemKey, DeloadTrigger.manual.rawValue)
    }

    func testRefresh_sinceFromAnEarlierLightWeek_isReplaced() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(date(2026, 8, 1).timeIntervalSince1970, forKey: CoachService.DefaultsKey.pendingDeloadSince)
        fixture.defaults.set(DeloadTrigger.scheduled.rawValue, forKey: CoachService.DefaultsKey.pendingDeloadTrigger)
        fixture.planner.sessionsToReturn = [
            session(startedAt: date(2026, 8, 3), isDeload: true),
            session(startedAt: date(2026, 9, 22)),
        ]
        fixture.planner.deloadStatusToReturn = .pending(trigger: .scheduled)

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .deload })
        XCTAssertEqual(message.id, "deload:2026-09-24", "Uma sessão de deload depois do since mostra que ele era de outra semana leve")
    }

    func testHandle_keepNormal_dismissesDeloadAndForgetsSince() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.deloadStatusToReturn = .pending(trigger: .scheduled)
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .deload })

        fixture.planner.deloadStatusToReturn = .inactive
        fixture.service.handle(.keepNormal, on: message)

        XCTAssertEqual(fixture.planner.dismissDeloadCalls, [now])
        XCTAssertNil(fixture.defaults.object(forKey: CoachService.DefaultsKey.pendingDeloadSince))
        XCTAssertEqual(fixture.logStore.log.entries.map(\.action), [.keepNormal])
        XCTAssertFalse(fixture.service.messages.contains { $0.rule == .deload })
    }

    func testHandle_logSaveFailure_hidesMessageAndExplains() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.deloadStatusToReturn = .pending(trigger: .scheduled)
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .deload })
        fixture.logStore.saveError = CoachTestError.disk

        fixture.service.handle(.ok, on: message)

        XCTAssertNotNil(fixture.service.errorMessage)
        XCTAssertFalse(fixture.service.messages.contains { $0.id == message.id })
    }

    // MARK: - C2 Revisão periódica

    func testRefresh_reviewDue_runsReviewAndKeepsItUntilTheNext() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let firstSession = date(2026, 7, 20)
        fixture.planner.sessionsToReturn = [session(startedAt: firstSession)]
        fixture.planner.reviewInputToReturn = ReviewInput(
            programID: UUID(),
            programName: "Completo",
            programDayCount: 1,
            programStartDate: firstSession,
            exercises: [],
            sessions: [],
            weeklySetTarget: 10...20,
            currentPrescriptions: []
        )

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        XCTAssertEqual(fixture.logStore.reviewSaveCount, 1)
        XCTAssertEqual(fixture.logStore.log.lastReviewAt, now)
        XCTAssertEqual(fixture.logStore.lastReview?.generatedAt, now)
        let message = try XCTUnwrap(
            fixture.service.messages.first { $0.rule == .review && ($0.suggestionID?.hasPrefix("switchProgram:") ?? false) },
            "Programa há 9 semanas: sugestão de troca (C2)"
        )

        fixture.clock.now = date(2026, 9, 25)
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        XCTAssertEqual(fixture.logStore.reviewSaveCount, 1, "A próxima revisão só daqui a 4 semanas")
        XCTAssertTrue(fixture.service.messages.contains { $0.id == message.id }, "O relatório guardado continua no feed")
    }

    func testHandle_applySwitchProgram_activatesTheNextProgramWithTheSameGoal() throws {
        let suggestion = ProgramSuggestion(
            id: "switchProgram:old:2026-W39",
            kind: .switchProgram,
            rule: "R5",
            title: "Experimentar um novo programa",
            reason: "Você treina com o programa Completo há 9 semanas.",
            strength: .optional,
            referenceTopic: "topic.substitution"
        )
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        let other = program(name: "Foco superior", goal: .hypertrophy)
        fixture.programs.programs = [
            program(name: "Completo", goal: .hypertrophy, isActive: true),
            program(name: "Força 3 dias", goal: .strength),
            other,
        ]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        XCTAssertTrue(fixture.service.applySummary(for: message)?.contains("Foco superior") ?? false)
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(fixture.programs.activated, [other.id])
        XCTAssertEqual(fixture.logStore.log.entries.map(\.action), [.apply])
        XCTAssertFalse(fixture.service.messages.contains { $0.id == message.id })
    }

    func testHandle_applySwitchProgram_withoutAnotherProgram_asksThePersonToChoose() throws {
        let suggestion = ProgramSuggestion(
            id: "switchProgram:old:2026-W39",
            kind: .switchProgram,
            rule: "R5",
            title: "Experimentar um novo programa",
            reason: "Você treina com o programa Completo há 9 semanas.",
            strength: .optional,
            referenceTopic: "topic.substitution"
        )
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        fixture.programs.programs = [program(name: "Completo", goal: .hypertrophy, isActive: true)]
        var chooseRequests = 0
        fixture.service.onChooseProgramRequested = { chooseRequests += 1 }

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        fixture.service.dismissHighlight()
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(fixture.programs.activated, [])
        XCTAssertEqual(chooseRequests, 1)
    }

    func testHandle_applyAddSets_updatesTargetsKeepingTheirOtherFields() throws {
        let target = ExerciseTarget(exerciseID: UUID(), order: 0, sets: 3, repMin: 8, repMax: 12, targetRIR: 2, restSeconds: 90, startingLoad: 20)
        let suggestion = ProgramSuggestion(
            id: "addSets:chest:\(target.id.uuidString):2026-W39",
            kind: .addSets,
            rule: "R3",
            title: "Mais séries para o peito",
            reason: "O peito teve 8 séries por semana.",
            targetIDs: [target.id],
            muscle: .chest,
            proposedSets: 4,
            referenceTopic: "topic.volume"
        )
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        fixture.programs.programs = [program(name: "Completo", goal: .hypertrophy, isActive: true, targets: [target])]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(
            fixture.programs.updates,
            [CoachTargetUpdate(id: target.id, sets: 4, repMin: 8, repMax: 12, targetRIR: 2, restSeconds: 90, startingLoad: 20)]
        )
        XCTAssertNil(fixture.service.errorMessage)
        XCTAssertEqual(fixture.logStore.log.entries.map(\.action), [.apply])
    }

    func testHandle_applyChangeRepRange_keepsSetsAndRest() throws {
        let target = ExerciseTarget(exerciseID: UUID(), order: 0, sets: 3, repMin: 8, repMax: 12, targetRIR: 1, restSeconds: 120)
        let suggestion = ProgramSuggestion(
            id: "changeRepRange:\(target.id.uuidString):2026-W39",
            kind: .changeRepRange,
            rule: "R5",
            title: "Trocar a faixa de repetições",
            reason: "Sem progresso nas últimas 3 sessões.",
            targetIDs: [target.id],
            proposedRepRange: 6...10,
            referenceTopic: "topic.substitution"
        )
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        fixture.programs.programs = [program(name: "Completo", goal: .hypertrophy, isActive: true, targets: [target])]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(
            fixture.programs.updates,
            [CoachTargetUpdate(id: target.id, sets: 3, repMin: 6, repMax: 10, targetRIR: 1, restSeconds: 120, startingLoad: nil)]
        )
    }

    func testHandle_applySwapExercise_usesTheFirstSubstitute() throws {
        let original = exercise(name: "Supino reto")
        let target = ExerciseTarget(exerciseID: original.id, order: 0)
        let suggestion = swapSuggestion(targetID: target.id)
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        fixture.programs.programs = [program(name: "Completo", goal: .hypertrophy, isActive: true, targets: [target])]
        let first = exercise(name: "Supino com halteres")
        fixture.planner.substitutesToReturn = [first, exercise(name: "Flexão")]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(fixture.programs.replacements.map { $0.targetID }, [target.id])
        XCTAssertEqual(fixture.programs.replacements.map { $0.exerciseID }, [first.id])
        XCTAssertEqual(fixture.planner.substitutesCalls.last, original.id)
    }

    func testHandle_applySwapWithoutSubstitute_changesNothingAndExplains() throws {
        let target = ExerciseTarget(exerciseID: UUID(), order: 0)
        let suggestion = swapSuggestion(targetID: target.id)
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        fixture.programs.programs = [program(name: "Completo", goal: .hypertrophy, isActive: true, targets: [target])]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(fixture.service.errorMessage, CoachService.errorText(for: CoachServiceError.noSubstitute))
        XCTAssertTrue(fixture.programs.replacements.isEmpty)
        XCTAssertTrue(fixture.logStore.log.entries.isEmpty, "Sem efeito, a resposta não vai para o log")
        XCTAssertTrue(fixture.service.messages.contains { $0.id == message.id }, "A mensagem fica para outra resposta")
    }

    func testHandle_applyToATargetNoLongerInTheProgram_changesNothing() throws {
        let suggestion = ProgramSuggestion(
            id: "removeSets:back:gone:2026-W39",
            kind: .removeSets,
            rule: "R3",
            title: "Menos séries para as costas",
            reason: "As costas tiveram 24 séries por semana.",
            targetIDs: [UUID()],
            muscle: .back,
            proposedSets: 2,
            referenceTopic: "topic.volume"
        )
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        fixture.programs.programs = [program(name: "Completo", goal: .hypertrophy, isActive: true)]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(fixture.service.errorMessage, CoachService.errorText(for: CoachServiceError.suggestionOutdated))
        XCTAssertTrue(fixture.programs.updates.isEmpty)
        XCTAssertTrue(fixture.logStore.log.entries.isEmpty)
    }

    func testHandle_applyUpdateFailure_keepsTheMessage() throws {
        let target = ExerciseTarget(exerciseID: UUID(), order: 0)
        let suggestion = ProgramSuggestion(
            id: "addSets:chest:\(target.id.uuidString):2026-W39",
            kind: .addSets,
            rule: "R3",
            title: "Mais séries para o peito",
            reason: "O peito teve 8 séries por semana.",
            targetIDs: [target.id],
            proposedSets: 4,
            referenceTopic: "topic.volume"
        )
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        fixture.programs.programs = [program(name: "Completo", goal: .hypertrophy, isActive: true, targets: [target])]
        fixture.programs.updateError = CoachTestError.disk

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        fixture.service.handle(.apply, on: message)

        XCTAssertNotNil(fixture.service.errorMessage)
        XCTAssertTrue(fixture.logStore.log.entries.isEmpty)
        XCTAssertTrue(fixture.service.messages.contains { $0.id == message.id })
    }

    func testHandle_applyDeloadSuggestion_requestsALightWeek() throws {
        let suggestion = ProgramSuggestion(
            id: "deload:2026-W39",
            kind: .deload,
            rule: "R2",
            title: "Semana mais leve",
            reason: "Sinais de fadiga nas últimas 2 semanas.",
            referenceTopic: "rule.D"
        )
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        fixture.planner.deloadStatusToReturn = .pending(trigger: .manual)
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(fixture.planner.requestDeloadCalls, [now])
        XCTAssertEqual(
            fixture.defaults.string(forKey: CoachService.DefaultsKey.pendingDeloadTrigger),
            DeloadTrigger.manual.rawValue
        )
        XCTAssertEqual(fixture.service.messages.first { $0.rule == .deload }?.id, "deload:2026-09-24")
    }

    // MARK: - C3 Saúde

    func testRefresh_healthSuggestions_becomeMessagesAndRespectRemindTomorrow() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let suggestion = HealthSuggestion(
            id: "wear-watch-at-night",
            kind: .wearWatchAtNight,
            title: "Use o Apple Watch para dormir",
            detail: "Sem dados de sono em 6 das últimas 7 noites.",
            referenceTopic: "topic.hrv"
        )

        fixture.service.refresh(healthSuggestions: [suggestion], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .health })
        fixture.service.handle(.remindTomorrow, on: message)
        XCTAssertFalse(fixture.service.messages.contains { $0.rule == .health })

        fixture.clock.now = date(2026, 9, 25)
        fixture.service.refresh(healthSuggestions: [suggestion], recovery: .unknown)
        XCTAssertTrue(fixture.service.messages.contains { $0.rule == .health }, "Lembrar amanhã: volta no dia seguinte")
    }

    // MARK: - C5 Retomada

    func testRefresh_afterAWeekAway_welcomesBackWithTheNextDay() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.sessionsToReturn = [session(startedAt: date(2026, 9, 16))]
        fixture.planner.planToReturn = SessionPlan(
            programID: UUID(),
            programName: "Completo",
            programDayID: UUID(),
            programDayName: "Dia B",
            exercises: [],
            generatedAt: now
        )

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .comeback })
        XCTAssertTrue(message.reason.contains("Dia B"))
        XCTAssertEqual(fixture.planner.nextPlanCalls, [now])
    }

    func testRefresh_recentSession_doesNotComputeTheNextPlan() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.sessionsToReturn = [session(startedAt: date(2026, 9, 22))]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        XCTAssertFalse(fixture.service.messages.contains { $0.rule == .comeback })
        XCTAssertEqual(fixture.planner.nextPlanCalls, [])
    }

    func testHandle_start_callsTheStartClosure() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.sessionsToReturn = [session(startedAt: date(2026, 9, 10))]
        var startRequests = 0
        fixture.service.onStartRequested = { startRequests += 1 }

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .comeback })
        fixture.service.dismissHighlight()
        fixture.service.handle(.start, on: message)

        XCTAssertEqual(startRequests, 1)
    }

    // MARK: - C6 Melhor marca

    func testRefresh_newBestMark_ofTheLastSession_andSeeProgress() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let bench = exercise(name: "Supino reto")
        let dayID = UUID()
        let older = UUID()
        let latest = UUID()
        let olderDate = date(2026, 9, 21, hour: 8)
        let latestDate = date(2026, 9, 23, hour: 8)
        fixture.planner.sessionsToReturn = [
            session(id: older, startedAt: olderDate),
            session(id: latest, startedAt: latestDate),
        ]
        fixture.planner.reviewInputToReturn = ReviewInput(
            programID: UUID(),
            programName: "Completo",
            programDayCount: 1,
            programStartDate: olderDate,
            exercises: [
                ExerciseReviewInput(
                    exercise: bench,
                    targetID: UUID(),
                    dayID: dayID,
                    sets: 3,
                    repMin: 8,
                    repMax: 12,
                    history: [
                        ExerciseHistoryEntry(sessionID: older, date: olderDate, sets: [SetResult(load: 60, reps: 8, rir: 2, completedAt: olderDate)]),
                        ExerciseHistoryEntry(sessionID: latest, date: latestDate, sets: [SetResult(load: 65, reps: 8, rir: 2, completedAt: latestDate)]),
                    ]
                ),
            ],
            sessions: [],
            weeklySetTarget: 10...20,
            currentPrescriptions: []
        )
        var progressRequests: [UUID] = []
        fixture.service.onProgressRequested = { progressRequests.append($0) }

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .personalRecord })
        XCTAssertEqual(message.suggestionID, bench.id.uuidString)
        XCTAssertTrue(message.reason.contains("Supino reto"), "O nome vem do catálogo do programa ativo")
        fixture.service.handle(.seeProgress, on: message)

        XCTAssertEqual(progressRequests, [bench.id])
    }

    // MARK: - C8 Longevidade

    func testHandle_done_marksTheBlockForTheWeekOnly() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.goalToReturn = .longevity

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let balance = try XCTUnwrap(fixture.service.messages.first { $0.itemKey == CoachInput.balanceKey })
        XCTAssertTrue(fixture.service.messages.contains { $0.itemKey == CoachInput.mobilityKey })
        fixture.service.handle(.done, on: balance)

        XCTAssertFalse(fixture.service.messages.contains { $0.itemKey == CoachInput.balanceKey })
        XCTAssertTrue(fixture.service.messages.contains { $0.itemKey == CoachInput.mobilityKey })
        XCTAssertEqual(fixture.service.longevityMarks(in: fixture.logStore.log, now: now), [CoachInput.balanceKey])

        fixture.clock.now = date(2026, 10, 1)
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        XCTAssertTrue(
            fixture.service.messages.contains { $0.itemKey == CoachInput.balanceKey },
            "Semana nova: equilíbrio volta a ser lembrado"
        )
    }

    func testIsoWeekLabel_matchesTheCoachPeriods() {
        XCTAssertEqual(CoachService.isoWeekLabel(for: now, calendar: calendar), "2026-W39")
        XCTAssertEqual(CoachService.isoWeekLabel(for: date(2027, 1, 1), calendar: calendar), "2026-W53")
    }

    // MARK: - Aviso da véspera (C4)

    func testRefresh_neverAsksForNotificationPermission() async throws {
        let fixture = try makeFixture(expiry: date(2026, 9, 27, hour: 21))
        defer { fixture.cleanUp() }
        fixture.defaults.set(true, forKey: CoachService.DefaultsKey.expiryReminderEnabled)

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        await fixture.service.pendingWork?.value

        let requests = await fixture.notifications.authorizationRequestCount
        XCTAssertEqual(requests, 0, "AGENTS §7: nunca pedir permissão no launch")
        let pending = await fixture.notifications.pendingRequests
        XCTAssertEqual(pending.map(\.identifier), [CoachService.expiryReminderIdentifier])
    }

    func testSetExpiryReminderEnabled_asksPermissionAndSchedulesAtTenTheDayBefore() async throws {
        let expiry = date(2026, 9, 27, hour: 21)
        let fixture = try makeFixture(expiry: expiry)
        defer { fixture.cleanUp() }

        fixture.service.setExpiryReminderEnabled(true)
        await fixture.service.pendingWork?.value

        XCTAssertTrue(fixture.defaults.bool(forKey: CoachService.DefaultsKey.expiryReminderEnabled))
        XCTAssertTrue(fixture.service.isExpiryReminderEnabled)
        let requests = await fixture.notifications.authorizationRequestCount
        XCTAssertEqual(requests, 1)
        let pending = await fixture.notifications.pendingRequests
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.fireDate, date(2026, 9, 26, hour: 10))
        XCTAssertEqual(pending.first?.title, CoachService.expiryReminderTitle)
        XCTAssertTrue(pending.first?.body.contains("21:00") ?? false)
    }

    func testDisablingTheReminder_cancelsIt() async throws {
        let fixture = try makeFixture(expiry: date(2026, 9, 27, hour: 21))
        defer { fixture.cleanUp() }

        fixture.service.setExpiryReminderEnabled(true)
        fixture.service.setExpiryReminderEnabled(false)
        await fixture.service.pendingWork?.value

        let pending = await fixture.notifications.pendingRequests
        XCTAssertTrue(pending.isEmpty)
        let cancelled = await fixture.notifications.cancelledIdentifiers
        XCTAssertEqual(cancelled.last, CoachService.expiryReminderIdentifier)
    }

    func testHowToRenew_withReminderOn_asksPermissionInTheAction() async throws {
        let fixture = try makeFixture(expiry: date(2026, 9, 26, hour: 21))
        defer { fixture.cleanUp() }
        fixture.defaults.set(true, forKey: CoachService.DefaultsKey.expiryReminderEnabled)
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .installExpiry })

        fixture.service.handle(.howToRenew, on: message)
        await fixture.service.pendingWork?.value

        let requests = await fixture.notifications.authorizationRequestCount
        XCTAssertEqual(requests, 1, "SPEC §7.11 C4: a permissão é pedida na ação da mensagem")
    }

    func testHowToRenew_withReminderOff_doesNotAskPermission() async throws {
        let fixture = try makeFixture(expiry: date(2026, 9, 26, hour: 21))
        defer { fixture.cleanUp() }
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .installExpiry })

        fixture.service.handle(.howToRenew, on: message)
        await fixture.service.pendingWork?.value

        let requests = await fixture.notifications.authorizationRequestCount
        XCTAssertEqual(requests, 0)
    }

    func testDeniedPermission_explainsWhyTheReminderWillNotShow() async throws {
        let fixture = try makeFixture(expiry: date(2026, 9, 27, hour: 21), authorizationToGrant: false)
        defer { fixture.cleanUp() }

        fixture.service.setExpiryReminderEnabled(true)
        await fixture.service.pendingWork?.value

        XCTAssertNotNil(fixture.service.errorMessage)
    }

    func testReminderTimeAlreadyPast_isNotScheduled() async throws {
        let fixture = try makeFixture(expiry: date(2026, 9, 24, hour: 20))
        defer { fixture.cleanUp() }

        fixture.service.setExpiryReminderEnabled(true)
        await fixture.service.pendingWork?.value

        let scheduled = await fixture.notifications.scheduledRequests
        XCTAssertTrue(scheduled.isEmpty, "As 10h da véspera já passaram")
    }

    func testExpiryReminderDate_isTenOClockOfTheDayBefore() {
        XCTAssertEqual(
            CoachService.expiryReminderDate(expiry: date(2026, 9, 27, hour: 8, minute: 30), calendar: calendar),
            date(2026, 9, 26, hour: 10)
        )
        XCTAssertEqual(
            CoachService.expiryReminderBody(expiry: date(2026, 9, 27, hour: 8, minute: 5), calendar: calendar),
            "A instalação atual vale até amanhã às 08:05. Renove hoje pelo Impactor no computador; reinstalar por cima mantém seus dados."
        )
    }

    func testJoinedNames_readsLikeASentence() {
        XCTAssertEqual(CoachService.joinedNames([]), "")
        XCTAssertEqual(CoachService.joinedNames(["Supino"]), "Supino")
        XCTAssertEqual(CoachService.joinedNames(["Supino", "Remada"]), "Supino e Remada")
        XCTAssertEqual(CoachService.joinedNames(["Supino", "Remada", "Agachamento"]), "Supino, Remada e Agachamento")
    }

    // MARK: - Fixture

    private struct Fixture {
        let service: CoachService
        let planner: CoachTestPlanner
        let programs: CoachTestPrograms
        let logStore: FakeCoachLogStore
        let notifications: FakeNotificationScheduler
        let defaults: UserDefaults
        let suite: String
        let clock: CoachTestClock

        func cleanUp() {
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func makeFixture(
        expiry: Date? = nil,
        logStore: FakeCoachLogStore? = nil,
        authorizationToGrant: Bool = true
    ) throws -> Fixture {
        let suite = "CoachServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let planner = CoachTestPlanner()
        let programs = CoachTestPrograms()
        let store = logStore ?? FakeCoachLogStore()
        let notifications = FakeNotificationScheduler(authorizationToGrant: authorizationToGrant)
        let clock = CoachTestClock(now)
        let reader: ProvisioningExpiryReader
        if let expiry {
            let data = try Self.profileData(expiry: expiry)
            reader = ProvisioningExpiryReader(readData: { data })
        } else {
            reader = .unavailable
        }
        let service = CoachService(
            planner: planner,
            programs: programs,
            log: store,
            expiry: reader,
            notifications: notifications,
            now: { clock.now },
            calendar: calendar,
            defaults: defaults
        )
        return Fixture(
            service: service,
            planner: planner,
            programs: programs,
            logStore: store,
            notifications: notifications,
            defaults: defaults,
            suite: suite,
            clock: clock
        )
    }

    /// Um `embedded.mobileprovision` mínimo: bytes quaisquer em volta do plist XML, como o CMS.
    static func profileData(expiry: Date) throws -> Data {
        let payload: [String: Any] = ["ExpirationDate": expiry, "Name": "Magister"]
        let plist = try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
        var data = Data([0x30, 0x82, 0x0B, 0x5A, 0x06, 0x09])
        data.append(plist)
        data.append(contentsOf: [0xA0, 0x82, 0x03])
        return data
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func session(id: UUID = UUID(), startedAt: Date, isDeload: Bool = false) -> SessionSummary {
        SessionSummary(
            id: id,
            programDayID: UUID(),
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3_600),
            status: .completed,
            workingSetCount: 12,
            isDeload: isDeload
        )
    }

    /// `count` sessões concluídas nos dias anteriores a `now` (nenhuma pausa para o C5).
    private func recentSessions(count: Int) -> [SessionSummary] {
        (1...count).map { offset in
            session(startedAt: now.addingTimeInterval(-Double(offset) * 86_400))
        }
    }

    private func storeWithReview(_ suggestions: [ProgramSuggestion]) -> FakeCoachLogStore {
        let report = ReviewReport(
            generatedAt: now,
            stagnantExerciseIDs: [],
            fatigueHigh: false,
            weeklySetsByMuscle: [:],
            adherence: nil,
            suggestions: suggestions
        )
        return FakeCoachLogStore(log: CoachLog(lastReviewAt: now), lastReview: report)
    }

    private func swapSuggestion(targetID: UUID) -> ProgramSuggestion {
        ProgramSuggestion(
            id: "swapExercise:\(targetID.uuidString):2026-W39",
            kind: .swapExercise,
            rule: "R5",
            title: "Trocar de exercício",
            reason: "Sem progresso nas últimas 6 sessões.",
            targetIDs: [targetID],
            referenceTopic: "topic.substitution"
        )
    }

    private func program(
        name: String,
        goal: ProgramGoal,
        isActive: Bool = false,
        targets: [ExerciseTarget] = []
    ) -> ProgramTemplate {
        let exercises = targets.isEmpty ? [ExerciseTarget(exerciseID: UUID(), order: 0)] : targets
        return ProgramTemplate(
            name: name,
            days: [ProgramDayTemplate(name: "Dia A", order: 0, exercises: exercises)],
            isActive: isActive,
            goal: goal
        )
    }

    private func exercise(name: String) -> ExerciseDefinition {
        ExerciseDefinition(
            slug: name.lowercased(),
            name: name,
            primaryMuscles: [.chest],
            equipment: .barbell,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )
    }
}

// MARK: - Doubles

enum CoachTestError: Error {
    case disk
}

/// Relógio mutável: os testes avançam o tempo entre chamadas.
final class CoachTestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

/// `SessionPlanning` controlável. Os cinco métodos do contrato §2.2 (`deloadStatus`,
/// `requestDeload`, `dismissDeload`, `completedSessionSummaries`, `reviewInput`) chegam aqui pela
/// ponte temporária `CoachPlanningShim` (CoachPlannerShimTests.swift) até o integrador mesclar o
/// planejador; depois disso eles implementam os requisitos reais do protocolo.
@MainActor
final class CoachTestPlanner: SessionPlanning {
    var deloadStatusToReturn: DeloadStatus = .inactive
    var sessionsToReturn: [SessionSummary] = []
    var reviewInputToReturn: ReviewInput?
    var goalToReturn: ProgramGoal?
    var planToReturn: SessionPlan?
    var substitutesToReturn: [ExerciseDefinition] = []
    private(set) var requestDeloadCalls: [Date] = []
    private(set) var dismissDeloadCalls: [Date] = []
    private(set) var nextPlanCalls: [Date] = []
    private(set) var substitutesCalls: [UUID] = []

    func nextPlan(now: Date) throws -> SessionPlan? {
        nextPlanCalls.append(now)
        return planToReturn
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        nil
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        UUID()
    }

    func activeProgramGoal() throws -> ProgramGoal? {
        goalToReturn
    }

    func substitutes(for exerciseID: UUID, limit: Int) throws -> [ExerciseDefinition] {
        substitutesCalls.append(exerciseID)
        return Array(substitutesToReturn.prefix(limit))
    }

    func deloadStatus(now: Date) throws -> DeloadStatus {
        deloadStatusToReturn
    }

    func requestDeload(now: Date) throws {
        requestDeloadCalls.append(now)
    }

    func dismissDeload(now: Date) throws {
        dismissDeloadCalls.append(now)
    }

    func completedSessionSummaries() throws -> [SessionSummary] {
        sessionsToReturn
    }

    func reviewInput(now: Date, recovery: RecoveryContext) throws -> ReviewInput? {
        reviewInputToReturn
    }
}

/// Uma chamada a `ProgramRepositoring.updateTarget`.
struct CoachTargetUpdate: Equatable {
    let id: UUID
    let sets: Int
    let repMin: Int
    let repMax: Int
    let targetRIR: Int
    let restSeconds: Int
    let startingLoad: Double?
}

/// `ProgramRepositoring` em memória que só registra as escritas do diálogo.
@MainActor
final class CoachTestPrograms: ProgramRepositoring {
    var programs: [ProgramTemplate] = []
    var updateError: (any Error)?
    private(set) var activated: [UUID] = []
    private(set) var updates: [CoachTargetUpdate] = []
    private(set) var replacements: [(targetID: UUID, exerciseID: UUID)] = []

    func allPrograms() throws -> [ProgramTemplate] {
        programs
    }

    func program(id: UUID) throws -> ProgramTemplate? {
        programs.first { $0.id == id }
    }

    func activate(programID: UUID) throws {
        activated.append(programID)
    }

    func rename(programID: UUID, to name: String) throws {}

    func setGoal(programID: UUID, goal: ProgramGoal, applyDefaults: Bool) throws {}

    func duplicate(programID: UUID, name: String, now: Date) throws -> UUID {
        UUID()
    }

    func delete(programID: UUID) throws {}

    func addExercise(exerciseID: UUID, toDay dayID: UUID) throws -> UUID {
        UUID()
    }

    func removeTarget(id: UUID) throws {}

    func moveTarget(id: UUID, toIndex newIndex: Int) throws {}

    func replaceExercise(targetID: UUID, with exerciseID: UUID) throws {
        replacements.append((targetID: targetID, exerciseID: exerciseID))
    }

    func updateTarget(
        id: UUID,
        sets: Int,
        repMin: Int,
        repMax: Int,
        targetRIR: Int,
        restSeconds: Int,
        startingLoad: Double?
    ) throws {
        if let updateError {
            throw updateError
        }
        updates.append(
            CoachTargetUpdate(
                id: id,
                sets: sets,
                repMin: repMin,
                repMax: repMax,
                targetRIR: targetRIR,
                restSeconds: restSeconds,
                startingLoad: startingLoad
            )
        )
    }
}
