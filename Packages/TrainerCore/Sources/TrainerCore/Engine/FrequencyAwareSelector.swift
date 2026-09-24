import Foundation

/// Frequency- and recovery-aware day selection (SPEC §7.3 v2, rules S5–S7).
///
/// - S5: every candidate day scores the number of its primary muscle groups still
///   below their weekly target (SPEC §7.4) in the week that contains `now`.
/// - S6: days with a primary group trained as primary less than `recoveryHours` ago
///   are excluded; if that excludes every day, S6 is ignored.
/// - S7: the highest score wins; ties follow the rotation order (SPEC S2), i.e. the
///   circular day order starting at the day `RotationSelector` would pick.
///
/// `ProgramDayTemplate` only knows exercise ids, so the caller supplies each day's
/// primary groups (`dayMuscles`, built from the catalogue). A day missing from that
/// map has no groups: it scores 0 and is never excluded by S6.
///
/// Like every selector, it ignores `inProgress` sessions (SPEC S3 belongs to the
/// planner), trusts no input order and never reads the clock (SPEC P11, AGENTS R3).
/// No heart-rate metric can reach it: `SessionSummary` has no such field (SPEC P12).
public struct FrequencyAwareSelector: WorkoutSelector {
    /// Per-group weekly goals; groups missing here use `defaultWeeklyTarget` (SPEC §7.4).
    public let weeklyTargets: [MuscleGroup: Int]
    /// SPEC §7.4: "Meta padrão: 2×/semana".
    public let defaultWeeklyTarget: Int
    /// SPEC S6: minimum rest, in hours, before a group can be the primary focus again.
    public let recoveryHours: Double
    /// Calendar and time zone that define the training week (SPEC §7.4).
    public let calendar: Calendar
    /// SPEC §7.4: the week starts on Monday unless configured otherwise.
    public let weekStartsOnMonday: Bool
    /// Primary muscle groups of each program day, keyed by `ProgramDayTemplate.id`.
    public let dayMuscles: [UUID: Set<MuscleGroup>]

    public init(
        weeklyTargets: [MuscleGroup: Int] = [:],
        defaultWeeklyTarget: Int = WeeklyFrequency.defaultTarget,
        recoveryHours: Double = 48,
        calendar: Calendar,
        weekStartsOnMonday: Bool = true,
        dayMuscles: [UUID: Set<MuscleGroup>]
    ) {
        self.weeklyTargets = weeklyTargets
        self.defaultWeeklyTarget = defaultWeeklyTarget
        self.recoveryHours = recoveryHours
        self.calendar = calendar
        self.weekStartsOnMonday = weekStartsOnMonday
        self.dayMuscles = dayMuscles
    }

    public func nextDay(
        program: ProgramTemplate,
        recentSessions: [SessionSummary],
        now: Date
    ) -> ProgramDayTemplate? {
        let candidates = rotationOrderedDays(program: program, recentSessions: recentSessions, now: now)
        guard !candidates.isEmpty else {
            return nil
        }

        // SPEC S6: drop days whose groups are still recovering; if nothing is left,
        // S6 is ignored and every day competes.
        let recovering = musclesTrainedWithinRecoveryWindow(recentSessions, now: now)
        let rested = candidates.filter { muscles(of: $0).isDisjoint(with: recovering) }
        let eligible = rested.isEmpty ? candidates : rested

        // SPEC S5 + S7: highest score wins. `eligible` keeps the rotation order and
        // only a strictly higher score replaces the current best, so a tie goes to the
        // day that comes first in the rotation (SPEC S2).
        let belowTarget = musclesBelowWeeklyTarget(recentSessions, now: now)
        var best = eligible[0]
        var bestScore = score(of: best, belowTarget: belowTarget)
        for day in eligible.dropFirst() {
            let dayScore = score(of: day, belowTarget: belowTarget)
            if dayScore > bestScore {
                best = day
                bestScore = dayScore
            }
        }
        return best
    }
}

private extension FrequencyAwareSelector {
    /// Program days in `order` (SPEC S1), rotated so the day `RotationSelector` would
    /// pick comes first and the others follow circularly. This is the tie-break order
    /// of SPEC S7 ("empate → ordem da rotação (S2)").
    func rotationOrderedDays(
        program: ProgramTemplate,
        recentSessions: [SessionSummary],
        now: Date
    ) -> [ProgramDayTemplate] {
        // Same ranking as RotationSelector: `order`, then array position, so a
        // duplicated `order` (an invariant violation) still ranks deterministically.
        let ordered = program.days
            .enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
        guard !ordered.isEmpty else {
            return []
        }

        let rotationPick = RotationSelector().nextDay(
            program: program,
            recentSessions: recentSessions,
            now: now
        )
        let start = rotationPick.flatMap { ordered.firstIndex(of: $0) } ?? 0
        return Array(ordered[start...] + ordered[..<start])
    }

    func muscles(of day: ProgramDayTemplate) -> Set<MuscleGroup> {
        dayMuscles[day.id] ?? []
    }

    /// SPEC S5: number of the day's primary groups still below the weekly target.
    func score(of day: ProgramDayTemplate, belowTarget: Set<MuscleGroup>) -> Int {
        muscles(of: day).intersection(belowTarget).count
    }

    /// SPEC S5 via §7.4: groups whose completed count this week is below the goal.
    /// `WeeklyFrequency.report` applies the §7.4 counting rule (completed sessions
    /// with ≥ 1 working set, one count per session and group, half-open week in the
    /// caller's calendar), so the selector and the weekly panel always agree.
    func musclesBelowWeeklyTarget(_ sessions: [SessionSummary], now: Date) -> Set<MuscleGroup> {
        let report = WeeklyFrequency.report(
            sessions: sessions,
            targets: weeklyTargets,
            defaultTarget: defaultWeeklyTarget,
            now: now,
            weekStartsOnMonday: weekStartsOnMonday,
            calendar: calendar
        )
        return Set(report.entries.filter { $0.completed < $0.target }.map(\.muscle))
    }

    /// SPEC S6: groups trained as primary less than `recoveryHours` before `now`.
    ///
    /// Counts `completed` and `abandoned` sessions with ≥ 1 working set — the muscles
    /// were worked either way, the same sessions that move the rotation (SPEC S2).
    /// `inProgress` sessions are the planner's business (SPEC S3).
    ///
    /// SPEC S6 does not say which instant "trained at" means. `startedAt` is used, the
    /// same instant that places a session in a week (§7.4) and orders the history (P3,
    /// S2). A session dated after `now` (clock skew) counts as just trained, which
    /// errs on the side of rest. A non-positive or NaN `recoveryHours` disables S6.
    func musclesTrainedWithinRecoveryWindow(_ sessions: [SessionSummary], now: Date) -> Set<MuscleGroup> {
        guard recoveryHours > 0 else {
            return []
        }
        let window = recoveryHours * 3_600

        var recovering = Set<MuscleGroup>()
        for session in sessions {
            switch session.status {
            case .inProgress:
                continue
            case .completed, .abandoned:
                guard session.workingSetCount >= 1 else { continue }
                // SPEC S6: "há < 48 h" — exactly `recoveryHours` ago is already rested.
                if now.timeIntervalSince(session.startedAt) < window {
                    recovering.formUnion(session.primaryMusclesTrained)
                }
            }
        }
        return recovering
    }
}
