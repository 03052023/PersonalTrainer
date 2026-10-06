import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Contrato V2-FINAL §2.3: `CoachService` sobre doubles de `SessionPlanning` e
/// `ProgramRepositoring`, `FakeCoachLogStore`, `FakeNotificationScheduler`, relógio controlado e
/// `UserDefaults` descartável. Cobre a montagem do `CoachInput` (C1 com `since` estável, C2 com a
/// revisão guardada, C5, C6, C7, C8), os efeitos de cada resposta, o destaque na abertura e, desde a
/// 2.5, a saída da C4 com o cancelamento único do aviso antigo (SPEC §7.18 L4).
@MainActor
final class CoachServiceTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -3 * 3_600)!
        return calendar
    }()

    /// Quinta-feira, 24/09/2026, 12:00 em UTC−3 (semana ISO 2026-W39).
    private var now: Date { date(2026, 9, 24) }

    // MARK: - Feed vazio e destaque

    func testRefresh_withoutAnyData_hasNoMessagesAndNoHighlight() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        XCTAssertEqual(fixture.service.messages, [])
        XCTAssertNil(fixture.service.highlight)
        XCTAssertNil(fixture.service.errorMessage)
    }

    /// Desde a 2.5, o C5 (que também destaca na abertura) faz o papel que a C4 fazia nestes testes do
    /// destaque: duas semanas sem sessão.
    func testRefresh_afterTwoWeeksAway_showsC5AsHighlight() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.sessionsToReturn = [session(startedAt: date(2026, 9, 10))]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        let message = try XCTUnwrap(fixture.service.messages.first)
        XCTAssertEqual(message.rule, .comeback)
        XCTAssertEqual(fixture.service.highlight?.id, message.id, "C5 destaca na abertura")
    }

    func testHighlight_eachMessageIsHighlightedOnlyOnce() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.sessionsToReturn = [session(startedAt: date(2026, 9, 10))]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let highlighted = try XCTUnwrap(fixture.service.highlight)
        fixture.service.dismissHighlight()
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        XCTAssertNil(fixture.service.highlight, "Fechar sem responder não reabre a folha a cada refresh")
        XCTAssertTrue(fixture.service.messages.contains { $0.id == highlighted.id }, "A mensagem continua no feed")
    }

    func testRefresh_withoutHighlight_updatesTheFeedButOpensNoSheet() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.sessionsToReturn = [session(startedAt: date(2026, 9, 10))]

        // Troca de aba, fim da sessão, leitura do Saúde: só o feed muda (SPEC §7.11, "na abertura").
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown, allowsHighlight: false)
        XCTAssertTrue(fixture.service.messages.contains { $0.rule == .comeback })
        XCTAssertNil(fixture.service.highlight)

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown, allowsHighlight: true)
        XCTAssertEqual(fixture.service.highlight?.rule, .comeback, "Na abertura, o destaque aparece")

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown, allowsHighlight: false)
        XCTAssertEqual(fixture.service.highlight?.rule, .comeback, "Um destaque já escolhido continua")
    }

    func testHandle_onHighlight_defersNavigationUntilSheetCloses() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.sessionsToReturn = [session(startedAt: date(2026, 9, 10))]
        var startRequests = 0
        fixture.service.onStartRequested = { startRequests += 1 }

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.highlight)
        XCTAssertEqual(message.rule, .comeback)
        fixture.service.handle(.start, on: message)

        XCTAssertNil(fixture.service.highlight, "Responder fecha o destaque")
        XCTAssertEqual(startRequests, 0, "Duas folhas ao mesmo tempo não abrem: espera o destaque fechar")
        fixture.service.highlightDidDismiss()
        XCTAssertEqual(startRequests, 1)
        XCTAssertFalse(fixture.service.messages.contains { $0.id == message.id })
        XCTAssertEqual(fixture.logStore.log.entries.last?.action, .start)
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

    /// SPEC §7.11 C1 com números (2.4, achado B11 da 2.1): o `CoachInput` recebe os números do planejador
    /// quando a semana leve está programada, e só então o planejador é consultado.
    func testC1_inputCarriesTheDeloadDetailWhenScheduled() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let detail = DeloadTriggerDetail(
            trigger: .manyDecreases,
            decreasedExercises: 4,
            countedExercises: 7
        )
        fixture.planner.deloadDetailToReturn = detail

        // Sem semana leve programada: sem números, e o planejador nem calcula.
        var log = CoachLog()
        XCTAssertNil(fixture.service.makeInput(log: &log, now: now).deloadDetail)
        XCTAssertEqual(fixture.planner.deloadTriggerDetailCalls, [])

        // Programada: os números vão ao C1.
        fixture.planner.deloadStatusToReturn = .pending(trigger: .manyDecreases)
        XCTAssertEqual(fixture.service.makeInput(log: &log, now: now).deloadDetail, detail)
        XCTAssertEqual(fixture.planner.deloadTriggerDetailCalls, [now])

        // Durante a passagem, de novo sem números.
        fixture.planner.deloadStatusToReturn = .active(start: now)
        XCTAssertNil(fixture.service.makeInput(log: &log, now: now).deloadDetail)
        XCTAssertEqual(fixture.planner.deloadTriggerDetailCalls.count, 1)

        // Uma falha de leitura deixa o C1 sem números, e a mensagem continua.
        fixture.planner.deloadStatusToReturn = .pending(trigger: .scheduled)
        fixture.planner.deloadDetailError = CoachTestError.disk
        XCTAssertNil(fixture.service.makeInput(log: &log, now: now).deloadDetail)
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        XCTAssertTrue(fixture.service.messages.contains { $0.rule == .deload })
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

    func testRefresh_storedReviewOfAnotherProgram_leavesTheFeed() throws {
        let firstSession = date(2026, 7, 20)
        let oldTarget = ExerciseTarget(exerciseID: UUID(), order: 0)
        let oldProgram = program(name: "Completo", goal: .hypertrophy, isActive: true, targets: [oldTarget])
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.sessionsToReturn = [session(startedAt: firstSession)]
        fixture.planner.reviewInputToReturn = reviewInput(programID: oldProgram.id, startDate: firstSession)
        fixture.programs.programs = [oldProgram]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        XCTAssertTrue(
            fixture.service.messages.contains { $0.rule == .review },
            "A revisão do programa ativo aparece (troca de programa, C2)"
        )

        // Outro programa ativado pela aba Programa, antes da próxima revisão.
        let newProgram = program(name: "Foco superior", goal: .hypertrophy, isActive: true)
        fixture.programs.programs = [newProgram]
        fixture.planner.reviewInputToReturn = reviewInput(programID: newProgram.id, startDate: nil)
        fixture.clock.now = date(2026, 9, 25)
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        XCTAssertEqual(fixture.logStore.reviewSaveCount, 1)
        XCTAssertFalse(
            fixture.service.messages.contains { $0.rule == .review },
            "As sugestões do programa anterior saem do feed"
        )
    }

    func testRefresh_storedSuggestionForARemovedExercise_leavesTheFeed() throws {
        let target = ExerciseTarget(exerciseID: UUID(), order: 0)
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
        fixture.programs.programs = [program(name: "Completo", goal: .hypertrophy, isActive: true)]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        XCTAssertFalse(fixture.service.messages.contains { $0.rule == .review }, "\"Aplicar\" só daria erro")
    }

    func testA5_resetAfterImport_forgetsTheStoredReview() throws {
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
        XCTAssertTrue(fixture.service.messages.contains { $0.rule == .review }, "A revisão guardada está no feed")

        // A importação apagou o last-review.json (BackupImportCleanup); o lastReviewAt fica no log.
        fixture.logStore.lastReview = nil
        fixture.service.resetAfterImport()

        XCTAssertFalse(fixture.service.messages.contains { $0.rule == .review })
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        XCTAssertFalse(fixture.service.messages.contains { $0.rule == .review }, "Nem ao voltar para Hoje")
        XCTAssertEqual(fixture.logStore.reviewSaveCount, 0, "A próxima revisão segue o calendário do lastReviewAt")
    }

    /// SPEC RF-45: o C2 troca para o próximo formato da Hipertrofia do seed, nunca para um programa
    /// escondido (o antigo Empurrar/Inferior/Puxar, que vem antes pelo nome).
    func testRF45_applySwitchProgram_activatesTheNextHypertrophyFormat() throws {
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
        let formats = CoachService.hypertrophyFormats.map(\.id)
        let legacyID = try XCTUnwrap(UUID(uuidString: "26262EE7-89B0-4048-93F9-1720FD9CBE40"))
        let other = program(id: formats[1], name: "Hipertrofia — Foco inferior", goal: .hypertrophy)
        fixture.programs.programs = [
            program(id: formats[0], name: "Hipertrofia — Equilibrado", goal: .hypertrophy, isActive: true),
            program(id: legacyID, name: "Hipertrofia — Empurrar/Inferior/Puxar", goal: .hypertrophy),
            program(name: "Força 3 dias", goal: .strength),
            other,
        ]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        XCTAssertEqual(
            fixture.service.applySummary(for: message),
            "O plano passa a ser Mais pernas e glúteos. As cargas de cada exercício são mantidas."
        )
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(fixture.programs.activated, [other.id])
        XCTAssertEqual(fixture.logStore.log.entries.map(\.action), [.apply])
        XCTAssertFalse(fixture.service.messages.contains { $0.id == message.id })
    }

    /// SPEC RF-45 e C2 (2.3, D1): o Corpo todo ficou escondido e não é um dos 3 formatos; com ele
    /// ativo, o próximo formato é o primeiro da lista, o Equilibrado.
    func testC2_nextFormatAfterFullBodyIsBalanced() throws {
        let suggestion = ProgramSuggestion(
            id: "switchProgram:old:2026-W39",
            kind: .switchProgram,
            rule: "R5",
            title: "Experimentar um novo programa",
            reason: "Você treina com este plano há 9 semanas.",
            strength: .optional,
            referenceTopic: "topic.substitution"
        )
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        XCTAssertEqual(CoachService.hypertrophyFormats.map(\.title), ["Equilibrado", "Mais pernas e glúteos", "Mais tronco e braços"])
        let formats = CoachService.hypertrophyFormats.map(\.id)
        XCTAssertEqual(formats.first, UUID(uuidString: "9FE0818F-1417-4953-B357-43D757054FCC"))
        let fullBodyID = try XCTUnwrap(UUID(uuidString: "14E3FAC0-8424-4360-AF9D-20D18DCB0E45"))
        XCTAssertFalse(formats.contains(fullBodyID), "O Corpo todo não é formato: fica escondido")
        let balanced = program(id: formats[0], name: "Hipertrofia — Equilibrado", goal: .hypertrophy)
        fixture.programs.programs = [
            program(id: fullBodyID, name: "Hipertrofia — Completo", goal: .hypertrophy, isActive: true),
            balanced,
            program(id: formats[1], name: "Hipertrofia — Foco inferior", goal: .hypertrophy),
            program(id: formats[2], name: "Hipertrofia — Foco superior", goal: .hypertrophy),
        ]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        XCTAssertEqual(
            fixture.service.applySummary(for: message),
            "O plano passa a ser Equilibrado. As cargas de cada exercício são mantidas."
        )
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(fixture.programs.activated, [balanced.id])
    }

    /// SPEC §7.15 M8: com um segundo plano ativo, o C2 troca só o formato da Hipertrofia (tira o antigo e
    /// acrescenta o próximo, nessa ordem) e mantém o outro. O principal sai do objetivo, não da ordem da lista.
    func testM8_coachC2KeepsSecondPlan() throws {
        let suggestion = ProgramSuggestion(
            id: "switchProgram:old:2026-W39",
            kind: .switchProgram,
            rule: "R5",
            title: "Experimentar um novo programa",
            reason: "Você treina com este plano há 9 semanas.",
            strength: .optional,
            referenceTopic: "topic.substitution"
        )
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        let formats = CoachService.hypertrophyFormats.map(\.id)
        let cardio = program(name: "Cardio", goal: .endurance, isActive: true)
        let next = program(id: formats[1], name: "Hipertrofia — Foco inferior", goal: .hypertrophy)
        fixture.programs.programs = [
            cardio,
            program(id: formats[0], name: "Hipertrofia — Equilibrado", goal: .hypertrophy, isActive: true),
            next,
        ]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        XCTAssertEqual(
            fixture.service.applySummary(for: message),
            "O plano passa a ser Mais pernas e glúteos. As cargas de cada exercício são mantidas."
        )
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(fixture.programs.removed, [formats[0]])
        XCTAssertEqual(fixture.programs.added, [next.id])
        XCTAssertEqual(fixture.programs.activated, [], "activate deixaria um plano só")
        XCTAssertNil(fixture.service.errorMessage)
        XCTAssertEqual(fixture.logStore.log.entries.map(\.action), [.apply])
    }

    /// SPEC §7.15 M8: se acrescentar o novo formato falhar, o antigo volta e nada é gravado no log.
    func testM8_coachC2FailedAddRestoresThePrincipal() throws {
        let suggestion = ProgramSuggestion(
            id: "switchProgram:old:2026-W39",
            kind: .switchProgram,
            rule: "R5",
            title: "Experimentar um novo programa",
            reason: "Você treina com este plano há 9 semanas.",
            strength: .optional,
            referenceTopic: "topic.substitution"
        )
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        let formats = CoachService.hypertrophyFormats.map(\.id)
        fixture.programs.programs = [
            program(id: formats[0], name: "Hipertrofia — Equilibrado", goal: .hypertrophy, isActive: true),
            program(name: "Cardio", goal: .endurance, isActive: true),
            program(id: formats[1], name: "Hipertrofia — Foco inferior", goal: .hypertrophy),
        ]
        fixture.programs.failingAddIDs = [formats[1]]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(fixture.programs.removed, [formats[0]])
        XCTAssertEqual(fixture.programs.added, [formats[0]], "O plano anterior volta")
        XCTAssertNotNil(fixture.service.errorMessage)
        XCTAssertTrue(fixture.logStore.log.entries.isEmpty)
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

    /// SPEC RF-45: fora da Hipertrofia não há formatos; uma cópia do mesmo objetivo fica escondida,
    /// então a pessoa escolhe na folha "Seu objetivo".
    func testRF45_applySwitchProgram_outsideHypertrophy_asksThePersonToChoose() throws {
        let suggestion = ProgramSuggestion(
            id: "switchProgram:old:2026-W39",
            kind: .switchProgram,
            rule: "R5",
            title: "Experimentar um novo programa",
            reason: "Você treina com o programa Força há 9 semanas.",
            strength: .optional,
            referenceTopic: "topic.substitution"
        )
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        fixture.programs.programs = [
            program(name: "Força", goal: .strength, isActive: true),
            program(name: "Força (cópia)", goal: .strength),
        ]
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
        XCTAssertEqual(fixture.planner.programSubstitutesCalls.last, original.id)
    }

    /// SPEC RF-42: "o programa não muda". Com o modo casa ligado, `substitutes` (a folha Trocar da
    /// sessão) só oferece exercícios de casa; a troca da revisão muda o programa, então usa
    /// `programSubstitutes`, a regra do RF-34 sobre o catálogo inteiro.
    func testHandle_applySwapExercise_usesProgramSubstitutes_notTheHomeModeOnes() throws {
        let original = exercise(name: "Supino reto")
        let target = ExerciseTarget(exerciseID: original.id, order: 0)
        let suggestion = swapSuggestion(targetID: target.id)
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        fixture.programs.programs = [program(name: "Completo", goal: .hypertrophy, isActive: true, targets: [target])]
        let homeOnly = exercise(name: "Flexão de joelhos")
        let gym = exercise(name: "Supino com halteres")
        fixture.planner.substitutesToReturn = [homeOnly]
        fixture.planner.programSubstitutesToReturn = [gym, homeOnly]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(fixture.programs.replacements.map { $0.exerciseID }, [gym.id])
        XCTAssertEqual(fixture.planner.programSubstitutesCalls.last, original.id)
        XCTAssertTrue(fixture.planner.substitutesCalls.isEmpty, "A folha da sessão não decide a troca no programa")
    }

    func testHandle_applySwapExercise_skipsASubstituteAlreadyInTheDay() throws {
        // Como no dia A do Empurrar/Inferior/Puxar: o melhor substituto do supino reto com barra
        // é o supino inclinado com halteres, que já é o exercício seguinte do dia.
        let original = exercise(name: "Supino reto com barra")
        let incline = exercise(name: "Supino inclinado com halteres")
        let target = ExerciseTarget(exerciseID: original.id, order: 0)
        let inclineTarget = ExerciseTarget(exerciseID: incline.id, order: 1)
        let suggestion = swapSuggestion(targetID: target.id)
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        fixture.programs.programs = [
            program(name: "Empurrar/Inferior/Puxar", goal: .hypertrophy, isActive: true, targets: [target, inclineTarget]),
        ]
        let flat = exercise(name: "Supino reto com halteres")
        fixture.planner.substitutesToReturn = [incline, flat]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        fixture.service.handle(.apply, on: message)

        XCTAssertEqual(fixture.programs.replacements.map { $0.targetID }, [target.id])
        XCTAssertEqual(
            fixture.programs.replacements.map { $0.exerciseID },
            [flat.id],
            "O dia não fica com o mesmo exercício duas vezes"
        )
        XCTAssertNil(fixture.service.errorMessage)
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
        let target = ExerciseTarget(exerciseID: UUID(), order: 0)
        let suggestion = ProgramSuggestion(
            id: "removeSets:back:\(target.id.uuidString):2026-W39",
            kind: .removeSets,
            rule: "R3",
            title: "Menos séries para as costas",
            reason: "As costas tiveram 24 séries por semana.",
            targetIDs: [target.id],
            muscle: .back,
            proposedSets: 2,
            referenceTopic: "topic.volume"
        )
        let fixture = try makeFixture(logStore: storeWithReview([suggestion]))
        defer { fixture.cleanUp() }
        fixture.programs.programs = [program(name: "Completo", goal: .hypertrophy, isActive: true, targets: [target])]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .review })
        // O exercício sai do programa depois que o feed foi montado.
        fixture.programs.programs = [program(name: "Completo", goal: .hypertrophy, isActive: true)]
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

    func testRefresh_abandonedSessionWithWorkingSets_countsAsTheLastSession() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        // SPEC P9/C5: a pausa conta da última sessão com série de trabalho, concluída ou abandonada.
        fixture.planner.sessionsToReturn = [
            session(startedAt: date(2026, 8, 30)),
            session(startedAt: date(2026, 9, 21), status: .abandoned, workingSetCount: 4),
        ]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        XCTAssertFalse(fixture.service.messages.contains { $0.rule == .comeback }, "Três dias não é uma pausa")
        XCTAssertEqual(fixture.planner.nextPlanCalls, [])
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

    /// SPEC §7.15 M2: com dois planos, o C5 olha o principal, com as sessões dos dias dele. O cardio de
    /// ontem não apaga 8 dias sem a força, e o próximo dia é o do principal. Com um plano só, todas contam.
    func testM2_comebackUsesPrincipal() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let cardio = program(name: "Cardio", goal: .endurance, isActive: true)
        let balanced = program(name: "Hipertrofia — Equilibrado", goal: .hypertrophy, isActive: true)
        fixture.programs.programs = [cardio, balanced]
        let cardioDayID = try XCTUnwrap(cardio.days.first).id
        let balancedDayID = try XCTUnwrap(balanced.days.first).id
        fixture.planner.sessionsToReturn = [
            SessionSummary(
                programDayID: balancedDayID,
                startedAt: date(2026, 9, 16),
                endedAt: date(2026, 9, 16, hour: 13),
                status: .completed,
                workingSetCount: 12
            ),
            SessionSummary(
                programDayID: cardioDayID,
                startedAt: date(2026, 9, 23),
                endedAt: date(2026, 9, 23, hour: 13),
                status: .completed,
                workingSetCount: 1
            ),
        ]
        fixture.planner.planToReturn = SessionPlan(
            programID: balanced.id,
            programName: balanced.name,
            programDayID: UUID(),
            programDayName: "Dia B — Inferior",
            exercises: [],
            generatedAt: now
        )

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        let message = try XCTUnwrap(fixture.service.messages.first { $0.rule == .comeback })
        XCTAssertTrue(message.reason.contains("Dia B — Inferior"), message.reason)
        XCTAssertTrue(message.reason.contains("8 dias"), message.reason)

        fixture.programs.programs = [cardio]
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        XCTAssertFalse(
            fixture.service.messages.contains { $0.rule == .comeback },
            "Com um plano só, a sessão de ontem é a última"
        )
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

    func testRefresh_newBestMark_onlyForExercisesMeasuredInReps() throws {
        let bench = exercise(name: "Supino reto")
        let walk = exercise(name: "Caminhada do fazendeiro")
        let fixture = try makeFixture(traits: ExerciseTraitsCatalog(traitsBySlug: [
            walk.slug: ExerciseTraits(measure: .steps),
        ]))
        defer { fixture.cleanUp() }
        let older = UUID()
        let latest = UUID()
        let olderDate = date(2026, 9, 21, hour: 8)
        let latestDate = date(2026, 9, 23, hour: 8)
        fixture.planner.sessionsToReturn = [
            session(id: older, startedAt: olderDate),
            session(id: latest, startedAt: latestDate),
        ]
        // Mesma progressão nos dois: 20 → 24 kg com o mesmo número por série.
        func slot(_ definition: ExerciseDefinition, reps: Int, repMin: Int, repMax: Int) -> ExerciseReviewInput {
            ExerciseReviewInput(
                exercise: definition,
                targetID: UUID(),
                dayID: UUID(),
                sets: 3,
                repMin: repMin,
                repMax: repMax,
                history: [
                    ExerciseHistoryEntry(sessionID: older, date: olderDate, sets: [SetResult(load: 20, reps: reps, rir: 2, completedAt: olderDate)]),
                    ExerciseHistoryEntry(sessionID: latest, date: latestDate, sets: [SetResult(load: 24, reps: reps, rir: 2, completedAt: latestDate)]),
                ]
            )
        }
        fixture.planner.reviewInputToReturn = ReviewInput(
            programID: UUID(),
            programName: "Completo",
            programDayCount: 1,
            programStartDate: olderDate,
            exercises: [
                slot(bench, reps: 8, repMin: 8, repMax: 12),
                slot(walk, reps: 30, repMin: 20, repMax: 40),
            ],
            sessions: [],
            weeklySetTarget: 10...20,
            currentPrescriptions: []
        )

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        // SPEC RF-43: passos não são repetições; o 1RM estimado de uma carregada não é marca.
        let records = fixture.service.messages.filter { $0.rule == .personalRecord }
        XCTAssertEqual(records.map(\.suggestionID), [bench.id.uuidString])
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

    /// SPEC §7.17 X6 (2.4): o "Feito" do C8 também grava 10 min leves de equilíbrio ou de mobilidade nas
    /// atividades fora do app, para as Metas contarem as vezes. "Pular" não grava nada, e uma falha ao
    /// gravar não tira a marca do C8.
    func testX6_coachDoneLogsLongevityEntry() throws {
        let activities = FakeOutsideActivityStore()
        let fixture = try makeFixture(activities: activities)
        defer { fixture.cleanUp() }
        fixture.planner.goalToReturn = .longevity

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let balance = try XCTUnwrap(fixture.service.messages.first { $0.itemKey == CoachInput.balanceKey })
        fixture.service.handle(.done, on: balance)

        XCTAssertEqual(activities.saveCount, 1)
        let entry = try XCTUnwrap(activities.log.entries.first)
        XCTAssertEqual(activities.log.entries.count, 1)
        XCTAssertEqual(entry.kind, .balance)
        XCTAssertEqual(entry.start, now)
        XCTAssertEqual(entry.minutes, OutsideActivities.longevityEntryMinutes)
        XCTAssertEqual(entry.minutes, 10)
        XCTAssertEqual(entry.intensity, .light)
        XCTAssertNil(entry.fixedActivityID)
        // As Metas contam a vez na semana (W2.6): segunda 21/09 a domingo 27/09.
        let week = DateInterval(start: date(2026, 9, 21, hour: 0), duration: 7 * 86_400)
        XCTAssertEqual(
            OutsideActivities.longevityCounts(entries: activities.log.entries, week: week),
            [CoachInput.balanceKey: 1]
        )
        XCTAssertNil(fixture.service.errorMessage)

        // "Pular" só esconde a mensagem: nada vai às atividades.
        let mobility = try XCTUnwrap(fixture.service.messages.first { $0.itemKey == CoachInput.mobilityKey })
        fixture.service.handle(.skip, on: mobility)
        XCTAssertEqual(activities.saveCount, 1)
        XCTAssertEqual(activities.log.entries.count, 1)
        XCTAssertFalse(fixture.service.messages.contains { $0.rule == .longevity })
    }

    func testX6_coachDoneWithActivitiesFailure_keepsTheC8Mark() throws {
        let activities = FakeOutsideActivityStore()
        activities.saveError = CoachTestError.disk
        let fixture = try makeFixture(activities: activities)
        defer { fixture.cleanUp() }
        fixture.planner.goalToReturn = .longevity

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let mobility = try XCTUnwrap(fixture.service.messages.first { $0.itemKey == CoachInput.mobilityKey })
        fixture.service.handle(.done, on: mobility)

        XCTAssertEqual(activities.log.entries, [])
        XCTAssertNil(fixture.service.errorMessage, "A falha vai para o log; a marca do C8 continua")
        XCTAssertEqual(fixture.service.longevityMarks(in: fixture.logStore.log, now: now), [CoachInput.mobilityKey])
        XCTAssertFalse(fixture.service.messages.contains { $0.itemKey == CoachInput.mobilityKey })
    }

    /// SPEC C8, §7.17 X6: equilíbrio registrado em "Fora do app" nesta semana já está feito. O lembrete de
    /// equilíbrio some (o de mobilidade fica), e nenhum "Feito" a mais grava a mesma vez de novo.
    func testX6_registeredBalanceSilencesC8() throws {
        let registered = OutsideActivityEntry(
            kind: .balance,
            start: now.addingTimeInterval(-3_600),
            minutes: 15,
            intensity: .light
        )
        let activities = FakeOutsideActivityStore(log: OutsideActivityLog(entries: [registered]))
        let fixture = try makeFixture(activities: activities)
        defer { fixture.cleanUp() }
        fixture.planner.goalToReturn = .longevity

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)

        XCTAssertFalse(fixture.service.messages.contains { $0.itemKey == CoachInput.balanceKey })
        XCTAssertTrue(fixture.service.messages.contains { $0.itemKey == CoachInput.mobilityKey })
        XCTAssertEqual(activities.saveCount, 0)

        // Na semana seguinte, o registro antigo não conta: o lembrete volta.
        fixture.clock.now = date(2026, 10, 1)
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        XCTAssertTrue(fixture.service.messages.contains { $0.itemKey == CoachInput.balanceKey })
    }

    /// SPEC §7.16 W2.6: só um "Feito" de antes da 2.4 (sem registro) vale 1 nas Metas. Depois do primeiro
    /// "Feito" que grava um registro, as marcas novas contam só pelo registro: apagá-lo desfaz a vez.
    func testW26_deletingC8EntryUndoesCount() throws {
        let oldMark = CoachLogEntry(
            messageID: "longevity:\(CoachInput.mobilityKey):old",
            rule: .longevity,
            itemKey: CoachInput.mobilityKey,
            action: .done,
            date: date(2026, 9, 22)
        )
        let activities = FakeOutsideActivityStore()
        let fixture = try makeFixture(
            logStore: FakeCoachLogStore(log: CoachLog(entries: [oldMark])),
            activities: activities
        )
        defer { fixture.cleanUp() }
        fixture.planner.goalToReturn = .longevity

        // Antes de qualquer "Feito" da 2.4, a marca antiga vale 1.
        XCTAssertEqual(
            fixture.service.legacyLongevityMarks(in: fixture.logStore.log, now: now),
            [CoachInput.mobilityKey]
        )

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let balance = try XCTUnwrap(fixture.service.messages.first { $0.itemKey == CoachInput.balanceKey })
        fixture.service.handle(.done, on: balance)
        XCTAssertEqual(activities.log.entries.map(\.kind), [.balance])

        // O "Feito" novo esconde o lembrete, mas nas Metas conta só pelo registro; a marca antiga continua.
        XCTAssertEqual(
            fixture.service.longevityMarks(in: fixture.logStore.log, now: now),
            [CoachInput.balanceKey, CoachInput.mobilityKey]
        )
        XCTAssertEqual(
            fixture.service.legacyLongevityMarks(in: fixture.logStore.log, now: now),
            [CoachInput.mobilityKey]
        )

        // Apagar o registro do C8 (na seção "Fora do app") tira a vez das Metas: nem registro nem marca.
        try activities.save(OutsideActivityLog.empty)
        let week = WeeklyFrequency.weekInterval(containing: now, weekStartsOnMonday: true, calendar: calendar)
        XCTAssertEqual(OutsideActivities.longevityCounts(entries: activities.log.entries, week: week), [:])
        XCTAssertFalse(
            fixture.service.legacyLongevityMarks(in: fixture.logStore.log, now: now).contains(CoachInput.balanceKey)
        )
    }

    /// SPEC §7.15 M2: o C8 vale quando qualquer plano ativo é de Longevidade, principal ou não.
    func testM2_longevityRemindersWithSecondPlan() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.goalToReturn = .hypertrophy
        fixture.planner.goalsToReturn = [.hypertrophy, .longevity]

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        XCTAssertTrue(fixture.service.messages.contains { $0.itemKey == CoachInput.balanceKey })
        XCTAssertTrue(fixture.service.messages.contains { $0.itemKey == CoachInput.mobilityKey })

        fixture.planner.goalsToReturn = [.hypertrophy, .endurance]
        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        XCTAssertFalse(fixture.service.messages.contains { $0.rule == .longevity })
    }

    func testIsoWeekLabel_matchesTheCoachPeriods() {
        XCTAssertEqual(CoachService.isoWeekLabel(for: now, calendar: calendar), "2026-W39")
        XCTAssertEqual(CoachService.isoWeekLabel(for: date(2027, 1, 1), calendar: calendar), "2026-W53")
    }

    // MARK: - L4 Sem sideload no app (2.5)

    /// SPEC §7.18 L4: uma cópia que vem da 2.4 pode ter o aviso antigo agendado e a chave gravada. No
    /// primeiro refresh, o pedido é cancelado e a chave apagada; no segundo, nada acontece.
    func testL4_legacyExpiryReminderIsCancelledOnce() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.defaults.set(true, forKey: "expiryReminderEnabled")
        // O pedido que a 2.4 deixou pendente (o Fake guarda qualquer agendamento pelo identificador).
        await fixture.notifications.scheduleRestTimerEnd(
            at: date(2026, 9, 26, hour: 10),
            identifier: "coach.expiryReminder",
            body: "Aviso antigo"
        )

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        await fixture.service.pendingWork?.value

        var cancelled = await fixture.notifications.cancelledIdentifiers
        XCTAssertEqual(cancelled, ["coach.expiryReminder"])
        let pending = await fixture.notifications.pendingRequests
        XCTAssertTrue(pending.isEmpty, "o aviso antigo sai da fila do iPhone")
        XCTAssertNil(fixture.defaults.object(forKey: "expiryReminderEnabled"), "a chave antiga é apagada")
        let requests = await fixture.notifications.authorizationRequestCount
        XCTAssertEqual(requests, 0, "cancelar não pede permissão de notificação (AGENTS §7)")
        XCTAssertEqual(CoachService.DefaultsKey.expiryReminderEnabled, "expiryReminderEnabled")
        XCTAssertEqual(CoachService.expiryReminderIdentifier, "coach.expiryReminder")

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        await fixture.service.pendingWork?.value

        cancelled = await fixture.notifications.cancelledIdentifiers
        XCTAssertEqual(cancelled, ["coach.expiryReminder"], "no segundo refresh, nada")
    }

    /// SPEC §7.18 L4: sem a chave antiga (instalação nova ou já limpa), nada é cancelado nem enfileirado.
    func testL4_noLegacyKeyCancelsNothing() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        await fixture.service.pendingWork?.value

        XCTAssertNil(fixture.service.pendingWork, "sem a chave, nada vai para a fila")
        let cancelled = await fixture.notifications.cancelledIdentifiers
        XCTAssertEqual(cancelled, [])
        let requests = await fixture.notifications.authorizationRequestCount
        XCTAssertEqual(requests, 0)
        XCTAssertNil(fixture.defaults.object(forKey: "expiryReminderEnabled"))
    }

    /// SPEC §7.18 L4: `howToRenew` nunca é oferecida; se chegar (por exemplo, de uma folha antiga), só
    /// vai para o log, sem navegar nem pedir permissão, nem depois que o destaque fecha.
    func testL4_howToRenewOnlyLogs() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        fixture.planner.sessionsToReturn = [session(startedAt: date(2026, 9, 10))]
        var navigations = 0
        fixture.service.onBackupRequested = { navigations += 1 }
        fixture.service.onStartRequested = { navigations += 1 }
        fixture.service.onProgressRequested = { _ in navigations += 1 }
        fixture.service.onChooseProgramRequested = { navigations += 1 }

        fixture.service.refresh(healthSuggestions: [], recovery: .unknown)
        let message = try XCTUnwrap(fixture.service.highlight)
        fixture.service.handle(.howToRenew, on: message)
        fixture.service.highlightDidDismiss()
        await fixture.service.pendingWork?.value

        XCTAssertEqual(navigations, 0, "nenhuma navegação")
        XCTAssertNil(fixture.service.errorMessage)
        let requests = await fixture.notifications.authorizationRequestCount
        XCTAssertEqual(requests, 0, "nenhum pedido de permissão")
        XCTAssertEqual(fixture.logStore.log.entries.map(\.action), [.howToRenew])
        XCTAssertEqual(fixture.logStore.log.entries.last?.messageID, message.id)
        XCTAssertFalse(fixture.service.messages.contains { $0.id == message.id }, "o log esconde a mensagem")
        XCTAssertFalse(fixture.service.messages.contains { $0.rule == .installExpiry })
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
        let activities: FakeOutsideActivityStore

        func cleanUp() {
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func makeFixture(
        logStore: FakeCoachLogStore? = nil,
        authorizationToGrant: Bool = true,
        traits: ExerciseTraitsCatalog = .empty,
        activities: FakeOutsideActivityStore = FakeOutsideActivityStore()
    ) throws -> Fixture {
        let suite = "CoachServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let planner = CoachTestPlanner()
        let programs = CoachTestPrograms()
        let store = logStore ?? FakeCoachLogStore()
        let notifications = FakeNotificationScheduler(authorizationToGrant: authorizationToGrant)
        let clock = CoachTestClock(now)
        let service = CoachService(
            planner: planner,
            programs: programs,
            log: store,
            notifications: notifications,
            now: { clock.now },
            calendar: calendar,
            defaults: defaults,
            traits: traits,
            activities: activities
        )
        return Fixture(
            service: service,
            planner: planner,
            programs: programs,
            logStore: store,
            notifications: notifications,
            defaults: defaults,
            suite: suite,
            clock: clock,
            activities: activities
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func session(
        id: UUID = UUID(),
        startedAt: Date,
        status: SessionStatus = .completed,
        workingSetCount: Int = 12,
        isDeload: Bool = false
    ) -> SessionSummary {
        SessionSummary(
            id: id,
            programDayID: UUID(),
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3_600),
            status: status,
            workingSetCount: workingSetCount,
            isDeload: isDeload
        )
    }

    /// `count` sessões concluídas nos dias anteriores a `now` (nenhuma pausa para o C5).
    private func recentSessions(count: Int) -> [SessionSummary] {
        (1...count).map { offset in
            session(startedAt: now.addingTimeInterval(-Double(offset) * 86_400))
        }
    }

    /// Entrada da revisão sem exercícios: só as sugestões do programa inteiro podem sair dela.
    private func reviewInput(programID: UUID, startDate: Date?) -> ReviewInput {
        ReviewInput(
            programID: programID,
            programName: "Completo",
            programDayCount: 1,
            programStartDate: startDate,
            exercises: [],
            sessions: [],
            weeklySetTarget: 10...20,
            currentPrescriptions: []
        )
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
        id: UUID = UUID(),
        name: String,
        goal: ProgramGoal,
        isActive: Bool = false,
        targets: [ExerciseTarget] = []
    ) -> ProgramTemplate {
        let exercises = targets.isEmpty ? [ExerciseTarget(exerciseID: UUID(), order: 0)] : targets
        return ProgramTemplate(
            id: id,
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

/// `SessionPlanning` controlável. `sessionsToReturn` alimenta as concluídas e as terminadas
/// (concluídas e abandonadas), cada uma com o seu filtro, como no `SessionPlanner`.
@MainActor
final class CoachTestPlanner: SessionPlanning {
    var deloadStatusToReturn: DeloadStatus = .inactive
    var sessionsToReturn: [SessionSummary] = []
    var reviewInputToReturn: ReviewInput?
    var goalToReturn: ProgramGoal?
    /// `nil`: só `goalToReturn`, como o padrão do protocolo.
    var goalsToReturn: [ProgramGoal]?
    var planToReturn: SessionPlan?
    var substitutesToReturn: [ExerciseDefinition] = []
    /// `nil`: `programSubstitutes` devolve o mesmo que `substitutes` (sem modo casa, as duas
    /// listas coincidem, como no `SessionPlanner`).
    var programSubstitutesToReturn: [ExerciseDefinition]?
    /// C1 com números (2.4): o que `deloadTriggerDetail(now:)` devolve, ou o erro que ela lança.
    var deloadDetailToReturn: DeloadTriggerDetail?
    var deloadDetailError: (any Error)?
    private(set) var deloadTriggerDetailCalls: [Date] = []
    private(set) var requestDeloadCalls: [Date] = []
    private(set) var dismissDeloadCalls: [Date] = []
    private(set) var nextPlanCalls: [Date] = []
    private(set) var substitutesCalls: [UUID] = []
    private(set) var programSubstitutesCalls: [UUID] = []

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

    func activeProgramGoals() throws -> [ProgramGoal] {
        if let goalsToReturn {
            return goalsToReturn
        }
        return goalToReturn.map { [$0] } ?? []
    }

    func substitutes(for exerciseID: UUID, limit: Int) throws -> [ExerciseDefinition] {
        substitutesCalls.append(exerciseID)
        return Array(substitutesToReturn.prefix(limit))
    }

    func programSubstitutes(for exerciseID: UUID, limit: Int) throws -> [ExerciseDefinition] {
        programSubstitutesCalls.append(exerciseID)
        return Array((programSubstitutesToReturn ?? substitutesToReturn).prefix(limit))
    }

    func deloadStatus(now: Date) throws -> DeloadStatus {
        deloadStatusToReturn
    }

    func deloadTriggerDetail(now: Date) throws -> DeloadTriggerDetail? {
        deloadTriggerDetailCalls.append(now)
        if let deloadDetailError {
            throw deloadDetailError
        }
        return deloadDetailToReturn
    }

    func requestDeload(now: Date) throws {
        requestDeloadCalls.append(now)
    }

    func dismissDeload(now: Date) throws {
        dismissDeloadCalls.append(now)
    }

    func completedSessionSummaries() throws -> [SessionSummary] {
        sessionsToReturn.filter { $0.status == .completed }
    }

    func finishedSessionSummaries() throws -> [SessionSummary] {
        sessionsToReturn.filter { $0.status != .inProgress }
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
    /// `addActivePlan` lança para estes ids (e não os registra).
    var failingAddIDs: Set<UUID> = []
    private(set) var added: [UUID] = []
    private(set) var removed: [UUID] = []
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

    func addActivePlan(programID: UUID) throws {
        if failingAddIDs.contains(programID) {
            throw ProgramRepositoryError.invalidParameters("Falha de teste.")
        }
        added.append(programID)
    }

    func removeActivePlan(programID: UUID) throws {
        removed.append(programID)
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
