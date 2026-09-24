import Foundation

/// Total de passos de um dia (SPEC §7.9 Longevidade, meta de passos), já somado pelo HealthKit.
public struct DailyStepCount: Codable, Sendable, Hashable {
    /// Início do dia no calendário do usuário.
    public let day: Date
    public let steps: Int

    public init(day: Date, steps: Int) {
        self.day = day
        self.steps = steps
    }
}
