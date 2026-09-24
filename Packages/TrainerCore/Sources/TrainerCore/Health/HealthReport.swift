import Foundation

/// Relatório do painel de saúde para a semana que contém `now` (SPEC §7.10, RF-27..RF-31).
public struct HealthReport: Codable, Sendable, Hashable {
    /// Segunda-feira 00:00 da semana corrente, no calendário recebido (mesma semana de §7.4).
    public let weekStart: Date
    public let aerobic: AerobicWeekSummary
    /// `nil` quando não há nenhuma estimativa de VO2max válida até `now`.
    public let vo2Max: Vo2MaxSummary?
    public let recovery: RecoverySummary
    public let steps: StepsSummary
    /// Em ordem fixa de `HealthSuggestionKind.allCases`, no máximo uma por tipo.
    public let suggestions: [HealthSuggestion]

    public init(
        weekStart: Date,
        aerobic: AerobicWeekSummary,
        vo2Max: Vo2MaxSummary?,
        recovery: RecoverySummary,
        steps: StepsSummary,
        suggestions: [HealthSuggestion]
    ) {
        self.weekStart = weekStart
        self.aerobic = aerobic
        self.vo2Max = vo2Max
        self.recovery = recovery
        self.steps = steps
        self.suggestions = suggestions
    }
}
