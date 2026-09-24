import Foundation
import Testing
@testable import TrainerCore

/// Shared fixtures for the coach tests (SPEC §7.11 C1–C8).
///
/// Every instant is fixed (AGENTS R3). `now` is Wednesday 2026-09-23 12:00 UTC, the same
/// instant as `ReviewFixtures.now`: ISO week 2026-W39, whose Monday is 2026-09-21.
enum CoachFixtures {
    static let oneHour: TimeInterval = 3_600
    static let oneDay: TimeInterval = 86_400

    static let now = ReviewFixtures.now
    /// Local day of `now` in UTC and in São Paulo (09:00 there).
    static let today = "2026-09-23"
    /// ISO week of `now`.
    static let week = "2026-W39"
    static let utc = ReviewFixtures.utc

    /// `dayOffset` days after Monday 2026-09-21 00:00 UTC (negative = before), at
    /// `hour`:`minute` UTC.
    static func at(_ dayOffset: Int, hour: Int = 18, minute: Int = 0) -> Date {
        ReviewFixtures.monday.addingTimeInterval(
            Double(dayOffset) * oneDay + Double(hour) * oneHour + Double(minute) * 60
        )
    }

    static func id(_ number: Int) -> UUID {
        ReviewFixtures.id(number)
    }

    static func feed(
        _ input: CoachInput,
        log: CoachLog = CoachLog(),
        now: Date = now,
        calendar: Calendar = utc
    ) -> [CoachMessage] {
        CoachFeedBuilder.feed(input: input, log: log, now: now, calendar: calendar)
    }

    static func entry(
        _ messageID: String,
        _ rule: CoachRule,
        _ itemKey: String,
        _ action: CoachAction,
        at date: Date
    ) -> CoachLogEntry {
        CoachLogEntry(messageID: messageID, rule: rule, itemKey: itemKey, action: action, date: date)
    }

    static func log(_ entries: [CoachLogEntry]) -> CoachLog {
        CoachLog(entries: entries)
    }

    // MARK: Health (C3)

    static func health(_ kind: HealthSuggestionKind) -> HealthSuggestion {
        HealthSuggestion(
            id: "health-\(kind.rawValue)",
            kind: kind,
            title: "Título \(kind.rawValue)",
            detail: "Detalhe \(kind.rawValue) com 7 números.",
            referenceTopic: "topic.\(kind.rawValue)"
        )
    }

    // MARK: Review (C2)

    static func suggestion(
        _ kind: ProgramSuggestionKind,
        id: String,
        topic: String = "topic.volume"
    ) -> ProgramSuggestion {
        ProgramSuggestion(
            id: id,
            kind: kind,
            rule: "R3",
            title: "Título \(kind.rawValue)",
            reason: "Motivo de \(kind.rawValue) com 12 séries.",
            referenceTopic: topic
        )
    }

    static func report(_ suggestions: [ProgramSuggestion], generatedAt: Date = now) -> ReviewReport {
        ReviewReport(
            generatedAt: generatedAt,
            stagnantExerciseIDs: [],
            fatigueHigh: false,
            weeklySetsByMuscle: [:],
            adherence: nil,
            suggestions: suggestions
        )
    }

    /// `addSets:chest:<target>:<week>` as `ProgramReviewer` writes it.
    static func addSetsID(target: Int, week: String = week) -> String {
        "addSets:chest:\(id(target).uuidString):\(week)"
    }

    // MARK: Personal records (C6)

    static func record(
        exercise: Int,
        load: Double,
        reps: Int,
        previousBest: Double?
    ) -> PersonalRecord {
        PersonalRecord(
            exerciseID: id(exercise),
            e1rm: EstimatedOneRepMax.epley(load: load, reps: reps),
            previousBest: previousBest,
            load: load,
            reps: reps
        )
    }

    // MARK: Everything at once

    /// One reason for every rule to speak at `now`.
    static func fullInput() -> CoachInput {
        CoachInput(
            deload: .scheduled(trigger: .scheduled, since: at(0, hour: 10)),
            review: report([
                suggestion(.addSets, id: addSetsID(target: 201)),
                suggestion(.switchProgram, id: "switchProgram:\(id(1).uuidString):\(week)", topic: "topic.mesocycle"),
            ]),
            healthSuggestions: [health(.lowSteps), health(.updateVo2Max)],
            provisioningExpiry: at(4, hour: 23),
            lastSessionStart: at(-5),
            nextDayName: "Dia B",
            personalRecords: [record(exercise: 101, load: 105, reps: 5, previousBest: 100 * (1 + 5.0 / 30))],
            exerciseNames: [id(101): "Supino reto"],
            lastBackupAt: nil,
            completedSessionCount: 12,
            goal: .longevity,
            longevityDoneThisWeek: []
        )
    }
}
