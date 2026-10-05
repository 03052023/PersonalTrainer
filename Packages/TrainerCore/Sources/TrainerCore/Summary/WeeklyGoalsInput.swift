import Foundation

/// Tudo que `WeeklyGoals.goals(_:)` precisa (SPEC §7.16), já calculado por quem chama (o app: SPEC P11,
/// AGENTS R3 — nada aqui lê o relógio nem o HealthKit). DTO puro, sem lógica.
public struct WeeklyGoalsInput: Sendable, Hashable {
    /// Progresso de cada plano ativo na semana (W2.1), na ordem de `ActivePlanOrder` (o principal
    /// primeiro) — a mesma ordem de `SessionPlanning.planWeekProgress(now:)`. Vazio sem plano ativo.
    public let plans: [PlanWeekProgress]
    /// Objetivos dos planos ativos (M1: o principal primeiro), para W7 (passos) e para saber se a
    /// Longevidade está ativa (equilíbrio e mobilidade, W2.6).
    public let activeGoals: [ProgramGoal]
    /// Frequência por grupo muscular da semana (W2.2), a mesma do antigo painel do Histórico (RF-17).
    public let frequency: WeeklyFrequencyReport
    /// `nil` sem o app Saúde conectado (W4): aeróbico, passos e sono viram "sem dados".
    public let health: HealthReport?
    /// Chaves do C8 já marcadas "Feito" nesta semana (`CoachInput.balanceKey`/`mobilityKey`, W2.6).
    public let longevityDone: Set<String>
    /// Metas de aeróbico, passos e sono (SPEC §7.9); mesmo tipo do painel de Saúde.
    public let targets: HealthTargets

    public init(
        plans: [PlanWeekProgress],
        activeGoals: [ProgramGoal],
        frequency: WeeklyFrequencyReport,
        health: HealthReport?,
        longevityDone: Set<String>,
        targets: HealthTargets = HealthTargets()
    ) {
        self.plans = plans
        self.activeGoals = activeGoals
        self.frequency = frequency
        self.health = health
        self.longevityDone = longevityDone
        self.targets = targets
    }
}
