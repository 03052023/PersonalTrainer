import Foundation
import TrainerCore

/// Planeja o próximo treino e inicia sessões. É o ÚNICO cliente do motor de `TrainerCore`
/// (`ProgressionRule`, `WorkoutSelector`) dentro do app (ARCHITECTURE §6).
///
/// Implementação concreta: `SessionPlanner` (Services/Planning/SessionPlanner.swift, T1.2).
/// Tudo roda no `MainActor` porque lê `@Model` via `ModelContext` (ARCHITECTURE §10).
@MainActor
protocol SessionPlanning: AnyObject {
    /// Plano do próximo dia do programa ativo (S1–S2), com uma prescrição por exercício (P1–P12).
    /// Devolve `nil` se não há programa ativo ou se o programa não tem dias.
    /// Não grava nada. Não trata S3: quem chama deve consultar `SessionCoordinating.activeSession`
    /// antes e oferecer "Retomar" se houver sessão em andamento.
    func nextPlan(now: Date) throws -> SessionPlan?

    /// Plano para um dia escolhido manualmente (S4). `nil` se o dia não existe no programa ativo.
    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan?

    /// Cria a sessão (snapshots de prescrição) através de `SessionCoordinating.startSession` e
    /// devolve o `uuid` da nova `WorkoutSessionModel`.
    /// Lança `PlanningError.sessionAlreadyInProgress` se já existe sessão em andamento.
    func startSession(from plan: SessionPlan, now: Date) throws -> UUID

    // M2 — declarados aqui para despacho dinâmico; padrões na extensão abaixo.
    func activeProgramDays() throws -> [ProgramDayTemplate]
    func activeProgramGoal() throws -> ProgramGoal?
    func substitutionPlan(replacing sessionExerciseID: UUID, target: ExerciseTarget, newExerciseID: UUID, now: Date) throws -> PlannedExercise
    func substitutes(for exerciseID: UUID, limit: Int) throws -> [ExerciseDefinition]
}

// MARK: - Operações do M2 (contrato; implementadas por `SessionPlanner` em T2.9/T2.14)

extension SessionPlanning {
    /// Dias do programa ativo, ordenados por `order`, para o seletor manual A/B/C (T2.14, S4).
    /// Vazio se não há programa ativo.
    func activeProgramDays() throws -> [ProgramDayTemplate] { [] }

    /// Objetivo do programa ativo (SPEC §7.9); `nil` se não há programa ativo.
    func activeProgramGoal() throws -> ProgramGoal? { nil }

    /// Prescrição para trocar um exercício por outro mantendo o alvo (séries, faixa, RIR,
    /// descanso) do exercício original (RF-34). O motor usa o histórico do NOVO exercício
    /// (P3 é por exercício); sem histórico, sai `calibrate`. `PlannedExercise.id` = `sessionExerciseID`
    /// do exercício substituído, para que o coordinator reaproveite o mesmo snapshot.
    func substitutionPlan(
        replacing sessionExerciseID: UUID,
        target: ExerciseTarget,
        newExerciseID: UUID,
        now: Date
    ) throws -> PlannedExercise {
        throw PlanningError.exerciseNotFound(newExerciseID)
    }

    /// Candidatos a substituto de um exercício, do catálogo não arquivado (RF-34),
    /// via `ExerciseSubstitution.candidates`. Vazio se o exercício não tem padrão de movimento.
    func substitutes(for exerciseID: UUID, limit: Int) throws -> [ExerciseDefinition] { [] }
}

enum PlanningError: Error, Equatable {
    case noActiveProgram
    case programHasNoDays
    case sessionAlreadyInProgress(UUID)
    case exerciseNotFound(UUID)
}
