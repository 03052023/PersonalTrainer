import Foundation

/// One exercise slot of the active program, as the periodic review sees it (SPEC §7.8).
///
/// `history` is the exercise's history (SPEC §7.1: history is per exercise, not per
/// program), in any order, from finished sessions only — the same entries the
/// progression engine receives. When the same exercise sits in two slots, both may carry
/// the same history: the reviewer pools it per exercise and counts each session once.
public struct ExerciseReviewInput: Sendable, Hashable {
    public let exercise: ExerciseDefinition
    /// `ExerciseTarget.id` of this slot; suggestions point at it (`ProgramSuggestion.targetIDs`).
    public let targetID: UUID
    /// `ProgramDayTemplate.id` of the day that holds the slot.
    public let dayID: UUID
    /// Current `ExerciseTarget.sets` (S).
    public let sets: Int
    public let repMin: Int
    public let repMax: Int
    public let history: [ExerciseHistoryEntry]

    public init(
        exercise: ExerciseDefinition,
        targetID: UUID,
        dayID: UUID,
        sets: Int,
        repMin: Int,
        repMax: Int,
        history: [ExerciseHistoryEntry]
    ) {
        self.exercise = exercise
        self.targetID = targetID
        self.dayID = dayID
        self.sets = sets
        self.repMin = repMin
        self.repMax = repMax
        self.history = history
    }
}
