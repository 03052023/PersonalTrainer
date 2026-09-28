import Foundation

/// Uma mudança que faz os planos caberem (SPEC §7.15 M5; owner notes item 9). O texto em pt-BR é da tela.
public enum FitChange: Sendable, Hashable {
    /// Treinar também nestes dias.
    case addDays([PlanWeekday])
    /// Aceitar 2 sessões no mesmo dia (força antes do aeróbico).
    case allowTwoSessionsPerDay
    /// Aeróbico leve ou moderado depois da força, nos dias que não são de pernas.
    case allowLightCardioAfterStrength
    /// Menos sessões por semana num plano (na prática, o Cardio).
    case fewerSessions(programID: UUID, perWeek: Int)

    /// As preferências depois desta mudança.
    public func applied(to preferences: WeekPreferences) -> WeekPreferences {
        var result = preferences
        switch self {
        case .addDays(let days):
            result.availableDays.formUnion(days)
        case .allowTwoSessionsPerDay:
            result.allowsTwoSessionsPerDay = true
        case .allowLightCardioAfterStrength:
            result.allowsLightCardioAfterStrength = true
        case .fewerSessions(let programID, let perWeek):
            result.sessionsPerWeek[programID] = perWeek
        }
        return result
    }
}
