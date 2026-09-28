import Foundation
import SwiftData
import TrainerCore

/// Dados e doubles para os `#Preview` da ficha da sessão (SPEC RF-44): uma sessão em andamento com
/// um exercício feito (com um aquecimento antigo), um pulado, um no meio, um de peso do corpo sem
/// carga (RF-46), um sem carga (RF-44 c, "sem carga") e os intervalos de corrida do Cardio (§7.14,
/// "4 × 3 min" com a recuperação andando) — o bastante para ver todos os estados dos cartões. Os
/// slugs são os do seed, para o "Como fazer" aparecer quando o preview injeta as guias. O catálogo
/// tem dois exercícios fora da sessão para a folha "Trocar" (RF-34) ter o que sugerir.
///
/// Os doubles (coordinator, planner) são `private` e prefixados pela feature para não colidir com
/// os das outras tarefas. Só previews usam `Date()` aqui: não é ViewModel nem serviço, e o timer de
/// descanso precisa do relógio real para contar na tela do Xcode.
///
/// Vive em `PreviewSupport/`, fora de `Features/`, porque grava direto no `ModelContext` (só
/// para montar a fixture); assim o grep de AGENTS R4 sobre `Features/` continua limpo.
@MainActor
enum SessionPreviewSupport {
    struct Fixture {
        let viewModel: ActiveSessionViewModel
        let session: WorkoutSessionModel
        let skippedExercise: SessionExerciseModel?
        /// Exercício de primeira vez, sem nenhuma série: o único em que "Trocar" aparece.
        let untouchedExercise: SessionExerciseModel?
    }

    /// `nil` só se o container in-memory não puder ser criado (o preview mostra um aviso).
    static func makeFixture() -> Fixture? {
        guard let coordinator = try? ActiveSessionPreviewCoordinator() else {
            return nil
        }
        let context = coordinator.context
        let now = Date()
        let startedAt = now.addingTimeInterval(-25 * 60)

        let legPressCatalog = makeCatalogExercise(
            slug: "leg-press-45",
            name: "Leg press 45°",
            primary: [.quads, .glutes],
            secondary: [.hamstrings],
            equipment: .machine,
            loadUnit: .kilograms,
            loadIncrement: 5,
            machineNotes: "Banco na posição 3, pés no alto da plataforma"
        )
        let squatCatalog = makeCatalogExercise(
            slug: "barbell-back-squat",
            name: "Agachamento livre",
            primary: [.quads, .glutes],
            secondary: [.core],
            equipment: .barbell,
            loadUnit: .kilograms,
            loadIncrement: 2.5,
            machineNotes: nil
        )
        let extensionCatalog = makeCatalogExercise(
            slug: "leg-extension",
            name: "Cadeira extensora",
            primary: [.quads],
            secondary: [],
            equipment: .machine,
            loadUnit: .plates,
            loadIncrement: 1,
            machineNotes: "Encosto 4"
        )
        let pullUpCatalog = makeCatalogExercise(
            slug: "pull-up",
            name: "Barra fixa",
            primary: [.back],
            secondary: [.biceps],
            equipment: .bodyweight,
            loadUnit: .kilograms,
            loadIncrement: 2.5,
            machineNotes: nil
        )
        let curlCatalog = makeCatalogExercise(
            slug: "lying-leg-curl",
            name: "Mesa flexora",
            primary: [.hamstrings],
            secondary: [],
            equipment: .machine,
            loadUnit: .kilograms,
            loadIncrement: 5,
            machineNotes: nil
        )
        // Fora da sessão: substitutos para a folha "Trocar".
        let seatedCurlCatalog = makeCatalogExercise(
            slug: "cadeira-flexora",
            name: "Cadeira flexora",
            primary: [.hamstrings],
            secondary: [],
            equipment: .machine,
            loadUnit: .kilograms,
            loadIncrement: 5,
            machineNotes: nil
        )
        let hackCatalog = makeCatalogExercise(
            slug: "agachamento-hack",
            name: "Agachamento hack",
            primary: [.quads, .glutes],
            secondary: [],
            equipment: .machine,
            loadUnit: .kilograms,
            loadIncrement: 5,
            machineNotes: nil
        )
        // Aeróbico do Cardio (SPEC §7.14): intervalos de corrida, medidos em minutos.
        let intervalsCatalog = makeCatalogExercise(
            slug: "run-intervals",
            name: "Intervalos de corrida",
            primary: [.quads, .glutes],
            secondary: [.hamstrings, .calves],
            equipment: .bodyweight,
            loadUnit: .kilograms,
            loadIncrement: 2.5,
            machineNotes: nil
        )
        intervalsCatalog.movementPattern = .cardio
        let catalogItems = [
            legPressCatalog, squatCatalog, extensionCatalog, pullUpCatalog, curlCatalog, seatedCurlCatalog, hackCatalog,
            intervalsCatalog,
        ]
        for catalogItem in catalogItems {
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

        // 1. Leg press: feito (um aquecimento antigo + 3 de trabalho) → linha compacta.
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
        makeSet(index: 0, load: 80, reps: 12, rir: nil, isWarmup: true, at: startedAt.addingTimeInterval(120), in: context, exercise: legPress)
        makeSet(index: 1, load: 140, reps: 10, rir: 2, isWarmup: false, at: startedAt.addingTimeInterval(300), in: context, exercise: legPress)
        makeSet(index: 2, load: 140, reps: 10, rir: 2, isWarmup: false, at: startedAt.addingTimeInterval(480), in: context, exercise: legPress)
        makeSet(index: 3, load: 140, reps: 9, rir: 1, isWarmup: false, at: startedAt.addingTimeInterval(660), in: context, exercise: legPress)

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

        // 3. Cadeira extensora: no meio (1 de 3) → é o exercício atual. Meta gravada (SPEC P5).
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
        legExtension.prescribedTargetReps = 8
        makeSet(index: 0, load: 9, reps: 8, rir: nil, isWarmup: false, at: startedAt.addingTimeInterval(1_080), in: context, exercise: legExtension)

        // 4. Barra fixa: peso do corpo sem carga (SPEC RF-46) → sem carga na meta.
        let pullUp = makeSessionExercise(
            order: 3,
            catalog: pullUpCatalog,
            prescribedLoad: nil,
            prescribedSets: 3,
            prescribedRIR: 2,
            restSeconds: 120,
            note: .hold,
            in: context,
            session: session
        )
        pullUp.prescribedTargetReps = 6

        // 5. Mesa flexora: primeira vez sem carga (SPEC P2) → "sem carga", que se toca para pôr uma.
        let legCurl = makeSessionExercise(
            order: 4,
            catalog: curlCatalog,
            prescribedLoad: nil,
            prescribedSets: 3,
            prescribedRIR: 3,
            restSeconds: 90,
            note: .calibrate,
            in: context,
            session: session
        )

        // 6. Intervalos de corrida: "4 × 3 min", forte pelo teste da fala, recuperação andando de 3 min.
        let intervals = makeSessionExercise(
            order: 5,
            catalog: intervalsCatalog,
            prescribedLoad: nil,
            prescribedSets: 4,
            prescribedRIR: 3,
            restSeconds: 180,
            note: .hold,
            in: context,
            session: session
        )
        intervals.prescribedRepMin = 3
        intervals.prescribedRepMax = 4
        intervals.prescribedTargetReps = 3

        do {
            try context.save()
        } catch {
            return nil
        }

        let notifications = FakeNotificationScheduler()
        // Sugestões de carga num domínio só de preview, para não marcar exercícios de verdade como já sugeridos.
        let previewDefaults = UserDefaults(suiteName: "SessionPreviewSupport") ?? .standard
        let viewModel = ActiveSessionViewModel(
            sessionID: session.uuid,
            coordinator: coordinator,
            planner: ActiveSessionPreviewPlanner(context: context),
            restTimer: RestTimer(notifications: notifications),
            notifications: notifications,
            now: { Date() },
            traits: ExerciseTraitsLibrary.load(bundle: .main),
            loadHintDefaults: previewDefaults
        )
        return Fixture(
            viewModel: viewModel,
            session: session,
            skippedExercise: squat,
            untouchedExercise: legCurl
        )
    }

    private static func makeCatalogExercise(
        slug: String,
        name: String,
        primary: [MuscleGroup],
        secondary: [MuscleGroup],
        equipment: Equipment,
        loadUnit: LoadUnit,
        loadIncrement: Double,
        machineNotes: String?
    ) -> ExerciseModel {
        ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: name,
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups(primary),
            secondaryMusclesRaw: SchemaV1.encodeMuscleGroups(secondary),
            equipmentRaw: equipment.rawValue,
            loadUnitRaw: loadUnit.rawValue,
            loadIncrement: loadIncrement,
            isUnilateral: false,
            machineNotes: machineNotes,
            isArchived: false
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

/// Catálogo não arquivado do container de preview, ordenado por nome. Exercícios que o mapper
/// não consegue ler são ignorados (preview, não produção).
@MainActor
private func activeSessionPreviewDefinitions(in context: ModelContext) -> [ExerciseDefinition] {
    let descriptor = FetchDescriptor<ExerciseModel>(
        predicate: #Predicate<ExerciseModel> { $0.isArchived == false }
    )
    let models = (try? context.fetch(descriptor)) ?? []
    return models
        .compactMap { try? ExerciseMapper.definition(from: $0) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}

/// `SessionPlanning` de preview: só a parte da troca (RF-34). Substitutos = exercícios com um
/// grupo primário em comum (o real usa o padrão de movimento); prescrição do novo = calibração
/// sem carga (SPEC P2), como a de um exercício nunca feito.
@MainActor
private final class ActiveSessionPreviewPlanner: SessionPlanning {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
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
        let all = activeSessionPreviewDefinitions(in: context)
        guard let original = all.first(where: { $0.id == exerciseID }) else {
            return []
        }
        let muscles = Set(original.primaryMuscles)
        let candidates = all.filter { candidate in
            candidate.id != exerciseID && !muscles.isDisjoint(with: candidate.primaryMuscles)
        }
        return Array(candidates.prefix(max(0, limit)))
    }

    func substitutionPlan(
        replacing sessionExerciseID: UUID,
        target: ExerciseTarget,
        newExerciseID: UUID,
        now: Date
    ) throws -> PlannedExercise {
        guard let exercise = activeSessionPreviewDefinitions(in: context).first(where: { $0.id == newExerciseID }) else {
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

    /// Flor do resumo nos previews.
    func activeProgramGoal() throws -> ProgramGoal? {
        .hypertrophy
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
            exercise.prescribedTargetReps = planned.prescription.targetReps
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
            // A troca chega por `substituteExercise` (abaixo); o resto não é disparado pela tela.
            break
        }
        try context.save()
    }

    /// RF-34 no preview: troca o snapshot inteiro pelo do `planned`, só sem séries registradas.
    func substituteExercise(sessionID: UUID, sessionExerciseID: UUID, with planned: PlannedExercise, now: Date) throws {
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

    /// Ninguém observa eventos no preview: o stream nasce encerrado.
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
