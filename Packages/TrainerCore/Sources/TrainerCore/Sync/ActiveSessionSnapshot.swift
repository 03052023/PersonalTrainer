import Foundation

// The five snapshot DTOs below share this file because the T0.7 scope fixes the
// file name `Sync/ActiveSessionSnapshot.swift` for the whole snapshot payload
// (AGENTS §4 prefers one public type per file; the deviation is deliberate).

/// One set already registered in the active session, as mirrored to the Watch.
///
/// Same shape as `SetResult` (Domain) plus the identifiers the Watch needs to
/// emit `setUpdated`/`setDeleted` for it: `SetLogModel` is addressed by the
/// `setID` minted by whoever logged the set (ARCHITECTURE §7, AR-4).
/// SPEC P12 / AGENTS R2: no heart-rate field, by construction.
public struct SetSnapshot: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let index: Int
    public let load: Double
    public let reps: Int
    public let rir: Int?
    public let isWarmup: Bool
    public let completedAt: Date

    public init(
        id: UUID,
        index: Int,
        load: Double,
        reps: Int,
        rir: Int? = nil,
        isWarmup: Bool = false,
        completedAt: Date
    ) {
        self.id = id
        self.index = index
        self.load = load
        self.reps = reps
        self.rir = rir
        self.isWarmup = isWarmup
        self.completedAt = completedAt
    }
}

/// One exercise of a session (or of the next plan) with its frozen prescription.
///
/// `id` is the session-exercise identifier (`SessionExerciseModel.uuid`) that
/// `setLogged`/`exerciseSkipped`/`exerciseSubstituted` reference; `exerciseID`
/// points at the catalog entry. `exerciseName` and `prescription` are snapshots
/// (ARCHITECTURE §5 decision 3, AR-10): editing the program later must not
/// change what the Watch shows for a session already planned.
public struct ExerciseSnapshot: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let exerciseID: UUID
    public let exerciseName: String
    public let order: Int
    public let prescription: ExercisePrescription
    public let wasSkipped: Bool
    public let sets: [SetSnapshot]

    public init(
        id: UUID,
        exerciseID: UUID,
        exerciseName: String,
        order: Int,
        prescription: ExercisePrescription,
        wasSkipped: Bool = false,
        sets: [SetSnapshot] = []
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.exerciseName = exerciseName
        self.order = order
        self.prescription = prescription
        self.wasSkipped = wasSkipped
        self.sets = sets
    }
}

/// The session in progress, complete enough for the Watch to run it with the
/// iPhone out of reach (SPEC §4, F6; ARCHITECTURE §9).
public struct SessionSnapshot: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let programDayID: UUID
    public let programDayName: String
    public let startedAt: Date
    public let status: SessionStatus
    public let exercises: [ExerciseSnapshot]

    public init(
        id: UUID,
        programDayID: UUID,
        programDayName: String,
        startedAt: Date,
        status: SessionStatus = .inProgress,
        exercises: [ExerciseSnapshot] = []
    ) {
        self.id = id
        self.programDayID = programDayID
        self.programDayName = programDayName
        self.startedAt = startedAt
        self.status = status
        self.exercises = exercises
    }
}

/// The next planned day, sent preemptively whenever the iPhone computes its
/// Home (ARCHITECTURE §9 "Iniciar pelo relógio"), so the Watch Home can show and
/// start the next workout even while the iPhone is off. Nothing has been
/// performed yet, so every `exercises[*].sets` is expected to be empty.
public struct PlanSnapshot: Codable, Sendable, Hashable {
    public let programDayID: UUID
    public let programDayName: String
    public let exercises: [ExerciseSnapshot]

    public init(
        programDayID: UUID,
        programDayName: String,
        exercises: [ExerciseSnapshot] = []
    ) {
        self.programDayID = programDayID
        self.programDayName = programDayName
        self.exercises = exercises
    }
}

/// Payload of `WCSession.updateApplicationContext` (iPhone → Watch), ARCHITECTURE §9.
/// Only the latest value matters: it fully replaces whatever the Watch had.
///
/// `schemaVersion` exists since M0 (AR-3) so a Watch app older than the iPhone
/// app can refuse a payload it does not understand and ask the user to update
/// the iPhone app, instead of misreading it. Decode with
/// `SyncCodec.decodeSnapshot`, which checks the version before the rest.
public struct ActiveSessionSnapshot: Codable, Sendable, Hashable {
    public let schemaVersion: Int
    public let generatedAt: Date
    /// `nil` when no session is in progress (SPEC RF-02: at most one).
    public let activeSession: SessionSnapshot?
    /// `nil` until the iPhone has computed its Home at least once.
    public let nextPlan: PlanSnapshot?

    public init(
        schemaVersion: Int = SyncSchema.currentVersion,
        generatedAt: Date,
        activeSession: SessionSnapshot? = nil,
        nextPlan: PlanSnapshot? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.activeSession = activeSession
        self.nextPlan = nextPlan
    }
}
