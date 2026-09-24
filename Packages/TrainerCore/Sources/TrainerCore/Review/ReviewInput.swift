import Foundation

/// Everything the periodic review reads (SPEC §7.8). Pure data: `now` and the calendar
/// are passed to `ProgramReviewer.review` separately (AGENTS R3).
public struct ReviewInput: Sendable, Hashable {
    public let programID: UUID
    public let programName: String
    /// Number of days of the active program (SPEC R4 denominator).
    public let programDayCount: Int
    /// First session of the active program. `nil` when it was never trained: R3, R4 and
    /// the mesocycle suggestion then have nothing to judge.
    public let programStartDate: Date?
    /// One entry per exercise slot of the active program.
    public let exercises: [ExerciseReviewInput]
    /// Sessions of the active program, in any order (SPEC R4).
    public let sessions: [SessionSummary]
    /// Weekly working-set range of the program goal (SPEC §7.9, e.g. 10...20 for hypertrophy).
    public let weeklySetTarget: ClosedRange<Int>
    /// Optional per-group override of the weekly minimum of working sets. The ceiling
    /// stays `weeklySetTarget.upperBound` (raised to the override when it is higher).
    /// A value of 0 means "never suggest more sets for this group".
    public let muscleTargets: [MuscleGroup: Int]?
    /// Today's prescription for each slot, as the progression engine computed it (SPEC R2).
    public let currentPrescriptions: [ExercisePrescription]
    public let recovery: RecoveryContext
    /// Weeks after which switching programs is suggested (SPEC §7.11 C2, default 8).
    public let mesocycleWeeks: Int
    /// SPEC §7.4: the training week starts on Monday unless configured otherwise.
    public let weekStartsOnMonday: Bool

    public init(
        programID: UUID,
        programName: String,
        programDayCount: Int,
        programStartDate: Date?,
        exercises: [ExerciseReviewInput],
        sessions: [SessionSummary],
        weeklySetTarget: ClosedRange<Int>,
        muscleTargets: [MuscleGroup: Int]? = nil,
        currentPrescriptions: [ExercisePrescription],
        recovery: RecoveryContext = .unknown,
        mesocycleWeeks: Int = 8,
        weekStartsOnMonday: Bool = true
    ) {
        self.programID = programID
        self.programName = programName
        self.programDayCount = programDayCount
        self.programStartDate = programStartDate
        self.exercises = exercises
        self.sessions = sessions
        self.weeklySetTarget = weeklySetTarget
        self.muscleTargets = muscleTargets
        self.currentPrescriptions = currentPrescriptions
        self.recovery = recovery
        self.mesocycleWeeks = mesocycleWeeks
        self.weekStartsOnMonday = weekStartsOnMonday
    }
}
