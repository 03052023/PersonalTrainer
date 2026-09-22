import Foundation

public struct SetResult: Codable, Sendable, Hashable {
    public let load: Double
    public let reps: Int
    public let rir: Int?
    public let isWarmup: Bool
    public let completedAt: Date

    public init(
        load: Double,
        reps: Int,
        rir: Int? = nil,
        isWarmup: Bool = false,
        completedAt: Date
    ) {
        self.load = load
        self.reps = reps
        self.rir = rir
        self.isWarmup = isWarmup
        self.completedAt = completedAt
    }
}
