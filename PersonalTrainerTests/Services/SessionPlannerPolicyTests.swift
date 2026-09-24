import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// v3/planner (docs/V2-FINAL-CONTRACT.md §2.2) sobre container in-memory e coordinator real:
/// - seletor por frequência no `nextPlan` (SPEC S5–S7, RF-39, CA4-1) e o motivo do dia (CA4-5);
/// - semana leve no plano (SPEC §7.5, CA4-3), gravada na sessão pelo coordinator (`isDeload`) e
///   lida de volta pelo `SessionSummaryMapper`;
/// - "Fazer semana leve agora" e "Seguir normal" (§7.5 c, §7.11 C1);
/// - sessões concluídas e entrada da revisão (§7.8).
/// Ajustes e decisões são injetados: nada aqui lê `UserDefaults.standard` nem o disco.
@MainActor
final class SessionPlannerPolicyTests: XCTestCase {
    /// Segunda-feira 2023-11-13 00:00 UTC: início da semana de treino dos testes (SPEC §7.4).
    private let monday = Date(timeIntervalSince1970: 1_699_833_600)
    private let day: TimeInterval = 86_400
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        return calendar
    }()

    /// Sábado 12:00 UTC da mesma semana.
    private var saturdayNoon: Date {
        monday.addingTimeInterval(5 * day + 12 * 3_600)
    }

    // MARK: - Seletor por frequência (S5–S7, RF-39, CA4-1, CA4-5)

    func testS5_S7_CA4_1_frequencyOn_picksDayBelowTargetOutOfRotation() throws {
        let fixture = try makeFixture(settings: PlannerSettings(frequencySelector: .on))
        let program = try insertFrequencyProgram(into: fixture.context)
        try insertFrequencyWeek(program, into: fixture.context)
        let week = WeeklyFrequency.weekInterval(containing: saturdayNoon, weekStartsOnMonday: true, calendar: calendar)
        XCTAssertEqual(week.start, monday, "premissa do teste: a semana começa na segunda 00:00 UTC")

        // Peito 2/2, costas 1/2, quadríceps 0/2, posteriores 0/2. A rotação daria B (depois de A),
        // mas C tem dois grupos abaixo da meta (S5) e nada treinado há < 48 h (S6).
        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: saturdayNoon))
        XCTAssertEqual(plan.programDayID, program.dayC.uuid)
        XCTAssertEqual(plan.programDayName, "Dia C")
        XCTAssertFalse(plan.isDeload)
        // CA4-5: empate de diferença (2 e 2) fica com o primeiro de `MuscleGroup.allCases`.
        XCTAssertEqual(plan.reason, .frequency(muscle: .quads, done: 0, target: 2))

        // Desligado: rotação pura (SPEC S2), mesmo histórico.
        fixture.settings.value = PlannerSettings(frequencySelector: .off)
        let rotation = try XCTUnwrap(try fixture.planner.nextPlan(now: saturdayNoon))
        XCTAssertEqual(rotation.programDayID, program.dayB.uuid)
        XCTAssertEqual(rotation.reason, .rotation)
    }

    func testRF39_auto_usesFrequencySelectorOnlyWithFourOrMoreDays() throws {
        // 3 dias: automático = rotação.
        let three = try makeFixture(settings: PlannerSettings(frequencySelector: .auto))
        let program3 = try insertFrequencyProgram(into: three.context)
        try insertFrequencyWeek(program3, into: three.context)
        let plan3 = try XCTUnwrap(try three.planner.nextPlan(now: saturdayNoon))
        XCTAssertEqual(plan3.programDayID, program3.dayB.uuid)
        XCTAssertEqual(plan3.reason, .rotation)

        // 4 dias (D = ombros, 0/2): automático = por frequência. Pontos: B 1, C 2, D 1, A 0.
        let four = try makeFixture(settings: PlannerSettings(frequencySelector: .auto))
        let program4 = try insertFrequencyProgram(includeShoulderDay: true, into: four.context)
        try insertFrequencyWeek(program4, into: four.context)
        let plan4 = try XCTUnwrap(try four.planner.nextPlan(now: saturdayNoon))
        XCTAssertEqual(plan4.programDayID, program4.dayC.uuid)
        XCTAssertEqual(plan4.reason, .frequency(muscle: .quads, done: 0, target: 2))
    }

    func testS5_weeklyTargetsComeFromUserSettings_zeroTargetDoesNotScore() throws {
        let fixture = try makeFixture(settings: PlannerSettings(frequencySelector: .on))
        let program = try insertFrequencyProgram(into: fixture.context)
        try insertFrequencyWeek(program, into: fixture.context)
        // SPEC §7.4: meta configurável por grupo; 0 tira o grupo da conta.
        let settingsRow = UserSettingsModel(
            uuid: UUID(),
            weekStartsOnMonday: true,
            weeklyTargetsRaw: #"{"hamstrings":0,"quads":0}"#,
            healthKitEnabled: false,
            defaultRestSeconds: 120,
            schemaSeedVersion: 1
        )
        fixture.context.insert(settingsRow)
        try fixture.context.save()

        // C passa a valer 0; B (costas 1/2) fica com o maior ponto.
        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: saturdayNoon))
        XCTAssertEqual(plan.programDayID, program.dayB.uuid)
        XCTAssertEqual(plan.reason, .frequency(muscle: .back, done: 1, target: 2))
    }

    func testRF39_plannerSettings_readsContractKeysFromUserDefaults() throws {
        let suiteName = "SessionPlannerPolicyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Nada gravado: automático e 6 semanas (SPEC RF-39, §7.5 b).
        XCTAssertEqual(PlannerSettings.load(from: defaults), PlannerSettings(frequencySelector: .auto, deloadWeeks: 6))

        defaults.set("on", forKey: "plannerFrequencySelector")
        defaults.set(0, forKey: "plannerDeloadWeeks")
        XCTAssertEqual(PlannerSettings.load(from: defaults), PlannerSettings(frequencySelector: .on, deloadWeeks: 0))

        defaults.set("off", forKey: "plannerFrequencySelector")
        defaults.set(4, forKey: "plannerDeloadWeeks")
        XCTAssertEqual(PlannerSettings.load(from: defaults), PlannerSettings(frequencySelector: .off, deloadWeeks: 4))

        // Valor desconhecido vale automático; semanas negativas desligam (b).
        defaults.set("sempre", forKey: "plannerFrequencySelector")
        defaults.set(-3, forKey: "plannerDeloadWeeks")
        XCTAssertEqual(PlannerSettings.load(from: defaults), PlannerSettings(frequencySelector: .auto, deloadWeeks: 0))

        XCTAssertEqual(PlannerSettings.frequencySelectorKey, "plannerFrequencySelector")
        XCTAssertEqual(PlannerSettings.deloadWeeksKey, "plannerDeloadWeeks")
        XCTAssertFalse(PlannerSettings(frequencySelector: .auto).usesFrequencySelector(programDayCount: 3))
        XCTAssertTrue(PlannerSettings(frequencySelector: .auto).usesFrequencySelector(programDayCount: 4))
        XCTAssertTrue(PlannerSettings(frequencySelector: .on).usesFrequencySelector(programDayCount: 1))
        XCTAssertFalse(PlannerSettings(frequencySelector: .off).usesFrequencySelector(programDayCount: 7))
    }

    // MARK: - Semana leve no plano (SPEC §7.5, CA4-3)

    func testCA4_3_manyDecreases_lightPass_thenPreDeloadLoadWithoutRetrigger() throws {
        let fixture = try makeFixture()
        let program = try insertSingleDayProgram(into: fixture.context)
        let now = saturdayNoon

        // SPEC P6: duas falhas seguidas na mesma carga (3 × 5 @ 40, faixa 8–12).
        let firstAt = now.addingTimeInterval(-4 * day)
        let first = try XCTUnwrap(try fixture.planner.nextPlan(now: firstAt))
        XCTAssertFalse(first.isDeload)
        XCTAssertEqual(first.exercises.first?.prescription.note, .calibrate)
        try runSession(first, startedAt: firstAt, load: 40, reps: 5, sets: 3, fixture: fixture)

        let secondAt = now.addingTimeInterval(-2 * day)
        let second = try XCTUnwrap(try fixture.planner.nextPlan(now: secondAt))
        XCTAssertFalse(second.isDeload)
        XCTAssertEqual(second.exercises.first?.prescription.note, .retry)
        try runSession(second, startedAt: secondAt, load: 40, reps: 5, sets: 3, fixture: fixture)

        // SPEC §7.5 (a): 1 de 1 exercício com `decrease` → semana leve programada.
        XCTAssertEqual(try fixture.planner.deloadStatus(now: now), .pending(trigger: .manyDecreases))
        let lightPlan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))
        XCTAssertTrue(lightPlan.isDeload)
        XCTAssertEqual(lightPlan.reason, .deload(.manyDecreases))
        XCTAssertEqual(lightPlan.programDayID, program.day.uuid)
        let lightPlanned = try XCTUnwrap(lightPlan.exercises.first)
        let light = lightPlanned.prescription
        // Normal seria `decrease` a 35 = min(↓(40 × 0,9), 40 − 2,5). Leve: ⌈0,6 × 3⌉ = 2 séries,
        // ↓(35 × 0,85) = 27,5 kg, RIR 4, meta = repMin.
        XCTAssertEqual(light.note, .deload)
        XCTAssertEqual(light.sets, 2)
        XCTAssertEqual(light.load, 27.5)
        XCTAssertEqual(light.targetRIR, 4)
        XCTAssertEqual(light.targetReps, 8)
        XCTAssertEqual(light.repMin, 8)
        XCTAssertEqual(light.repMax, 12)

        // O coordinator marca a sessão e o mapper devolve a marca: a passagem está em andamento.
        let lightSessionID = try fixture.planner.startSession(from: lightPlan, now: now)
        let stored = try XCTUnwrap(fixture.coordinator.session(withID: lightSessionID))
        XCTAssertTrue(stored.isDeload)
        XCTAssertTrue(try SessionSummaryMapper.summary(from: stored).isDeload)
        XCTAssertEqual(try fixture.planner.deloadStatus(now: now.addingTimeInterval(60)), .active(start: now))
        let during = try XCTUnwrap(try fixture.planner.nextPlan(now: now.addingTimeInterval(60)))
        XCTAssertTrue(during.isDeload)
        XCTAssertEqual(during.reason, .deload(nil))

        for index in 0..<light.sets {
            try fixture.coordinator.logSet(
                sessionID: lightSessionID,
                sessionExerciseID: lightPlanned.id,
                index: index,
                load: 27.5,
                reps: 8,
                rir: 4,
                isWarmup: false,
                now: now.addingTimeInterval(Double(index + 1) * 120)
            )
        }
        try fixture.coordinator.finishSession(sessionID: lightSessionID, now: now.addingTimeInterval(3_600))

        // Passagem completa (programa de 1 dia): volta a carga de antes, porque P3 ignora a
        // sessão leve, e as mesmas reduções não disparam outra semana leve (rearme, §7.5).
        let after = now.addingTimeInterval(2 * day)
        XCTAssertEqual(try fixture.planner.deloadStatus(now: after), .inactive)
        let normal = try XCTUnwrap(try fixture.planner.nextPlan(now: after))
        XCTAssertFalse(normal.isDeload)
        XCTAssertEqual(normal.reason, .rotation)
        let back = try XCTUnwrap(normal.exercises.first).prescription
        XCTAssertEqual(back.note, .decrease)
        XCTAssertEqual(back.load, 35)
        XCTAssertEqual(back.sets, 3)
    }

    func testD_scheduled_followsPlannerDeloadWeeks_andZeroTurnsItOff() throws {
        let fixture = try makeFixture(settings: PlannerSettings(deloadWeeks: 1))
        _ = try insertSingleDayProgram(into: fixture.context)
        let firstAt = saturdayNoon.addingTimeInterval(-8 * day)
        let first = try XCTUnwrap(try fixture.planner.nextPlan(now: firstAt))
        try runSession(first, startedAt: firstAt, load: 40, reps: 10, sets: 3, fixture: fixture)

        // SPEC §7.5 (b) com N = 1: 8 dias desde a primeira sessão.
        XCTAssertEqual(try fixture.planner.deloadStatus(now: saturdayNoon), .pending(trigger: .scheduled))
        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: saturdayNoon))
        XCTAssertTrue(plan.isDeload)
        XCTAssertEqual(plan.reason, .deload(.scheduled))

        // Com a semana leve já programada, o pedido manual não grava nada nem troca o gatilho.
        try fixture.planner.requestDeload(now: saturdayNoon)
        XCTAssertEqual(fixture.decisions.saveCount, 0)
        XCTAssertEqual(try fixture.planner.deloadStatus(now: saturdayNoon), .pending(trigger: .scheduled))

        // Padrão (6 semanas): ainda não.
        fixture.settings.value = PlannerSettings()
        XCTAssertEqual(try fixture.planner.deloadStatus(now: saturdayNoon), .inactive)

        // N = 0 desliga (b).
        fixture.settings.value = PlannerSettings(deloadWeeks: 0)
        XCTAssertEqual(try fixture.planner.deloadStatus(now: saturdayNoon), .inactive)
        XCTAssertFalse(try XCTUnwrap(try fixture.planner.nextPlan(now: saturdayNoon)).isDeload)
    }

    func testD_substitutionInsideLightSession_keepsLightPrescription() throws {
        let fixture = try makeFixture()
        _ = try insertTwoDayProgram(into: fixture.context)
        let dumbbell = insertExercise(
            slug: "supino-halteres",
            name: "Supino com halteres",
            primary: [.chest],
            equipment: .dumbbell,
            increment: 2,
            into: fixture.context
        )
        try fixture.context.save()
        try fixture.planner.requestDeload(now: saturdayNoon)
        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: saturdayNoon))
        XCTAssertTrue(plan.isDeload)
        _ = try fixture.planner.startSession(from: plan, now: saturdayNoon)
        let benchPlanned = try XCTUnwrap(plan.exercises.first)

        // Dentro da sessão leve, o substituto também é leve (SPEC §7.5).
        let swapped = try fixture.planner.substitutionPlan(
            replacing: benchPlanned.id,
            target: benchPlanned.target,
            newExerciseID: dumbbell.uuid,
            now: saturdayNoon
        )
        XCTAssertEqual(swapped.id, benchPlanned.id)
        XCTAssertEqual(swapped.prescription.note, .deload)
        XCTAssertEqual(swapped.prescription.sets, 2)
        XCTAssertEqual(swapped.prescription.targetRIR, 4)
        XCTAssertNil(swapped.prescription.load, "sem histórico nem carga inicial, a pessoa digita (P2)")

        // Fora de uma sessão leve, a troca segue a prescrição normal.
        let outside = try fixture.planner.substitutionPlan(
            replacing: UUID(),
            target: benchPlanned.target,
            newExerciseID: dumbbell.uuid,
            now: saturdayNoon
        )
        XCTAssertEqual(outside.prescription.note, .calibrate)
    }

    // MARK: - Decisões da pessoa (§7.5 c, §7.11 C1)

    func testC1_manualRequest_plansLightWeek_keepsFirstDate_andDismissRestoresNormal() throws {
        let fixture = try makeFixture()
        let program = try insertTwoDayProgram(into: fixture.context)
        let now = saturdayNoon

        try fixture.planner.requestDeload(now: now)
        XCTAssertEqual(fixture.decisions.decisions.manualRequestedAt, now)
        XCTAssertEqual(fixture.decisions.saveCount, 1)
        XCTAssertEqual(try fixture.planner.deloadStatus(now: now), .pending(trigger: .manual))

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))
        XCTAssertTrue(plan.isDeload)
        XCTAssertEqual(plan.reason, .deload(.manual))
        XCTAssertEqual(plan.programDayID, program.dayA.uuid)
        let bench = try XCTUnwrap(plan.exercises.first).prescription
        // Calibração com carga inicial 40: leve = ↓(40 × 0,85) = 32,5 kg, 2 séries, RIR 4.
        XCTAssertEqual(bench.note, .deload)
        XCTAssertEqual(bench.load, 32.5)
        XCTAssertEqual(bench.sets, 2)
        XCTAssertEqual(bench.targetRIR, 4)

        // Pedir de novo enquanto a semana leve espera não muda a data do pedido.
        try fixture.planner.requestDeload(now: now.addingTimeInterval(60))
        XCTAssertEqual(fixture.decisions.decisions.manualRequestedAt, now)
        XCTAssertEqual(fixture.decisions.saveCount, 1)

        // S4: escolher outro dia não escapa da semana leve; o motivo é a escolha da pessoa.
        let manual = try XCTUnwrap(try fixture.planner.plan(forDayID: program.dayB.uuid, now: now))
        XCTAssertEqual(manual.programDayID, program.dayB.uuid)
        XCTAssertTrue(manual.isDeload)
        XCTAssertEqual(manual.reason, .manual)
        XCTAssertEqual(manual.exercises.first?.prescription.note, .deload)

        // "Seguir normal": limpa o pedido e registra a dispensa.
        let dismissedAt = now.addingTimeInterval(120)
        try fixture.planner.dismissDeload(now: dismissedAt)
        XCTAssertNil(fixture.decisions.decisions.manualRequestedAt)
        XCTAssertEqual(fixture.decisions.decisions.dismissedAt, dismissedAt)
        XCTAssertEqual(fixture.decisions.saveCount, 2)
        XCTAssertEqual(try fixture.planner.deloadStatus(now: dismissedAt), .inactive)
        let normal = try XCTUnwrap(try fixture.planner.nextPlan(now: dismissedAt))
        XCTAssertFalse(normal.isDeload)
        XCTAssertEqual(normal.reason, .rotation)
        XCTAssertEqual(normal.exercises.first?.prescription.note, .calibrate)
        let manualAfter = try XCTUnwrap(try fixture.planner.plan(forDayID: program.dayB.uuid, now: dismissedAt))
        XCTAssertFalse(manualAfter.isDeload)
        XCTAssertEqual(manualAfter.reason, .manual)

        // Sem semana leve programada, "Seguir normal" não grava nada.
        try fixture.planner.dismissDeload(now: dismissedAt.addingTimeInterval(60))
        XCTAssertEqual(fixture.decisions.saveCount, 2)
        XCTAssertEqual(fixture.decisions.decisions.dismissedAt, dismissedAt)
    }

    func testC1_lightPassAlreadyStarted_cannotBeDismissed() throws {
        let fixture = try makeFixture()
        _ = try insertTwoDayProgram(into: fixture.context)
        let now = saturdayNoon
        try fixture.planner.requestDeload(now: now)
        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))
        let startedAt = now.addingTimeInterval(60)
        _ = try fixture.planner.startSession(from: plan, now: startedAt)
        XCTAssertEqual(try fixture.planner.deloadStatus(now: startedAt), .active(start: startedAt))

        try fixture.planner.dismissDeload(now: startedAt.addingTimeInterval(60))
        // Pedir de novo durante a passagem não emenda outra semana leve.
        try fixture.planner.requestDeload(now: startedAt.addingTimeInterval(90))

        XCTAssertEqual(fixture.decisions.saveCount, 1, "só o primeiro pedido foi gravado")
        XCTAssertEqual(fixture.decisions.decisions.manualRequestedAt, now)
        XCTAssertNil(fixture.decisions.decisions.dismissedAt)
        XCTAssertEqual(try fixture.planner.deloadStatus(now: startedAt.addingTimeInterval(120)), .active(start: startedAt))
    }

    func testC1_saveFailure_propagatesAndPlanStaysNormal() throws {
        let fixture = try makeFixture()
        _ = try insertTwoDayProgram(into: fixture.context)
        fixture.decisions.saveError = DeloadDecisionsStoreError.storageUnavailable

        XCTAssertThrowsError(try fixture.planner.requestDeload(now: saturdayNoon)) { error in
            XCTAssertEqual(error as? DeloadDecisionsStoreError, .storageUnavailable)
        }
        XCTAssertEqual(try fixture.planner.deloadStatus(now: saturdayNoon), .inactive)
        XCTAssertFalse(try XCTUnwrap(try fixture.planner.nextPlan(now: saturdayNoon)).isDeload)
    }

    func testD_withoutActiveProgram_statusInactive_andReviewInputNil() throws {
        let fixture = try makeFixture()
        XCTAssertEqual(try fixture.planner.deloadStatus(now: saturdayNoon), .inactive)
        XCTAssertNil(try fixture.planner.reviewInput(now: saturdayNoon, recovery: .unknown))
        XCTAssertEqual(try fixture.planner.completedSessionSummaries(), [])
    }

    // MARK: - Sessões concluídas e revisão (§7.8, §7.11)

    func testCompletedSessionSummaries_onlyCompleted_oldestFirst_withDeloadFlag() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let program = try insertTwoDayProgram(into: context)

        let older = insertCompletedSession(day: program.dayA, exercises: [program.bench], startedAt: monday, into: context)
        _ = insertSession(status: .abandoned, day: program.dayB, startedAt: monday.addingTimeInterval(day), into: context)
        _ = insertSession(status: .inProgress, day: program.dayA, startedAt: monday.addingTimeInterval(3 * day), into: context)
        let newer = insertCompletedSession(
            day: program.dayB,
            exercises: [program.row],
            startedAt: monday.addingTimeInterval(2 * day),
            isDeload: true,
            into: context
        )
        try context.save()

        let summaries = try fixture.planner.completedSessionSummaries()

        XCTAssertEqual(summaries.map { $0.id }, [older.uuid, newer.uuid])
        XCTAssertEqual(summaries.map { $0.isDeload }, [false, true])
        XCTAssertEqual(summaries.map { $0.workingSetCount }, [3, 3])
        XCTAssertTrue(summaries.allSatisfy { $0.status == .completed })
    }

    func testP9_finishedSessionSummaries_completedAndAbandoned_oldestFirst() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let program = try insertTwoDayProgram(into: context)

        let older = insertCompletedSession(day: program.dayA, exercises: [program.bench], startedAt: monday, into: context)
        let abandoned = insertSession(status: .abandoned, day: program.dayB, startedAt: monday.addingTimeInterval(day), into: context)
        _ = insertSession(status: .inProgress, day: program.dayA, startedAt: monday.addingTimeInterval(3 * day), into: context)
        let newer = insertCompletedSession(day: program.dayB, exercises: [program.row], startedAt: monday.addingTimeInterval(2 * day), into: context)
        try context.save()

        // SPEC P3/P9: o histórico do motor conta concluídas e abandonadas; em andamento fica fora.
        let summaries = try fixture.planner.finishedSessionSummaries()

        XCTAssertEqual(summaries.map { $0.id }, [older.uuid, abandoned.uuid, newer.uuid])
        XCTAssertEqual(summaries.map { $0.status }, [.completed, .abandoned, .completed])
    }

    func testR_reviewInput_activeProgramSessionsOnly_andLightPrescriptionsDuringLightWeek() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let program = try insertTwoDayProgram(into: context)
        // Sessão de um programa inativo: entra no histórico do supino (é por exercício, SPEC §7.1)
        // mas não nas sessões do programa ativo (R4).
        let other = insertProgram(name: "Antigo", isActive: false, createdAt: monday.addingTimeInterval(-90 * day), into: context)
        let otherDay = insertDay(name: "Dia X", order: 0, program: other, into: context)
        _ = insertCompletedSession(day: otherDay, exercises: [program.bench], startedAt: monday, into: context)
        let sessionA = insertCompletedSession(
            day: program.dayA,
            exercises: [program.bench],
            startedAt: monday.addingTimeInterval(day + 10 * 3_600),
            into: context
        )
        try context.save()

        let recovery = RecoveryContext(hrvDropped: true, hasData: true)
        let input = try XCTUnwrap(try fixture.planner.reviewInput(now: saturdayNoon, recovery: recovery))

        XCTAssertEqual(input.programID, program.program.uuid)
        XCTAssertEqual(input.programName, "AB")
        XCTAssertEqual(input.programDayCount, 2)
        XCTAssertEqual(input.programStartDate, sessionA.startedAt)
        XCTAssertEqual(input.sessions.map { $0.id }, [sessionA.uuid])
        XCTAssertEqual(input.weeklySetTarget, 10...20, "SPEC §7.9: hipertrofia")
        XCTAssertEqual(input.recovery, recovery)
        XCTAssertTrue(input.weekStartsOnMonday)
        XCTAssertEqual(Set(input.exercises.map { $0.targetID }), [program.benchTarget.uuid, program.rowTarget.uuid])
        let benchInput = try XCTUnwrap(input.exercises.first { $0.exercise.id == program.bench.uuid })
        XCTAssertEqual(benchInput.dayID, program.dayA.uuid)
        XCTAssertEqual(benchInput.sets, 3)
        XCTAssertEqual(benchInput.repMin, 8)
        XCTAssertEqual(benchInput.repMax, 12)
        XCTAssertEqual(benchInput.history.count, 2)
        // Supino 3 × 10 dentro da faixa → hold; remada sem histórico → calibrate.
        XCTAssertEqual(
            input.currentPrescriptions.map { $0.note.rawValue }.sorted(),
            [PrescriptionNote.calibrate.rawValue, PrescriptionNote.hold.rawValue]
        )

        // Semana leve programada: a revisão recebe as prescrições leves e não sugere outra.
        try fixture.planner.requestDeload(now: saturdayNoon)
        let light = try XCTUnwrap(try fixture.planner.reviewInput(now: saturdayNoon, recovery: recovery))
        XCTAssertEqual(light.currentPrescriptions.map { $0.note }, [.deload, .deload])
    }

    // MARK: - Fixtures

    /// Ajustes mutáveis dentro de um teste; a closure do planejador lê o valor atual.
    private final class SettingsBox {
        var value: PlannerSettings

        init(_ value: PlannerSettings) {
            self.value = value
        }
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let coordinator: SessionCoordinator
        let decisions: FakeDeloadDecisionsStore
        let settings: SettingsBox
        let planner: SessionPlanner
    }

    private func makeFixture(settings: PlannerSettings = PlannerSettings()) throws -> Fixture {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let coordinator = SessionCoordinator(modelContext: context, appliedEvents: AppliedEventStore.inMemory())
        let decisions = FakeDeloadDecisionsStore()
        let box = SettingsBox(settings)
        let planner = SessionPlanner(
            modelContext: context,
            coordinator: coordinator,
            deloadDecisions: decisions,
            settings: { box.value },
            calendar: calendar
        )
        return Fixture(
            container: container,
            context: context,
            coordinator: coordinator,
            decisions: decisions,
            settings: box,
            planner: planner
        )
    }

    /// A = peito (supino), B = costas (remada), C = quadríceps + posteriores (agachamento e
    /// flexora); com `includeShoulderDay`, D = ombros (elevação lateral).
    private struct FrequencyProgram {
        let program: ProgramModel
        let dayA: ProgramDayModel
        let dayB: ProgramDayModel
        let dayC: ProgramDayModel
        let bench: ExerciseModel
        let row: ExerciseModel
    }

    private func insertFrequencyProgram(
        includeShoulderDay: Bool = false,
        into context: ModelContext
    ) throws -> FrequencyProgram {
        let bench = insertExercise(slug: "supino-reto", name: "Supino reto", primary: [.chest], equipment: .barbell, increment: 2.5, into: context)
        let row = insertExercise(slug: "remada-baixa", name: "Remada baixa", primary: [.back], equipment: .machine, increment: 5, into: context)
        let squat = insertExercise(slug: "agachamento", name: "Agachamento", primary: [.quads], equipment: .barbell, increment: 2.5, into: context)
        let legCurl = insertExercise(slug: "flexora", name: "Mesa flexora", primary: [.hamstrings], equipment: .machine, increment: 5, into: context)

        let program = insertProgram(name: "Frequência", isActive: true, createdAt: monday.addingTimeInterval(-60 * day), into: context)
        let dayA = insertDay(name: "Dia A", order: 0, program: program, into: context)
        let dayB = insertDay(name: "Dia B", order: 1, program: program, into: context)
        let dayC = insertDay(name: "Dia C", order: 2, program: program, into: context)
        insertProgramExercise(order: 0, exercise: bench, startingLoad: 40, day: dayA, into: context)
        insertProgramExercise(order: 0, exercise: row, startingLoad: 30, day: dayB, into: context)
        insertProgramExercise(order: 0, exercise: squat, startingLoad: nil, day: dayC, into: context)
        insertProgramExercise(order: 1, exercise: legCurl, startingLoad: nil, day: dayC, into: context)
        if includeShoulderDay {
            let raise = insertExercise(slug: "elevacao-lateral", name: "Elevação lateral", primary: [.shoulders], equipment: .dumbbell, increment: 2, into: context)
            let dayD = insertDay(name: "Dia D", order: 3, program: program, into: context)
            insertProgramExercise(order: 0, exercise: raise, startingLoad: nil, day: dayD, into: context)
        }
        try context.save()
        return FrequencyProgram(program: program, dayA: dayA, dayB: dayB, dayC: dayC, bench: bench, row: row)
    }

    /// Semana até sábado: A na segunda, B na terça e A na quarta, sempre às 10:00 UTC, com
    /// 3 × 10 a 40 kg. Peito 2/2, costas 1/2, pernas 0/2; nada nas 48 h antes de sábado 12:00.
    private func insertFrequencyWeek(_ program: FrequencyProgram, into context: ModelContext) throws {
        let tenAM: TimeInterval = 10 * 3_600
        _ = insertCompletedSession(day: program.dayA, exercises: [program.bench], startedAt: monday.addingTimeInterval(tenAM), into: context)
        _ = insertCompletedSession(day: program.dayB, exercises: [program.row], startedAt: monday.addingTimeInterval(day + tenAM), into: context)
        _ = insertCompletedSession(day: program.dayA, exercises: [program.bench], startedAt: monday.addingTimeInterval(2 * day + tenAM), into: context)
        try context.save()
    }

    /// Um dia, um exercício: supino (barra, inc 2,5, carga inicial 40, 3 × 8–12, RIR 2).
    private struct SingleDayProgram {
        let program: ProgramModel
        let day: ProgramDayModel
        let bench: ExerciseModel
    }

    private func insertSingleDayProgram(into context: ModelContext) throws -> SingleDayProgram {
        let bench = insertExercise(slug: "supino-reto", name: "Supino reto", primary: [.chest], equipment: .barbell, increment: 2.5, into: context)
        let program = insertProgram(name: "Um dia", isActive: true, createdAt: monday.addingTimeInterval(-60 * day), into: context)
        let dayA = insertDay(name: "Dia A", order: 0, program: program, into: context)
        insertProgramExercise(order: 0, exercise: bench, startingLoad: 40, day: dayA, into: context)
        try context.save()
        return SingleDayProgram(program: program, day: dayA, bench: bench)
    }

    /// "AB": Dia A = supino (carga inicial 40, inc 2,5); Dia B = remada (carga inicial 30, inc 5).
    private struct TwoDayProgram {
        let program: ProgramModel
        let dayA: ProgramDayModel
        let dayB: ProgramDayModel
        let bench: ExerciseModel
        let row: ExerciseModel
        let benchTarget: ProgramExerciseModel
        let rowTarget: ProgramExerciseModel
    }

    private func insertTwoDayProgram(into context: ModelContext) throws -> TwoDayProgram {
        let bench = insertExercise(slug: "supino-reto", name: "Supino reto", primary: [.chest], equipment: .barbell, increment: 2.5, into: context)
        let row = insertExercise(slug: "remada-baixa", name: "Remada baixa", primary: [.back], equipment: .machine, increment: 5, into: context)
        let program = insertProgram(name: "AB", isActive: true, createdAt: monday.addingTimeInterval(-60 * day), into: context)
        let dayA = insertDay(name: "Dia A", order: 0, program: program, into: context)
        let dayB = insertDay(name: "Dia B", order: 1, program: program, into: context)
        let benchTarget = insertProgramExercise(order: 0, exercise: bench, startingLoad: 40, day: dayA, into: context)
        let rowTarget = insertProgramExercise(order: 0, exercise: row, startingLoad: 30, day: dayB, into: context)
        try context.save()
        return TwoDayProgram(
            program: program,
            dayA: dayA,
            dayB: dayB,
            bench: bench,
            row: row,
            benchTarget: benchTarget,
            rowTarget: rowTarget
        )
    }

    /// Executa o plano pelo caminho oficial (ARCHITECTURE §7): inicia, registra `sets` séries de
    /// trabalho em cada exercício e finaliza uma hora depois.
    @discardableResult
    private func runSession(
        _ plan: SessionPlan,
        startedAt: Date,
        load: Double,
        reps: Int,
        sets: Int,
        fixture: Fixture
    ) throws -> UUID {
        let sessionID = try fixture.planner.startSession(from: plan, now: startedAt)
        for planned in plan.exercises {
            for index in 0..<sets {
                try fixture.coordinator.logSet(
                    sessionID: sessionID,
                    sessionExerciseID: planned.id,
                    index: index,
                    load: load,
                    reps: reps,
                    rir: 2,
                    isWarmup: false,
                    now: startedAt.addingTimeInterval(Double(index + 1) * 120)
                )
            }
        }
        try fixture.coordinator.finishSession(sessionID: sessionID, now: startedAt.addingTimeInterval(3_600))
        return sessionID
    }

    private func insertExercise(
        slug: String,
        name: String,
        primary: [MuscleGroup],
        equipment: Equipment,
        increment: Double,
        into context: ModelContext
    ) -> ExerciseModel {
        let model = ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: name,
            primaryMusclesRaw: CurrentSchema.encodeMuscleGroups(primary),
            secondaryMusclesRaw: "",
            equipmentRaw: equipment.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: increment,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        context.insert(model)
        return model
    }

    private func insertProgram(
        name: String,
        isActive: Bool,
        createdAt: Date,
        into context: ModelContext
    ) -> ProgramModel {
        let model = ProgramModel(uuid: UUID(), name: name, isActive: isActive, createdAt: createdAt)
        context.insert(model)
        return model
    }

    private func insertDay(
        name: String,
        order: Int,
        program: ProgramModel,
        into context: ModelContext
    ) -> ProgramDayModel {
        let model = ProgramDayModel(uuid: UUID(), name: name, order: order)
        context.insert(model)
        program.days.append(model)
        return model
    }

    @discardableResult
    private func insertProgramExercise(
        order: Int,
        exercise: ExerciseModel,
        startingLoad: Double?,
        day: ProgramDayModel,
        into context: ModelContext
    ) -> ProgramExerciseModel {
        let model = ProgramExerciseModel(
            uuid: UUID(),
            order: order,
            sets: 3,
            repMin: 8,
            repMax: 12,
            targetRIR: 2,
            restSeconds: 120,
            startingLoad: startingLoad
        )
        context.insert(model)
        model.exercise = exercise
        day.exercises.append(model)
        return model
    }

    private func insertSession(
        status: SessionStatus,
        day: ProgramDayModel,
        startedAt: Date,
        isDeload: Bool = false,
        into context: ModelContext
    ) -> WorkoutSessionModel {
        let model = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: day.uuid,
            programDayName: day.name,
            statusRaw: status.rawValue,
            startedAt: startedAt,
            endedAt: status == .inProgress ? nil : startedAt.addingTimeInterval(3_600),
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: isDeload,
            sourceRaw: DeviceSource.iphone.rawValue
        )
        context.insert(model)
        return model
    }

    /// Sessão concluída com 3 × 10 a 40 kg (RIR 2) em cada exercício, que ficam relacionados ao
    /// catálogo para o `SessionSummaryMapper` achar os grupos primários (SPEC §7.4).
    private func insertCompletedSession(
        day: ProgramDayModel,
        exercises: [ExerciseModel],
        startedAt: Date,
        isDeload: Bool = false,
        into context: ModelContext
    ) -> WorkoutSessionModel {
        let session = insertSession(status: .completed, day: day, startedAt: startedAt, isDeload: isDeload, into: context)
        for (order, exercise) in exercises.enumerated() {
            let sessionExercise = SessionExerciseModel(
                uuid: UUID(),
                order: order,
                exerciseUUID: exercise.uuid,
                exerciseName: exercise.name,
                prescribedLoad: 40,
                prescribedSets: 3,
                prescribedRepMin: 8,
                prescribedRepMax: 12,
                prescribedRIR: 2,
                restSeconds: 120,
                noteRaw: PrescriptionNote.hold.rawValue,
                wasSkipped: false,
                substitutedFromUUID: nil
            )
            context.insert(sessionExercise)
            sessionExercise.exercise = exercise
            session.exercises.append(sessionExercise)
            for index in 0..<3 {
                let completedAt = startedAt.addingTimeInterval(Double(order * 3 + index + 1) * 120)
                let setLog = SetLogModel(
                    uuid: UUID(),
                    index: index,
                    load: 40,
                    reps: 10,
                    rir: 2,
                    isWarmup: false,
                    completedAt: completedAt,
                    sourceRaw: DeviceSource.iphone.rawValue,
                    updatedAt: completedAt
                )
                context.insert(setLog)
                sessionExercise.sets.append(setLog)
            }
        }
        return session
    }
}
