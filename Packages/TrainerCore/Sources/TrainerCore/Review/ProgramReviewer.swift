import Foundation

/// Periodic review of the active program — SPEC §7.8 R1–R7 (TASKS T4.5), the recovery
/// modulation of R6 (T5.4) and the end-of-mesocycle program switch of §7.11 C2.
///
/// A pure function of its input (SPEC §7.7): `now` and the calendar are parameters
/// (AGENTS R3), nothing is random and the output order is fixed (SPEC R7). It lives in
/// `Review/`, outside `Engine/`: aggregated recovery trends may modulate its suggestions,
/// but nothing here reaches a prescribed load (SPEC P12, AGENTS R2).
public enum ProgramReviewer: Sendable {
    /// SPEC R1: sessions in a row without a new best estimate that make an exercise stagnant.
    static let stagnationSessions = 3
    /// Sessions without progress after which swapping the exercise is suggested instead of
    /// changing its rep range. SPEC R5 asks for stagnation "por 2 revisões seguidas"; the
    /// review keeps no memory of earlier reports, so 6 sessions (two stagnation windows of
    /// 3) stand in for it (task T4.5).
    static let swapSessions = 6
    /// SPEC R2: the RIR 0 share is measured over the last 2 weeks.
    static let fatigueWindowDays = 14
    /// SPEC R3/R4: volume and adherence are averaged over the last 4 complete weeks.
    static let windowWeeks = 4
    /// SPEC R3: at most +2 sets per group per review. Removals use the same cap so a
    /// single review never cuts a group by more than it could add.
    static let maxSetChangesPerMuscle = 2
    /// Task T4.5: added sets never take an exercise above 10 sets.
    static let maxSetsPerExercise = 10
    /// Removed sets never take an exercise below 1 set.
    static let minSetsPerExercise = 1
    /// SPEC R5 / task T4.5: the neighbouring rep range is 2 reps away (8–12 → 6–10).
    static let repRangeShift = 2
    /// Lowest `repMin` a shifted range may reach: the floor of the strength goal (SPEC §7.9,
    /// 3–6). Below it the range moves up instead (3–6 → 5–8).
    static let lowestRepMin = 3

    /// Computes the review report for `input` as of `now`.
    ///
    /// - Parameters:
    ///   - input: Program, histories, sessions and current prescriptions.
    ///   - now: Instant of the review; picks the ISO week of the suggestion ids and the
    ///     4 complete weeks before the current one.
    ///   - calendar: Calendar and time zone that define midnight and the week (SPEC §7.4).
    public static func review(input: ReviewInput, now: Date, calendar: Calendar) -> ReviewReport {
        let week = isoWeekLabel(for: now, calendar: calendar)
        let window = reviewWindow(now: now, weekStartsOnMonday: input.weekStartsOnMonday, calendar: calendar)
        let pools = exercisePools(from: input.exercises, now: now)
        let fatigue = fatigueSignals(
            pools: pools,
            prescriptions: input.currentPrescriptions,
            now: now,
            calendar: calendar
        )
        let setsInWindow = workingSetsByMuscle(pools: pools, window: window)

        // SPEC R3/R4 compare 4 complete weeks. Weeks before the program's first training
        // day belong to another program (or to none) and would read as missed sessions
        // and missing volume, so both rules wait until the program covers the whole window.
        // A program first trained at any time on the window's first day covers it.
        let coversWindow = input.programStartDate.map {
            calendar.startOfDay(for: $0) <= window.start
        } ?? false
        let attendance = coversWindow
            ? attendanceCounts(sessions: input.sessions, programDayCount: input.programDayCount, window: window)
            : nil
        // SPEC R4: with low adherence, fewer days come before any extra volume.
        let lowAdherence = attendance?.isLow ?? false

        var suggestions: [ProgramSuggestion] = []

        if let attendance, attendance.isLow, input.programDayCount > 1 {
            suggestions.append(
                reduceDaysSuggestion(attendance: attendance, programDayCount: input.programDayCount, week: week)
            )
        }

        if coversWindow {
            suggestions += volumeSuggestions(
                input: input,
                pools: pools,
                setsInWindow: setsInWindow,
                fatigue: fatigue,
                allowAdditions: !lowAdherence,
                week: week
            )
        }

        let stagnant = pools.filter(\.isStagnant)
        // SPEC R5: "R1 em ≥ 50 % dos exercícios" — distinct exercises of the program.
        let stagnationWide = !pools.isEmpty && stagnant.count * 2 >= pools.count
        // A deload already running (its prescriptions carry the `deload` note, SPEC §7.5)
        // makes a new deload suggestion redundant.
        let deloadRunning = input.currentPrescriptions.contains { $0.note == .deload }
        if fatigue.isHigh || stagnationWide, !deloadRunning {
            suggestions.append(
                deloadSuggestion(
                    fatigue: fatigue,
                    stagnantCount: stagnationWide ? stagnant.count : nil,
                    exerciseCount: pools.count,
                    week: week
                )
            )
        }

        for pool in stagnant {
            suggestions += exerciseChangeSuggestions(for: pool, week: week)
        }

        if let switchProgram = switchProgramSuggestion(input: input, now: now, calendar: calendar, week: week) {
            suggestions.append(switchProgram)
        }

        suggestions = modulated(suggestions, recovery: input.recovery, fatigueHigh: fatigue.isHigh)

        // SPEC R7: fixed kind order, then the stable id.
        suggestions.sort { lhs, rhs in
            if lhs.kind.reviewRank != rhs.kind.reviewRank {
                return lhs.kind.reviewRank < rhs.kind.reviewRank
            }
            return lhs.id < rhs.id
        }

        return ReviewReport(
            generatedAt: now,
            stagnantExerciseIDs: stagnant.map(\.exercise.id),
            fatigueHigh: fatigue.isHigh,
            weeklySetsByMuscle: setsInWindow.mapValues { Double($0) / Double(windowWeeks) },
            adherence: attendance?.ratio,
            suggestions: suggestions
        )
    }
}

// MARK: - Calendar

extension ProgramReviewer {
    /// ISO 8601 week of `date` in `calendar`'s time zone, e.g. "2026-W39". Used in the
    /// suggestion ids so reviewing the same history twice in one week gives the same ids.
    /// Always ISO (Monday, 4-day first week) so the label never depends on the locale.
    static func isoWeekLabel(for date: Date, calendar: Calendar) -> String {
        var iso = Calendar(identifier: .gregorian)
        iso.timeZone = calendar.timeZone
        iso.firstWeekday = 2
        iso.minimumDaysInFirstWeek = 4
        let components = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return "\(year)-W\(week < 10 ? "0" : "")\(week)"
    }

    /// SPEC R3/R4: the last `windowWeeks` complete weeks before the week that contains
    /// `now`, as the half-open interval `[start, end)` of SPEC §7.4.
    static func reviewWindow(now: Date, weekStartsOnMonday: Bool, calendar: Calendar) -> DateInterval {
        let current = WeeklyFrequency.weekInterval(
            containing: now,
            weekStartsOnMonday: weekStartsOnMonday,
            calendar: calendar
        )
        // Calendar days, not 86 400 s, so a DST change inside the window keeps midnight.
        let start = calendar.startOfDay(
            for: addingDays(-7 * windowWeeks, to: current.start, calendar: calendar)
        )
        return DateInterval(start: start, end: current.start)
    }

    /// `Calendar.date(byAdding:)` is optional only for absurd inputs; fall back to plain
    /// seconds instead of trapping (AGENTS §4).
    static func addingDays(_ days: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)
            ?? date.addingTimeInterval(TimeInterval(days) * 86_400)
    }
}
