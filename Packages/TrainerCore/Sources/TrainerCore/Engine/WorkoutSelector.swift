import Foundation

/// Picks the program day to train next (SPEC §7.3).
///
/// Implementations are pure functions over their inputs: same inputs → same output
/// (SPEC P11; the S-rules share that guarantee), `now` is always injected (AGENTS R3,
/// ARCHITECTURE AR-9) and no heart-rate metric can reach the selector because
/// `SessionSummary` has no such field by construction (SPEC P12, AGENTS R2).
///
/// ARCHITECTURE §6 sketches a non-optional return type. T0.4 fixed it as optional so
/// that an empty program is representable without a precondition failure; `nil` is
/// returned in that case only.
public protocol WorkoutSelector: Sendable {
    /// Returns the day to train next, or `nil` only when `program.days` is empty.
    ///
    /// - Parameters:
    ///   - program: the active program. Days are ranked by `order`, not by their
    ///     position in the array (SPEC S1).
    ///   - recentSessions: sessions of this program, in any order. Implementations
    ///     sort them; callers do not need to.
    ///   - now: the reference instant, injected for determinism (SPEC P11). The v1
    ///     rotation does not read it; the M4 frequency-aware selector (S5–S7) will.
    func nextDay(
        program: ProgramTemplate,
        recentSessions: [SessionSummary],
        now: Date
    ) -> ProgramDayTemplate?
}
