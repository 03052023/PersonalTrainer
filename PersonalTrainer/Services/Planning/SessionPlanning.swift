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
}

enum PlanningError: Error, Equatable {
    case noActiveProgram
    case programHasNoDays
    case sessionAlreadyInProgress(UUID)
    case exerciseNotFound(UUID)
}
