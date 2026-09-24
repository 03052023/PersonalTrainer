import Foundation

/// Metas do painel de saúde. Padrões: OMS 2020 (150 min moderados-equivalentes por semana, A2),
/// Paluch 2022 (7.000 passos/dia) e consenso AASM/SRS (7 h de sono), SPEC §7.9.
public struct HealthTargets: Codable, Sendable, Hashable {
    public let weeklyModerateEquivalentMinutes: Int
    public let dailySteps: Int
    public let sleepHours: Double

    public init(weeklyModerateEquivalentMinutes: Int = 150, dailySteps: Int = 7000, sleepHours: Double = 7) {
        self.weeklyModerateEquivalentMinutes = weeklyModerateEquivalentMinutes
        self.dailySteps = dailySteps
        self.sleepHours = sleepHours
    }
}
