import Foundation

/// Double progression engine — SPEC §7.2, rules P1–P12.
///
/// Reps are progressed before load: the load only rises once every working set
/// reaches `repMax` (P4), and only falls when a failure repeats at the same load
/// (P6) or after a long pause (P9). Everything is derived from the history on each
/// call; no progression state is persisted (ARCHITECTURE ADR 003).
public struct DoubleProgressionRule: ProgressionRule {
    /// SPEC P9: an exercise last trained more than this long ago is "returning".
    private static let pauseThreshold: TimeInterval = 21 * 86_400

    /// SPEC P6 and P9 both cut the reference load by 10 % before rounding.
    private static let reductionFactor = 0.9

    /// SPEC P4: extra reps in reserve above the target that earn a second increment.
    private static let bonusReserveMargin = 2

    public init() {}

    public func prescribe(
        target: ExerciseTarget,
        exercise: ExerciseDefinition,
        history: [ExerciseHistoryEntry],
        now: Date
    ) -> ExercisePrescription {
        let increment = exercise.loadIncrement
        // SPEC P8: a prescribed load never drops below one increment, except pure
        // bodyweight work, where 0 means "no added load" (SPEC §12).
        let minimumLoad = exercise.equipment == .bodyweight ? 0 : increment

        guard let ledger = Self.ledger(for: history) else {
            // SPEC P2. Also reached when the history holds only deload sessions: they
            // never supply a reference load (SPEC 7.5, P3), so there is nothing to build on.
            return Self.calibration(for: target, increment: increment, minimumLoad: minimumLoad)
        }

        let latest = ledger.latest
        let referenceLoad = latest.referenceLoad
        // SPEC P8: the reference may be an off-increment override (SPEC P10), so it is
        // normalised once (rounded down) and every prescription below builds on it.
        let baseLoad = Load.round(referenceLoad, toIncrement: increment)
        let reducedLoad = Load.round(referenceLoad * Self.reductionFactor, toIncrement: increment)

        // SPEC P9: prevails over P4–P6. The pause is measured from the most recent
        // session with ≥ 1 working set *including* deload sessions — a deload week is
        // still training and resets the pause — while L keeps coming from the latest
        // non-deload session (SPEC 7.5, P3). Sessions without working sets never count
        // (SPEC P7).
        if now.timeIntervalSince(ledger.lastTrainedDate) > Self.pauseThreshold {
            return Self.prescription(
                for: target,
                load: max(reducedLoad, minimumLoad),
                targetReps: target.repMin,
                note: .returning
            )
        }

        // SPEC P6: failure is evaluated before success because a session with fewer
        // sets than S can still fail on the sets it did complete (SPEC P7).
        if latest.isFailure(repMin: target.repMin) {
            let repeatedAtSameLoad = ledger.previous.map {
                $0.isFailure(repMin: target.repMin) && $0.referenceLoad == referenceLoad
            } ?? false

            if repeatedAtSameLoad {
                // SPEC P6: new load = min(round↓(0.9·L, inc), L − inc) — a 10 % cut
                // rounded down, and never less than one full increment below the
                // reference. `baseLoad − inc` stands in for the raw `L − inc` so an
                // off-increment override (SPEC P10) still lands on the grid (SPEC P8).
                // The P8 minimum is applied last (e.g. L = 5, inc = 2.5 → 2.5).
                let decreased = min(reducedLoad, baseLoad - increment)
                return Self.prescription(
                    for: target,
                    load: max(decreased, minimumLoad),
                    targetReps: target.repMin,
                    note: .decrease
                )
            }

            return Self.prescription(
                for: target,
                load: max(baseLoad, minimumLoad),
                targetReps: target.repMin,
                note: .retry
            )
        }

        // SPEC P4 (with P7: fewer working sets than S can never count as success).
        if latest.workingSets.count >= target.sets, latest.lowestReps >= target.repMax {
            // SPEC P4: the +2·inc jump needs every set to report RIR; a missing value
            // is treated as "unknown effort", not as high reserve. The threshold
            // saturates so an absurd `targetRIR` can never trap (SPEC P11 robustness).
            let bonusThreshold = target.targetRIR.saturatingAdding(Self.bonusReserveMargin)
            let steps: Double = latest.hasReserve(atLeast: bonusThreshold) ? 2 : 1
            return Self.prescription(
                for: target,
                load: max(baseLoad + steps * increment, minimumLoad),
                targetReps: target.repMin,
                note: .increase
            )
        }

        // SPEC P5: every set reached repMin but not all reached repMax (or fewer than
        // S sets were done, SPEC P7). Keep the load and chase one more rep.
        return Self.prescription(
            for: target,
            load: max(baseLoad, minimumLoad),
            targetReps: min(target.repMax, latest.lowestReps.saturatingAdding(1)),
            note: .hold
        )
    }
}

// MARK: - Reading the history

extension DoubleProgressionRule {
    /// One session that is eligible for evaluation, with the derived values the
    /// rules need (SPEC P1, P3, P7).
    private struct EvaluableSession: Sendable {
        let date: Date
        let sessionID: UUID
        let workingSets: [SetResult]
        /// SPEC P3: mode of the working-set loads, ties resolved to the heavier load.
        let referenceLoad: Double
        let lowestReps: Int

        /// `workingSets` is never empty: SPEC P7 filters empty sessions out before.
        init(entry: ExerciseHistoryEntry, workingSets: [SetResult]) {
            self.date = entry.date
            self.sessionID = entry.sessionID
            self.workingSets = workingSets
            self.referenceLoad = Self.mode(of: workingSets.map(\.load))
            self.lowestReps = workingSets.map(\.reps).min() ?? 0
        }

        /// SPEC P6: any working set below `repMin` makes the whole session a failure.
        func isFailure(repMin: Int) -> Bool {
            lowestReps < repMin
        }

        /// SPEC P4 bonus: true only when every set reports RIR and none is below `threshold`.
        func hasReserve(atLeast threshold: Int) -> Bool {
            let reserves = workingSets.compactMap(\.rir)
            guard reserves.count == workingSets.count, let lowest = reserves.min() else {
                return false
            }
            return lowest >= threshold
        }

        private static func mode(of loads: [Double]) -> Double {
            var frequency: [Double: Int] = [:]
            for load in loads {
                frequency[load, default: 0] += 1
            }
            // SPEC P3: most frequent load wins; on a tie the heavier one is the reference.
            // The (count, load) ordering is total, so dictionary iteration order cannot
            // change the answer (SPEC P11).
            let best = frequency.max { lhs, rhs in
                lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
            }
            return best?.key ?? 0
        }
    }

    /// What the rules read from the history: the evaluable (non-deload) sessions
    /// that matter and the instant the exercise was last trained at all.
    private struct Ledger: Sendable {
        /// SPEC P3: the session L and the P4–P6 verdict come from.
        let latest: EvaluableSession
        /// SPEC P6: the session before `latest`, to detect a repeated failure.
        let previous: EvaluableSession?
        /// SPEC P9: date of the most recent session with ≥ 1 working set, deload included.
        let lastTrainedDate: Date
    }

    /// Builds the ledger, or `nil` when no non-deload session with working sets
    /// exists (SPEC P2). The caller may pass entries in any order (SPEC P11).
    private static func ledger(for history: [ExerciseHistoryEntry]) -> Ledger? {
        var lastTrainedDate: Date?
        var sessions: [EvaluableSession] = []

        for entry in mergedBySession(history) {
            // SPEC P1: only working sets are evaluated. A set whose load is not a finite
            // number can never be a reference — SPEC P8 rounding would carry NaN into the
            // prescription — so it is dropped as if it had not been recorded.
            let working = entry.sets.filter { !$0.isWarmup && $0.load.isFinite }

            // SPEC P7: a session without working sets is ignored entirely.
            guard !working.isEmpty else { continue }

            // SPEC P9: any training with working sets, deload included, moves the pause.
            lastTrainedDate = max(lastTrainedDate ?? entry.date, entry.date)

            // SPEC 7.5: deload sessions count neither as success nor as failure, and
            // never supply the reference load L (SPEC P3).
            guard !entry.wasDeload else { continue }

            sessions.append(EvaluableSession(entry: entry, workingSets: working))
        }

        guard let lastTrainedDate, !sessions.isEmpty else { return nil }

        // Most recent first. Session IDs are unique after `mergedBySession`, so
        // (date, sessionID) is a total order and equal-dated entries keep a fixed
        // rank: the higher `uuidString` is treated as the more recent (SPEC P11; the
        // same convention as `RotationSelector` and the app's `HistoryMapper`).
        sessions.sort { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            return lhs.sessionID.uuidString > rhs.sessionID.uuidString
        }

        return Ledger(
            latest: sessions[0],
            previous: sessions.dropFirst().first,
            lastTrainedDate: lastTrainedDate
        )
    }

    /// One entry per session. The same exercise can appear twice in a session (a
    /// hand-edited program or a substitution, SPEC RF-11), which the mapper delivers
    /// as two entries sharing `sessionID`. Evaluating only one of them would make the
    /// verdict depend on input order (SPEC P11) and on half the sets, so they are
    /// pooled first. Set order inside an entry is irrelevant to every rule.
    private static func mergedBySession(_ history: [ExerciseHistoryEntry]) -> [ExerciseHistoryEntry] {
        var merged: [UUID: ExerciseHistoryEntry] = [:]
        for entry in history {
            guard let existing = merged[entry.sessionID] else {
                merged[entry.sessionID] = entry
                continue
            }
            merged[entry.sessionID] = ExerciseHistoryEntry(
                sessionID: entry.sessionID,
                // Both halves carry the session start; if they disagree, the earlier wins.
                date: min(existing.date, entry.date),
                sets: existing.sets + entry.sets,
                // A session is a deload as a whole (SPEC 7.5); either half saying so is enough.
                wasDeload: existing.wasDeload || entry.wasDeload
            )
        }
        return Array(merged.values)
    }
}

// MARK: - Building prescriptions

extension DoubleProgressionRule {
    /// SPEC P2: no evaluable history for this exercise.
    private static func calibration(
        for target: ExerciseTarget,
        increment: Double,
        minimumLoad: Double
    ) -> ExercisePrescription {
        guard let startingLoad = target.startingLoad else {
            // SPEC P2: nothing to suggest; the user types the load on the first set.
            // One extra rep in reserve keeps that first guess conservative.
            return prescription(
                for: target,
                load: nil,
                targetReps: target.repMin,
                targetRIR: target.targetRIR.saturatingAdding(1),
                note: .calibrate
            )
        }

        // SPEC P8 applies to the starting load as well: it must sit on the increment grid.
        let load = max(Load.round(startingLoad, toIncrement: increment), minimumLoad)
        return prescription(for: target, load: load, targetReps: target.repMin, note: .calibrate)
    }

    /// Structural fields (sets, rep range, rest) always come from the target; only
    /// load, rep goal, note and — for SPEC P2 without load — RIR are decided here.
    private static func prescription(
        for target: ExerciseTarget,
        load: Double?,
        targetReps: Int,
        targetRIR: Int? = nil,
        note: PrescriptionNote
    ) -> ExercisePrescription {
        ExercisePrescription(
            exerciseID: target.exerciseID,
            load: load,
            sets: target.sets,
            repMin: target.repMin,
            repMax: target.repMax,
            targetReps: targetReps,
            targetRIR: targetRIR ?? target.targetRIR,
            restSeconds: target.restSeconds,
            note: note
        )
    }
}

// MARK: - Overflow-safe arithmetic

private extension Int {
    /// `self + other` that saturates instead of trapping. Reps and RIR reach the
    /// engine from sync events and backups without range checks; an absurd value
    /// must degrade the prescription, never crash the plan computation (SPEC P11,
    /// AGENTS §4: no trap outside programming preconditions).
    func saturatingAdding(_ other: Int) -> Int {
        let (sum, overflow) = addingReportingOverflow(other)
        guard overflow else { return sum }
        return other > 0 ? .max : .min
    }
}
