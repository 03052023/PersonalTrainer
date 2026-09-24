import Foundation

/// Result of one periodic review (SPEC §7.8): the signals it measured and the
/// suggestions it derived from them, in the fixed order of SPEC R7.
public struct ReviewReport: Codable, Sendable, Hashable {
    /// The `now` the review was computed for (never the system clock, AGENTS R3).
    public let generatedAt: Date
    /// SPEC R1: exercises (`ExerciseDefinition.id`) whose best estimated 1RM did not rise
    /// in their last 3 sessions, sorted by `uuidString`.
    public let stagnantExerciseIDs: [UUID]
    /// SPEC R2: either fatigue signal fired.
    public let fatigueHigh: Bool
    /// SPEC R3: average working sets per week for every primary group of the program,
    /// over the last 4 complete weeks (the current week is excluded).
    public let weeklySetsByMuscle: [MuscleGroup: Double]
    /// SPEC R4: completed sessions per week ÷ program days over the last 4 complete
    /// weeks, capped at 1. `nil` when the program does not cover those 4 weeks yet.
    public let adherence: Double?
    public let suggestions: [ProgramSuggestion]

    public init(
        generatedAt: Date,
        stagnantExerciseIDs: [UUID],
        fatigueHigh: Bool,
        weeklySetsByMuscle: [MuscleGroup: Double],
        adherence: Double?,
        suggestions: [ProgramSuggestion]
    ) {
        self.generatedAt = generatedAt
        self.stagnantExerciseIDs = stagnantExerciseIDs
        self.fatigueHigh = fatigueHigh
        self.weeklySetsByMuscle = weeklySetsByMuscle
        self.adherence = adherence
        self.suggestions = suggestions
    }
}
