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

    /// Os 9 programas do seed 4 (2.3); `activeID` fica ativo (o Equilibrado, por padrão).
    static func seed(activeID: UUID? = GoalPlanCatalog.hypertrophyBalancedID) -> [ProgramTemplate] {
        seed(activeIDs: activeID.map { Set([$0]) } ?? Set<UUID>())
    }

    /// Os 9 programas do seed 4 com vários ativos (SPEC §7.15 M1).
    static func seed(activeIDs: Set<UUID>) -> [ProgramTemplate] {
        [
            program(id: GoalPlanCatalog.hypertrophyBalancedID, name: "Hipertrofia — Equilibrado", goal: .hypertrophy, dayCount: 4, isActive: activeIDs.contains(GoalPlanCatalog.hypertrophyBalancedID)),
            program(id: GoalPlanCatalog.hypertrophyFullBodyID, name: "Hipertrofia — Completo", goal: .hypertrophy, dayCount: 3, isActive: activeIDs.contains(GoalPlanCatalog.hypertrophyFullBodyID)),
            program(id: GoalPlanCatalog.legacyPushLegsPullID, name: "Hipertrofia — Empurrar/Inferior/Puxar", goal: .hypertrophy, dayCount: 3, isActive: activeIDs.contains(GoalPlanCatalog.legacyPushLegsPullID)),
            program(id: GoalPlanCatalog.hypertrophyLowerFocusID, name: "Hipertrofia — Foco inferior", goal: .hypertrophy, dayCount: 4, isActive: activeIDs.contains(GoalPlanCatalog.hypertrophyLowerFocusID)),
            program(id: GoalPlanCatalog.hypertrophyUpperFocusID, name: "Hipertrofia — Foco superior", goal: .hypertrophy, dayCount: 4, isActive: activeIDs.contains(GoalPlanCatalog.hypertrophyUpperFocusID)),
            program(id: GoalPlanCatalog.strengthID, name: "Força", goal: .strength, isActive: activeIDs.contains(GoalPlanCatalog.strengthID)),
            program(id: GoalPlanCatalog.enduranceCardioID, name: "Cardio", goal: .endurance, isActive: activeIDs.contains(GoalPlanCatalog.enduranceCardioID)),
            program(id: GoalPlanCatalog.longevityID, name: "Longevidade", goal: .longevity, isActive: activeIDs.contains(GoalPlanCatalog.longevityID)),
            program(id: GoalPlanCatalog.combatID, name: "Combate", goal: .combat, isActive: activeIDs.contains(GoalPlanCatalog.combatID), firstDayExercises: [benchID, archivedID, rowID]),
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
    /// SPEC §7.15 M1, M8.
    case addActivePlan(UUID)
    case removeActivePlan(UUID)
    case otherWrite
}

/// `ProgramRepositoring` em memória: ativar troca o único ativo; acrescentar e tirar seguem M1 (até
/// dois, de objetivos diferentes, nunca o último); as outras escritas só registram.
@MainActor
final class GoalPlanTestRepository: ProgramRepositoring {
    private(set) var programs: [ProgramTemplate]
    private(set) var calls: [GoalPlanTestCall] = []
    var readError: (any Error)?
    var writeError: (any Error)?
    /// Falha só no `addActivePlan` (a troca de formato com dois planos tenta devolver o antigo).
    var addError: (any Error)?
    /// Quantas vezes o `addActivePlan` ainda falha com `addError` (depois volta a funcionar).
    var addFailures = Int.max

    /// Ids dos programas ativos agora.
    var activeIDs: Set<UUID> {
        Set(programs.filter(\.isActive).map(\.id))
    }

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

    func addActivePlan(programID: UUID) throws {
        calls.append(.addActivePlan(programID))
        if let writeError { throw writeError }
        if let addError, addFailures > 0 {
            addFailures -= 1
            throw addError
        }
        guard let program = programs.first(where: { $0.id == programID }) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        guard !program.isActive else { return }
        let actives = programs.filter(\.isActive)
        guard
            actives.count < ActivePlanOrder.maxActivePlans,
            !actives.contains(where: { $0.effectiveGoal == program.effectiveGoal })
        else {
            throw ProgramRepositoryError.invalidParameters("M1")
        }
        setActive(programID, true)
    }

    func removeActivePlan(programID: UUID) throws {
        calls.append(.removeActivePlan(programID))
        if let writeError { throw writeError }
        guard let program = programs.first(where: { $0.id == programID }) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        guard program.isActive else { return }
        guard programs.filter(\.isActive).count > 1 else {
            throw ProgramRepositoryError.invalidParameters("M8: nunca o último")
        }
        setActive(programID, false)
    }

    private func setActive(_ programID: UUID, _ isActive: Bool) {
        programs = programs.map { program in
            guard program.id == programID else { return program }
            return ProgramTemplate(
                id: program.id,
                name: program.name,
                days: program.days,
                isActive: isActive,
                goal: program.goal,
                summary: program.summary
            )
        }
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

/// `SessionPlanning` mínimo: `nextPlan` devolve `planToReturn` (ou lança `error`). Para os vários
/// planos (SPEC §7.15), responde a semana, os dias da pessoa e o encaixe com valores prontos e registra
/// o que foi gravado. As assinaturas são exatamente as do protocolo (senão valeria o padrão em silêncio).
@MainActor
final class GoalPlanTestPlanner: SessionPlanning {
    var planToReturn: SessionPlan?
    var error: (any Error)?
    private(set) var requestedDates: [Date] = []

    /// `weekPreferences()`; `saveWeekPreferences` também grava aqui.
    var preferences = WeekPreferences.default
    var saveError: (any Error)?
    private(set) var savedPreferences: [WeekPreferences] = []
    /// `fitCheck` devolve isto (ou lança `fitError`).
    var fitResult = FitResult.unchecked
    var fitError: (any Error)?
    private(set) var fitCheckedIDs: [[UUID]] = []
    private(set) var fitCheckedPreferences: [WeekPreferences] = []
    private(set) var fitCheckedDates: [Date] = []
    /// `weekSchedule(now:)`.
    var scheduleToReturn: WeekSchedule?
    private(set) var weekScheduleCalls: [Date] = []
    /// `nextPlan(forProgramID:now:)`.
    var nextPlansByProgramID: [UUID: SessionPlan] = [:]

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

    func nextPlan(forProgramID programID: UUID, now: Date) throws -> SessionPlan? {
        if let error { throw error }
        return nextPlansByProgramID[programID]
    }

    func weekSchedule(now: Date) throws -> WeekSchedule? {
        weekScheduleCalls.append(now)
        return scheduleToReturn
    }

    func weekPreferences() -> WeekPreferences {
        preferences
    }

    func saveWeekPreferences(_ preferences: WeekPreferences) throws {
        if let saveError { throw saveError }
        savedPreferences.append(preferences)
        self.preferences = preferences
    }

    func fitCheck(programIDs: [UUID], preferences: WeekPreferences, now: Date) throws -> FitResult {
        fitCheckedIDs.append(programIDs)
        fitCheckedPreferences.append(preferences)
        fitCheckedDates.append(now)
        if let fitError { throw fitError }
        return fitResult
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
