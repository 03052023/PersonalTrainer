import Foundation

/// Reads exercise histories the same way everywhere in `Review/` (SPEC §7.8, §7.11 C6).
enum ReviewHistory {
    /// One entry per session, oldest first.
    ///
    /// - Exact duplicate entries are dropped: when the same exercise sits in two program
    ///   slots, both slots may carry the same history and a session must count once.
    /// - Entries that share a `sessionID` but differ (the exercise done twice in one
    ///   session, SPEC RF-11) are pooled, as the progression engine does: evaluating only
    ///   one half would make the answer depend on input order (SPEC R7).
    /// - Ties on `date` are broken by `sessionID.uuidString`, the higher one being the
    ///   more recent — the convention of `DoubleProgressionRule` and `RotationSelector`.
    static func sessions(from entries: [ExerciseHistoryEntry]) -> [ExerciseHistoryEntry] {
        var seen = Set<ExerciseHistoryEntry>()
        var merged: [UUID: ExerciseHistoryEntry] = [:]
        for entry in entries where seen.insert(entry).inserted {
            guard let existing = merged[entry.sessionID] else {
                merged[entry.sessionID] = entry
                continue
            }
            merged[entry.sessionID] = ExerciseHistoryEntry(
                sessionID: entry.sessionID,
                // Both halves carry the session start; if they disagree, the earlier wins.
                date: min(existing.date, entry.date),
                sets: existing.sets + entry.sets,
                // A session is a deload as a whole (SPEC §7.5).
                wasDeload: existing.wasDeload || entry.wasDeload
            )
        }
        return merged.values.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.sessionID.uuidString < rhs.sessionID.uuidString
        }
    }

    /// SPEC P1: working sets only. A non-finite load is a corrupt record and is dropped,
    /// as in the progression engine.
    static func workingSets(_ sets: [SetResult]) -> [SetResult] {
        sets.filter { !$0.isWarmup && $0.load.isFinite }
    }

    /// Best Epley estimate of a session, or `nil` when nothing in it is measurable
    /// (no working set, or only sets without added load). SPEC R1 cannot see progress
    /// in work it cannot estimate, so such sessions are left out of R1 and C6.
    static func measurableEstimate(of entry: ExerciseHistoryEntry) -> (set: SetResult, e1rm: Double)? {
        guard let best = EstimatedOneRepMax.bestWorkingSet(entry.sets), best.e1rm > 0 else {
            return nil
        }
        return best
    }
}
