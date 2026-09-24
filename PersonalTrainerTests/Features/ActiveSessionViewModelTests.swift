import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T1.5 + T2.9: seleção, rascunho da série (RF-04, P5), avanço, pular (RF-10), finalizar
/// (RF-02), totais, confirmação de 0 kg na calibração (P2/P8), troca de exercício (RF-34) e
/// correção/remoção de série (RF-19). Usa doubles próprios (`SessionTestCoordinator`,
/// `SessionTestPlanner`, `SessionTestCatalog`) sobre um container in-memory: o coordinator e o
/// planner reais têm testes próprios. Tudo em `@MainActor` (ARCHITECTURE §10).
@MainActor
final class ActiveSessionViewModelTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    /// Relógio injetado no ViewModel; cada teste avança como precisar (SPEC P11).
    private var clock = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Seleção inicial

    func testInitialSelection_firstExerciseWithPendingWorkingSets() throws {
        let fixture = try makeFixture()

        let model = makeViewModel(fixture)

        XCTAssertEqual(model.exercises.map(\.uuid), [fixture.legPress.uuid, fixture.bench.uuid], "ordenado por `order`, não por inserção")
        XCTAssertEqual(model.selectedExerciseID, fixture.legPress.uuid)
        XCTAssertEqual(model.selectedExercise?.uuid, fixture.legPress.uuid)
        XCTAssertFalse(model.isFinished)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.session?.uuid, fixture.session.uuid)
        XCTAssertFalse(model.needsZeroLoadConfirmation)
        XCTAssertFalse(model.isShowingSubstituteSheet)
        XCTAssertNil(model.editingSet)
    }

    func testInitialSelection_skipsCompletedExercise() throws {
        let fixture = try makeFixture()
        // Aquecimento não conta (SPEC P1): 1 aquecimento + 3 de trabalho = completo.
        insertSet(fixture, exercise: fixture.legPress, index: 0, load: 60, reps: 12, rir: nil, isWarmup: true)
        insertSet(fixture, exercise: fixture.legPress, index: 1, load: 100, reps: 10, rir: 2, isWarmup: false)
        insertSet(fixture, exercise: fixture.legPress, index: 2, load: 100, reps: 10, rir: 2, isWarmup: false)
        insertSet(fixture, exercise: fixture.legPress, index: 3, load: 100, reps: 9, rir: 1, isWarmup: false)
        try fixture.coordinator.context.save()

        let model = makeViewModel(fixture)

        XCTAssertEqual(model.selectedExerciseID, fixture.bench.uuid)
    }

    func testInitialSelection_onlyWarmups_isStillPending() throws {
        let fixture = try makeFixture()
        insertSet(fixture, exercise: fixture.legPress, index: 0, load: 60, reps: 12, rir: nil, isWarmup: true)
        insertSet(fixture, exercise: fixture.legPress, index: 1, load: 80, reps: 8, rir: nil, isWarmup: true)
        insertSet(fixture, exercise: fixture.legPress, index: 2, load: 90, reps: 5, rir: nil, isWarmup: true)
        try fixture.coordinator.context.save()

        let model = makeViewModel(fixture)

        XCTAssertEqual(model.selectedExerciseID, fixture.legPress.uuid)
        XCTAssertEqual(model.currentDraft?.setIndex, 3, "o índice conta todas as séries, aquecimento incluído")
        XCTAssertEqual(model.currentDraft?.setNumber, 4)
    }

    func testInitialSelection_nothingPending_selectsLastExercise() throws {
        let fixture = try makeFixture()
        insertSet(fixture, exercise: fixture.legPress, index: 0, load: 100, reps: 10, rir: 2, isWarmup: false)
        insertSet(fixture, exercise: fixture.legPress, index: 1, load: 100, reps: 10, rir: 2, isWarmup: false)
        insertSet(fixture, exercise: fixture.legPress, index: 2, load: 100, reps: 10, rir: 2, isWarmup: false)
        fixture.bench.wasSkipped = true
        try fixture.coordinator.context.save()

        let model = makeViewModel(fixture)

        XCTAssertEqual(model.selectedExerciseID, fixture.bench.uuid)
        XCTAssertNil(model.currentDraft, "exercício pulado não tem série a registrar")
    }

    func testInit_unknownSession_setsErrorMessage() throws {
        let fixture = try makeFixture()

        let model = ActiveSessionViewModel(
            sessionID: UUID(),
            coordinator: fixture.coordinator,
            planner: fixture.planner,
            catalog: fixture.catalog,
            restTimer: fixture.timer,
            notifications: FakeNotificationScheduler(),
            now: { self.clock }
        )

        XCTAssertNil(model.session)
        XCTAssertEqual(model.errorMessage, "Sessão não encontrada.")
        XCTAssertTrue(model.isShowingError)
        XCTAssertTrue(model.exercises.isEmpty)
        XCTAssertNil(model.selectedExerciseID)
        XCTAssertNil(model.currentDraft)
        XCTAssertEqual(model.stats.workingSetCount, 0)
        XCTAssertFalse(model.isFinished)
        XCTAssertFalse(model.canSubstituteSelectedExercise)
    }

    func testInit_finishedSession_isFinished() throws {
        let fixture = try makeFixture()
        fixture.session.statusRaw = SessionStatus.completed.rawValue
        fixture.session.endedAt = start.addingTimeInterval(3_600)
        try fixture.coordinator.context.save()

        let model = makeViewModel(fixture)

        XCTAssertTrue(model.isFinished)
        XCTAssertEqual(model.stats.duration, 3_600)
        XCTAssertFalse(model.canSubstituteSelectedExercise, "sessão encerrada não troca exercício")
    }

    // MARK: - Rascunho inicial (RF-04, 1ª série = prescrição)

    func testInitialDraft_usesPrescriptionAndCatalogIncrement() throws {
        let fixture = try makeFixture()

        let model = makeViewModel(fixture)

        let draft = try XCTUnwrap(model.currentDraft)
        XCTAssertEqual(draft.load, 100)
        XCTAssertEqual(draft.reps, 8, "sem meta gravada (prescribedTargetReps = 0), começa em repMin")
        XCTAssertEqual(draft.rir, 2)
        XCTAssertFalse(draft.isWarmup)
        XCTAssertEqual(draft.setIndex, 0)
        XCTAssertEqual(draft.setNumber, 1)
        XCTAssertEqual(draft.plannedSets, 3)
        XCTAssertEqual(draft.prescribedLoad, 100, "carga prescrita do snapshot, só para exibição")
        XCTAssertEqual(draft.loadIncrement, 5, "vem do ExerciseModel relacionado")
        XCTAssertEqual(draft.loadUnit, .kilograms)
        XCTAssertEqual(draft.repMin, 8)
        XCTAssertEqual(draft.repMax, 12)
        XCTAssertEqual(draft.targetReps, 8)
        XCTAssertEqual(draft.targetRIR, 2)
        XCTAssertEqual(draft.note, .increase)
    }

    func testP5_initialDraft_usesPrescribedTargetRepsWhenKnown() throws {
        let fixture = try makeFixture()
        // SPEC P5 (hold): meta = min(repMax, menor reps da última sessão + 1), gravada no snapshot.
        fixture.legPress.noteRaw = PrescriptionNote.hold.rawValue
        fixture.legPress.prescribedTargetReps = 10
        try fixture.coordinator.context.save()

        let model = makeViewModel(fixture)

        let draft = try XCTUnwrap(model.currentDraft)
        XCTAssertEqual(draft.reps, 10, "a 1ª série parte da meta do motor, não de repMin")
        XCTAssertEqual(draft.targetReps, 10)
        XCTAssertEqual(draft.repMin, 8, "a faixa exibida continua 8–12")
        XCTAssertEqual(model.prescriptionSummary(for: fixture.legPress), "3 × 8–12 · 100 kg · RIR 2")
    }

    func testP5_laterSets_copyPreviousRepsNotTarget() throws {
        let fixture = try makeFixture()
        fixture.legPress.prescribedTargetReps = 10
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)
        var draft = try XCTUnwrap(model.currentDraft)
        draft.reps = 11
        model.currentDraft = draft

        model.completeSet()

        XCTAssertEqual(model.currentDraft?.reps, 11, "RF-04: a 2ª série copia o registro real")
        XCTAssertEqual(model.currentDraft?.targetReps, 10)
    }

    func testInitialDraft_withoutPrescribedLoad_startsAtZero() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        model.select(exerciseID: fixture.bench.uuid)

        XCTAssertEqual(model.selectedExerciseID, fixture.bench.uuid)
        let draft = try XCTUnwrap(model.currentDraft)
        XCTAssertEqual(draft.load, 0, "SPEC P2 sem startingLoad: o usuário digita")
        XCTAssertNil(draft.prescribedLoad, "a prescrição continua vazia; só o stepper começa em 0")
        XCTAssertEqual(draft.reps, 8)
        XCTAssertEqual(draft.rir, 3)
        XCTAssertEqual(draft.plannedSets, 2)
        XCTAssertEqual(draft.loadIncrement, 2.5)
        XCTAssertEqual(draft.note, .calibrate)
    }

    func testInitialDraft_withoutCatalogRelation_usesDefaults() throws {
        let fixture = try makeFixture()
        fixture.legPress.exercise = nil
        fixture.legPress.noteRaw = "unknown-note"
        try fixture.coordinator.context.save()

        let model = makeViewModel(fixture)

        let draft = try XCTUnwrap(model.currentDraft)
        XCTAssertEqual(draft.loadIncrement, 2.5)
        XCTAssertEqual(draft.loadUnit, .kilograms)
        XCTAssertEqual(draft.note, .hold)
    }

    func testPrescriptionSummary_formatsSnapshotPrescription() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        XCTAssertEqual(model.prescriptionSummary(for: fixture.legPress), "3 × 8–12 · 100 kg · RIR 2")
        // SPEC P2: carga vazia é "—" (mesma convenção da Home e do histórico), nunca "0 kg".
        XCTAssertEqual(model.prescriptionSummary(for: fixture.bench), "2 × 8–12 · — · RIR 3")
    }

    func testPrescriptionSummary_doesNotFollowEditedLoad() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        var draft = try XCTUnwrap(model.currentDraft)
        draft.load = 120

        XCTAssertEqual(draft.prescriptionSummary, "3 × 8–12 · 100 kg · RIR 2", "o texto rotulado de prescrição não muda com o stepper")

        model.select(exerciseID: fixture.bench.uuid)
        var calibration = try XCTUnwrap(model.currentDraft)
        calibration.load = 30
        XCTAssertEqual(calibration.prescriptionSummary, "2 × 8–12 · — · RIR 3")
    }

    // MARK: - completeSet (RF-03, RF-04, RF-05, RF-06)

    func testCompleteSet_persistsSetAndNextDraftCopiesPrevious() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        var draft = try XCTUnwrap(model.currentDraft)
        draft.load = 102.5
        draft.reps = 9
        draft.rir = 1
        model.currentDraft = draft
        clock = start.addingTimeInterval(300)

        model.completeSet()

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(fixture.coordinator.appliedEvents.count, 1)
        let sets = fixture.legPress.sets
        XCTAssertEqual(sets.count, 1)
        let stored = try XCTUnwrap(sets.first)
        XCTAssertEqual(stored.index, 0)
        XCTAssertEqual(stored.load, 102.5)
        XCTAssertEqual(stored.reps, 9)
        XCTAssertEqual(stored.rir, 1)
        XCTAssertFalse(stored.isWarmup)
        XCTAssertEqual(stored.completedAt, clock, "hora vem do relógio injetado")

        // RF-04: a 2ª série copia os valores reais da 1ª; a prescrição exibida não muda.
        let next = try XCTUnwrap(model.currentDraft)
        XCTAssertEqual(next.setIndex, 1)
        XCTAssertEqual(next.setNumber, 2)
        XCTAssertEqual(next.load, 102.5)
        XCTAssertEqual(next.reps, 9)
        XCTAssertEqual(next.rir, 1)
        XCTAssertFalse(next.isWarmup)
        XCTAssertEqual(next.prescribedLoad, 100)
        XCTAssertEqual(next.prescriptionSummary, "3 × 8–12 · 100 kg · RIR 2")
        XCTAssertEqual(model.selectedExerciseID, fixture.legPress.uuid, "ainda faltam séries: não avança")

        // RF-05: descanso do exercício começa em `now`.
        XCTAssertTrue(fixture.timer.isRunning)
        XCTAssertEqual(fixture.timer.remainingSeconds(at: clock), 120)
    }

    func testCompleteSet_warmup_advancesIndexWithoutStartingTimer() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        var draft = try XCTUnwrap(model.currentDraft)
        draft.load = 60
        draft.reps = 12
        draft.rir = nil
        draft.isWarmup = true
        model.currentDraft = draft

        model.completeSet()

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(fixture.legPress.sets.count, 1)
        XCTAssertEqual(fixture.legPress.sets.first?.isWarmup, true)
        XCTAssertFalse(fixture.timer.isRunning, "aquecimento não inicia descanso")
        let next = try XCTUnwrap(model.currentDraft)
        XCTAssertEqual(next.setIndex, 1)
        XCTAssertFalse(next.isWarmup, "o rascunho seguinte volta a ser série de trabalho")
        XCTAssertEqual(next.load, 60, "copia a anterior mesmo sendo aquecimento; o usuário ajusta")
        XCTAssertEqual(model.workingSetCount(of: fixture.legPress), 0)
        XCTAssertEqual(model.selectedExerciseID, fixture.legPress.uuid)
    }

    func testCompleteSet_afterPrescribedSets_advancesToNextExercise() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        model.completeSet()
        model.completeSet()
        XCTAssertEqual(model.selectedExerciseID, fixture.legPress.uuid, "2 de 3: continua")
        XCTAssertEqual(model.currentDraft?.setIndex, 2)

        model.completeSet()

        XCTAssertEqual(model.workingSetCount(of: fixture.legPress), 3)
        XCTAssertEqual(model.selectedExerciseID, fixture.bench.uuid, "3 de 3: avança para o próximo pendente")
        let draft = try XCTUnwrap(model.currentDraft)
        XCTAssertEqual(draft.setIndex, 0)
        XCTAssertEqual(draft.plannedSets, 2)
        XCTAssertEqual(draft.load, 0)
    }

    func testCompleteSet_wrapsAroundToEarlierPendingExercise() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        // Máquina do leg press ocupada: o usuário vai direto ao supino e digita a carga
        // (calibração sem carga prescrita, SPEC P2).
        model.select(exerciseID: fixture.bench.uuid)
        model.currentDraft?.load = 40

        model.completeSet()
        model.completeSet()

        XCTAssertFalse(model.needsZeroLoadConfirmation)
        XCTAssertEqual(model.workingSetCount(of: fixture.bench), 2)
        XCTAssertEqual(model.selectedExerciseID, fixture.legPress.uuid, "volta ao que ficou para trás")
        XCTAssertEqual(model.currentDraft?.setIndex, 0)
    }

    func testCompleteSet_lastPendingExercise_staysSelectedAndAllowsExtraSet() throws {
        let fixture = try makeFixture()
        fixture.bench.wasSkipped = true
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)

        model.completeSet()
        model.completeSet()
        model.completeSet()

        XCTAssertEqual(model.selectedExerciseID, fixture.legPress.uuid)
        XCTAssertEqual(model.currentDraft?.setIndex, 3, "SPEC P10: o usuário pode registrar mais que o prescrito")
    }

    func testCompleteSet_coordinatorError_setsMessageAndKeepsDraft() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        fixture.coordinator.errorToThrow = .sessionNotInProgress(fixture.session.uuid)

        model.completeSet()

        XCTAssertEqual(model.errorMessage, "Esta sessão já foi encerrada.")
        XCTAssertTrue(model.isShowingError)
        XCTAssertTrue(fixture.legPress.sets.isEmpty)
        XCTAssertEqual(model.currentDraft?.setIndex, 0, "rascunho preservado para tentar de novo")
        XCTAssertFalse(fixture.timer.isRunning)
        XCTAssertTrue(fixture.coordinator.appliedEvents.isEmpty)

        // Fechar o alerta limpa a mensagem.
        model.isShowingError = false
        XCTAssertNil(model.errorMessage)
    }

    func testCompleteSet_withoutDraft_doesNothing() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.currentDraft = nil

        model.completeSet()

        XCTAssertTrue(fixture.coordinator.appliedEvents.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.needsZeroLoadConfirmation)
    }

    // MARK: - Confirmação de 0 kg (SPEC P2, P8)

    func testP2_calibrationAtZeroLoad_asksBeforeLogging() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.select(exerciseID: fixture.bench.uuid)
        XCTAssertEqual(model.currentDraft?.load, 0)

        model.completeSet()

        XCTAssertTrue(model.needsZeroLoadConfirmation, "sem carga prescrita e sem carga digitada: pergunta")
        XCTAssertTrue(fixture.coordinator.appliedEvents.isEmpty, "nada gravado antes da confirmação")
        XCTAssertTrue(fixture.bench.sets.isEmpty)
        XCTAssertFalse(fixture.timer.isRunning)

        // "Corrigir carga": fecha sem gravar e mantém o rascunho.
        model.cancelZeroLoadSet()

        XCTAssertFalse(model.needsZeroLoadConfirmation)
        XCTAssertTrue(fixture.coordinator.appliedEvents.isEmpty)
        XCTAssertEqual(model.currentDraft?.setIndex, 0)
        XCTAssertEqual(model.selectedExerciseID, fixture.bench.uuid)
    }

    func testP2_calibrationAtZeroLoad_confirmedLogsZero() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.select(exerciseID: fixture.bench.uuid)
        model.completeSet()
        XCTAssertTrue(model.needsZeroLoadConfirmation)

        model.confirmZeroLoadSet()

        XCTAssertFalse(model.needsZeroLoadConfirmation)
        XCTAssertEqual(fixture.bench.sets.count, 1)
        XCTAssertEqual(fixture.bench.sets.first?.load, 0)
        XCTAssertEqual(fixture.coordinator.appliedEvents.count, 1)
        XCTAssertEqual(model.currentDraft?.setIndex, 1)
    }

    func testP2_calibrationWithTypedLoad_logsWithoutAsking() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.select(exerciseID: fixture.bench.uuid)
        model.currentDraft?.load = 40

        model.completeSet()

        XCTAssertFalse(model.needsZeroLoadConfirmation)
        XCTAssertEqual(fixture.bench.sets.first?.load, 40)
    }

    func testP8_bodyweightAtZeroLoad_logsWithoutAsking() throws {
        let fixture = try makeFixture()
        fixture.benchCatalog.equipmentRaw = Equipment.bodyweight.rawValue
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)
        model.select(exerciseID: fixture.bench.uuid)

        model.completeSet()

        XCTAssertFalse(model.needsZeroLoadConfirmation, "SPEC P8: 0 é peso corporal puro")
        XCTAssertEqual(fixture.bench.sets.count, 1)
        XCTAssertEqual(fixture.bench.sets.first?.load, 0)
    }

    func testZeroLoad_withPrescribedLoad_logsWithoutAsking() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.currentDraft?.load = 0

        model.completeSet()

        XCTAssertFalse(model.needsZeroLoadConfirmation, "só a calibração sem carga pergunta")
        XCTAssertEqual(fixture.legPress.sets.first?.load, 0)
    }

    // MARK: - Pular (RF-10)

    func testSkip_marksExerciseAndAdvances() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        model.skipCurrentExercise()

        XCTAssertTrue(fixture.legPress.wasSkipped)
        XCTAssertEqual(model.selectedExerciseID, fixture.bench.uuid)
        let draft = try XCTUnwrap(model.currentDraft)
        XCTAssertEqual(draft.setIndex, 0)
        XCTAssertEqual(draft.plannedSets, 2)
        XCTAssertEqual(fixture.coordinator.appliedEvents.count, 1)

        // Último pendente pulado: fica nele, sem série a registrar.
        model.skipCurrentExercise()

        XCTAssertTrue(fixture.bench.wasSkipped)
        XCTAssertEqual(model.selectedExerciseID, fixture.bench.uuid)
        XCTAssertNil(model.currentDraft)
    }

    func testSkip_keepsSetsAlreadyLogged() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.completeSet()

        model.skipCurrentExercise()

        XCTAssertTrue(fixture.legPress.wasSkipped)
        XCTAssertEqual(fixture.legPress.sets.count, 1)
        XCTAssertEqual(model.stats.workingSetCount, 1)
    }

    // MARK: - Selecionar

    func testSelect_changesDraftToThatExercise() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        model.select(exerciseID: fixture.bench.uuid)
        XCTAssertEqual(model.selectedExerciseID, fixture.bench.uuid)
        XCTAssertEqual(model.currentDraft?.plannedSets, 2)

        model.select(exerciseID: fixture.legPress.uuid)
        XCTAssertEqual(model.selectedExerciseID, fixture.legPress.uuid)
        XCTAssertEqual(model.currentDraft?.plannedSets, 3)
    }

    func testSelect_unknownID_isIgnored() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        model.select(exerciseID: UUID())

        XCTAssertEqual(model.selectedExerciseID, fixture.legPress.uuid)
        XCTAssertNotNil(model.currentDraft)
    }

    // MARK: - Trocar exercício (RF-34)

    func testRF34_substitution_allowedOnlyBeforeFirstSet() throws {
        let fixture = try makeFixture()
        fixture.planner.substitutesResult = [fixture.hackDefinition]
        let model = makeViewModel(fixture)
        XCTAssertTrue(model.canSubstituteSelectedExercise, "sem séries: pode trocar")

        model.completeSet()

        XCTAssertFalse(model.canSubstituteSelectedExercise, "com série registrada: não troca")
        model.beginSubstitution()
        XCTAssertFalse(model.isShowingSubstituteSheet)
        XCTAssertTrue(fixture.planner.substitutesCalls.isEmpty)
        model.substituteSelectedExercise(with: fixture.hackDefinition)
        XCTAssertTrue(fixture.planner.substitutionPlanCalls.isEmpty, "o planner nem é consultado")
        XCTAssertTrue(fixture.coordinator.substituteCalls.isEmpty, "o coordinator nem é chamado")
        XCTAssertEqual(fixture.legPress.exerciseUUID, fixture.legPressCatalog.uuid)

        // Apagar a única série libera a troca de novo.
        let setID = try XCTUnwrap(fixture.legPress.sets.first?.uuid)
        model.deleteSet(id: setID)

        XCTAssertTrue(model.canSubstituteSelectedExercise)
    }

    func testRF34_skippedExercise_cannotBeSubstituted() throws {
        let fixture = try makeFixture()
        fixture.bench.wasSkipped = true
        try fixture.coordinator.context.save()
        let model = makeViewModel(fixture)
        model.select(exerciseID: fixture.bench.uuid)

        XCTAssertFalse(model.canSubstituteSelectedExercise)
        model.beginSubstitution()
        XCTAssertFalse(model.isShowingSubstituteSheet)
        XCTAssertTrue(fixture.planner.substitutesCalls.isEmpty)
    }

    func testRF34_beginSubstitution_loadsSuggestionsAndCatalog() throws {
        let fixture = try makeFixture()
        // O supino já está na sessão: não é sugerido de novo.
        fixture.planner.substitutesResult = [fixture.benchDefinition, fixture.hackDefinition]
        let model = makeViewModel(fixture)

        model.beginSubstitution()

        XCTAssertTrue(model.isShowingSubstituteSheet)
        XCTAssertEqual(
            fixture.planner.substitutesCalls,
            [SessionTestPlanner.SubstitutesCall(exerciseID: fixture.legPressCatalog.uuid, limit: 20)]
        )
        XCTAssertEqual(model.substituteSuggestions.map(\.id), [fixture.hackDefinition.id])
        XCTAssertEqual(
            Set(model.substitutionCatalog.map(\.id)),
            Set([fixture.benchDefinition.id, fixture.hackDefinition.id]),
            "\"Ver todos\" traz o catálogo sem o exercício atual"
        )

        model.cancelSubstitution()

        XCTAssertFalse(model.isShowingSubstituteSheet)
        XCTAssertTrue(model.substituteSuggestions.isEmpty)
        XCTAssertTrue(model.substitutionCatalog.isEmpty)
        XCTAssertTrue(fixture.coordinator.substituteCalls.isEmpty)
    }

    func testRF34_beginSubstitution_listFailures_leaveEmptyListsButOpenSheet() throws {
        let fixture = try makeFixture()
        fixture.planner.substitutesError = .noActiveProgram
        fixture.catalog.error = .invalidDraft
        let model = makeViewModel(fixture)

        model.beginSubstitution()

        XCTAssertTrue(model.isShowingSubstituteSheet)
        XCTAssertTrue(model.substituteSuggestions.isEmpty)
        XCTAssertTrue(model.substitutionCatalog.isEmpty)
        XCTAssertNil(model.errorMessage)
    }

    func testRF34_substitute_buildsTargetFromSnapshotAndReplacesExercise() throws {
        let fixture = try makeFixture()
        fixture.planner.substitutesResult = [fixture.hackDefinition]
        let model = makeViewModel(fixture)
        clock = start.addingTimeInterval(120)
        model.beginSubstitution()

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

        XCTAssertEqual(fixture.coordinator.substituteCalls.count, 1)
        let substitution = try XCTUnwrap(fixture.coordinator.substituteCalls.first)
        XCTAssertEqual(substitution.sessionID, fixture.session.uuid)
        XCTAssertEqual(substitution.sessionExerciseID, fixture.legPress.uuid)
        XCTAssertEqual(substitution.planned.id, fixture.legPress.uuid, "mesmo snapshot, exercício novo")
        XCTAssertEqual(substitution.planned.exercise.id, fixture.hackDefinition.id)
        XCTAssertEqual(substitution.now, clock)

        XCTAssertFalse(model.isShowingSubstituteSheet)
        XCTAssertEqual(model.selectedExerciseID, fixture.legPress.uuid)
        XCTAssertEqual(fixture.legPress.exerciseUUID, fixture.hackCatalog.uuid)
        XCTAssertEqual(fixture.legPress.exerciseName, "Agachamento hack")
        XCTAssertEqual(fixture.legPress.substitutedFromUUID, fixture.legPressCatalog.uuid)

        // Rascunho refeito com a prescrição do novo (sem histórico: calibração, SPEC P2).
        let draft = try XCTUnwrap(model.currentDraft)
        XCTAssertNil(draft.prescribedLoad)
        XCTAssertEqual(draft.load, 0)
        XCTAssertEqual(draft.note, .calibrate)
        XCTAssertEqual(draft.targetRIR, 3)
        XCTAssertEqual(draft.loadIncrement, 10, "incremento do exercício novo")
        XCTAssertEqual(draft.setIndex, 0)
    }

    func testRF34_substituteCalibrationWithoutLoad_passesBaseRIR() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        // Supino: calibração sem carga, RIR gravado 3 = T + 1 (SPEC P2) com T = 2.
        model.select(exerciseID: fixture.bench.uuid)

        model.substituteSelectedExercise(with: fixture.hackDefinition)

        let call = try XCTUnwrap(fixture.planner.substitutionPlanCalls.first)
        XCTAssertEqual(call.target.targetRIR, 2, "sem desfazer o +1 o substituto calibraria com T + 2")
        XCTAssertEqual(call.target.sets, 2)
        XCTAssertEqual(call.target.restSeconds, 90)
        XCTAssertEqual(call.target.order, 1)
    }

    func testRF34_substitute_plannerError_showsMessageAfterSheetCloses() throws {
        let fixture = try makeFixture()
        fixture.planner.substitutionError = .exerciseNotFound(fixture.hackDefinition.id)
        let model = makeViewModel(fixture)
        model.beginSubstitution()

        model.substituteSelectedExercise(with: fixture.hackDefinition)

        XCTAssertFalse(model.isShowingSubstituteSheet)
        XCTAssertNil(model.errorMessage, "o alerta espera a folha terminar de fechar")
        XCTAssertTrue(fixture.coordinator.substituteCalls.isEmpty)
        XCTAssertEqual(fixture.legPress.exerciseUUID, fixture.legPressCatalog.uuid)

        model.sheetDidDismiss()

        XCTAssertEqual(model.errorMessage, "Não foi possível trocar o exercício.")

        // A mensagem só é entregue uma vez.
        model.isShowingError = false
        model.sheetDidDismiss()
        XCTAssertNil(model.errorMessage)
    }

    func testRF34_substitute_coordinatorRefuses_showsCoordinatorMessage() throws {
        let fixture = try makeFixture()
        fixture.coordinator.errorToThrow = .unsupported
        let model = makeViewModel(fixture)

        model.substituteSelectedExercise(with: fixture.hackDefinition)
        model.sheetDidDismiss()

        XCTAssertEqual(fixture.coordinator.substituteCalls.count, 1)
        XCTAssertEqual(model.errorMessage, "Esta ação não está disponível agora.")
        XCTAssertEqual(fixture.legPress.exerciseUUID, fixture.legPressCatalog.uuid)
    }

    // MARK: - Corrigir / apagar série (RF-19)

    func testRF19_beginEditingSet_copiesStoredValues() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.completeSet()
        let setID = try XCTUnwrap(fixture.legPress.sets.first?.uuid)

        model.beginEditingSet(id: setID)

        let edit = try XCTUnwrap(model.editingSet)
        XCTAssertEqual(edit.setID, setID)
        XCTAssertEqual(edit.id, setID)
        XCTAssertEqual(edit.number, 1)
        XCTAssertEqual(edit.load, 100)
        XCTAssertEqual(edit.reps, 8)
        XCTAssertEqual(edit.rir, 2)
        XCTAssertFalse(edit.isWarmup)
        XCTAssertEqual(edit.loadIncrement, 5)
        XCTAssertEqual(edit.loadUnit, .kilograms)
        XCTAssertEqual(edit.repMin, 8)
        XCTAssertEqual(edit.repMax, 12)

        model.cancelEditingSet()
        XCTAssertNil(model.editingSet)
        XCTAssertEqual(fixture.coordinator.appliedEvents.count, 1, "cancelar não grava nada")
    }

    func testRF19_beginEditingSet_unknownID_keepsSheetClosed() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)

        model.beginEditingSet(id: UUID())

        XCTAssertNil(model.editingSet)
    }

    func testRF19_saveEditedSet_updatesStoredSetAndNextDraft() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.completeSet()
        let setID = try XCTUnwrap(fixture.legPress.sets.first?.uuid)
        model.beginEditingSet(id: setID)
        var edit = try XCTUnwrap(model.editingSet)
        edit.load = 105
        edit.reps = 7
        edit.rir = nil
        clock = start.addingTimeInterval(400)

        model.saveEditedSet(edit)

        XCTAssertNil(model.editingSet)
        XCTAssertNil(model.errorMessage)
        let stored = try XCTUnwrap(fixture.legPress.sets.first)
        XCTAssertEqual(stored.load, 105)
        XCTAssertEqual(stored.reps, 7)
        XCTAssertNil(stored.rir)
        XCTAssertEqual(stored.updatedAt, clock)
        XCTAssertEqual(fixture.coordinator.appliedEvents.count, 2)
        XCTAssertEqual(
            fixture.coordinator.appliedEvents.last?.kind,
            .setUpdated(setID: setID, load: 105, reps: 7, rir: nil)
        )
        // RF-04: a próxima série copia a anterior já corrigida.
        let next = try XCTUnwrap(model.currentDraft)
        XCTAssertEqual(next.load, 105)
        XCTAssertEqual(next.reps, 7)
        XCTAssertNil(next.rir)
        XCTAssertEqual(next.setIndex, 1)
    }

    func testRF19_saveEditedSet_coordinatorError_showsMessageAfterSheetCloses() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.completeSet()
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

    func testRF19_deleteSet_removesItAndKeepsNextIndexUnique() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.completeSet()
        model.completeSet()
        let sorted = fixture.legPress.sets.sorted { $0.index < $1.index }
        XCTAssertEqual(sorted.map(\.index), [0, 1])
        let firstID = sorted[0].uuid
        let secondID = sorted[1].uuid
        model.beginEditingSet(id: firstID)
        XCTAssertEqual(model.editingSet?.number, 1)

        model.deleteSet(id: firstID)

        XCTAssertNil(model.editingSet)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(fixture.legPress.sets.map(\.uuid), [secondID])
        XCTAssertEqual(fixture.coordinator.appliedEvents.last?.kind, .setDeleted(setID: firstID))
        XCTAssertEqual(model.workingSetCount(of: fixture.legPress), 1)
        let next = try XCTUnwrap(model.currentDraft)
        XCTAssertEqual(next.setIndex, 2, "maior índice + 1: não colide com a série de índice 1 que ficou")
        XCTAssertEqual(next.setNumber, 2, "o título conta as séries que existem")
        XCTAssertEqual(model.selectedExerciseID, fixture.legPress.uuid)

        model.beginEditingSet(id: secondID)
        XCTAssertEqual(model.editingSet?.number, 1, "posição na lista, não índice + 1")
    }

    func testRF19_deleteSet_coordinatorError_keepsSetAndDefersMessage() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.completeSet()
        let setID = try XCTUnwrap(fixture.legPress.sets.first?.uuid)
        fixture.coordinator.errorToThrow = .sessionNotInProgress(fixture.session.uuid)

        model.deleteSet(id: setID)

        XCTAssertEqual(fixture.legPress.sets.count, 1)
        model.sheetDidDismiss()
        XCTAssertEqual(model.errorMessage, "Esta sessão já foi encerrada.")
    }

    // MARK: - Finalizar / abandonar (RF-02)

    func testFinish_marksFinishedAndStopsTimer() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.completeSet()
        XCTAssertTrue(fixture.timer.isRunning)
        clock = start.addingTimeInterval(1_800)

        model.finish()

        XCTAssertTrue(model.isFinished)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(fixture.session.status, .completed)
        XCTAssertEqual(fixture.session.endedAt, clock)
        XCTAssertFalse(fixture.timer.isRunning, "descanso pendente é cancelado ao finalizar")
        XCTAssertNil(fixture.coordinator.activeSession)
        XCTAssertEqual(model.stats.duration, 1_800)
    }

    func testAbandon_marksFinishedWithAbandonedStatus() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        model.completeSet()
        clock = start.addingTimeInterval(600)

        model.abandon()

        XCTAssertTrue(model.isFinished)
        XCTAssertEqual(fixture.session.status, .abandoned)
        XCTAssertEqual(fixture.session.endedAt, clock)
        XCTAssertFalse(fixture.timer.isRunning)
        XCTAssertEqual(fixture.legPress.sets.count, 1, "séries registradas continuam no histórico")
    }

    func testFinish_coordinatorError_keepsSessionOpen() throws {
        let fixture = try makeFixture()
        let model = makeViewModel(fixture)
        fixture.coordinator.errorToThrow = .sessionNotFound(fixture.session.uuid)

        model.finish()

        XCTAssertFalse(model.isFinished)
        XCTAssertEqual(model.errorMessage, "A sessão não foi encontrada.")
        XCTAssertEqual(fixture.session.status, .inProgress)
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
        XCTAssertEqual(stats.tonnage, 1_900, "Σ carga × reps só das séries de trabalho")
        XCTAssertEqual(stats.exerciseCount, 1, "supino sem série não conta")
        XCTAssertNil(stats.duration, "sessão em andamento não tem duração")
        XCTAssertEqual(model.workingSetCount(of: fixture.legPress), 2)
    }

    // MARK: - Fixtures

    private struct Fixture {
        let coordinator: SessionTestCoordinator
        let planner: SessionTestPlanner
        let catalog: SessionTestCatalog
        let session: WorkoutSessionModel
        /// `order` 0, carga prescrita 100 kg, 3 × 8–12, RIR 2, descanso 120 s, nota `increase`,
        /// catálogo com incremento 5 kg.
        let legPress: SessionExerciseModel
        /// `order` 1, sem carga prescrita (calibrar), 2 × 8–12, RIR 3, descanso 90 s,
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
            catalog: fixture.catalog,
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
        let catalogDefinitions = [legPressDefinition, benchDefinition, hackDefinition]

        return Fixture(
            coordinator: coordinator,
            planner: SessionTestPlanner(catalog: catalogDefinitions),
            catalog: SessionTestCatalog(exercises: catalogDefinitions),
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
        if let active = activeSession {
            throw SessionCoordinatorError.sessionAlreadyInProgress(active.uuid)
        }
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: plan.programDayID,
            programDayName: plan.programDayName,
            statusRaw: SessionStatus.inProgress.rawValue,
            startedAt: now,
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: source.rawValue
        )
        context.insert(session)
        for planned in plan.exercises {
            let exercise = SessionExerciseModel(
                uuid: planned.id,
                order: planned.target.order,
                exerciseUUID: planned.exercise.id,
                exerciseName: planned.exercise.name,
                prescribedLoad: planned.prescription.load,
                prescribedSets: planned.prescription.sets,
                prescribedRepMin: planned.prescription.repMin,
                prescribedRepMax: planned.prescription.repMax,
                prescribedRIR: planned.prescription.targetRIR,
                restSeconds: planned.prescription.restSeconds,
                noteRaw: planned.prescription.note.rawValue,
                wasSkipped: false,
                substitutedFromUUID: nil
            )
            exercise.prescribedTargetReps = planned.prescription.targetReps
            context.insert(exercise)
            session.exercises.append(exercise)
        }
        try context.save()
        return session.uuid
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

/// Só a parte de troca (RF-34) importa aqui. Registra as chamadas; a prescrição devolvida é a
/// calibração sem carga de um exercício nunca feito (SPEC P2: RIR alvo + 1).
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
    private(set) var substitutesCalls: [SubstitutesCall] = []
    private(set) var substitutionPlanCalls: [SubstitutionPlanCall] = []
    private let catalog: [ExerciseDefinition]

    init(catalog: [ExerciseDefinition]) {
        self.catalog = catalog
    }

    func nextPlan(now: Date) throws -> SessionPlan? {
        nil
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        nil
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        throw PlanningError.noActiveProgram
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

// MARK: - Double do catálogo

/// Catálogo fixo em memória; `error` simula falha de leitura. A sessão não escreve no catálogo.
@MainActor
private final class SessionTestCatalog: CatalogRepositoring {
    var error: CatalogRepositoryError?
    private let exercises: [ExerciseDefinition]

    init(exercises: [ExerciseDefinition]) {
        self.exercises = exercises
    }

    func allExercises(includeArchived: Bool) throws -> [ExerciseDefinition] {
        if let error {
            throw error
        }
        return exercises
    }

    func exercise(id: UUID) throws -> ExerciseDefinition? {
        if let error {
            throw error
        }
        return exercises.first { $0.id == id }
    }

    func createExercise(_ draft: ExerciseDraft) throws -> UUID {
        throw CatalogRepositoryError.invalidDraft
    }

    func updateExercise(id: UUID, with draft: ExerciseDraft) throws {
        throw CatalogRepositoryError.exerciseNotFound(id)
    }

    func setArchived(id: UUID, _ archived: Bool) throws {
        throw CatalogRepositoryError.exerciseNotFound(id)
    }
}
