import Foundation

/// Everything the coach reads to build the feed (SPEC §7.11). Pure data computed by the
/// app from its stores; `now` and the calendar are passed to `CoachFeedBuilder.feed`
/// separately (AGENTS R3).
public struct CoachInput: Sendable {
    /// C8 key of the balance block in `longevityDoneThisWeek`.
    public static let balanceKey = "balance"
    /// C8 key of the mobility block in `longevityDoneThisWeek`.
    public static let mobilityKey = "mobility"

    /// C1: the deload status computed by `DeloadScheduler`.
    public var deload: CoachDeloadState
    /// C2: the report of the current review cycle. The app runs `ProgramReviewer` when
    /// `ReviewSchedule.isDue`, stores `generatedAt` in `CoachLog.lastReviewAt` and keeps
    /// passing that report until the next review; answered suggestions are hidden by
    /// the log. `nil` when no review was run.
    public var review: ReviewReport?
    /// C3: `HealthReport.suggestions` of today.
    public var healthSuggestions: [HealthSuggestion]
    /// C4: `ExpirationDate` of the embedded provisioning profile
    /// (`ProvisioningProfileParser`), or `nil` when unknown.
    public var provisioningExpiry: Date?
    /// C5: `startedAt` of the most recent session with ≥ 1 working set, deload included
    /// (the session SPEC P9 measures the pause from). `nil` before the first session.
    public var lastSessionStart: Date?
    /// C5: name of the next day of the rotation, e.g. "Dia A".
    public var nextDayName: String?
    /// C6: `PersonalRecordDetector.newRecords` of the last completed session.
    public var personalRecords: [PersonalRecord]
    /// C6: exercise names by `ExerciseDefinition.id`.
    public var exerciseNames: [UUID: String]
    /// C6: load unit by `ExerciseDefinition.id`; a missing exercise reads as kilograms.
    public var loadUnits: [UUID: LoadUnit]
    /// C7: when the last backup was made, or `nil` if never.
    public var lastBackupAt: Date?
    /// C7: completed sessions ever recorded.
    public var completedSessionCount: Int
    /// C8: goal of the active program.
    public var goal: ProgramGoal?
    /// C8: blocks already marked this week (`balanceKey`, `mobilityKey`).
    public var longevityDoneThisWeek: Set<String>

    public init(
        deload: CoachDeloadState = .none,
        review: ReviewReport? = nil,
        healthSuggestions: [HealthSuggestion] = [],
        provisioningExpiry: Date? = nil,
        lastSessionStart: Date? = nil,
        nextDayName: String? = nil,
        personalRecords: [PersonalRecord] = [],
        exerciseNames: [UUID: String] = [:],
        loadUnits: [UUID: LoadUnit] = [:],
        lastBackupAt: Date? = nil,
        completedSessionCount: Int = 0,
        goal: ProgramGoal? = nil,
        longevityDoneThisWeek: Set<String> = []
    ) {
        self.deload = deload
        self.review = review
        self.healthSuggestions = healthSuggestions
        self.provisioningExpiry = provisioningExpiry
        self.lastSessionStart = lastSessionStart
        self.nextDayName = nextDayName
        self.personalRecords = personalRecords
        self.exerciseNames = exerciseNames
        self.loadUnits = loadUnits
        self.lastBackupAt = lastBackupAt
        self.completedSessionCount = completedSessionCount
        self.goal = goal
        self.longevityDoneThisWeek = longevityDoneThisWeek
    }
}
