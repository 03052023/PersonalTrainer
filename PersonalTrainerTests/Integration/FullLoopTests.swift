import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T1.11 (CA1-5): o loop completo do M1 sobre os componentes reais — `SeedLoader` →
/// `SessionPlanner` → `SessionCoordinator` → `HistoryMapper` → `SessionPlanner` — em container
/// in-memory, tudo em `@MainActor` (ARCHITECTURE §10). O relógio é um valor fixo que avança
/// explicitamente entre ações (SPEC P11); nada aqui lê `Date()`.
///
/// Os JSON do seed vêm de `Bundle.main`, o bundle do app hospedeiro dos testes (mesma premissa
/// de `SeedLoaderTests`).
@MainActor
final class FullLoopTests: XCTestCase {
    /// Data de referência fixa; cada sessão termina e o relógio avança um dia.
    private var clock = Date(timeIntervalSince1970: 1_758_600_000)

    // MARK: - SPEC P4 + S2: rotação completa e subida de carga

    func testP4_threeSetsAtRepMax_afterFullRotation_dayAIncreasesByOneIncrement() throws {
        let harness = try makeHarness()
        let days = try programDays(in: harness)
        XCTAssertEqual(days.count, 3, "o seed padrão tem Dia A, B e C")

        // Plano A em instalação limpa: primeiro exercício sem carga (SPEC P2, sem `startingLoad`).
        let planA = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        XCTAssertEqual(planA.programDayID, days[0].uuid)
        XCTAssertFalse(planA.exercises.isEmpty)
        let first = try XCTUnwrap(planA.exercises.first)
        XCTAssertEqual(first.prescription.note, .calibrate)
        XCTAssertNil(first.prescription.load)
        let increment = first.exercise.loadIncrement

        // 3 séries no topo da faixa a 40 kg, RIR 2 → sucesso (P4) na próxima vez que A voltar.
        let sessionA = try performSession(
            planA,
            firstExercise: FirstExerciseScript(sets: 3, reps: first.prescription.repMax, load: 40, rir: 2),
            in: harness
        )
        let storedA = try XCTUnwrap(harness.coordinator.session(withID: sessionA))
        XCTAssertEqual(storedA.status, .completed)
        XCTAssertNotNil(storedA.endedAt)
        XCTAssertNil(harness.coordinator.activeSession)

        // SPEC S2: depois de A vem B; depois de B, C; depois de C, A de novo.
        let planB = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        XCTAssertEqual(planB.programDayID, days[1].uuid)
        try performSession(planB, firstExercise: nil, in: harness)

        let planC = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        XCTAssertEqual(planC.programDayID, days[2].uuid)
        try performSession(planC, firstExercise: nil, in: harness)

        let planA2 = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        XCTAssertEqual(planA2.programDayID, days[0].uuid)
        let firstAgain = try XCTUnwrap(planA2.exercises.first)
        XCTAssertEqual(firstAgain.exercise.id, first.exercise.id)
        // SPEC P4: L + inc, meta = repMin, nota increase (RIR 2 não chega a T + 2 para o dobro).
        XCTAssertEqual(firstAgain.prescription.note, .increase)
        XCTAssertEqual(firstAgain.prescription.load, Load.round(40, toIncrement: increment) + increment)
        XCTAssertEqual(firstAgain.prescription.targetReps, first.prescription.repMin)
    }

    // MARK: - SPEC P5: reps dentro da faixa mantêm a carga e sobem a meta

    func testP5_repsInsideRange_afterFullRotation_dayAHoldsLoadAndRaisesTarget() throws {
        let harness = try makeHarness()
        let days = try programDays(in: harness)

        let planA = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        XCTAssertEqual(planA.programDayID, days[0].uuid)
        let first = try XCTUnwrap(planA.exercises.first)
        let increment = first.exercise.loadIncrement
        // Acima de repMin e abaixo de repMax em todas as séries: nem sucesso (P4) nem falha (P6).
        let holdingReps = first.prescription.repMin + 1
        XCTAssertLessThan(holdingReps, first.prescription.repMax, "a faixa do seed precisa ter ao menos 3 valores")

        try performSession(
            planA,
            firstExercise: FirstExerciseScript(sets: 3, reps: holdingReps, load: 40, rir: 2),
            in: harness
        )
        try performSession(try XCTUnwrap(try harness.planner.nextPlan(now: clock)), firstExercise: nil, in: harness)
        try performSession(try XCTUnwrap(try harness.planner.nextPlan(now: clock)), firstExercise: nil, in: harness)

        let planA2 = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        XCTAssertEqual(planA2.programDayID, days[0].uuid)
        let firstAgain = try XCTUnwrap(planA2.exercises.first)
        XCTAssertEqual(firstAgain.exercise.id, first.exercise.id)
        // SPEC P5: carga = L, meta = min(repMax, menor reps da última sessão + 1), nota hold.
        XCTAssertEqual(firstAgain.prescription.note, .hold)
        XCTAssertEqual(firstAgain.prescription.load, Load.round(40, toIncrement: increment))
        XCTAssertEqual(firstAgain.prescription.targetReps, min(first.prescription.repMax, holdingReps + 1))
    }

    // MARK: - CA1-6: exercício pulado sem séries não altera a prescrição futura

    func testCA16_skippedExerciseWithoutSets_afterFullRotation_dayAStillCalibrates() throws {
        let harness = try makeHarness()
        let days = try programDays(in: harness)

        let planA = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        let first = try XCTUnwrap(planA.exercises.first)
        XCTAssertEqual(first.prescription.note, .calibrate)
        XCTAssertNil(first.prescription.load)

        // Máquina ocupada (SPEC F3, RF-10): o primeiro exercício é pulado sem nenhuma série.
        let sessionA = try performSession(planA, firstExercise: nil, skippingFirstExercise: true, in: harness)
        let storedA = try XCTUnwrap(harness.coordinator.session(withID: sessionA))
        XCTAssertEqual(storedA.status, .completed)
        let skipped = try XCTUnwrap(storedA.exercises.first { $0.uuid == first.id })
        XCTAssertTrue(skipped.wasSkipped)
        XCTAssertTrue(skipped.sets.isEmpty)

        // Os demais exercícios têm série de trabalho, então a rotação segue (SPEC S2) e o
        // histórico do exercício pulado continua vazio.
        let planB = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        XCTAssertEqual(planB.programDayID, days[1].uuid)
        try performSession(planB, firstExercise: nil, in: harness)
        try performSession(try XCTUnwrap(try harness.planner.nextPlan(now: clock)), firstExercise: nil, in: harness)

        let planA2 = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        XCTAssertEqual(planA2.programDayID, days[0].uuid)
        let firstAgain = try XCTUnwrap(planA2.exercises.first)
        XCTAssertEqual(firstAgain.exercise.id, first.exercise.id)
        // SPEC P7: sessão com 0 séries de trabalho é ignorada; sem histórico vale P2 de novo.
        XCTAssertEqual(firstAgain.prescription.note, .calibrate)
        XCTAssertNil(firstAgain.prescription.load)
        XCTAssertEqual(firstAgain.prescription.targetReps, first.prescription.targetReps)
        XCTAssertEqual(firstAgain.prescription.targetRIR, first.prescription.targetRIR)
    }

    // MARK: - SPEC P6: falha repetida na mesma carga

    func testP6_twoConsecutiveFailuresAtSameLoad_afterTwoRotations_dayADecreases() throws {
        let harness = try makeHarness()
        let days = try programDays(in: harness)

        let planA1 = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        XCTAssertEqual(planA1.programDayID, days[0].uuid)
        let first = try XCTUnwrap(planA1.exercises.first)
        let increment = first.exercise.loadIncrement
        let failingReps = first.prescription.repMin - 2
        let failure = FirstExerciseScript(sets: 3, reps: failingReps, load: 40, rir: 2)

        // Primeira passagem: A falha; B e C só mantêm a rotação andando.
        try performSession(planA1, firstExercise: failure, in: harness)
        try performSession(try XCTUnwrap(try harness.planner.nextPlan(now: clock)), firstExercise: nil, in: harness)
        try performSession(try XCTUnwrap(try harness.planner.nextPlan(now: clock)), firstExercise: nil, in: harness)

        // SPEC P6, primeira ocorrência: mesma carga, meta repMin, nota retry.
        let planA2 = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        XCTAssertEqual(planA2.programDayID, days[0].uuid)
        let firstA2 = try XCTUnwrap(planA2.exercises.first)
        XCTAssertEqual(firstA2.prescription.note, .retry)
        XCTAssertEqual(firstA2.prescription.load, Load.round(40, toIncrement: increment))
        XCTAssertEqual(firstA2.prescription.targetReps, first.prescription.repMin)

        // Segunda passagem: A falha de novo na mesma carga.
        try performSession(planA2, firstExercise: failure, in: harness)
        try performSession(try XCTUnwrap(try harness.planner.nextPlan(now: clock)), firstExercise: nil, in: harness)
        try performSession(try XCTUnwrap(try harness.planner.nextPlan(now: clock)), firstExercise: nil, in: harness)

        // SPEC P6, segunda ocorrência: min(arredondar↓(L × 0,9, inc), L − inc), respeitando P8.
        let planA3 = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        XCTAssertEqual(planA3.programDayID, days[0].uuid)
        let firstA3 = try XCTUnwrap(planA3.exercises.first)
        XCTAssertEqual(firstA3.exercise.id, first.exercise.id)
        XCTAssertEqual(firstA3.prescription.note, .decrease)
        let expected = max(min(Load.round(36, toIncrement: increment), 40 - increment), increment)
        XCTAssertEqual(firstA3.prescription.load, expected)
        XCTAssertEqual(firstA3.prescription.targetReps, first.prescription.repMin)
    }

    // MARK: - RF-02: só uma sessão em andamento

    func testRF02_startSessionWhileAnotherIsInProgress_throwsSessionAlreadyInProgress() throws {
        let harness = try makeHarness()
        let plan = try XCTUnwrap(try harness.planner.nextPlan(now: clock))

        let activeID = try harness.planner.startSession(from: plan, now: clock)
        // CA1-4: é isto que faz a Home mostrar "Retomar treino" ao relançar o app.
        XCTAssertEqual(harness.coordinator.activeSession?.uuid, activeID)

        XCTAssertThrowsError(try harness.planner.startSession(from: plan, now: clock)) { error in
            XCTAssertEqual(error as? PlanningError, .sessionAlreadyInProgress(activeID))
        }
        XCTAssertEqual(try harness.context.fetchCount(FetchDescriptor<WorkoutSessionModel>()), 1)
        XCTAssertEqual(harness.coordinator.activeSession?.uuid, activeID)

        // S3 é de quem chama: o planejador continua propondo o mesmo dia enquanto a sessão corre.
        let planWhileActive = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        XCTAssertEqual(planWhileActive.programDayID, plan.programDayID)
    }

    // MARK: - SPEC F4: finalizar limpa a sessão ativa e alimenta histórico e plano

    func testF4_finish_clearsActiveSessionAndUpdatesHistoryAndNextPlan() throws {
        let harness = try makeHarness()
        let days = try programDays(in: harness)
        let planA = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        let first = try XCTUnwrap(planA.exercises.first)
        let repMax = first.prescription.repMax

        let sessionID = try performSession(
            planA,
            firstExercise: FirstExerciseScript(sets: 3, reps: repMax, load: 40, rir: 2),
            in: harness
        )

        XCTAssertNil(harness.coordinator.activeSession)
        let session = try XCTUnwrap(harness.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.programDayUUID, planA.programDayID)
        XCTAssertEqual(session.programDayName, planA.programDayName)
        XCTAssertEqual(session.exercises.count, planA.exercises.count)

        // Histórico do primeiro exercício, como o planejador o lê (ARCHITECTURE §6).
        let exerciseUUID = first.exercise.id
        let descriptor = FetchDescriptor<SessionExerciseModel>(
            predicate: #Predicate<SessionExerciseModel> { $0.exerciseUUID == exerciseUUID }
        )
        let sessionExercises = try harness.context.fetch(descriptor)
        let entries = try HistoryMapper.historyEntries(from: sessionExercises, exerciseUUID: exerciseUUID)
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.sessionID, sessionID)
        XCTAssertFalse(entry.wasDeload)
        XCTAssertEqual(entry.sets.count, 3)
        XCTAssertEqual(entry.sets.map(\.load), [40, 40, 40])
        XCTAssertEqual(entry.sets.map(\.reps), [repMax, repMax, repMax])
        XCTAssertEqual(entry.sets.map(\.rir), [2, 2, 2])
        XCTAssertTrue(entry.sets.allSatisfy { !$0.isWarmup })

        // Resumo do seletor e totais do resumo de sessão (RF-12): 3 séries no primeiro
        // exercício + 1 em cada um dos demais, todas de trabalho.
        let otherCount = planA.exercises.count - 1
        let summary = try SessionSummaryMapper.summary(from: session)
        XCTAssertEqual(summary.status, .completed)
        XCTAssertEqual(summary.workingSetCount, 3 + otherCount)

        let stats = SessionStats.compute(
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            exerciseSets: session.exercises
                .sorted { $0.order < $1.order }
                .map { exercise in
                    exercise.sets
                        .sorted { $0.index < $1.index }
                        .map { HistoryMapper.setResult(from: $0) }
                }
        )
        XCTAssertEqual(stats.workingSetCount, 3 + otherCount)
        XCTAssertEqual(stats.warmupSetCount, 0)
        XCTAssertEqual(stats.exerciseCount, planA.exercises.count)
        let othersTonnage = planA.exercises.dropFirst().reduce(0.0) { partial, planned in
            partial + 20 * Double(planned.prescription.repMin)
        }
        XCTAssertEqual(stats.tonnage, 3 * 40 * Double(repMax) + othersTonnage, accuracy: 0.001)
        XCTAssertNotNil(stats.duration)

        // O histórico da UI mostra a sessão (não é `inProgress`), o próximo plano é o Dia B e
        // pedir o Dia A à mão (SPEC S4) já reflete P4.
        XCTAssertEqual(HistoryListView.filterVisible([session]).map(\.uuid), [sessionID])
        let next = try XCTUnwrap(try harness.planner.nextPlan(now: clock))
        XCTAssertEqual(next.programDayID, days[1].uuid)
        let dayAAgain = try XCTUnwrap(try harness.planner.plan(forDayID: days[0].uuid, now: clock))
        let firstAgain = try XCTUnwrap(dayAAgain.exercises.first)
        XCTAssertEqual(firstAgain.prescription.note, .increase)
    }

    // MARK: - Harness

    private struct Harness {
        let container: ModelContainer
        let context: ModelContext
        let coordinator: SessionCoordinator
        let planner: SessionPlanner
    }

    /// Container in-memory com o seed do bundle já aplicado, coordinator e planner reais.
    private func makeHarness() throws -> Harness {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let report = try SeedLoader.loadIfNeeded(context: context, bundle: .main, now: clock)
        XCTAssertEqual(report.insertedPrograms, 1)
        XCTAssertFalse(report.skipped)
        let coordinator = SessionCoordinator(modelContext: context, appliedEvents: AppliedEventStore.inMemory())
        let planner = SessionPlanner(modelContext: context, coordinator: coordinator)
        return Harness(container: container, context: context, coordinator: coordinator, planner: planner)
    }

    /// Dias do programa ativo em ordem de `order` (SPEC S1).
    private func programDays(in harness: Harness) throws -> [ProgramDayModel] {
        let programs = try harness.context.fetch(FetchDescriptor<ProgramModel>())
        let program = try XCTUnwrap(programs.first(where: { $0.isActive }))
        return program.days.sorted { $0.order < $1.order }
    }

    /// Como registrar o primeiro exercício do plano. `nil` = igual aos demais (1 série leve).
    private struct FirstExerciseScript {
        let sets: Int
        let reps: Int
        let load: Double
        let rir: Int?
    }

    /// Executa uma sessão inteira do plano pelo caminho oficial (ARCHITECTURE §7): inicia,
    /// registra as séries (primeiro exercício conforme `script`; os demais 1 série de trabalho a
    /// 20 kg com `repMin` reps, RIR 2), finaliza e avança o relógio um dia — bem dentro dos
    /// 21 dias de SPEC P9. Com `skippingFirstExercise`, o primeiro exercício é pulado (RF-10)
    /// sem registrar série alguma e `script` é ignorado.
    @discardableResult
    private func performSession(
        _ plan: SessionPlan,
        firstExercise script: FirstExerciseScript?,
        skippingFirstExercise: Bool = false,
        in harness: Harness
    ) throws -> UUID {
        let sessionID = try harness.planner.startSession(from: plan, now: clock)
        XCTAssertEqual(harness.coordinator.activeSession?.uuid, sessionID)

        for (position, planned) in plan.exercises.enumerated() {
            if position == 0, skippingFirstExercise {
                clock = clock.addingTimeInterval(60)
                try harness.coordinator.skipExercise(sessionID: sessionID, sessionExerciseID: planned.id, now: clock)
                continue
            }
            let effective = (position == 0 ? script : nil)
                ?? FirstExerciseScript(sets: 1, reps: planned.prescription.repMin, load: 20, rir: 2)
            for index in 0..<max(0, effective.sets) {
                clock = clock.addingTimeInterval(180)
                try harness.coordinator.logSet(
                    sessionID: sessionID,
                    sessionExerciseID: planned.id,
                    index: index,
                    load: effective.load,
                    reps: effective.reps,
                    rir: effective.rir,
                    isWarmup: false,
                    now: clock
                )
            }
        }

        clock = clock.addingTimeInterval(300)
        try harness.coordinator.finishSession(sessionID: sessionID, now: clock)
        clock = clock.addingTimeInterval(86_400)
        return sessionID
    }
}
