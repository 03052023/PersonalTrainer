import Foundation

/// Uma estimativa de VO2max gravada pelo Apple Watch (SPEC §7.10 A3).
public struct Vo2MaxSample: Codable, Sendable, Hashable {
    public let date: Date
    /// mL/kg/min.
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}
