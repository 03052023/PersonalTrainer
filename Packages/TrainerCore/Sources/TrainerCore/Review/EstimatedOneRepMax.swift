import Foundation

/// Estimated one-repetition maximum (SPEC §7.8 R1, §7.11 C6).
///
/// The periodic review measures performance per exercise with the Epley formula over
/// the best working set of each session. Pure arithmetic: no clock, no heart rate.
public enum EstimatedOneRepMax: Sendable {
    /// Relative tolerance under which two estimates are the same mark. Different
    /// load × reps pairs can land on the same estimate (90 × 10 and 100 × 6 both give
    /// 120) with IEEE-754 noise in the last bit; that noise must never read as progress
    /// (SPEC R1 "sem aumento") nor as a new record (SPEC C6).
    static let improvementTolerance = 1e-9

    /// SPEC R1: 1RM estimate = load × (1 + reps / 30) (Epley).
    ///
    /// Returns 0 when there is nothing measurable: `reps ≤ 0`, a non-finite load or a
    /// load ≤ 0 (pure bodyweight work has no added load to estimate from). One rep is
    /// the maximum itself, so `reps == 1` returns `load` unchanged.
    public static func epley(load: Double, reps: Int) -> Double {
        guard load.isFinite, load > 0, reps > 0 else { return 0 }
        if reps == 1 { return load }
        return load * (1 + Double(reps) / 30)
    }

    /// SPEC R1: the best working set of a session and its estimate.
    ///
    /// Warm-ups (SPEC P1) and sets with a non-finite load are ignored; `nil` when no
    /// set is left. Ties are broken by a total order over the set's fields (heavier
    /// load, then more reps, then the earlier set, then the lower recorded RIR) so the
    /// answer never depends on input order (SPEC R7).
    public static func bestWorkingSet(_ sets: [SetResult]) -> (set: SetResult, e1rm: Double)? {
        var best: (set: SetResult, e1rm: Double)?
        for set in sets where !set.isWarmup && set.load.isFinite {
            let candidate = (set: set, e1rm: epley(load: set.load, reps: set.reps))
            if let current = best, !ranksAbove(candidate, current) {
                continue
            }
            best = candidate
        }
        return best
    }

    /// Whether `value` beats `best` by more than floating-point noise.
    static func isImprovement(_ value: Double, over best: Double) -> Bool {
        value > best + improvementTolerance * max(1, abs(best))
    }

    private static func ranksAbove(
        _ lhs: (set: SetResult, e1rm: Double),
        _ rhs: (set: SetResult, e1rm: Double)
    ) -> Bool {
        if lhs.e1rm != rhs.e1rm { return lhs.e1rm > rhs.e1rm }
        if lhs.set.load != rhs.set.load { return lhs.set.load > rhs.set.load }
        if lhs.set.reps != rhs.set.reps { return lhs.set.reps > rhs.set.reps }
        if lhs.set.completedAt != rhs.set.completedAt { return lhs.set.completedAt < rhs.set.completedAt }
        switch (lhs.set.rir, rhs.set.rir) {
        case let (left?, right?):
            return left < right
        case (.some, .none):
            return true
        case (.none, _):
            return false
        }
    }
}
