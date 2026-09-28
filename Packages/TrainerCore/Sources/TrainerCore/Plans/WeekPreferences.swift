import Foundation

/// O que a pessoa disse sobre a semana dela (SPEC §7.15 M4 e M5; docs/V23-UI-CONTRACT.md §3.1). O app grava
/// em `UserDefaults` (JSON), fora do backup. As saídas de M5 (`FitChange`) mudam estes campos.
public struct WeekPreferences: Codable, Sendable, Hashable {
    /// Dias em que a pessoa pode treinar.
    public var availableDays: Set<PlanWeekday>
    /// "Aceito 2 sessões no mesmo dia": uma de força e uma de aeróbico, com a força antes (A5).
    public var allowsTwoSessionsPerDay: Bool
    /// "Cardio leve depois da força": no mesmo dia de uma força que não é de pernas, um aeróbico leve
    /// ou moderado, depois dela, mesmo sem aceitar 2 sessões no mesmo dia.
    public var allowsLightCardioAfterStrength: Bool
    /// "Menos sessões": sessões por semana de um plano, pelo id do programa. Sem a chave, uma por dia
    /// do plano.
    public var sessionsPerWeek: [UUID: Int]

    public init(
        availableDays: Set<PlanWeekday> = WeekPreferences.defaultAvailableDays,
        allowsTwoSessionsPerDay: Bool = false,
        allowsLightCardioAfterStrength: Bool = false,
        sessionsPerWeek: [UUID: Int] = [:]
    ) {
        self.availableDays = availableDays
        self.allowsTwoSessionsPerDay = allowsTwoSessionsPerDay
        self.allowsLightCardioAfterStrength = allowsLightCardioAfterStrength
        self.sessionsPerWeek = sessionsPerWeek
    }

    /// Padrão: de segunda a sábado, com o domingo livre (M4 recomenda um dia de descanso completo).
    public static let defaultAvailableDays: Set<PlanWeekday> = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
    ]

    public static let `default` = WeekPreferences()
}
