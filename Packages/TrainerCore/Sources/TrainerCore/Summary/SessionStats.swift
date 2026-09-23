import Foundation

/// Totals shown in the session summary: duration, working sets and tonnage
/// (SPEC RF-12). Pure value computed from the recorded sets; the session bounds
/// come from the caller so this code never reads the system clock (SPEC P11).
public struct SessionStats: Sendable, Hashable {
    /// Wall-clock length of the session. `nil` while the session has no `endedAt`
    /// (still in progress), so the UI can show "em andamento" instead of a number.
    public let duration: TimeInterval?
    /// Sets with `isWarmup == false`, across every exercise (SPEC P1).
    public let workingSetCount: Int
    /// Sets with `isWarmup == true`. Kept separate because warm-ups never enter
    /// volume or progression (SPEC P1, RF-12).
    public let warmupSetCount: Int
    /// Σ load × reps over working sets only (SPEC RF-12). Warm-ups are excluded
    /// so the number reflects training volume, not ramp-up sets.
    public let tonnage: Double
    /// Exercises with at least one working set recorded. Skipped exercises and
    /// exercises with only warm-ups are not counted, mirroring SPEC P7/§7.4 where
    /// zero working sets means the exercise was not performed. The SPEC does not
    /// define this field explicitly; this is the conservative reading.
    public let exerciseCount: Int

    public init(
        duration: TimeInterval?,
        workingSetCount: Int,
        warmupSetCount: Int,
        tonnage: Double,
        exerciseCount: Int
    ) {
        self.duration = duration
        self.workingSetCount = workingSetCount
        self.warmupSetCount = warmupSetCount
        self.tonnage = tonnage
        self.exerciseCount = exerciseCount
    }

    /// Computes the summary for one session.
    ///
    /// - Parameters:
    ///   - startedAt: When the session started.
    ///   - endedAt: When the session finished; `nil` while in progress.
    ///   - exerciseSets: One inner array per session exercise, in session order,
    ///     holding the sets recorded for that exercise (may be empty for a skipped
    ///     exercise, SPEC RF-10).
    public static func compute(
        startedAt: Date,
        endedAt: Date?,
        exerciseSets: [[SetResult]]
    ) -> SessionStats {
        // The SPEC has no rule for `endedAt` earlier than `startedAt` (corrupt or
        // clock-skewed data). Clamp to zero rather than surface a negative duration.
        let duration = endedAt.map { max(0, $0.timeIntervalSince(startedAt)) }

        var workingSetCount = 0
        var warmupSetCount = 0
        var tonnage = 0.0
        var exerciseCount = 0

        for sets in exerciseSets {
            var exerciseHasWorkingSet = false
            for set in sets {
                if set.isWarmup {
                    warmupSetCount += 1
                } else {
                    // SPEC P1: only working sets count toward volume.
                    workingSetCount += 1
                    tonnage += set.load * Double(set.reps)
                    exerciseHasWorkingSet = true
                }
            }
            if exerciseHasWorkingSet {
                exerciseCount += 1
            }
        }

        return SessionStats(
            duration: duration,
            workingSetCount: workingSetCount,
            warmupSetCount: warmupSetCount,
            tonnage: tonnage,
            exerciseCount: exerciseCount
        )
    }
}
