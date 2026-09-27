import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T7.1: a ficha da sessão (SPEC RF-44, RF-04, RF-46, RF-10, RF-19, RF-34, RF-47; docs/V22-CONTRACT.md
/// §3.1). Cobre o que cada toque grava (bolinha, "Feito", "Marcar como feitos, como previsto"), a
/// primeira vez com carga, o peso do corpo sem carga, o "A seguir" do descanso, o "Concluir" com e
/// sem pendentes, pular, trocar, corrigir e apagar série, e o resumo.
///
/// Usa doubles próprios (`SessionTestCoordinator`, `SessionTestPlanner`) sobre um container
/// in-memory: o coordinator e o planner reais têm testes próprios. Tudo em `@MainActor`
/// (ARCHITECTURE §10).
@MainActor
final class ActiveSessionViewModelTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    /// Relógio injetado no ViewModel; cada teste avança como precisar (SPEC P11).
    private var clock = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Estado inicial

    func testInit_ordersExercisesAndPointsCurrentToFirstPending() throws {
        let fixture = try makeFixture()

        let model = makeViewModel(fixture)

        XCTAssertEqual(model.exercises.map(\.uuid), [fixture.legPress.uuid, fixture.bench.uuid], "ordenado por `order`, não por inserção")
        XCTAssertEqual(model.currentExerciseID, fixture.legPress.uuid)
        XCTAssertEqual(model.pendingExercises.map(\.uuid), [fixture.legPress.uuid, fixture.bench.uuid])
        XCTAssertTrue(model.isOpen)
        XCTAssertFalse(model.isFinished)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.session?.uuid, fixture.session.uuid)
        XCTAssertEqual(model.markCount, 0)
        XCTAssertNil(model.restNextUpText, "sem descanso marcado, sem \"A seguir\"")
        XCTAssertFalse(model.isShowingSubstituteSheet)
        XCTAssertNil(model.editingSet)
    }

    func testCurrent_skipsCompletedExerciseAndIgnoresWarmups() throws {
        let fixture = try makeFixture()
        // Aquecimento antigo não conta (SPEC P1): 1 aquecimento + 3 de trabalho = completo.
        insertSet(fixture, exercise: fixture.legPress, index: 0, load: 60, reps: 12, rir: nil, isWarmup: true)
        insertSet(fixture, exercise: fixture.legPress, index: 1, load: 100, reps: 10, rir: 2, isWarmup: false)
        insertSet(fixture, exercise: fixture.legPress, index: 2, load: 100, reps: 10, rir: 2, isWarmup: false)
        insertSet(fixture, exercise: fixture.legPress, index: 3, load: 100, reps: 9, rir: 1, isWarmup: false)
        try fixture.coordinator.context.save()

        let model = makeViewModel(fixture)

        XCTAssertEqual(model.currentExerciseID, fixture.bench.uuid)
        XCTAssertTrue(model.isDone(fixture.legPress))
        XCTAssertEqual(model.pendingExercises.map(\.uuid), [fixture.bench.uuid])
        XCTAssertEqual(model.workingSets(of: fixture.legPress).map(\.index), [1, 2, 3], "só as de trabalho, na ordem")
    }

    func testCurrent_onlyWarmups_isStillPending() throws {
        let fixture = try makeFixture()
        insertSet(fixture, exercise: fixture.legPress, index: 0, load: 60, reps: 12, rir: nil, isWarmup: true)
        insertSet(fixture, exercise: fixture.legPress, index: 1, load: 80, reps: 8, rir: nil, isWarmup: true)
        insertSet(fixture, exercise: fixture.legPress, index: 2, load: 90, reps: 5, rir: nil, isWarmup: true)
        try fixture.coordinator.context.save()

        let model = makeViewModel(fixture)

        XCTAssertEqual(model.currentExerciseID, fixture.legPress.uuid)
        XCTAssertEqual(model.workingSetCount(of: fixture.legPress), 0)
        XCTAssertEqual(model.workingLoad(for: fixture.legPress), 100, "aquecimento não vira a carga da próxima bolinha")
    }

    func testCurrent_nothingPending_isNil() throws {
        let fixture = try makeFixture()
        insertSet(fixture, exercise: fixture.legPress, index: 0, load: 100, reps: 10, rir: 2, isWarmup: false)
        insertSet(fixture, exercise: fixture.legPress, index: 1, load: 100, reps: 10, rir: 2, isWarmup: false)
        insertSet(fixture, exercise: fixture.legPress, index: 2, load: 100, reps: 10, rir: 2, isWarmup: false)
        fixture.bench.wasSkipped = true
        try fixture.coordinator.context.save()

        let model = makeViewModel(fixture)

        XCTAssertNil(model.currentExerciseID)
        XCTAssertTrue(model.pendingExercises.isEmpty)
        XCTAssertFalse(model.isDone(fixture.bench), "pulado não é feito")
    }

    func testInit_unknownSession_setsErrorMessage() throws {
        let fixture = try makeFixture()

        let model = ActiveSessionViewModel(
            sessionID: UUID(),
            coordinator: fixture.coordinator,
            planner: fixture.planner,
            restTimer: fixture.timer,
            notifications: FakeNotificationScheduler(),
            now: { self.clock }
        )

        XCTAssertNil(model.session)
        XCTAssertEqual(model.errorMessage, "Sessão não encontrada.")
        XCTAssertTrue(model.isShowingError)
        XCTAssertTrue(model.exercises.isEmpty)
        XCTAssertNil(model.currentExerciseID)
        XCTAssertEqual(model.stats.workingSetCount, 0)
        XCTAssertFalse(model.isFinished)
        XCTAssertFalse(model.isOpen)
    }

    func testInit_finishedSession_isFinishedAndClosed() throws {
        let fixture = try makeFixture()
        fixture.session.statusRaw = SessionStatus.completed.rawValue
        fixture.session.endedAt = start.addingTimeInterval(3_600)
        try fixture.coordinator.context.save()

        let model = makeViewModel(fixture)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertTrue(model.isFinished)
        XCTAssertFalse(model.isOpen)
        XCTAssertFalse(model.canMark(fixture.legPress))
        XCTAssertFalse(model.canSubstitute(fixture.legPress), "sessão encerrada não troca exercício")
        XCTAssertTrue(fixture.coordinator.appliedEvents.isEmpty)
        XCTAssertEqual(model.stats.duration, 3_600)
    }

    // MARK: - Meta e carga de hoje (RF-04, RF-46)

    func testRF04_goal_usesTargetRepsOrRepMin() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        XCTAssertEqual(model.goal(for: fixture.legPress), 8, "sem meta gravada (sessão antiga), vale repMin")

        fixture.legPress.prescribedTargetReps = 10
        XCTAssertEqual(model.goal(for: fixture.legPress), 10, "SPEC P5: a meta do motor")
    }

    func testRF46_loadDisplay_perExercise() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        XCTAssertEqual(model.loadDisplay(for: fixture.legPress), .load("100 kg"))
        XCTAssertEqual(model.loadDisplay(for: fixture.bench), .toChoose, "primeira vez sem carga (P2)")
        XCTAssertNil(model.workingLoad(for: fixture.bench))

        fixture.benchCatalog.equipmentRaw = Equipment.bodyweight.rawValue
        XCTAssertEqual(model.loadDisplay(for: fixture.bench), .hidden, "peso do corpo sem carga não mostra nada")
        XCTAssertEqual(model.workingLoad(for: fixture.bench), 0)

        fixture.bench.prescribedLoad = 2.5
        XCTAssertEqual(model.loadDisplay(for: fixture.bench), .extra("+ 2,5 kg extra"))
    }

    func testRF44_loadDisplay_followsChosenLoad() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        model.setWorkingLoad(102.5, for: fixture.legPress.uuid)

        XCTAssertEqual(model.chosenLoad(for: fixture.legPress.uuid), 102.5)
        XCTAssertEqual(model.workingLoad(for: fixture.legPress), 102.5)
        XCTAssertEqual(model.loadDisplay(for: fixture.legPress), .load("102,5 kg"))
        XCTAssertTrue(fixture.coordinator.appliedEvents.isEmpty, "o teclado não grava nada")

        model.clearWorkingLoad(for: fixture.legPress.uuid)

        XCTAssertNil(model.chosenLoad(for: fixture.legPress.uuid))
        XCTAssertEqual(model.workingLoad(for: fixture.legPress), 100, "volta à prescrita")
    }

    // MARK: - Bolinha (RF-44 b, RF-04)

    func testRF44_dot_firstSetUsesPrescribedLoadAndGoal() throws {
        let fixture = try makeFixture()
        fixture.legPress.prescribedTargetReps = 10
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)
        clock = start.addingTimeInterval(300)

        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertNil(model.errorMessage)
        let stored = try XCTUnwrap(fixture.legPress.sets.first)
        XCTAssertEqual(fixture.legPress.sets.count, 1)
        XCTAssertEqual(stored.index, 0)
        XCTAssertEqual(stored.load, 100, "carga prescrita")
        XCTAssertEqual(stored.reps, 10, "meta de hoje, não repMin")
        XCTAssertEqual(stored.completedAt, clock, "hora vem do relógio injetado")
        XCTAssertEqual(model.markCount, 1)
        XCTAssertEqual(model.currentExerciseID, fixture.legPress.uuid, "ainda faltam séries")
    }

    func testRF44_dot_nextSetCopiesLoadAndReturnsToGoal() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        // A pessoa corrige a 1ª série: usou 105 kg e fez 7.
        let firstID = try XCTUnwrap(fixture.legPress.sets.first?.uuid)
        model.beginEditingSet(id: firstID)
        var edit = try XCTUnwrap(model.editingSet)
        edit.load = 105
        edit.reps = 7
        model.saveEditedSet(edit)

        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        let sets = fixture.legPress.sets.sorted { $0.index < $1.index }
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[1].index, 1)
        XCTAssertEqual(sets[1].load, 105, "RF-04: a carga copia a série anterior")
        XCTAssertEqual(sets[1].reps, 8, "RF-04 (2.2): as repetições voltam à meta, não copiam as 7")
    }

    func testRF44_dot_usesChosenLoad() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        model.setWorkingLoad(110, for: fixture.legPress.uuid)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertEqual(fixture.legPress.sets.map(\.load), [110, 110], "P10: a carga escolhida vale para as próximas bolinhas")
    }

    func testRF44_dot_rirNilAndNotWarmup() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        let stored = try XCTUnwrap(fixture.legPress.sets.first)
        XCTAssertNil(stored.rir, "SPEC RF-41: séries novas não têm RIR")
        XCTAssertFalse(stored.isWarmup, "SPEC RF-44 d: a chave Aquecimento saiu")
        let event = try XCTUnwrap(fixture.coordinator.appliedEvents.first)
        guard case let .setLogged(sessionExerciseID, _, index, load, reps, rir, isWarmup) = event.kind else {
            return XCTFail("esperava setLogged, veio \(event.kind)")
        }
        XCTAssertEqual(sessionExerciseID, fixture.legPress.uuid)
        XCTAssertEqual(index, 0)
        XCTAssertEqual(load, 100)
        XCTAssertEqual(reps, 8)
        XCTAssertNil(rir)
        XCTAssertFalse(isWarmup)
    }

    func testRF44_dot_startsRest_feitoDoesNot() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        clock = start.addingTimeInterval(60)

        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertTrue(fixture.timer.isRunning)
        XCTAssertEqual(fixture.timer.remainingSeconds(at: clock), 120, "descanso do exercício (RF-05)")

        fixture.timer.skip()
        model.markExerciseDone(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertEqual(model.workingSetCount(of: fixture.legPress), 3)
        XCTAssertFalse(fixture.timer.isRunning, "\"Feito\" não inicia descanso")
    }

    func testRF44_dot_zeroRest_doesNotStartTimer() throws {
        let fixture = try makeFixture()
        fixture.legPress.restSeconds = 0
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)

        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertEqual(fixture.legPress.sets.count, 1)
        XCTAssertFalse(fixture.timer.isRunning)
        XCTAssertNil(model.restNextUpText)
    }

    func testRF44_dot_indexIsMaxPlusOneAfterWarmupAndDeletion() throws {
        let fixture = try makeFixture()
        insertSet(fixture, exercise: fixture.legPress, index: 0, load: 60, reps: 12, rir: nil, isWarmup: true)
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        let sorted = fixture.legPress.sets.sorted { $0.index < $1.index }
        XCTAssertEqual(sorted.map(\.index), [0, 1, 2], "o índice conta o aquecimento antigo")

        model.deleteSet(id: sorted[1].uuid)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertEqual(fixture.legPress.sets.map(\.index).sorted(), [0, 2, 3], "maior índice + 1: nunca repete")
    }

    func testRF44_dot_completeExercise_ignoresExtraTap() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markExerciseDone(sessionExerciseID: fixture.legPress.uuid)
        let events = fixture.coordinator.appliedEvents.count

        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertEqual(fixture.coordinator.appliedEvents.count, events, "sem bolinha vazia, nada a marcar")
        XCTAssertEqual(model.workingSetCount(of: fixture.legPress), 3)
    }

    func testRF44_dot_coordinatorError_setsMessage() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        fixture.coordinator.errorToThrow = .sessionNotInProgress(fixture.session.uuid)

        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertEqual(model.errorMessage, "Esta sessão já foi encerrada.")
        XCTAssertTrue(fixture.legPress.sets.isEmpty)
        XCTAssertFalse(fixture.timer.isRunning)
        XCTAssertEqual(model.markCount, 0)

        // Fechar o alerta limpa a mensagem.
        model.isShowingError = false
        XCTAssertNil(model.errorMessage)
    }

    func testRF44_dot_unknownExercise_doesNothing() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        model.markSet(sessionExerciseID: UUID())
        model.markExerciseDone(sessionExerciseID: UUID())

        XCTAssertTrue(fixture.coordinator.appliedEvents.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    // MARK: - "Feito" (RF-44 b)

    func testRF44_feito_logsOnlyMissingSets() throws {
        let fixture = try makeFixture()
        fixture.legPress.prescribedTargetReps = 9
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        clock = start.addingTimeInterval(600)

        model.markExerciseDone(sessionExerciseID: fixture.legPress.uuid)

        let sets = fixture.legPress.sets.sorted { $0.index < $1.index }
        XCTAssertEqual(sets.map(\.index), [0, 1, 2], "só as 2 que faltavam")
        XCTAssertEqual(sets.map(\.reps), [9, 9, 9], "todas com a meta de hoje")
        XCTAssertEqual(sets.map(\.load), [100, 100, 100])
        XCTAssertTrue(sets.allSatisfy { $0.rir == nil && !$0.isWarmup })
        XCTAssertEqual(sets[2].completedAt, clock)
        XCTAssertEqual(model.currentExerciseID, fixture.bench.uuid, "a borda passa ao próximo pendente")
        let events = fixture.coordinator.appliedEvents.count

        model.markExerciseDone(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertEqual(fixture.coordinator.appliedEvents.count, events, "exercício completo: nada")
    }

    // MARK: - "Marcar como feitos, como previsto" (RF-44 e)

    func testRF44_markRemaining_skipsSkippedAndUnloaded() throws {
        let fixture = try makeFixture()
        let row = addExercise(fixture, order: 2, name: "Remada baixa", equipment: .cable, prescribedLoad: 50, sets: 2)
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)
        model.skip(sessionExerciseID: row.uuid)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        model.markRemainingAsPrescribed()

        XCTAssertEqual(model.workingSetCount(of: fixture.legPress), 3, "com carga: marcado até o prescrito")
        XCTAssertTrue(fixture.bench.sets.isEmpty, "primeira vez sem carga fica de fora")
        XCTAssertTrue(row.sets.isEmpty, "pulado fica de fora")
        XCTAssertEqual(model.pendingExercises.map(\.uuid), [fixture.bench.uuid])
        XCTAssertFalse(model.isFinished, "marcar não conclui sozinho")
    }

    // MARK: - Primeira vez com carga (RF-44 c) e peso do corpo (RF-46)

    func testRF44_firstTime_requiresLoadAboveZero() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        XCTAssertTrue(model.isFirstTimeWithLoad(fixture.bench))
        XCTAssertTrue(model.needsLoadChoice(fixture.bench))
        XCTAssertFalse(model.canMark(fixture.bench))
        model.markSet(sessionExerciseID: fixture.bench.uuid)
        model.markExerciseDone(sessionExerciseID: fixture.bench.uuid)
        XCTAssertTrue(fixture.coordinator.appliedEvents.isEmpty, "sem carga, nada é gravado")

        model.setWorkingLoad(0, for: fixture.bench.uuid)
        XCTAssertFalse(model.canMark(fixture.bench), "0 não é carga")
        model.setWorkingLoad(-5, for: fixture.bench.uuid)
        XCTAssertFalse(model.canMark(fixture.bench))
        model.setWorkingLoad(1_001, for: fixture.bench.uuid)
        XCTAssertFalse(model.canMark(fixture.bench), "acima de 1.000 é erro de digitação")
        XCTAssertNil(model.chosenLoad(for: fixture.bench.uuid))

        model.setWorkingLoad(40, for: fixture.bench.uuid)
        XCTAssertTrue(model.canMark(fixture.bench))
        XCTAssertEqual(model.loadDisplay(for: fixture.bench), .load("40 kg"))
        model.markSet(sessionExerciseID: fixture.bench.uuid)
        model.markExerciseDone(sessionExerciseID: fixture.bench.uuid)

        XCTAssertEqual(fixture.bench.sets.map(\.load), [40, 40])
        XCTAssertEqual(fixture.bench.sets.map(\.reps), [8, 8], "meta de hoje (repMin na primeira vez)")
        XCTAssertFalse(model.isFirstTimeWithLoad(fixture.bench), "com série gravada, não é mais primeira vez")
    }

    func testRF44_firstTime_afterFirstSet_keepsLoggedLoadWithoutChoice() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.setWorkingLoad(40, for: fixture.bench.uuid)
        model.markSet(sessionExerciseID: fixture.bench.uuid)

        model.clearWorkingLoad(for: fixture.bench.uuid)

        XCTAssertFalse(model.needsLoadChoice(fixture.bench), "a série gravada já tem carga")
        XCTAssertEqual(model.workingLoad(for: fixture.bench), 40)
    }

    func testRF46_bodyweight_logsZeroWithoutAsking() throws {
        let fixture = try makeFixture()
        fixture.benchCatalog.equipmentRaw = Equipment.bodyweight.rawValue
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)

        XCTAssertFalse(model.isFirstTimeWithLoad(fixture.bench), "peso do corpo pula a primeira vez com carga")
        XCTAssertFalse(model.needsLoadChoice(fixture.bench))
        XCTAssertTrue(model.canMark(fixture.bench))

        model.markSet(sessionExerciseID: fixture.bench.uuid)

        XCTAssertEqual(fixture.bench.sets.count, 1)
        XCTAssertEqual(fixture.bench.sets.first?.load, 0, "SPEC P8")
        XCTAssertNil(model.errorMessage)
    }

    func testRF46_bodyweight_extraLoadCanGoBackToZero() throws {
        let fixture = try makeFixture()
        fixture.benchCatalog.equipmentRaw = Equipment.bodyweight.rawValue
        fixture.bench.prescribedLoad = 2.5
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)

        model.setWorkingLoad(0, for: fixture.bench.uuid)
        model.markSet(sessionExerciseID: fixture.bench.uuid)

        XCTAssertEqual(fixture.bench.sets.first?.load, 0, "sem a mochila: carga extra 0")
        XCTAssertEqual(model.loadDisplay(for: fixture.bench), .hidden)
    }

    // MARK: - "A seguir" do descanso (RF-44 f)

    func testRF44_restNextUp_nextSetThenNextExerciseThenAllMarked() throws {
        let fixture = try makeFixture()
        fixture.benchCatalog.equipmentRaw = Equipment.bodyweight.rawValue
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)

        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        XCTAssertEqual(model.restNextUpText, "A seguir: série 2 de Leg press 45°")

        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        XCTAssertEqual(model.restNextUpText, "A seguir: Supino reto")

        model.markExerciseDone(sessionExerciseID: fixture.bench.uuid)
        XCTAssertEqual(model.restNextUpText, "Tudo marcado. Toque em Concluir.")
    }

    // MARK: - Concluir (RF-44 e)

    func testRF44_finish_allDone_finishesDirectly() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markExerciseDone(sessionExerciseID: fixture.legPress.uuid)
        model.setWorkingLoad(40, for: fixture.bench.uuid)
        model.markExerciseDone(sessionExerciseID: fixture.bench.uuid)
        clock = start.addingTimeInterval(1_800)

        let request = model.requestFinish()

        XCTAssertEqual(request, .finished)
        XCTAssertTrue(model.isFinished)
        XCTAssertEqual(fixture.session.status, .completed)
        XCTAssertEqual(fixture.session.endedAt, clock)
        XCTAssertNil(fixture.coordinator.activeSession)
        XCTAssertEqual(model.stats.duration, 1_800)
    }

    func testRF44_finish_pending_asksWithNames() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        let request = model.requestFinish()

        XCTAssertEqual(
            request,
            .needsConfirmation(pendingNames: ["Leg press 45°", "Supino reto"], hasAnySet: true)
        )
        XCTAssertFalse(model.isFinished, "com pendentes, nada é concluído antes da resposta")
        XCTAssertEqual(fixture.session.status, .inProgress)

        // "Marcar como feitos, como previsto" marca e conclui.
        model.markRemainingAsPrescribed()
        model.finish()

        XCTAssertTrue(model.isFinished)
        XCTAssertEqual(model.workingSetCount(of: fixture.legPress), 3)
        XCTAssertEqual(fixture.session.status, .completed)
    }

    func testRF44_finish_nothingMarked_offersLeaveWithoutRecording() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        let request = model.requestFinish()

        XCTAssertEqual(
            request,
            .needsConfirmation(pendingNames: ["Leg press 45°", "Supino reto"], hasAnySet: false)
        )

        // "Sair sem registrar" abandona.
        model.abandon()

        XCTAssertTrue(model.isFinished)
        XCTAssertEqual(fixture.session.status, .abandoned)
        XCTAssertTrue(fixture.legPress.sets.isEmpty)
    }

    func testRF44_finish_warmupsOnly_countAsNothingMarked() throws {
        let fixture = try makeFixture()
        insertSet(fixture, exercise: fixture.legPress, index: 0, load: 60, reps: 12, rir: nil, isWarmup: true)
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)

        XCTAssertEqual(
            model.requestFinish(),
            .needsConfirmation(pendingNames: ["Leg press 45°", "Supino reto"], hasAnySet: false)
        )
    }

    func testRF44_finish_skippedExercisesAreNotPending() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markExerciseDone(sessionExerciseID: fixture.legPress.uuid)
        model.skip(sessionExerciseID: fixture.bench.uuid)

        XCTAssertEqual(model.requestFinish(), .finished, "pulado não conta como pendente")
        XCTAssertTrue(model.isFinished)
    }

    func testRF44_finish_coordinatorError_keepsSessionOpen() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markExerciseDone(sessionExerciseID: fixture.legPress.uuid)
        model.skip(sessionExerciseID: fixture.bench.uuid)
        fixture.coordinator.errorToThrow = .sessionNotFound(fixture.session.uuid)

        let request = model.requestFinish()

        XCTAssertEqual(request, .finished, "tentou concluir direto")
        XCTAssertFalse(model.isFinished, "a tela confere `isFinished` antes de ir ao resumo")
        XCTAssertEqual(model.errorMessage, "A sessão não foi encontrada.")
        XCTAssertEqual(fixture.session.status, .inProgress)
    }

    func testFinish_stopsRestTimer() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        XCTAssertTrue(fixture.timer.isRunning)

        model.finish()

        XCTAssertTrue(model.isFinished)
        XCTAssertFalse(fixture.timer.isRunning, "descanso pendente é cancelado ao concluir")
        XCTAssertFalse(model.isOpen)
    }

    func testAbandon_keepsLoggedSets() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        clock = start.addingTimeInterval(600)

        model.abandon()

        XCTAssertTrue(model.isFinished)
        XCTAssertEqual(fixture.session.status, .abandoned)
        XCTAssertEqual(fixture.session.endedAt, clock)
        XCTAssertFalse(fixture.timer.isRunning)
        XCTAssertEqual(fixture.legPress.sets.count, 1, "séries registradas continuam no histórico")
    }

    // MARK: - Pular (RF-10)

    func testRF10_skip_marksExerciseAndKeepsSets() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        model.skip(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertTrue(fixture.legPress.wasSkipped)
        XCTAssertEqual(fixture.legPress.sets.count, 1)
        XCTAssertEqual(model.currentExerciseID, fixture.bench.uuid)
        XCTAssertFalse(model.canMark(fixture.legPress))
        XCTAssertFalse(model.canSkip(fixture.legPress), "já pulado")
        XCTAssertEqual(model.stats.workingSetCount, 1)
    }

    func testRF10_skip_coordinatorError_setsMessage() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        fixture.coordinator.errorToThrow = .sessionExerciseNotFound(fixture.legPress.uuid)

        model.skip(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertFalse(fixture.legPress.wasSkipped)
        XCTAssertEqual(model.errorMessage, "O exercício não foi encontrado nesta sessão.")
    }

    // MARK: - Informações do exercício (RF-47)

    func testRF47_infoContent_usesSnapshotAndLastSession() throws {
        let fixture = try makeFixture()
        fixture.legPress.prescribedTargetReps = 10
        let last = ExerciseLastSession(
            sessionID: UUID(),
            date: start.addingTimeInterval(-86_400 * 3),
            sets: [SetResult(load: 95, reps: 12, rir: nil, isWarmup: false, completedAt: start)],
            wasDeload: false
        )
        fixture.planner.lastSessionResult = last
        let model = makeViewModel(fixture)

        let content = model.infoContent(for: fixture.legPress)

        XCTAssertEqual(fixture.planner.lastSessionCalls, [fixture.legPressCatalog.uuid], "busca pelo exercício do catálogo")
        XCTAssertEqual(content.id, fixture.legPress.uuid)
        XCTAssertEqual(content.exerciseID, fixture.legPressCatalog.uuid)
        XCTAssertEqual(content.name, "Leg press 45°")
        XCTAssertEqual(content.sets, 3)
        XCTAssertEqual(content.targetReps, 10)
        XCTAssertEqual(content.load, 100)
        XCTAssertEqual(content.restSeconds, 120)
        XCTAssertEqual(content.note, .increase)
        XCTAssertEqual(content.machineNotes, "Banco 3")
        XCTAssertEqual(content.lastSession, last)
    }

    func testRF47_infoContent_plannerError_hidesLastSession() throws {
        let fixture = try makeFixture()
        fixture.planner.lastSessionError = .noActiveProgram
        let model = makeViewModel(fixture)

        let content = model.infoContent(for: fixture.bench)

        XCTAssertNil(content.lastSession)
        XCTAssertNil(content.load, "primeira vez sem carga")
        XCTAssertNil(model.errorMessage, "a falha só esconde \"Da última vez\"")
    }

    // MARK: - Trocar exercício (RF-34)

    func testRF34_substitution_allowedOnlyBeforeFirstSet() throws {
        let fixture = try makeFixture()
        fixture.planner.substitutesResult = [fixture.hackDefinition]
        let model = makeViewModel(fixture)
        XCTAssertTrue(model.canSubstitute(fixture.legPress), "sem séries: pode trocar")

        model.markSet(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertFalse(model.canSubstitute(fixture.legPress), "com série registrada: não troca")
        model.beginSubstitution(sessionExerciseID: fixture.legPress.uuid)
        XCTAssertFalse(model.isShowingSubstituteSheet)
        XCTAssertTrue(fixture.planner.substitutesCalls.isEmpty)
        model.substituteSelectedExercise(with: fixture.hackDefinition)
        XCTAssertTrue(fixture.planner.substitutionPlanCalls.isEmpty, "o planner nem é consultado")
        XCTAssertTrue(fixture.coordinator.substituteCalls.isEmpty, "o coordinator nem é chamado")
        XCTAssertEqual(fixture.legPress.exerciseUUID, fixture.legPressCatalog.uuid)

        // Apagar a única série libera a troca de novo.
        let setID = try XCTUnwrap(fixture.legPress.sets.first?.uuid)
        model.deleteSet(id: setID)

        XCTAssertTrue(model.canSubstitute(fixture.legPress))
    }

    func testRF34_skippedExercise_cannotBeSubstituted() throws {
        let fixture = try makeFixture()
        fixture.bench.wasSkipped = true
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)

        XCTAssertFalse(model.canSubstitute(fixture.bench))
        model.beginSubstitution(sessionExerciseID: fixture.bench.uuid)
        XCTAssertFalse(model.isShowingSubstituteSheet)
        XCTAssertTrue(fixture.planner.substitutesCalls.isEmpty)
    }

    func testRF34_beginSubstitution_loadsSuggestionsWithoutExercisesInSession() throws {
        let fixture = try makeFixture()
        // O supino já está na sessão: não é sugerido de novo.
        fixture.planner.substitutesResult = [fixture.benchDefinition, fixture.hackDefinition]
        let model = makeViewModel(fixture)

        model.beginSubstitution(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertTrue(model.isShowingSubstituteSheet)
        XCTAssertEqual(model.substitutingExerciseName, "Leg press 45°")
        XCTAssertEqual(
            fixture.planner.substitutesCalls,
            [SessionTestPlanner.SubstitutesCall(exerciseID: fixture.legPressCatalog.uuid, limit: 20)]
        )
        XCTAssertEqual(model.substituteSuggestions.map(\.id), [fixture.hackDefinition.id])

        model.cancelSubstitution()

        XCTAssertFalse(model.isShowingSubstituteSheet)
        XCTAssertTrue(model.substituteSuggestions.isEmpty)
        XCTAssertEqual(model.substitutingExerciseName, "")
        XCTAssertTrue(fixture.coordinator.substituteCalls.isEmpty)
    }

    func testRF34_beginSubstitution_listFailure_leavesEmptyListButOpensSheet() throws {
        let fixture = try makeFixture()
        fixture.planner.substitutesError = .noActiveProgram
        let model = makeViewModel(fixture)

        model.beginSubstitution(sessionExerciseID: fixture.legPress.uuid)

        XCTAssertTrue(model.isShowingSubstituteSheet)
        XCTAssertTrue(model.substituteSuggestions.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testRF34_substitute_buildsTargetFromSnapshotAndReplacesExercise() throws {
        let fixture = try makeFixture()
        fixture.planner.substitutesResult = [fixture.hackDefinition]
        let model = makeViewModel(fixture)
        model.setWorkingLoad(120, for: fixture.legPress.uuid)
        clock = start.addingTimeInterval(120)
        model.beginSubstitution(sessionExerciseID: fixture.legPress.uuid)

        model.substituteSelectedExercise(with: fixture.hackDefinition)

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(fixture.planner.substitutionPlanCalls.count, 1)
        let call = try XCTUnwrap(fixture.planner.substitutionPlanCalls.first)
        XCTAssertEqual(call.sessionExerciseID, fixture.legPress.uuid)
        XCTAssertEqual(call.newExerciseID, fixture.hackDefinition.id)
        XCTAssertEqual(call.now, clock)
        // Alvo do original (RF-34), a partir do snapshot: 3 × 8–12, RIR 2, 120 s, sem carga inicial.
        XCTAssertEqual(call.target.exerciseID, fixture.hackDefinition.id)
        XCTAssertEqual(call.target.order, 0)
        XCTAssertEqual(call.target.sets, 3)
        XCTAssertEqual(call.target.repMin, 8)
        XCTAssertEqual(call.target.repMax, 12)
        XCTAssertEqual(call.target.targetRIR, 2)
        XCTAssertEqual(call.target.restSeconds, 120)
        XCTAssertNil(call.target.startingLoad)

        let substitution = try XCTUnwrap(fixture.coordinator.substituteCalls.first)
        XCTAssertEqual(substitution.sessionID, fixture.session.uuid)
        XCTAssertEqual(substitution.sessionExerciseID, fixture.legPress.uuid)
        XCTAssertEqual(substitution.planned.exercise.id, fixture.hackDefinition.id)
        XCTAssertEqual(substitution.now, clock)

        XCTAssertFalse(model.isShowingSubstituteSheet)
        XCTAssertEqual(fixture.legPress.exerciseUUID, fixture.hackCatalog.uuid)
        XCTAssertEqual(fixture.legPress.exerciseName, "Agachamento hack")
        XCTAssertEqual(fixture.legPress.substitutedFromUUID, fixture.legPressCatalog.uuid)

        // O novo começa como primeira vez (P2): a carga digitada para o antigo não vale.
        XCTAssertNil(model.chosenLoad(for: fixture.legPress.uuid))
        XCTAssertTrue(model.isFirstTimeWithLoad(fixture.legPress))
        XCTAssertTrue(model.needsLoadChoice(fixture.legPress))
    }

    func testRF34_substituteFirstTimeWithoutLoad_passesBaseRIR() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        // Supino: primeira vez sem carga, RIR gravado 3 = T + 1 (SPEC P2) com T = 2.
        model.beginSubstitution(sessionExerciseID: fixture.bench.uuid)

        model.substituteSelectedExercise(with: fixture.hackDefinition)

        let call = try XCTUnwrap(fixture.planner.substitutionPlanCalls.first)
        XCTAssertEqual(call.target.targetRIR, 2, "sem desfazer o +1 o substituto começaria com T + 2")
        XCTAssertEqual(call.target.sets, 2)
        XCTAssertEqual(call.target.restSeconds, 90)
        XCTAssertEqual(call.target.order, 1)
    }

    func testRF34_substitute_plannerError_showsMessageAfterSheetCloses() throws {
        let fixture = try makeFixture()
        fixture.planner.substitutionError = .exerciseNotFound(fixture.hackDefinition.id)
        let model = makeViewModel(fixture)
        model.beginSubstitution(sessionExerciseID: fixture.legPress.uuid)

        model.substituteSelectedExercise(with: fixture.hackDefinition)

        XCTAssertFalse(model.isShowingSubstituteSheet)
        XCTAssertNil(model.errorMessage, "o alerta espera a folha terminar de fechar")
        XCTAssertTrue(fixture.coordinator.substituteCalls.isEmpty)

        model.sheetDidDismiss()

        XCTAssertEqual(model.errorMessage, "Não foi possível trocar o exercício.")

        // A mensagem só é entregue uma vez.
        model.isShowingError = false
        model.sheetDidDismiss()
        XCTAssertNil(model.errorMessage)
    }

    func testRF34_substituteWithoutOpeningSheet_doesNothing() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        model.substituteSelectedExercise(with: fixture.hackDefinition)

        XCTAssertTrue(fixture.planner.substitutionPlanCalls.isEmpty)
        XCTAssertTrue(fixture.coordinator.substituteCalls.isEmpty)
    }

    // MARK: - Corrigir / apagar série (RF-19)

    func testRF19_edit_keepsStoredRIR() throws {
        let fixture = try makeFixture()
        // Série de uma versão anterior, com RIR 2: a correção não pode apagar esse dado.
        let old = insertSet(fixture, exercise: fixture.legPress, index: 0, load: 100, reps: 9, rir: 2, isWarmup: false)
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)
        model.beginEditingSet(id: old.uuid)
        var edit = try XCTUnwrap(model.editingSet)
        XCTAssertEqual(edit.rir, 2)
        edit.load = 102.5
        edit.reps = 8
        clock = start.addingTimeInterval(400)

        model.saveEditedSet(edit)

        XCTAssertNil(model.editingSet)
        XCTAssertEqual(old.load, 102.5)
        XCTAssertEqual(old.reps, 8)
        XCTAssertEqual(old.rir, 2, "SPEC RF-41: setUpdated regrava o RIR que já estava")
        XCTAssertEqual(old.updatedAt, clock)
        XCTAssertEqual(
            fixture.coordinator.appliedEvents.last?.kind,
            .setUpdated(setID: old.uuid, load: 102.5, reps: 8, rir: 2)
        )
    }

    func testRF19_edit_newSetKeepsNilRIR() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        let setID = try XCTUnwrap(fixture.legPress.sets.first?.uuid)
        model.beginEditingSet(id: setID)
        var edit = try XCTUnwrap(model.editingSet)
        edit.reps = 6

        model.saveEditedSet(edit)

        XCTAssertEqual(fixture.coordinator.appliedEvents.last?.kind, .setUpdated(setID: setID, load: 100, reps: 6, rir: nil))
    }

    func testRF19_beginEditingSet_copiesStoredValues() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        let second = try XCTUnwrap(fixture.legPress.sets.first { $0.index == 1 })

        model.beginEditingSet(id: second.uuid)

        let edit = try XCTUnwrap(model.editingSet)
        XCTAssertEqual(edit.setID, second.uuid)
        XCTAssertEqual(edit.id, second.uuid)
        XCTAssertEqual(edit.number, 2)
        XCTAssertEqual(edit.load, 100)
        XCTAssertEqual(edit.reps, 8)
        XCTAssertNil(edit.rir)
        XCTAssertEqual(edit.loadIncrement, 5)
        XCTAssertEqual(edit.loadUnit, .kilograms)
        XCTAssertEqual(edit.repMin, 8)
        XCTAssertEqual(edit.repMax, 12)
        XCTAssertFalse(edit.isBodyweight)
        XCTAssertEqual(edit.plannedLine, "Leg press 45° · previsto: 8 repetições · 100 kg")

        model.cancelEditingSet()
        XCTAssertNil(model.editingSet)
        XCTAssertEqual(fixture.coordinator.appliedEvents.count, 2, "cancelar não grava nada")
    }

    func testRF19_beginEditingSet_bodyweightShowsExtraLoad() throws {
        let fixture = try makeFixture()
        fixture.benchCatalog.equipmentRaw = Equipment.bodyweight.rawValue
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)
        model.markSet(sessionExerciseID: fixture.bench.uuid)
        let setID = try XCTUnwrap(fixture.bench.sets.first?.uuid)

        model.beginEditingSet(id: setID)

        let edit = try XCTUnwrap(model.editingSet)
        XCTAssertTrue(edit.isBodyweight, "o stepper vira \"Carga extra\"")
        XCTAssertEqual(edit.load, 0)
        XCTAssertEqual(edit.plannedLine, "Supino reto · previsto: 8 repetições", "peso do corpo sem carga (RF-46)")
    }

    func testRF19_beginEditingSet_unknownIDOrClosedSession_keepsSheetClosed() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        model.beginEditingSet(id: UUID())

        XCTAssertNil(model.editingSet)
    }

    func testRF19_saveEditedSet_coordinatorError_showsMessageAfterSheetCloses() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        let setID = try XCTUnwrap(fixture.legPress.sets.first?.uuid)
        model.beginEditingSet(id: setID)
        let edit = try XCTUnwrap(model.editingSet)
        fixture.coordinator.errorToThrow = .setNotFound(setID)

        model.saveEditedSet(edit)

        XCTAssertNil(model.editingSet)
        XCTAssertNil(model.errorMessage)
        model.sheetDidDismiss()
        XCTAssertEqual(model.errorMessage, "A série não foi encontrada.")
    }

    func testRF19_deleteSet_removesItAndExerciseIsPendingAgain() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markExerciseDone(sessionExerciseID: fixture.legPress.uuid)
        XCTAssertTrue(model.isDone(fixture.legPress))
        let first = try XCTUnwrap(fixture.legPress.sets.first { $0.index == 0 })

        model.deleteSet(id: first.uuid)

        XCTAssertNil(model.editingSet)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(fixture.coordinator.appliedEvents.last?.kind, .setDeleted(setID: first.uuid))
        XCTAssertEqual(model.workingSetCount(of: fixture.legPress), 2)
        XCTAssertTrue(model.isPending(fixture.legPress))
        XCTAssertEqual(model.currentExerciseID, fixture.legPress.uuid)
    }

    func testRF19_deleteSet_coordinatorError_keepsSetAndDefersMessage() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.markSet(sessionExerciseID: fixture.legPress.uuid)
        let setID = try XCTUnwrap(fixture.legPress.sets.first?.uuid)
        fixture.coordinator.errorToThrow = .sessionNotInProgress(fixture.session.uuid)

        model.deleteSet(id: setID)

        XCTAssertEqual(fixture.legPress.sets.count, 1)
        model.sheetDidDismiss()
        XCTAssertEqual(model.errorMessage, "Esta sessão já foi encerrada.")
    }

    // MARK: - Resumo (RF-44 h)

    func testRF44_summary_goalAndNextSessionFromPlanner() throws {
        let fixture = try makeFixture()
        fixture.planner.activeGoalResult = .combat
        fixture.planner.nextPlanResult = SessionPlan(
            programID: UUID(),
            programName: "Combate",
            programDayID: UUID(),
            programDayName: "Dia B — Salto, terra e supino",
            exercises: [],
            generatedAt: start
        )
        let model = makeViewModel(fixture)
        clock = start.addingTimeInterval(3_000)

        XCTAssertEqual(model.activeGoal(), .combat)
        XCTAssertEqual(model.nextSessionName(), "Dia B — Salto, terra e supino")
        XCTAssertEqual(fixture.planner.nextPlanDates, [clock], "a próxima sessão usa o relógio injetado")
    }

    func testRF44_summary_plannerErrors_areNil() throws {
        let fixture = try makeFixture()
        fixture.planner.activeGoalError = .noActiveProgram
        fixture.planner.nextPlanError = .programHasNoDays
        let model = makeViewModel(fixture)

        XCTAssertNil(model.activeGoal())
        XCTAssertNil(model.nextSessionName())
        XCTAssertNil(model.errorMessage, "o resumo só omite a linha")
    }

    // MARK: - Totais

    func testStats_countsWorkingSetsOnly() throws {
        let fixture = try makeFixture()
        insertSet(fixture, exercise: fixture.legPress, index: 0, load: 60, reps: 12, rir: nil, isWarmup: true)
        insertSet(fixture, exercise: fixture.legPress, index: 1, load: 100, reps: 10, rir: 2, isWarmup: false)
        insertSet(fixture, exercise: fixture.legPress, index: 2, load: 100, reps: 9, rir: 1, isWarmup: false)
        try fixture.coordinator.context.save()

        let model = makeViewModel(fixture)
        let stats = model.stats

        XCTAssertEqual(stats.workingSetCount, 2)
        XCTAssertEqual(stats.warmupSetCount, 1)
        XCTAssertEqual(stats.exerciseCount, 1, "supino sem série não conta")
        XCTAssertNil(stats.duration, "sessão em andamento não tem duração")
        XCTAssertEqual(model.workingSetCount(of: fixture.legPress), 2)
    }

    // MARK: - Fixtures

    private struct Fixture {
        let coordinator: SessionTestCoordinator
        let planner: SessionTestPlanner
        let session: WorkoutSessionModel
        /// `order` 0, carga prescrita 100 kg, 3 × 8–12, RIR 2, descanso 120 s, nota `increase`,
        /// catálogo (máquina) com incremento 5 kg.
        let legPress: SessionExerciseModel
        /// `order` 1, sem carga prescrita (primeira vez), 2 × 8–12, RIR 3, descanso 90 s,
        /// catálogo (barra) com incremento 2,5 kg.
        let bench: SessionExerciseModel
        let legPressCatalog: ExerciseModel
        let benchCatalog: ExerciseModel
        /// Fora da sessão: o substituto dos testes de troca (incremento 10 kg).
        let hackCatalog: ExerciseModel
        let benchDefinition: ExerciseDefinition
        let hackDefinition: ExerciseDefinition
        let timer: RestTimer
    }

    private func makeViewModel(_ fixture: Fixture) -> ActiveSessionViewModel {
        ActiveSessionViewModel(
            sessionID: fixture.session.uuid,
            coordinator: fixture.coordinator,
            planner: fixture.planner,
            restTimer: fixture.timer,
            notifications: FakeNotificationScheduler(),
            now: { self.clock }
        )
    }

    private func makeFixture() throws -> Fixture {
        let coordinator = try SessionTestCoordinator()
        let context = coordinator.context

        let legPressCatalog = ExerciseModel(
            uuid: UUID(),
            slug: "leg-press-45",
            name: "Leg press 45°",
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.quads, .glutes]),
            secondaryMusclesRaw: SchemaV1.encodeMuscleGroups([.hamstrings]),
            equipmentRaw: Equipment.machine.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 5,
            isUnilateral: false,
            machineNotes: "Banco 3",
            isArchived: false
        )
        context.insert(legPressCatalog)
        let benchCatalog = ExerciseModel(
            uuid: UUID(),
            slug: "supino-reto",
            name: "Supino reto",
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.chest]),
            secondaryMusclesRaw: SchemaV1.encodeMuscleGroups([.triceps]),
            equipmentRaw: Equipment.barbell.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 2.5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        context.insert(benchCatalog)
        let hackCatalog = ExerciseModel(
            uuid: UUID(),
            slug: "agachamento-hack",
            name: "Agachamento hack",
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.quads, .glutes]),
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.machine.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 10,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        context.insert(hackCatalog)

        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia B — Inferior",
            statusRaw: SessionStatus.inProgress.rawValue,
            startedAt: start,
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: DeviceSource.iphone.rawValue
        )
        context.insert(session)

        // Inseridos fora de ordem de propósito: o ViewModel ordena por `order`.
        let bench = SessionExerciseModel(
            uuid: UUID(),
            order: 1,
            exerciseUUID: benchCatalog.uuid,
            exerciseName: benchCatalog.name,
            prescribedLoad: nil,
            prescribedSets: 2,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: 3,
            restSeconds: 90,
            noteRaw: PrescriptionNote.calibrate.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(bench)
        bench.exercise = benchCatalog
        session.exercises.append(bench)

        let legPress = SessionExerciseModel(
            uuid: UUID(),
            order: 0,
            exerciseUUID: legPressCatalog.uuid,
            exerciseName: legPressCatalog.name,
            prescribedLoad: 100,
            prescribedSets: 3,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: 2,
            restSeconds: 120,
            noteRaw: PrescriptionNote.increase.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(legPress)
        legPress.exercise = legPressCatalog
        session.exercises.append(legPress)

        try context.save()

        let legPressDefinition = try ExerciseMapper.definition(from: legPressCatalog)
        let benchDefinition = try ExerciseMapper.definition(from: benchCatalog)
        let hackDefinition = try ExerciseMapper.definition(from: hackCatalog)

        return Fixture(
            coordinator: coordinator,
            planner: SessionTestPlanner(catalog: [legPressDefinition, benchDefinition, hackDefinition]),
            session: session,
            legPress: legPress,
            bench: bench,
            legPressCatalog: legPressCatalog,
            benchCatalog: benchCatalog,
            hackCatalog: hackCatalog,
            benchDefinition: benchDefinition,
            hackDefinition: hackDefinition,
            timer: RestTimer(notifications: FakeNotificationScheduler())
        )
    }

    /// Mais um exercício na sessão da fixture (com o próprio item de catálogo). Quem chama salva.
    private func addExercise(
        _ fixture: Fixture,
        order: Int,
        name: String,
        equipment: Equipment,
        prescribedLoad: Double?,
        sets: Int
    ) -> SessionExerciseModel {
        let context = fixture.coordinator.context
        let catalogItem = ExerciseModel(
            uuid: UUID(),
            slug: "teste-\(order)",
            name: name,
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.back]),
            secondaryMusclesRaw: "",
            equipmentRaw: equipment.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 2.5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        context.insert(catalogItem)
        let exercise = SessionExerciseModel(
            uuid: UUID(),
            order: order,
            exerciseUUID: catalogItem.uuid,
            exerciseName: name,
            prescribedLoad: prescribedLoad,
            prescribedSets: sets,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: 2,
            restSeconds: 60,
            noteRaw: PrescriptionNote.hold.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(exercise)
        exercise.exercise = catalogItem
        fixture.session.exercises.append(exercise)
        return exercise
    }

    /// Série pré-existente (estado inicial do teste); não passa pelo coordinator de propósito.
    @discardableResult
    private func insertSet(
        _ fixture: Fixture,
        exercise: SessionExerciseModel,
        index: Int,
        load: Double,
        reps: Int,
        rir: Int?,
        isWarmup: Bool
    ) -> SetLogModel {
        let completedAt = start.addingTimeInterval(Double(index + 1) * 180)
        let model = SetLogModel(
            uuid: UUID(),
            index: index,
            load: load,
            reps: reps,
            rir: rir,
            isWarmup: isWarmup,
            completedAt: completedAt,
            sourceRaw: DeviceSource.iphone.rawValue,
            updatedAt: completedAt
        )
        fixture.coordinator.context.insert(model)
        exercise.sets.append(model)
        return model
    }
}

// MARK: - Double do coordinator

/// `SessionCoordinating` em memória sobre modelos reais: aplica `setLogged`, `setUpdated`,
/// `setDeleted`, `exerciseSkipped`, `sessionFinished` e `sessionAbandoned` num container
/// in-memory e registra os eventos aplicados; `substituteExercise` registra a chamada e troca o
/// snapshot como o contrato do M2 descreve. `errorToThrow` simula falha do caminho de escrita.
@MainActor
private final class SessionTestCoordinator: SessionCoordinating {
    struct SubstituteCall {
        let sessionID: UUID
        let sessionExerciseID: UUID
        let planned: PlannedExercise
        let now: Date
    }

    let container: ModelContainer
    private(set) var appliedEvents: [SessionEvent] = []
    private(set) var substituteCalls: [SubstituteCall] = []
    var errorToThrow: SessionCoordinatorError?

    var context: ModelContext {
        container.mainContext
    }

    init() throws {
        container = try ModelContainerFactory.make(.inMemory)
    }

    var activeSession: WorkoutSessionModel? {
        let inProgress = SessionStatus.inProgress.rawValue
        let descriptor = FetchDescriptor<WorkoutSessionModel>(
            predicate: #Predicate<WorkoutSessionModel> { $0.statusRaw == inProgress }
        )
        return try? context.fetch(descriptor).first
    }

    func session(withID id: UUID) -> WorkoutSessionModel? {
        let descriptor = FetchDescriptor<WorkoutSessionModel>(
            predicate: #Predicate<WorkoutSessionModel> { $0.uuid == id }
        )
        return try? context.fetch(descriptor).first
    }

    func startSession(plan: SessionPlan, now: Date, source: DeviceSource) throws -> UUID {
        throw SessionCoordinatorError.unsupported
    }

    func apply(_ event: SessionEvent) throws {
        if let errorToThrow {
            throw errorToThrow
        }
        guard let session = session(withID: event.sessionID) else {
            throw SessionCoordinatorError.sessionNotFound(event.sessionID)
        }
        switch event.kind {
        case let .setLogged(sessionExerciseID, setID, index, load, reps, rir, isWarmup):
            let exercise = try sessionExercise(sessionExerciseID, in: session)
            let setLog = SetLogModel(
                uuid: setID,
                index: index,
                load: load,
                reps: reps,
                rir: rir,
                isWarmup: isWarmup,
                completedAt: event.occurredAt,
                sourceRaw: event.source.rawValue,
                updatedAt: event.occurredAt
            )
            context.insert(setLog)
            exercise.sets.append(setLog)
        case let .setUpdated(setID, load, reps, rir):
            let (_, setLog) = try findSet(setID, in: session)
            setLog.load = load
            setLog.reps = reps
            setLog.rir = rir
            setLog.updatedAt = event.occurredAt
        case .setDeleted(let setID):
            let (exercise, setLog) = try findSet(setID, in: session)
            // Tira da relação antes de apagar, para o array em memória refletir já a remoção.
            exercise.sets.removeAll { $0.uuid == setID }
            context.delete(setLog)
        case .exerciseSkipped(let sessionExerciseID):
            let exercise = try sessionExercise(sessionExerciseID, in: session)
            exercise.wasSkipped = true
        case .sessionFinished(let endedAt):
            session.statusRaw = SessionStatus.completed.rawValue
            session.endedAt = endedAt
        case .sessionAbandoned(let endedAt):
            session.statusRaw = SessionStatus.abandoned.rawValue
            session.endedAt = endedAt
        case .sessionStarted, .exerciseSubstituted, .heartRateSummary:
            // A troca chega por `substituteExercise`; o resto não é disparado pela tela.
            break
        }
        try context.save()
        appliedEvents.append(event)
    }

    /// Contrato do M2 (RF-34): só sem séries; troca exercício e prescrição do snapshot inteiro.
    func substituteExercise(sessionID: UUID, sessionExerciseID: UUID, with planned: PlannedExercise, now: Date) throws {
        substituteCalls.append(SubstituteCall(
            sessionID: sessionID,
            sessionExerciseID: sessionExerciseID,
            planned: planned,
            now: now
        ))
        if let errorToThrow {
            throw errorToThrow
        }
        guard let session = session(withID: sessionID) else {
            throw SessionCoordinatorError.sessionNotFound(sessionID)
        }
        let exercise = try sessionExercise(sessionExerciseID, in: session)
        guard exercise.sets.isEmpty else {
            throw SessionCoordinatorError.unsupported
        }
        let newID = planned.exercise.id
        let descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate<ExerciseModel> { $0.uuid == newID }
        )
        guard let catalogItem = try context.fetch(descriptor).first else {
            throw SessionCoordinatorError.exerciseNotFound(newID)
        }
        exercise.substitutedFromUUID = exercise.exerciseUUID
        exercise.exerciseUUID = catalogItem.uuid
        exercise.exerciseName = catalogItem.name
        exercise.exercise = catalogItem
        exercise.prescribedLoad = planned.prescription.load
        exercise.prescribedSets = planned.prescription.sets
        exercise.prescribedRepMin = planned.prescription.repMin
        exercise.prescribedRepMax = planned.prescription.repMax
        exercise.prescribedRIR = planned.prescription.targetRIR
        exercise.prescribedTargetReps = planned.prescription.targetReps
        exercise.restSeconds = planned.prescription.restSeconds
        exercise.noteRaw = planned.prescription.note.rawValue
        try context.save()
    }

    /// Ninguém observa eventos nestes testes: o stream nasce encerrado.
    var eventsApplied: AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    private func sessionExercise(_ id: UUID, in session: WorkoutSessionModel) throws -> SessionExerciseModel {
        guard let exercise = session.exercises.first(where: { $0.uuid == id }) else {
            throw SessionCoordinatorError.sessionExerciseNotFound(id)
        }
        return exercise
    }

    private func findSet(_ setID: UUID, in session: WorkoutSessionModel) throws -> (SessionExerciseModel, SetLogModel) {
        for exercise in session.exercises {
            if let setLog = exercise.sets.first(where: { $0.uuid == setID }) {
                return (exercise, setLog)
            }
        }
        throw SessionCoordinatorError.setNotFound(setID)
    }
}

// MARK: - Double do planner

/// Troca (RF-34), "Da última vez" (RF-47) e o resumo (objetivo ativo e próxima sessão). Registra
/// as chamadas; a prescrição da troca é a de um exercício nunca feito (SPEC P2: RIR alvo + 1).
@MainActor
private final class SessionTestPlanner: SessionPlanning {
    struct SubstitutesCall: Equatable {
        let exerciseID: UUID
        let limit: Int
    }

    struct SubstitutionPlanCall {
        let sessionExerciseID: UUID
        let target: ExerciseTarget
        let newExerciseID: UUID
        let now: Date
    }

    var substitutesResult: [ExerciseDefinition] = []
    var substitutesError: PlanningError?
    var substitutionError: PlanningError?
    var lastSessionResult: ExerciseLastSession?
    var lastSessionError: PlanningError?
    var activeGoalResult: ProgramGoal?
    var activeGoalError: PlanningError?
    var nextPlanResult: SessionPlan?
    var nextPlanError: PlanningError?
    private(set) var substitutesCalls: [SubstitutesCall] = []
    private(set) var substitutionPlanCalls: [SubstitutionPlanCall] = []
    private(set) var lastSessionCalls: [UUID] = []
    private(set) var nextPlanDates: [Date] = []
    private let catalog: [ExerciseDefinition]

    init(catalog: [ExerciseDefinition]) {
        self.catalog = catalog
    }

    func nextPlan(now: Date) throws -> SessionPlan? {
        nextPlanDates.append(now)
        if let nextPlanError {
            throw nextPlanError
        }
        return nextPlanResult
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        nil
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        throw PlanningError.noActiveProgram
    }

    func activeProgramGoal() throws -> ProgramGoal? {
        if let activeGoalError {
            throw activeGoalError
        }
        return activeGoalResult
    }

    func lastSession(forExerciseID exerciseID: UUID) throws -> ExerciseLastSession? {
        lastSessionCalls.append(exerciseID)
        if let lastSessionError {
            throw lastSessionError
        }
        return lastSessionResult
    }

    func substitutes(for exerciseID: UUID, limit: Int) throws -> [ExerciseDefinition] {
        substitutesCalls.append(SubstitutesCall(exerciseID: exerciseID, limit: limit))
        if let substitutesError {
            throw substitutesError
        }
        return substitutesResult
    }

    func substitutionPlan(
        replacing sessionExerciseID: UUID,
        target: ExerciseTarget,
        newExerciseID: UUID,
        now: Date
    ) throws -> PlannedExercise {
        substitutionPlanCalls.append(SubstitutionPlanCall(
            sessionExerciseID: sessionExerciseID,
            target: target,
            newExerciseID: newExerciseID,
            now: now
        ))
        if let substitutionError {
            throw substitutionError
        }
        guard let exercise = catalog.first(where: { $0.id == newExerciseID }) else {
            throw PlanningError.exerciseNotFound(newExerciseID)
        }
        let prescription = ExercisePrescription(
            exerciseID: newExerciseID,
            load: nil,
            sets: target.sets,
            repMin: target.repMin,
            repMax: target.repMax,
            targetReps: target.repMin,
            targetRIR: target.targetRIR + 1,
            restSeconds: target.restSeconds,
            note: .calibrate
        )
        return PlannedExercise(id: sessionExerciseID, exercise: exercise, target: target, prescription: prescription)
    }
}
