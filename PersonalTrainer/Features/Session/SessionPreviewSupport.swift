import Foundation
import SwiftData
import TrainerCore

/// Dados e doubles para os `#Preview` da feature Sessão: uma sessão em andamento com um
/// exercício completo, um no meio (aquecimento + 1 série), um por fazer e um pulado — o
/// bastante para ver todos os estados dos chips e do painel.
///
/// O double do coordinator é `private` e prefixado pela feature para não colidir com os das
/// outras tarefas. Só previews usam `Date()` aqui: não é ViewModel nem serviço, e o timer de
/// descanso precisa do relógio real para contar na tela do Xcode.
@MainActor
enum SessionPreviewSupport {
    struct Fixture {
        let viewModel: ActiveSessionViewModel
        let session: WorkoutSessionModel
        /// Séries do exercício já completo, para o preview de `CompletedSetRow`.
        let completedSets: [SetLogModel]
        let skippedExercise: SessionExerciseModel?
    }

    /// `nil` só se o container in-memory não puder ser criado (o preview mostra um aviso).
    static func makeFixture() -> Fixture? {
        guard let coordinator = try? ActiveSessionPreviewCoordinator() else {
            return nil
        }
        let context = coordinator.context
        let now = Date()
        let startedAt = now.addingTimeInterval(-25 * 60)

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
            machineNotes: "Banco na posição 3, pés no alto da plataforma",
            isArchived: false
        )
        let squatCatalog = ExerciseModel(
            uuid: UUID(),
            slug: "agachamento-livre",
            name: "Agachamento livre",
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.quads, .glutes]),
            secondaryMusclesRaw: SchemaV1.encodeMuscleGroups([.core]),
            equipmentRaw: Equipment.barbell.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 2.5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        let extensionCatalog = ExerciseModel(
            uuid: UUID(),
            slug: "cadeira-extensora",
            name: "Cadeira extensora",
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.quads]),
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.machine.rawValue,
            loadUnitRaw: LoadUnit.plates.rawValue,
            loadIncrement: 1,
            isUnilateral: false,
            machineNotes: "Encosto 4",
            isArchived: false
        )
        let curlCatalog = ExerciseModel(
            uuid: UUID(),
            slug: "mesa-flexora",
            name: "Mesa flexora",
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.hamstrings]),
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.machine.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        for catalogItem in [legPressCatalog, squatCatalog, extensionCatalog, curlCatalog] {
            context.insert(catalogItem)
        }

        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia B — Inferior",
            statusRaw: SessionStatus.inProgress.rawValue,
            startedAt: startedAt,
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: DeviceSource.iphone.rawValue
        )
        context.insert(session)

        // 1. Leg press: completo (aquecimento + 3 de trabalho).
        let legPress = makeSessionExercise(
            order: 0,
            catalog: legPressCatalog,
            prescribedLoad: 140,
            prescribedSets: 3,
            prescribedRIR: 2,
            restSeconds: 120,
            note: .increase,
            in: context,
            session: session
        )
        let legPressSets = [
            makeSet(index: 0, load: 80, reps: 12, rir: nil, isWarmup: true, at: startedAt.addingTimeInterval(120), in: context, exercise: legPress),
            makeSet(index: 1, load: 140, reps: 10, rir: 2, isWarmup: false, at: startedAt.addingTimeInterval(300), in: context, exercise: legPress),
            makeSet(index: 2, load: 140, reps: 10, rir: 2, isWarmup: false, at: startedAt.addingTimeInterval(480), in: context, exercise: legPress),
            makeSet(index: 3, load: 140, reps: 9, rir: 1, isWarmup: false, at: startedAt.addingTimeInterval(660), in: context, exercise: legPress),
        ]

        // 2. Agachamento: pulado (barra ocupada).
        let squat = makeSessionExercise(
            order: 1,
            catalog: squatCatalog,
            prescribedLoad: 60,
            prescribedSets: 3,
            prescribedRIR: 2,
            restSeconds: 150,
            note: .hold,
            in: context,
            session: session
        )
        squat.wasSkipped = true

        // 3. Cadeira extensora: no meio (aquecimento + 1 de trabalho) → é o selecionado inicial.
        let legExtension = makeSessionExercise(
            order: 2,
            catalog: extensionCatalog,
            prescribedLoad: 9,
            prescribedSets: 3,
            prescribedRIR: 2,
            restSeconds: 90,
            note: .retry,
            in: context,
            session: session
        )
        makeSet(index: 0, load: 5, reps: 12, rir: nil, isWarmup: true, at: startedAt.addingTimeInterval(900), in: context, exercise: legExtension)
        makeSet(index: 1, load: 9, reps: 8, rir: 2, isWarmup: false, at: startedAt.addingTimeInterval(1_080), in: context, exercise: legExtension)

        // 4. Mesa flexora: por fazer, sem carga inicial (SPEC P2: calibrar).
        makeSessionExercise(
            order: 3,
            catalog: curlCatalog,
            prescribedLoad: nil,
            prescribedSets: 3,
            prescribedRIR: 3,
            restSeconds: 90,
            note: .calibrate,
            in: context,
            session: session
        )

        do {
            try context.save()
        } catch {
            return nil
        }

        let viewModel = ActiveSessionViewModel(
            sessionID: session.uuid,
            coordinator: coordinator,
            restTimer: RestTimer(notifications: FakeNotificationScheduler()),
            now: { Date() }
        )
        return Fixture(
            viewModel: viewModel,
            session: session,
            completedSets: legPressSets,
            skippedExercise: squat
        )
    }

    @discardableResult
    private static func makeSessionExercise(
        order: Int,
        catalog: ExerciseModel,
        prescribedLoad: Double?,
        prescribedSets: Int,
        prescribedRIR: Int,
        restSeconds: Int,
        note: PrescriptionNote,
        in context: ModelContext,
        session: WorkoutSessionModel
    ) -> SessionExerciseModel {
        let model = SessionExerciseModel(
            uuid: UUID(),
            order: order,
            exerciseUUID: catalog.uuid,
            exerciseName: catalog.name,
            prescribedLoad: prescribedLoad,
            prescribedSets: prescribedSets,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: prescribedRIR,
            restSeconds: restSeconds,
            noteRaw: note.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(model)
        model.exercise = catalog
        session.exercises.append(model)
        return model
    }

    @discardableResult
    private static func makeSet(
        index: Int,
        load: Double,
        reps: Int,
        rir: Int?,
        isWarmup: Bool,
        at completedAt: Date,
        in context: ModelContext,
        exercise: SessionExerciseModel
    ) -> SetLogModel {
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
        context.insert(model)
        exercise.sets.append(model)
        return model
    }
}

/// `SessionCoordinating` em memória para previews: aplica sobre modelos reais num container
/// in-memory, sem dedup nem publicação de eventos. O `SessionCoordinator` real é de T1.3.
@MainActor
private final class ActiveSessionPreviewCoordinator: SessionCoordinating {
    let container: ModelContainer

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
            // Fora do que a tela de sessão de M1 dispara; o preview não precisa deles.
            break
        }
        try context.save()
    }

    /// Ninguém observa eventos no preview: o stream nasce encerrado.
    var eventsApplied: AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
