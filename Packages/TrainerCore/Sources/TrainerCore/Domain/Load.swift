import Foundation

public enum Load: Sendable {
    /// Rounds to a valid load increment. The two-argument form rounds down,
    /// matching SPEC P8; pass `.up` when the next higher increment is needed.
    public static func round(
        _ value: Double,
        toIncrement increment: Double,
        rule: FloatingPointRoundingRule = .down
    ) -> Double {
        guard value.isFinite, increment.isFinite, increment > 0 else {
            return value
        }

        let rounded = (value / increment).rounded(rule) * increment
        return rounded == 0 ? 0 : rounded
    }
}
