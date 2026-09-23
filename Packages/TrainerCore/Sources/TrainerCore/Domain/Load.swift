import Foundation

public enum Load: Sendable {
    /// Values whose quotient by the increment sits this close (relative) to an
    /// integer are treated as already on the grid. IEEE-754 division is the only
    /// source of such noise (`0.3 / 0.1 == 2.9999999999999996`), and it is many
    /// orders of magnitude below any load a user can enter.
    private static let gridTolerance = 1e-9

    /// Rounds to a valid load increment. The two-argument form rounds down,
    /// matching SPEC P8; pass `.up` when the next higher increment is needed.
    ///
    /// A value that is already a multiple of the increment is returned unchanged,
    /// even when floating-point division says otherwise: with a non-dyadic
    /// increment (0.1, 0.2, 1.1 …) the plain `floor(value / increment)` would move a
    /// valid load one whole increment down, which SPEC P8 does not allow.
    public static func round(
        _ value: Double,
        toIncrement increment: Double,
        rule: FloatingPointRoundingRule = .down
    ) -> Double {
        guard value.isFinite, increment.isFinite, increment > 0 else {
            return value
        }

        let quotient = value / increment
        let nearest = quotient.rounded()
        if abs(quotient - nearest) <= gridTolerance * max(1, abs(quotient)) {
            // On the grid already; `value == 0` also normalises -0 to 0.
            return value == 0 ? 0 : value
        }

        let rounded = quotient.rounded(rule) * increment
        return rounded == 0 ? 0 : rounded
    }
}
