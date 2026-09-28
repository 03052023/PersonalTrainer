import Foundation
import TrainerCore
@testable import PersonalTrainer

// Doubles dos testes da folha "Seu objetivo" e da aba Plano (T7.4). Prefixo "GoalPlan" para não
// colidir com os doubles privados de outras features.

enum GoalPlanTestError: Error {
    case boom
}

/// Programas com os ids do seed (`programs.v2.json`) e poucos dias, para montar cenários.
enum GoalPlanTestPrograms {
    static let squatID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1") ?? UUID()
    static let benchID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E2") ?? UUID()
    static let rowID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E3") ?? UUID()
    static let archivedID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E4") ?? UUID()

    static let exercises: [ExerciseDefinition] = [
        ExerciseDefinition(id: squatID, slug: "agachamento-livre", name: "Agachamento livre", primaryMuscles: [.quads], equipment: .barbell, loadUnit: .kilograms, loadIncrement: 2.5, movementPattern: .squat),
        ExerciseDefinition(id: benchID, slug: "supino-reto-barra", name: "Supino reto com barra", primaryMuscles: [.chest], equipment: .barbell, loadUnit: .kilograms, loadIncrement: 2.5, movementPattern: .horizontalPush),
        ExerciseDefinition(id: rowID, slug: "remada-baixa", name: "Remada baixa", primaryMuscles: [.back], equipment: .cable, loadUnit: .kilograms, loadIncrement: 5, movementPattern: .horizontalPull),
        ExerciseDefinition(id: archivedID, slug: "supino-maquina-antiga", name: "Supino máquina antiga", primaryMuscles: [.chest], equipment: .machine, loadUnit: .kilograms, loadIncrement: 5, movementPattern: .horizontalPush),
    ]

    /// Programa com `dayCount` dias; o primeiro dia tem, na ordem, `firstDayExercises`.
    static func program(
        id: UUID,
        name: String,
        goal: ProgramGoal?,
        dayCount: Int = 3,
        isActive: Bool = false,
        firstDayExercises: [UUID] = [GoalPlanTestPrograms.squatID, GoalPlanTestPrograms.benchID]
    ) -> ProgramTemplate {
        let letters = ["A", "B", "C", "D", "E", "F", "G"]
        let days = (0..<dayCount).map { index -> ProgramDayTemplate in
            let exercises = index == 0 ? firstDayExercises : [rowID]
            // Alvos gravados fora de ordem: quem lê ordena por `order`.
            let targets = exercises.enumerated().map { order, exerciseID in
                ExerciseTarget(exerciseID: exerciseID, order: order)
            }.reversed()
            return ProgramDayTemplate(
                name: "Dia \(letters[index % letters.count]) — Parte \(index + 1)",
                order: index,
                exercises: Array(targets)
            )
        }
        // Dias fora de ordem também.
        return ProgramTemplate(id: id, name: name, days: Array(days.reversed()), isActive: isActive, goal: goal)
    }

    /// Os 8 programas do seed; `activeID` fica ativo (o Completo, por padrão).
    static func seed(activeID: UUID? = GoalPlanCatalog.hypertrophyFullBodyID) -> [ProgramTemplate] {
        [
            program(id: GoalPlanCatalog.hypertrophyFullBodyID, name: "Hipertrofia — Completo", goal: .hypertrophy, dayCount: 3, isActive: activeID == GoalPlanCatalog.hypertrophyFullBodyID),
            program(id: GoalPlanCatalog.legacyPushLegsPullID, name: "Hipertrofia — Empurrar/Inferior/Puxar", goal: .hypertrophy, dayCount: 3, isActive: activeID == GoalPlanCatalog.legacyPushLegsPullID),
            program(id: GoalPlanCatalog.hypertrophyLowerFocusID, name: "Hipertrofia — Foco inferior", goal: .hypertrophy, dayCount: 4, isActive: activeID == GoalPlanCatalog.hypertrophyLowerFocusID),
            program(id: GoalPlanCatalog.hypertrophyUpperFocusID, name: "Hipertrofia — Foco superior", goal: .hypertrophy, dayCount: 4, isActive: activeID == GoalPlanCatalog.hypertrophyUpperFocusID),
            program(id: GoalPlanCatalog.strengthID, name: "Força", goal: .strength, isActive: activeID == GoalPlanCatalog.strengthID),
            program(id: GoalPlanCatalog.enduranceID, name: "Resistência muscular", goal: .endurance, isActive: activeID == GoalPlanCatalog.enduranceID),
            program(id: GoalPlanCatalog.longevityID, name: "Longevidade", goal: .longevity, isActive: activeID == GoalPlanCatalog.longevityID),
            program(id: GoalPlanCatalog.combatID, name: "Combate", goal: .combat, isActive: activeID == GoalPlanCatalog.combatID, firstDayExercises: [benchID, archivedID, rowID]),
        ]
    }
}

/// Escritas recebidas pelo repositório falso, na ordem.
enum GoalPlanTestCall: Equatable {
    case activate(UUID)
    case setGoal(UUID, ProgramGoal, Bool)
    case rename(UUID, String)
    case duplicate(UUID)
    case delete(UUID)
    case otherWrite
}

/// `ProgramRepositoring` em memória: ativar troca o único ativo; as outras escritas só registram.
@MainActor
final class GoalPlanTestRepository: ProgramRepositoring {
    private(set) var programs: [ProgramTemplate]
    private(set) var calls: [GoalPlanTestCall] = []
    var readError: (any Error)?
    var writeError: (any Error)?

    init(programs: [ProgramTemplate]) {
        self.programs = programs
    }

    func allPrograms() throws -> [ProgramTemplate] {
        if let readError { throw readError }
        return programs.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func program(id: UUID) throws -> ProgramTemplate? {
        if let readError { throw readError }
        return programs.first { $0.id == id }
    }

    func activate(programID: UUID) throws {
        calls.append(.activate(programID))
        if let writeError { throw writeError }
        guard programs.contains(where: { $0.id == programID }) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        programs = programs.map { program in
            ProgramTemplate(
                id: program.id,
                name: program.name,
                days: program.days,
                isActive: program.id == programID,
                goal: program.goal,
                summary: program.summary
            )
        }
    }

    func rename(programID: UUID, to name: String) throws {
        calls.append(.rename(programID, name))
    }

    func setGoal(programID: UUID, goal: ProgramGoal, applyDefaults: Bool) throws {
        calls.append(.setGoal(programID, goal, applyDefaults))
    }

    func duplicate(programID: UUID, name: String, now: Date) throws -> UUID {
        calls.append(.duplicate(programID))
        return UUID()
    }

    func delete(programID: UUID) throws {
        calls.append(.delete(programID))
    }

    func addExercise(exerciseID: UUID, toDay dayID: UUID) throws -> UUID {
        calls.append(.otherWrite)
        return UUID()
    }

    func removeTarget(id: UUID) throws {
        calls.append(.otherWrite)
    }

    func moveTarget(id: UUID, toIndex newIndex: Int) throws {
        calls.append(.otherWrite)
    }

    func replaceExercise(targetID: UUID, with exerciseID: UUID) throws {
        calls.append(.otherWrite)
    }

    func updateTarget(id: UUID, sets: Int, repMin: Int, repMax: Int, targetRIR: Int, restSeconds: Int, startingLoad: Double?) throws {
        calls.append(.otherWrite)
    }
}

/// Catálogo só de leitura; `readError` simula falha.
@MainActor
final class GoalPlanTestCatalog: CatalogRepositoring {
    private let exercises: [ExerciseDefinition]
    private let archivedIDs: Set<UUID>
    var readError: (any Error)?

    init(exercises: [ExerciseDefinition] = GoalPlanTestPrograms.exercises, archivedIDs: Set<UUID> = [GoalPlanTestPrograms.archivedID]) {
        self.exercises = exercises
        self.archivedIDs = archivedIDs
    }

    func allExercises(includeArchived: Bool) throws -> [ExerciseDefinition] {
        if let readError { throw readError }
        return exercises.filter { includeArchived || !archivedIDs.contains($0.id) }
    }

    func exercise(id: UUID) throws -> ExerciseDefinition? {
        exercises.first { $0.id == id }
    }

    func createExercise(_ draft: ExerciseDraft) throws -> UUID {
        UUID()
    }

    func updateExercise(id: UUID, with draft: ExerciseDraft) throws {}

    func setArchived(id: UUID, _ archived: Bool) throws {}
}

/// `SessionPlanning` mínimo: `nextPlan` devolve `planToReturn` (ou lança `error`).
@MainActor
final class GoalPlanTestPlanner: SessionPlanning {
    var planToReturn: SessionPlan?
    var error: (any Error)?
    private(set) var requestedDates: [Date] = []

    init(planToReturn: SessionPlan? = nil) {
        self.planToReturn = planToReturn
    }

    func nextPlan(now: Date) throws -> SessionPlan? {
        requestedDates.append(now)
        if let error { throw error }
        return planToReturn
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        nil
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        UUID()
    }
}

/// `SessionCoordinating` mínimo: só a sessão em andamento importa para a aba Plano.
@MainActor
final class GoalPlanTestCoordinator: SessionCoordinating {
    var activeSession: WorkoutSessionModel?

    init(activeSession: WorkoutSessionModel? = nil) {
        self.activeSession = activeSession
    }

    func session(withID id: UUID) -> WorkoutSessionModel? {
        nil
    }

    func startSession(plan: SessionPlan, now: Date, source: DeviceSource) throws -> UUID {
        UUID()
    }

    func apply(_ event: SessionEvent) throws {}

    var eventsApplied: AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
