import Foundation
import SwiftData
import TrainerCore

/// Implementação de `SessionPlanning` (T1.2). Orquestra o motor de `TrainerCore` sobre o
/// `ModelContext` (ARCHITECTURE §6): escolhe o dia com o `WorkoutSelector`, busca o histórico
/// de cada exercício e pede a prescrição ao `ProgressionRule`. Só lê o banco; a única escrita
/// (iniciar a sessão) é delegada ao `SessionCoordinating` (ARCHITECTURE §7, AR-2).
///
/// Roda no `MainActor` porque lê `@Model` (ARCHITECTURE §10). `now` é sempre parâmetro; nenhum
/// `Date()` aqui (SPEC P11). SPEC S3 (retomar sessão em andamento) é de quem chama, conforme o
/// contrato de `SessionPlanning`.
@MainActor
final class SessionPlanner: SessionPlanning {
    private let modelContext: ModelContext
    private let coordinator: any SessionCoordinating
    private let progression: any ProgressionRule
    private let selector: any WorkoutSelector

    init(
        modelContext: ModelContext,
        coordinator: any SessionCoordinating,
        progression: any ProgressionRule = DoubleProgressionRule(),
        selector: any WorkoutSelector = RotationSelector()
    ) {
        self.modelContext = modelContext
        self.coordinator = coordinator
        self.progression = progression
        self.selector = selector
    }

    // MARK: - SessionPlanning

    func nextPlan(now: Date) throws -> SessionPlan? {
        guard let program = try activeProgram() else {
            return nil
        }
        let template = try programTemplate(from: program)
        guard !template.days.isEmpty else {
            return nil
        }

        // SPEC S2: todas as sessões entram, inclusive as de dias que já não existem no programa;
        // o seletor trata esse caso (reinicia em D1) e ignora `inProgress` sozinho (SPEC S3).
        let recentSessions = try recentSessionSummaries()
        guard
            let nextDay = selector.nextDay(program: template, recentSessions: recentSessions, now: now),
            let day = program.days.first(where: { $0.uuid == nextDay.id })
        else {
            return nil
        }
        return try buildPlan(program: program, day: day, now: now)
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        guard
            let program = try activeProgram(),
            let day = program.days.first(where: { $0.uuid == dayID })
        else {
            return nil
        }
        return try buildPlan(program: program, day: day, now: now)
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        // RF-02: no máximo uma sessão em andamento. O coordinator repete a checagem, mas o erro
        // daqui é o do contrato de planejamento (`PlanningError`), que a Home entende.
        if let active = coordinator.activeSession {
            throw PlanningError.sessionAlreadyInProgress(active.uuid)
        }
        return try coordinator.startSession(plan: plan, now: now, source: .iphone)
    }
}

// MARK: - Leitura do banco

private extension SessionPlanner {
    /// Programa com `isActive == true`. Deveria haver só um; se houver mais (store editado à mão
    /// ou bug de repositório), vale o mais antigo, com desempate por `uuid` para ser
    /// determinístico (SPEC P11). Ordenação em memória: são um ou dois registros.
    func activeProgram() throws -> ProgramModel? {
        let descriptor = FetchDescriptor<ProgramModel>(
            predicate: #Predicate<ProgramModel> { $0.isActive == true }
        )
        let activePrograms = try modelContext.fetch(descriptor)
        return activePrograms.min { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.uuid.uuidString < rhs.uuid.uuidString
        }
    }

    /// `ProgramMapper.template` lança `MappingError.missingExercise` para relação anulada; aqui
    /// vira `PlanningError.exerciseNotFound` para que `nextPlan` e `plan(forDayID:)` falhem com o
    /// mesmo erro diante do mesmo store corrompido (ver `buildPlan`).
    func programTemplate(from program: ProgramModel) throws -> ProgramTemplate {
        do {
            return try ProgramMapper.template(from: program)
        } catch MappingError.missingExercise(let programExerciseUUID) {
            throw PlanningError.exerciseNotFound(programExerciseUUID)
        }
    }

    /// Entrada do seletor (SPEC S2). Sem catálogo auxiliar: a relação `exercise` só é anulada se o
    /// catálogo for apagado, o que o esquema não permite (ARCHITECTURE §5), e a rotação v1 não lê
    /// `primaryMusclesTrained`.
    func recentSessionSummaries() throws -> [SessionSummary] {
        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSessionModel>())
        return try sessions.map { try SessionSummaryMapper.summary(from: $0) }
    }

    /// Histórico de UM exercício (ARCHITECTURE §6): o filtro por `exerciseUUID` é feito no banco;
    /// o mapper refiltra por status (`completed`/`abandoned`, SPEC P3) e ordena.
    func history(forExerciseUUID exerciseUUID: UUID) throws -> [ExerciseHistoryEntry] {
        let uuid = exerciseUUID
        let descriptor = FetchDescriptor<SessionExerciseModel>(
            predicate: #Predicate<SessionExerciseModel> { $0.exerciseUUID == uuid }
        )
        let sessionExercises = try modelContext.fetch(descriptor)
        return try HistoryMapper.historyEntries(from: sessionExercises, exerciseUUID: uuid)
    }
}

// MARK: - Montagem do plano

private extension SessionPlanner {
    /// Uma prescrição por `ProgramExerciseModel` do dia, na ordem de `order` (SPEC RF-01).
    /// Nada é gravado: o plano é um DTO que `SessionCoordinating.startSession` transforma em
    /// snapshots (ARCHITECTURE §5, decisão 3).
    func buildPlan(program: ProgramModel, day: ProgramDayModel, now: Date) throws -> SessionPlan {
        let programExercises = day.exercises.sorted { $0.order < $1.order }
        var planned: [PlannedExercise] = []
        planned.reserveCapacity(programExercises.count)

        for programExercise in programExercises {
            guard let exerciseModel = programExercise.exercise else {
                // O catálogo nunca é apagado (ARCHITECTURE §5); relação nula é store corrompido.
                throw PlanningError.exerciseNotFound(programExercise.uuid)
            }
            let exercise = try ExerciseMapper.definition(from: exerciseModel)
            let target = try ProgramMapper.target(from: programExercise)
            let entries = try history(forExerciseUUID: exercise.id)
            let prescription = progression.prescribe(
                target: target,
                exercise: exercise,
                history: entries,
                now: now
            )
            planned.append(
                PlannedExercise(
                    id: UUID(),
                    exercise: exercise,
                    target: target,
                    prescription: prescription
                )
            )
        }

        return SessionPlan(
            programID: program.uuid,
            programName: program.name,
            programDayID: day.uuid,
            programDayName: day.name,
            exercises: planned,
            generatedAt: now
        )
    }
}
