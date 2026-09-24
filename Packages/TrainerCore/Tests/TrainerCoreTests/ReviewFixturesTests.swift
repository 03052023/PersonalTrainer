import Foundation
import Testing
@testable import TrainerCore

/// Shared fixtures for the periodic review tests (SPEC §7.8, §7.11 C6).
///
/// Every instant is fixed (AGENTS R3). `monday` is 2026-09-21 00:00 UTC, the first day
/// of ISO week 2026-W39; the review runs on Wednesday of that week at 12:00 UTC. The
/// 4 complete weeks of SPEC R3/R4 are then [2026-08-24, 2026-09-21) in UTC.
enum ReviewFixtures {
    static let oneHour: TimeInterval = 3_600
    static let oneDay: TimeInterval = 86_400

    /// 2026-09-21T00:00:00Z, Monday.
    static let monday = Date(timeIntervalSince1970: 1_789_948_800)
    /// Wednesday 2026-09-23 12:00 UTC.
    static let now = monday.addingTimeInterval(2 * oneDay + 12 * oneHour)
    /// Monday 2026-08-24 00:00 UTC: first instant of the review window.
    static let windowStart = monday.addingTimeInterval(-28 * oneDay)
    /// ISO week of `now`, as it appears in the suggestion ids.
    static let week = "2026-W39"

    static let programID = id(1)
    /// First session of the program: 6 weeks before `monday`. Covers the whole window and
    /// is 6 weeks and 2.5 days before `now`, short of the 8-week mesocycle.
    static let defaultStart = at(-42, hour: 9)

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// America/Sao_Paulo is UTC−3 all year since 2019 (no DST).
    static func saoPaulo() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        return calendar
    }

    /// Deterministic UUID `00000000-0000-0000-0000-<number padded to 12 digits>`.
    static func id(_ number: Int) -> UUID {
        let digits = String(number)
        let padded = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
        return UUID(uuidString: "00000000-0000-0000-0000-\(padded)")!
    }

    /// `dayOffset` days after `monday` (negative = before), at `hour`:00 UTC.
    static func at(_ dayOffset: Int, hour: Int = 18) -> Date {
        monday.addingTimeInterval(Double(dayOffset) * oneDay + Double(hour) * oneHour)
    }

    // MARK: Catalog and program

    static func exercise(
        _ number: Int,
        _ primaries: [MuscleGroup],
        name: String? = nil,
        unit: LoadUnit = .kilograms,
        equipment: Equipment = .barbell
    ) -> ExerciseDefinition {
        ExerciseDefinition(
            id: id(100 + number),
            slug: "exercise-\(number)",
            name: name ?? "Exercício \(number)",
            primaryMuscles: primaries,
            equipment: equipment,
            loadUnit: unit,
            loadIncrement: 2.5
        )
    }

    /// Program slot `target` (targetID = id(200 + target)) of `exercise`.
    static func slot(
        _ exercise: ExerciseDefinition,
        target: Int,
        day: Int = 1,
        sets: Int = 3,
        repMin: Int = 8,
        repMax: Int = 12,
        history: [ExerciseHistoryEntry] = []
    ) -> ExerciseReviewInput {
        ExerciseReviewInput(
            exercise: exercise,
            targetID: id(200 + target),
            dayID: id(300 + day),
            sets: sets,
            repMin: repMin,
            repMax: repMax,
            history: history
        )
    }

    // MARK: History

    static func workingSet(_ load: Double, _ reps: Int, rir: Int? = 2, at date: Date) -> SetResult {
        SetResult(load: load, reps: reps, rir: rir, isWarmup: false, completedAt: date)
    }

    static func warmup(_ load: Double, _ reps: Int, rir: Int? = nil, at date: Date) -> SetResult {
        SetResult(load: load, reps: reps, rir: rir, isWarmup: true, completedAt: date)
    }

    static func entry(
        _ session: UUID,
        _ date: Date,
        _ sets: [SetResult],
        deload: Bool = false
    ) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(sessionID: session, date: date, sets: sets, wasDeload: deload)
    }

    /// One session per value, on consecutive days ending the day before `monday` (inside
    /// the last complete week), each with one working set of 1 rep so the Epley estimate
    /// equals the load (SPEC R1).
    static func history(
        e1rms: [Double],
        exercise number: Int,
        deloadAt: Set<Int> = [],
        rir: Int? = 2
    ) -> [ExerciseHistoryEntry] {
        let count = e1rms.count
        return e1rms.enumerated().map { index, load -> ExerciseHistoryEntry in
            let date = at(index - count)
            return entry(
                id(10_000 + number * 100 + index),
                date,
                [workingSet(load, 1, rir: rir, at: date)],
                deload: deloadAt.contains(index)
            )
        }
    }

    /// One session per window week (Wednesday 18:00) with `setsPerWeek[w]` working sets.
    /// The load rises every week, so the exercise never stagnates (SPEC R1).
    static func weeklyHistory(
        _ setsPerWeek: [Int],
        exercise number: Int,
        rir: Int? = 2
    ) -> [ExerciseHistoryEntry] {
        setsPerWeek.enumerated().map { week, count -> ExerciseHistoryEntry in
            let date = at(-28 + week * 7 + 2)
            let sets = (0..<count).map { _ in workingSet(50 + Double(week) * 2.5, 10, rir: rir, at: date) }
            return entry(id(20_000 + number * 100 + week), date, sets)
        }
    }

    // MARK: Sessions

    static func session(
        _ number: Int,
        at date: Date,
        status: SessionStatus = .completed,
        workingSets: Int = 9
    ) -> SessionSummary {
        SessionSummary(
            id: id(30_000 + number),
            programDayID: id(301),
            startedAt: date,
            endedAt: date.addingTimeInterval(oneHour),
            status: status,
            primaryMusclesTrained: [.chest],
            workingSetCount: workingSets
        )
    }

    /// `count` completed sessions inside the window, every other day from its start.
    static func sessionsInWindow(_ count: Int) -> [SessionSummary] {
        (0..<count).map { session($0, at: at(-28 + ($0 * 2) % 28, hour: 10)) }
    }

    // MARK: Review

    static func prescription(_ note: PrescriptionNote, exercise number: Int = 1) -> ExercisePrescription {
        ExercisePrescription(exerciseID: id(100 + number), load: 50, note: note)
    }

    static func input(
        exercises: [ExerciseReviewInput],
        sessions: [SessionSummary] = sessionsInWindow(12),
        programDayCount: Int = 3,
        programStartDate: Date? = defaultStart,
        weeklySetTarget: ClosedRange<Int> = 10...20,
        muscleTargets: [MuscleGroup: Int]? = nil,
        prescriptions: [ExercisePrescription] = [],
        recovery: RecoveryContext = .unknown,
        mesocycleWeeks: Int = 8,
        weekStartsOnMonday: Bool = true
    ) -> ReviewInput {
        ReviewInput(
            programID: programID,
            programName: "Programa A",
            programDayCount: programDayCount,
            programStartDate: programStartDate,
            exercises: exercises,
            sessions: sessions,
            weeklySetTarget: weeklySetTarget,
            muscleTargets: muscleTargets,
            currentPrescriptions: prescriptions,
            recovery: recovery,
            mesocycleWeeks: mesocycleWeeks,
            weekStartsOnMonday: weekStartsOnMonday
        )
    }

    static func review(_ input: ReviewInput, now: Date = now, calendar: Calendar = utc) -> ReviewReport {
        ProgramReviewer.review(input: input, now: now, calendar: calendar)
    }

    static func suggestions(_ report: ReviewReport, _ kind: ProgramSuggestionKind) -> [ProgramSuggestion] {
        report.suggestions.filter { $0.kind == kind }
    }

    static func kinds(_ report: ReviewReport) -> [ProgramSuggestionKind] {
        report.suggestions.map(\.kind)
    }

    static func isClose(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 1e-9
    }
}
