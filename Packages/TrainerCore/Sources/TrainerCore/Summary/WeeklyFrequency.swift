import Foundation

// NOTE: this file holds three public types (`WeeklyFrequencyEntry`,
// `WeeklyFrequencyReport`, `WeeklyFrequency`) although AGENTS.md §4 prefers one
// public type per file. The T2.3 scope (TASKS.md) lists exactly
// `Summary/WeeklyFrequency.swift`, and R10 forbids files outside that scope.

/// One row of the weekly frequency panel (SPEC §7.4, RF-17): how many completed
/// sessions trained `muscle` as a primary group this week versus the target.
public struct WeeklyFrequencyEntry: Sendable, Hashable {
    public let muscle: MuscleGroup
    /// Completed sessions this week that count for `muscle` (SPEC §7.4).
    public let completed: Int
    /// Weekly goal for `muscle`: the per-group override or the default (2×).
    public let target: Int

    public init(muscle: MuscleGroup, completed: Int, target: Int) {
        self.muscle = muscle
        self.completed = completed
        self.target = target
    }
}

/// Weekly frequency for every muscle group over one training week (SPEC §7.4).
public struct WeeklyFrequencyReport: Sendable, Hashable {
    /// First instant of the week (00:00 on the configured first day, in the
    /// caller's calendar). Inclusive.
    public let weekStart: Date
    /// First instant of the following week. Exclusive: a session starting exactly
    /// at `weekEnd` belongs to the next week.
    public let weekEnd: Date
    /// One entry per `MuscleGroup`, in `MuscleGroup.allCases` order, so the panel
    /// renders in the fixed SPEC §7.4 order without sorting.
    public let entries: [WeeklyFrequencyEntry]

    public init(weekStart: Date, weekEnd: Date, entries: [WeeklyFrequencyEntry]) {
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.entries = entries
    }
}

/// Pure functions behind the weekly frequency panel (SPEC §7.4). `now` and the
/// `Calendar` (with its time zone) are parameters so the result is deterministic
/// (SPEC P11) and identical on iPhone, Watch and in tests (AGENTS R3).
public enum WeeklyFrequency: Sendable {
    /// Default weekly goal per muscle group (SPEC §7.4: "Meta padrão: 2×/semana").
    public static let defaultTarget = 2

    /// The training week that contains `now`, as a half-open interval
    /// `[weekStart, weekEnd)` in `calendar`'s time zone.
    ///
    /// The week starts at 00:00 on Monday (SPEC §7.4) or Sunday when
    /// `weekStartsOnMonday == false`. The computation uses the `weekday`
    /// component rather than `calendar.firstWeekday` so a locale-configured
    /// calendar cannot silently change the result.
    public static func weekInterval(
        containing now: Date,
        weekStartsOnMonday: Bool,
        calendar: Calendar
    ) -> DateInterval {
        // Gregorian weekday numbering: 1 = Sunday … 7 = Saturday.
        let firstWeekday = weekStartsOnMonday ? 2 : 1
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceWeekStart = (weekday - firstWeekday + 7) % 7

        // Day arithmetic goes through the calendar (not 86 400 s) so weeks that
        // cross a DST change still start at local midnight.
        let weekStart = calendar.startOfDay(
            for: addingDays(-daysSinceWeekStart, to: today, calendar: calendar)
        )
        let weekEnd = calendar.startOfDay(
            for: addingDays(7, to: weekStart, calendar: calendar)
        )
        return DateInterval(start: weekStart, end: weekEnd)
    }

    /// Completed-versus-target counts for every muscle group in the week that
    /// contains `now` (SPEC §7.4).
    ///
    /// A session counts once for each group in `primaryMusclesTrained` when it is
    /// `.completed`, has `workingSetCount >= 1` and `startedAt` falls inside the
    /// week. `inProgress` and `abandoned` sessions never count. Secondary muscles
    /// are not part of `SessionSummary`, so they cannot count (SPEC §7.4 v1).
    ///
    /// - Parameters:
    ///   - sessions: Any set of sessions; filtering by week happens here. Duplicate
    ///     ids are counted once.
    ///   - targets: Per-group weekly goals; groups missing here use `defaultTarget`.
    ///   - defaultTarget: Goal for groups without an override (SPEC §7.4: 2).
    ///   - now: Reference instant that picks the week.
    ///   - weekStartsOnMonday: SPEC §7.4 default is Monday; `false` starts on Sunday.
    ///   - calendar: Calendar and time zone that define "00:00" and the weekday.
    public static func report(
        sessions: [SessionSummary],
        targets: [MuscleGroup: Int],
        defaultTarget: Int = WeeklyFrequency.defaultTarget,
        now: Date,
        weekStartsOnMonday: Bool = true,
        calendar: Calendar
    ) -> WeeklyFrequencyReport {
        let week = weekInterval(
            containing: now,
            weekStartsOnMonday: weekStartsOnMonday,
            calendar: calendar
        )

        var completedByMuscle: [MuscleGroup: Int] = [:]
        var countedSessionIDs = Set<UUID>()

        for session in sessions {
            // SPEC §7.4: only completed sessions with at least one working set.
            guard session.status == .completed,
                  session.workingSetCount >= 1,
                  // Half-open week: `DateInterval.contains` is inclusive at the end,
                  // which would double-count a session starting exactly at weekEnd.
                  session.startedAt >= week.start,
                  session.startedAt < week.end,
                  // "counts 1 per session": a duplicated summary must not count twice.
                  countedSessionIDs.insert(session.id).inserted
            else {
                continue
            }

            for muscle in session.primaryMusclesTrained {
                completedByMuscle[muscle, default: 0] += 1
            }
        }

        let entries = MuscleGroup.allCases.map { muscle in
            WeeklyFrequencyEntry(
                muscle: muscle,
                completed: completedByMuscle[muscle] ?? 0,
                target: targets[muscle] ?? defaultTarget
            )
        }

        return WeeklyFrequencyReport(
            weekStart: week.start,
            weekEnd: week.end,
            entries: entries
        )
    }

    /// `Calendar.date(byAdding:)` is optional only for absurd inputs; fall back to
    /// plain seconds instead of trapping, so a bad date can never crash the app.
    private static func addingDays(_ days: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)
            ?? date.addingTimeInterval(TimeInterval(days) * 86_400)
    }
}
