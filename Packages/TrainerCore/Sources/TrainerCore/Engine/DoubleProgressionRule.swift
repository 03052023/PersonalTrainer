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

        let sessions = Self.evaluableSessions(in: history)

        guard let latest = sessions.first else {
            // SPEC P2
            return Self.calibration(for: target, increment: increment, minimumLoad: minimumLoad)
        }

        let referenceLoad = latest.referenceLoad
        // SPEC P8: the reference may be an off-increment override (SPEC P10), so it is
        // normalised once and every prescription below builds on the normalised value.
        let baseLoad = Load.round(referenceLoad, toIncrement: increment)
        let reducedLoad = Load.round(referenceLoad * Self.reductionFactor, toIncrement: increment)

        // SPEC P9: prevails over P4–P6. Only evaluable sessions count, so a deload or
        // an empty session does not reset the pause (SPEC 7.5, P7).
        if now.timeIntervalSince(latest.date) > Self.pauseThreshold {
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
            let previous = sessions.dropFirst().first
            let repeatedAtSameLoad = previous.map {
                $0.isFailure(repMin: target.repMin) && $0.referenceLoad == referenceLoad
            } ?? false

            if repeatedAtSameLoad {
                // SPEC P6: "round down 0.9·L, at minimum L − inc". Read as a floor on the
                // new load (fixed task decision). Note that for any L that is already a
                // multiple of inc, round-down(0.9·L) ≤ L − inc, so this floor makes the
                // decrease exactly one increment; the 10 % cut only bites on off-increment
                // references. Reported as a SPEC ambiguity; kept literal here.
                let decreased = max(reducedLoad, baseLoad - increment)
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
            // is treated as "unknown effort", not as high reserve.
            let steps: Double = latest.hasReserve(
                atLeast: target.targetRIR + Self.bonusReserveMargin
            ) ? 2 : 1
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
            targetReps: min(target.repMax, latest.lowestReps + 1),
            note: .hold
        )
    }
}

// MARK: - Evaluable sessions

extension DoubleProgressionRule {
    /// One history entry that is eligible for evaluation, with the derived values
    /// the rules need (SPEC P1, P3, P7).
    private struct EvaluableSession: Sendable {
        let date: Date
        let sessionID: UUID
        let workingSets: [SetResult]
        /// SPEC P3: mode of the working-set loads, ties resolved to the heavier load.
        let referenceLoad: Double
        let lowestReps: Int

        init?(entry: ExerciseHistoryEntry) {
            // SPEC 7.5: deload sessions count neither as success nor as failure.
            guard !entry.wasDeload else { return nil }

            // SPEC P1: only working sets are evaluated.
            let working = entry.sets.filter { !$0.isWarmup }

            // SPEC P7: a session without working sets is ignored entirely.
            guard let lowestReps = working.map(\.reps).min() else { return nil }

            self.date = entry.date
            self.sessionID = entry.sessionID
            self.workingSets = working
            self.referenceLoad = Self.mode(of: working.map(\.load))
            self.lowestReps = lowestReps
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

    /// Filters and orders the history most-recent first. The caller may pass entries
    /// in any order; sorting here keeps the rule deterministic (SPEC P11). Session ID
    /// breaks date ties so equal-dated entries also have a fixed order.
    private static func evaluableSessions(in history: [ExerciseHistoryEntry]) -> [EvaluableSession] {
        history
            .compactMap(EvaluableSession.init(entry:))
            .sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return lhs.date > rhs.date
                }
                return lhs.sessionID.uuidString > rhs.sessionID.uuidString
            }
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
                targetRIR: target.targetRIR + 1,
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
