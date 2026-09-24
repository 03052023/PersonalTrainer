import Foundation

/// A new best estimated 1RM for one exercise in the latest session (SPEC §7.11 C6).
public struct PersonalRecord: Codable, Sendable, Hashable {
    public let exerciseID: UUID
    /// Epley estimate of the session's best working set (SPEC R1).
    public let e1rm: Double
    /// Best estimate of every earlier session. `PersonalRecordDetector` always fills it:
    /// the first measurable session of an exercise is never a record (SPEC C6).
    public let previousBest: Double?
    /// Load and reps of the set that produced `e1rm`, for the message text.
    public let load: Double
    public let reps: Int

    public init(exerciseID: UUID, e1rm: Double, previousBest: Double?, load: Double, reps: Int) {
        self.exerciseID = exerciseID
        self.e1rm = e1rm
        self.previousBest = previousBest
        self.load = load
        self.reps = reps
    }
}
