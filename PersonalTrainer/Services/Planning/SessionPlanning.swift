import Foundation
import TrainerCore

/// Planeja o próximo treino e inicia sessões. É o ÚNICO cliente do motor de `TrainerCore`
/// (`ProgressionRule`, `WorkoutSelector`, `DeloadScheduler`) dentro do app (ARCHITECTURE §6).
///
/// Implementação concreta: `SessionPlanner` (Services/Planning/SessionPlanner.swift, T1.2).
/// Tudo roda no `MainActor` porque lê `@Model` via `ModelContext` (ARCHITECTURE §10).
@MainActor
protocol SessionPlanning: AnyObject {
    /// Plano do próximo dia do programa ativo (S1–S2, ou S5–S7 com o seletor por frequência
    /// ligado), com uma prescrição por exercício (P1–P12) e, em semana leve, as prescrições de
    /// SPEC §7.5 com `isDeload = true`. `reason` diz por que este dia (CA4-5).
    /// Devolve `nil` se não há programa ativo ou se o programa não tem dias.
    /// Não grava nada. Não trata S3: quem chama deve consultar `SessionCoordinating.activeSession`
    /// antes e oferecer "Retomar" se houver sessão em andamento.
    func nextPlan(now: Date) throws -> SessionPlan?

    /// Plano para um dia escolhido manualmente (S4), com `reason = .manual`. Em semana leve
    /// (programada ou em andamento) as prescrições também são as de SPEC §7.5.
    /// `nil` se o dia não existe no programa ativo.
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

    // M4 (docs/V2-FINAL-CONTRACT.md §2.2) — padrões na extensão abaixo, para doubles e previews.
    func deloadStatus(now: Date) throws -> DeloadStatus
    func requestDeload(now: Date) throws
    func dismissDeload(now: Date) throws
    func completedSessionSummaries() throws -> [SessionSummary]
    func finishedSessionSummaries() throws -> [SessionSummary]
    func reviewInput(now: Date, recovery: RecoveryContext) throws -> ReviewInput?
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

// MARK: - Operações do M4 (semana leve, diálogo e revisão)

extension SessionPlanning {
    /// Estado da semana leve para o próximo plano (SPEC §7.5, `DeloadScheduler`). `.inactive`
    /// sem programa ativo ou com programa sem dias.
    func deloadStatus(now: Date) throws -> DeloadStatus { .inactive }

    /// "Fazer semana leve agora" (SPEC §7.5 c): grava `DeloadDecisions.manualRequestedAt = now`.
    /// Só grava com `deloadStatus == .inactive`: com semana leve já programada (qualquer
    /// gatilho) o próximo plano já é leve e a data do pedido, que a mensagem C1 usa, não muda a
    /// cada toque; durante a passagem (`.active`) o pedido emendaria outra semana leve.
    func requestDeload(now: Date) throws {}

    /// "Seguir normal" (SPEC §7.11 C1): grava `dismissedAt = now` e limpa `manualRequestedAt`.
    /// Só vale enquanto a semana leve está programada (`.pending`): uma passagem já iniciada
    /// não se desfaz, e sem semana leve não há o que dispensar; nesses casos nada é gravado.
    func dismissDeload(now: Date) throws {}

    /// Todas as sessões `completed`, de qualquer programa, da mais antiga para a mais recente
    /// (empate de `startedAt` pelo `id`). Com `isDeload` e as séries de trabalho de cada uma.
    func completedSessionSummaries() throws -> [SessionSummary] { [] }

    /// Sessões `completed` e `abandoned`, de qualquer programa, na mesma ordem de
    /// `completedSessionSummaries`: as que o motor lê como histórico (SPEC P3) e de onde conta a
    /// pausa de P9 e do C5. O padrão devolve só as concluídas, para doubles que não distinguem.
    func finishedSessionSummaries() throws -> [SessionSummary] {
        try completedSessionSummaries()
    }

    /// Entrada de `ProgramReviewer.review` para o programa ativo (SPEC §7.8). `nil` sem programa
    /// ativo ou com programa sem dias.
    func reviewInput(now: Date, recovery: RecoveryContext) throws -> ReviewInput? { nil }
}

enum PlanningError: Error, Equatable {
    case noActiveProgram
    case programHasNoDays
    case sessionAlreadyInProgress(UUID)
    case exerciseNotFound(UUID)
}
