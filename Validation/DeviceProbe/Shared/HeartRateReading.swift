import Foundation

struct HeartRateReading: Sendable, Equatable {
    let beatsPerMinute: Double
    let sampledAt: Date
}