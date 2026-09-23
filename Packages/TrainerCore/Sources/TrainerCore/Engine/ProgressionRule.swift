import Foundation

/// Strategy that turns an exercise's history into today's prescription (SPEC §7.2).
///
/// Implementations are pure functions: `now` is an explicit parameter so the same
/// input always yields the same output (SPEC P11, ARCHITECTURE AR-9), and the input
/// types carry no heart-rate data by construction (SPEC P12, AGENTS R2).
public protocol ProgressionRule: Sendable {
    /// Computes the prescription for one exercise, independently of the others.
    ///
    /// - Parameters:
    ///   - target: program parameters for the exercise (sets, rep range, RIR, rest,
    ///     optional starting load). Structural fields are copied into the prescription.
    ///   - exercise: catalogue definition; supplies `loadIncrement` and `equipment`
    ///     for the rounding and minimum-load rules (SPEC P8).
    ///   - history: entries for this exercise only, already filtered by the caller
    ///     (ARCHITECTURE §6). Any order is accepted; the rule orders them itself.
    ///   - now: reference instant for time-based rules (SPEC P9). Never read from
    ///     the system clock inside the engine (AGENTS R3).
    func prescribe(
        target: ExerciseTarget,
        exercise: ExerciseDefinition,
        history: [ExerciseHistoryEntry],
        now: Date
    ) -> ExercisePrescription
}
