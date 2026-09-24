import Foundation

/// Minutos aeróbicos da semana corrente contra a meta (SPEC §7.10 A1/A2, RF-27).
public struct AerobicWeekSummary: Codable, Sendable, Hashable {
    public let moderateMinutes: Int
    public let vigorousMinutes: Int
    /// `moderateMinutes + 2 × vigorousMinutes` (OMS 2020: 1 min vigoroso = 2 moderados).
    public let moderateEquivalentMinutes: Int
    /// Meta semanal em minutos moderados-equivalentes (`HealthTargets.weeklyModerateEquivalentMinutes`).
    public let target: Int
    /// Sempre 7 entradas, de segunda a domingo, na ordem da semana.
    public let perDay: [DailyAerobicMinutes]

    public init(
        moderateMinutes: Int,
        vigorousMinutes: Int,
        moderateEquivalentMinutes: Int,
        target: Int,
        perDay: [DailyAerobicMinutes]
    ) {
        self.moderateMinutes = moderateMinutes
        self.vigorousMinutes = vigorousMinutes
        self.moderateEquivalentMinutes = moderateEquivalentMinutes
        self.target = target
        self.perDay = perDay
    }
}
