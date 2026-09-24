import Foundation

/// Decides whether the next plan is a deload: SPEC §7.5 (triggers, re-arm and
/// duration) and §7.11 C1, on top of the pure rules of `DeloadPolicy`.
///
/// Everything is derived from the history on each call; the only stored input is
/// the user's `DeloadDecisions` (ARCHITECTURE ADR 003). Pure: `now` is a parameter
/// (AGENTS R3), no input type carries cardiac data (SPEC §7.6, P12), and the order
/// of every input is irrelevant (SPEC P11).
///
/// How the sessions are read:
/// - A **deload run** is a chronological group of sessions flagged `isDeload`, of
///   any status. It starts at the `startedAt` of its first session and is running
///   while `DeloadPolicy.isDeloadActive` says its pass of the rotation is not over.
/// - A deload session opens a new run, instead of joining the previous one, when a
///   normal session `completed` with ≥ 1 working set lies between them, or when the
///   previous run had already completed its pass. The second case keeps apart two
///   deloads with nothing normal in between (a pause of N weeks right after a light
///   week, or a manual request right after one): merged into one run, the old start
///   would keep (b) due and every later session would be light.
/// - The end of a finished run is the `startedAt` of its last session, the one
///   that completed the pass.
///
/// Priority: running deload > manual (c) > many decreases (a) > scheduled (b).
public enum DeloadScheduler: Sendable {
    /// The deload status for the next plan.
    ///
    /// - `.active(start:)` while the most recent deload run has not completed its
    ///   pass. Nothing ends it early: a long pause keeps it running (SPEC §7.5), and
    ///   `DeloadDecisions` are not consulted.
    /// - `.pending(.manual)` when `manualRequestedAt` is set and no deload session
    ///   started at or after it (so the request is also later than the start of the
    ///   last deload, which is itself such a session).
    /// - `.pending(.manyDecreases)`, SPEC §7.5 (a) with the re-arm: a `decrease`
    ///   counts only if the latest non-deload session with ≥ 1 working set in that
    ///   exercise's history started after both the end of the last deload and
    ///   `dismissedAt`. The others stay in the total as non-reductions.
    /// - `.pending(.scheduled)`, SPEC §7.5 (b): N weeks since the more recent of the
    ///   start of the last deload and `dismissedAt`, or since the first session when
    ///   neither exists.
    /// - `.inactive` otherwise, and always for a program without days.
    ///
    /// - Parameters:
    ///   - normalPrescriptions: the normal (non-deload) prescription of each exercise
    ///     of the active program, as `DoubleProgressionRule` computes it.
    ///   - histories: each exercise's history, keyed by `exerciseID`, in any order.
    ///   - sessions: every known session, in any order.
    ///   - programDayCount: days in the active program (the length of one pass).
    ///   - decisions: the user's manual request and dismissal.
    ///   - weeksBetweenDeloads: SPEC §7.5 N; a non-positive N turns (b) off.
    ///   - now: the reference instant (AGENTS R3).
    public static func status(
        normalPrescriptions: [ExercisePrescription],
        histories: [UUID: [ExerciseHistoryEntry]],
        sessions: [SessionSummary],
        programDayCount: Int,
        decisions: DeloadDecisions,
        weeksBetweenDeloads: Int = DeloadPolicy.defaultWeeksBetweenDeloads,
        now: Date
    ) -> DeloadStatus {
        // A program without days has nothing to plan, light or not.
        guard programDayCount > 0 else {
            return .inactive
        }

        let ordered = chronological(sessions)
        let lastRun = latestRun(in: ordered, programDayCount: programDayCount)

        if let lastRun, lastRun.isRunning(programDayCount: programDayCount) {
            return .active(start: lastRun.start)
        }

        if isManualRequestPending(decisions.manualRequestedAt, sessions: ordered) {
            return .pending(trigger: .manual)
        }

        // Past this point the last run, if any, has completed its pass.
        let rearmCutoff = latest(lastRun?.end, decisions.dismissedAt)
        let counted = normalPrescriptions.map { prescription in
            countedForManyDecreases(
                prescription,
                history: histories[prescription.exerciseID] ?? [],
                cutoff: rearmCutoff
            )
        }

        // `DeloadPolicy.trigger` falls back to `firstSessionDate` only when the
        // anchor is nil, which is exactly the (b) rule with a dismissal folded in.
        let trigger = DeloadPolicy.trigger(
            currentPrescriptions: counted,
            lastDeloadStart: latest(lastRun?.start, decisions.dismissedAt),
            firstSessionDate: ordered.first?.startedAt,
            weeksBetweenDeloads: weeksBetweenDeloads,
            now: now
        )
        if let trigger {
            return .pending(trigger: trigger)
        }
        return .inactive
    }
}

// MARK: - Deload runs

private extension DeloadScheduler {
    /// Consecutive deload sessions that make up one light week (see the type doc).
    struct DeloadRun {
        let start: Date
        /// Never empty; chronological.
        var sessions: [SessionSummary]

        /// `startedAt` of the session that completed the pass, once it is complete.
        var end: Date {
            sessions.last?.startedAt ?? start
        }

        func isRunning(programDayCount: Int) -> Bool {
            // Only this run's own sessions: a session of the previous run that
            // started at the same instant must not count towards this pass.
            DeloadPolicy.isDeloadActive(
                deloadStart: start,
                sessionsSinceStart: sessions,
                programDayCount: programDayCount
            )
        }
    }

    /// The most recent deload run, or `nil` when no session was ever a deload.
    static func latestRun(in ordered: [SessionSummary], programDayCount: Int) -> DeloadRun? {
        var run: DeloadRun?
        // A normal session completed with working sets since the run's last session.
        var interrupted = false

        for session in ordered {
            if session.isDeload {
                if let current = run, !interrupted, current.isRunning(programDayCount: programDayCount) {
                    run?.sessions.append(session)
                } else {
                    run = DeloadRun(start: session.startedAt, sessions: [session])
                }
                interrupted = false
            } else if session.status == .completed, session.workingSetCount >= 1 {
                interrupted = true
            }
        }
        return run
    }

    /// Sessions oldest first, one per id.
    ///
    /// Ties on `startedAt` are broken by id, the lower `uuidString` first, so the
    /// higher one ranks as the more recent, as in `RotationSelector` and
    /// `DoubleProgressionRule`. A duplicated id keeps its earliest copy.
    static func chronological(_ sessions: [SessionSummary]) -> [SessionSummary] {
        var seen = Set<UUID>()
        return sessions
            .sorted { precedes($0, $1) }
            .filter { seen.insert($0.id).inserted }
    }

    static func precedes(_ lhs: SessionSummary, _ rhs: SessionSummary) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt
        }
        if lhs.id != rhs.id {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        // Copies of one record: ranking them by every field read here makes the
        // copy kept independent of the input order (SPEC P11).
        if lhs.isDeload != rhs.isDeload {
            return lhs.isDeload
        }
        if lhs.status != rhs.status {
            return lhs.status.rawValue < rhs.status.rawValue
        }
        return lhs.workingSetCount > rhs.workingSetCount
    }
}

// MARK: - Triggers

private extension DeloadScheduler {
    /// SPEC §7.5 (c). "Later than the start of the last deload and no deload session
    /// since the request" reduces to the second clause: the start of the last
    /// deload is a deload session, so a start at or after the request fails it.
    static func isManualRequestPending(_ requestedAt: Date?, sessions: [SessionSummary]) -> Bool {
        guard let requestedAt else {
            return false
        }
        return !sessions.contains { $0.isDeload && $0.startedAt >= requestedAt }
    }

    /// SPEC §7.5 re-arm of (a). A `decrease` whose source session did not start
    /// after `cutoff` (end of the last deload or the dismissal, whichever is later)
    /// was already answered, so it is handed to `DeloadPolicy` as `retry`: still
    /// part of the total, no longer a reduction. Without a cutoff nothing is gated.
    static func countedForManyDecreases(
        _ prescription: ExercisePrescription,
        history: [ExerciseHistoryEntry],
        cutoff: Date?
    ) -> ExercisePrescription {
        guard prescription.note == .decrease, let cutoff else {
            return prescription
        }
        if let source = latestNormalSessionDate(in: history), source > cutoff {
            return prescription
        }
        return ExercisePrescription(
            exerciseID: prescription.exerciseID,
            load: prescription.load,
            sets: prescription.sets,
            repMin: prescription.repMin,
            repMax: prescription.repMax,
            targetReps: prescription.targetReps,
            targetRIR: prescription.targetRIR,
            restSeconds: prescription.restSeconds,
            note: .retry
        )
    }

    /// One session of an exercise's history, its entries pooled.
    struct PooledSession {
        var date: Date
        var isDeload: Bool
        var hasWorkingSet: Bool
    }

    /// Start of the latest non-deload session with ≥ 1 working set: the session
    /// SPEC P3 takes the reference from, hence the source of a `decrease` note.
    /// Entries sharing a session are pooled as `DoubleProgressionRule` does: the
    /// session is a deload if either part says so, and it starts at the earlier date.
    static func latestNormalSessionDate(in history: [ExerciseHistoryEntry]) -> Date? {
        var pooled: [UUID: PooledSession] = [:]
        for entry in history {
            // SPEC P1 and P7: warm-ups and non-finite loads are not working sets.
            let hasWorkingSet = entry.sets.contains { !$0.isWarmup && $0.load.isFinite }
            if var session = pooled[entry.sessionID] {
                session.date = min(session.date, entry.date)
                session.isDeload = session.isDeload || entry.wasDeload
                session.hasWorkingSet = session.hasWorkingSet || hasWorkingSet
                pooled[entry.sessionID] = session
            } else {
                pooled[entry.sessionID] = PooledSession(
                    date: entry.date,
                    isDeload: entry.wasDeload,
                    hasWorkingSet: hasWorkingSet
                )
            }
        }
        return pooled.values
            .filter { !$0.isDeload && $0.hasWorkingSet }
            .map { $0.date }
            .max()
    }

    static func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
        [lhs, rhs].compactMap { $0 }.max()
    }
}
