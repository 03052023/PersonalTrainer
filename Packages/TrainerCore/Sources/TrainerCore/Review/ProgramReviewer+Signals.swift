import Foundation

// Measurement side of the periodic review: SPEC §7.8 R1 (performance), R2 (fatigue),
// R3 (weekly volume) and R4 (adherence). Suggestions are built in
// `ProgramReviewer+Suggestions.swift`.

extension ProgramReviewer {
    /// Everything the review knows about one exercise of the program. Histories are per
    /// exercise (SPEC §7.1), so slots of the same exercise share one pool.
    struct ExercisePool: Sendable {
        let exercise: ExerciseDefinition
        /// Program slots of this exercise, sorted by `targetID.uuidString`.
        let slots: [ExerciseReviewInput]
        /// One entry per session up to `now`, oldest first (`ReviewHistory.sessions`).
        let sessions: [ExerciseHistoryEntry]
        /// SPEC R1 over `sessions`; `nil` when no session is measurable.
        let progress: ExerciseProgress?

        /// SPEC R1: no new best in the last 3 measurable sessions. A streak of 3 implies
        /// an earlier session to compare with, so 3 sessions alone are never stagnant.
        var isStagnant: Bool {
            (progress?.sessionsWithoutProgress ?? 0) >= ProgramReviewer.stagnationSessions
        }
    }

    /// SPEC R1 summary of an exercise.
    struct ExerciseProgress: Sendable, Hashable {
        /// Measurable sessions since the last one that set a new best estimate (the first
        /// measurable session sets the initial best).
        let sessionsWithoutProgress: Int
        let bestE1RM: Double
    }

    /// SPEC R2 counts, kept so the deload reason can show them.
    struct FatigueSignals: Sendable, Hashable {
        /// Working sets of the last 2 weeks recorded with RIR 0.
        let zeroReserveSets: Int
        /// Working sets of the last 2 weeks that have a recorded RIR.
        let ratedSets: Int
        /// Current prescriptions with `decrease` or `retry`.
        let strugglingPrescriptions: Int
        /// Current prescriptions other than `calibrate`.
        let judgedPrescriptions: Int

        /// SPEC R2: RIR 0 in more than 30 % of the rated working sets (30 % itself is not).
        var byReserve: Bool {
            ratedSets > 0 && Double(zeroReserveSets) * 10 > Double(ratedSets) * 3
        }

        /// SPEC R2 / §7.5 (a): at least 50 % of the judged prescriptions struggling.
        var byPrescriptions: Bool {
            judgedPrescriptions > 0 && strugglingPrescriptions * 2 >= judgedPrescriptions
        }

        var isHigh: Bool { byReserve || byPrescriptions }
    }

    /// SPEC R4 counts over the review window.
    struct Attendance: Sendable, Hashable {
        /// Distinct completed sessions with ≥ 1 working set that started in the window.
        let completed: Int
        /// `windowWeeks × programDayCount`.
        let expected: Int

        /// Completed ÷ expected, capped at 1 (training more than planned is not > 100 %).
        var ratio: Double { min(1, Double(completed) / Double(expected)) }

        /// SPEC R4: below 70 % (exactly 70 % is not low). Integers compared as `Double`
        /// are exact at these magnitudes, so the boundary never depends on rounding.
        var isLow: Bool { Double(completed) * 10 < Double(expected) * 7 }
    }

    /// Groups the slots per exercise, pools their histories and measures R1. Sorted by
    /// `exercise.id.uuidString` so the input order of the slots never matters (SPEC R7).
    static func exercisePools(from slots: [ExerciseReviewInput], now: Date) -> [ExercisePool] {
        var slotsByExercise: [UUID: [ExerciseReviewInput]] = [:]
        for slot in slots {
            slotsByExercise[slot.exercise.id, default: []].append(slot)
        }

        var pools: [ExercisePool] = []
        for exerciseSlots in slotsByExercise.values {
            let sortedSlots = exerciseSlots.sorted { $0.targetID.uuidString < $1.targetID.uuidString }
            guard let definition = sortedSlots.first?.exercise else { continue }
            // Sessions dated after `now` cannot have happened yet; they are ignored.
            let sessions = ReviewHistory.sessions(from: sortedSlots.flatMap(\.history))
                .filter { $0.date <= now }
            pools.append(
                ExercisePool(
                    exercise: definition,
                    slots: sortedSlots,
                    sessions: sessions,
                    progress: progress(of: sessions)
                )
            )
        }
        return pools.sorted { $0.exercise.id.uuidString < $1.exercise.id.uuidString }
    }

    /// SPEC R1: walks the sessions oldest first and counts how many measurable sessions
    /// followed the last new best. Comparing each session with the best before it is the
    /// same, for the last 3, as comparing them with the best before the three.
    ///
    /// Deload sessions are skipped: they are planned at 85 % of the load (SPEC §7.5) and
    /// are not a performance test, just as they count neither as success nor as failure
    /// for P4–P6.
    static func progress(of sessions: [ExerciseHistoryEntry]) -> ExerciseProgress? {
        var best: Double?
        var sinceBest = 0
        for entry in sessions where !entry.wasDeload {
            guard let estimate = ReviewHistory.measurableEstimate(of: entry)?.e1rm else { continue }
            if let current = best, !EstimatedOneRepMax.isImprovement(estimate, over: current) {
                sinceBest += 1
            } else {
                best = estimate
                sinceBest = 0
            }
        }
        return best.map { ExerciseProgress(sessionsWithoutProgress: sinceBest, bestE1RM: $0) }
    }

    /// SPEC R2 over the last 14 calendar days `[now − 14 d, now]`.
    ///
    /// A set without RIR is unknown effort, not "reps to spare": it is left out of both
    /// sides of the share (the progression engine reads a missing RIR the same way).
    /// Deload sessions stay in: their effort is real and shows fatigue fading.
    static func fatigueSignals(
        pools: [ExercisePool],
        prescriptions: [ExercisePrescription],
        now: Date,
        calendar: Calendar
    ) -> FatigueSignals {
        let start = addingDays(-fatigueWindowDays, to: now, calendar: calendar)
        var zeroReserve = 0
        var rated = 0
        for pool in pools {
            for entry in pool.sessions where entry.date >= start {
                for set in ReviewHistory.workingSets(entry.sets) {
                    guard let rir = set.rir else { continue }
                    rated += 1
                    // A negative RIR is not a valid record; it can only mean "no reps left".
                    if rir <= 0 {
                        zeroReserve += 1
                    }
                }
            }
        }

        // SPEC R2: a calibrating exercise has no verdict yet, so it is not in the base.
        // Each prescription is one program slot, like §7.5 (a) "exercícios do programa".
        let judged = prescriptions.filter { $0.note != .calibrate }
        let struggling = judged.filter { $0.note == .decrease || $0.note == .retry }

        return FatigueSignals(
            zeroReserveSets: zeroReserve,
            ratedSets: rated,
            strugglingPrescriptions: struggling.count,
            judgedPrescriptions: judged.count
        )
    }

    /// SPEC R3: working sets per primary group inside the window. An exercise with several
    /// primary groups counts each set once for each of them. Every primary group of the
    /// program has an entry, 0 included.
    static func workingSetsByMuscle(pools: [ExercisePool], window: DateInterval) -> [MuscleGroup: Int] {
        var totals: [MuscleGroup: Int] = [:]
        for pool in pools {
            let count = pool.sessions
                .filter { $0.date >= window.start && $0.date < window.end }
                .reduce(0) { $0 + ReviewHistory.workingSets($1.sets).count }
            for muscle in Set(pool.exercise.primaryMuscles) {
                totals[muscle, default: 0] += count
            }
        }
        return totals
    }

    /// SPEC R4: completed sessions of the window against the program days. Only
    /// `completed` sessions with ≥ 1 working set count, once per id (as in SPEC §7.4).
    /// `nil` when the program has no days (nothing to compare with).
    static func attendanceCounts(sessions: [SessionSummary], programDayCount: Int, window: DateInterval) -> Attendance? {
        let (expected, overflow) = programDayCount.multipliedReportingOverflow(by: windowWeeks)
        guard programDayCount > 0, !overflow else { return nil }

        var counted = Set<UUID>()
        for session in sessions
        where session.status == .completed
            && session.workingSetCount >= 1
            && session.startedAt >= window.start
            && session.startedAt < window.end {
            counted.insert(session.id)
        }
        return Attendance(completed: counted.count, expected: expected)
    }
}
