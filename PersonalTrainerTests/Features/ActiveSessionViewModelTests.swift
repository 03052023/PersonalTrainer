import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T1.5: seleção, rascunho da série (RF-04), avanço, pular (RF-10), finalizar (RF-02) e
/// totais. Usa um coordinator em memória próprio (`SessionTestCoordinator`) sobre um
/// container in-memory: o `SessionCoordinator` real (T1.3) é escrito em paralelo e tem
/// testes próprios. Tudo em `@MainActor` (ARCHITECTURE §10).
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
    }

    func testInit_finishedSession_isFinished() throws {
        let fixture = try makeFixture()
        fixture.session.statusRaw = SessionStatus.completed.rawValue
        fixture.session.endedAt = start.addingTimeInterval(3_600)
        try fixture.coordinator.context.save()

        let model = makeViewModel(fixture)

        XCTAssertTrue(model.isFinished)
        XCTAssertEqual(model.stats.duration, 3_600)
    }

    // MARK: - Rascunho inicial (RF-04, 1ª série = prescrição)

    func testInitialDraft_usesPrescriptionAndCatalogIncrement() throws {
        let fixture = try makeFixture()

        let model = makeViewModel(fixture)

        let draft = try XCTUnwrap(model.currentDraft)
        XCTAssertEqual(draft.load, 100)
        XCTAssertEqual(draft.reps, 8, "meta inicial = repMin")
        XCTAssertEqual(draft.rir, 2)
        XCTAssertFalse(draft.isWarmup)
        XCTAssertEqual(draft.setIndex, 0)
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
        // Máquina do leg press ocupada: o usuário vai direto ao supino.
        model.select(exerciseID: fixture.bench.uuid)

        model.completeSet()
        model.completeSet()

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
        let session: WorkoutSessionModel
        /// `order` 0, carga prescrita 100 kg, 3 × 8–12, RIR 2, descanso 120 s, nota `increase`,
        /// catálogo com incremento 5 kg.
        let legPress: SessionExerciseModel
        /// `order` 1, sem carga prescrita (calibrar), 2 × 8–12, RIR 3, descanso 90 s,
        /// catálogo com incremento 2,5 kg.
        let bench: SessionExerciseModel
        let timer: RestTimer
    }

    private func makeViewModel(_ fixture: Fixture) -> ActiveSessionViewModel {
        ActiveSessionViewModel(
            sessionID: fixture.session.uuid,
            coordinator: fixture.coordinator,
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

        return Fixture(
            coordinator: coordinator,
            session: session,
            legPress: legPress,
            bench: bench,
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

/// `SessionCoordinating` em memória sobre modelos reais: aplica `setLogged`,
/// `exerciseSkipped`, `sessionFinished` e `sessionAbandoned` num container in-memory e
/// registra os eventos aplicados. `errorToThrow` simula falha do caminho de escrita.
@MainActor
private final class SessionTestCoordinator: SessionCoordinating {
    let container: ModelContainer
    private(set) var appliedEvents: [SessionEvent] = []
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
            guard let exercise = session.exercises.first(where: { $0.uuid == sessionExerciseID }) else {
                throw SessionCoordinatorError.sessionExerciseNotFound(sessionExerciseID)
            }
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
        case .exerciseSkipped(let sessionExerciseID):
            guard let exercise = session.exercises.first(where: { $0.uuid == sessionExerciseID }) else {
                throw SessionCoordinatorError.sessionExerciseNotFound(sessionExerciseID)
            }
            exercise.wasSkipped = true
        case .sessionFinished(let endedAt):
            session.statusRaw = SessionStatus.completed.rawValue
            session.endedAt = endedAt
        case .sessionAbandoned(let endedAt):
            session.statusRaw = SessionStatus.abandoned.rawValue
            session.endedAt = endedAt
        case .sessionStarted, .setUpdated, .setDeleted, .exerciseSubstituted, .heartRateSummary:
            // Não são disparados pela tela de sessão em M1.
            break
        }
        try context.save()
        appliedEvents.append(event)
    }

    /// Ninguém observa eventos nestes testes: o stream nasce encerrado.
    var eventsApplied: AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
