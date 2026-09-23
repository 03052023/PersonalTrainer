import Foundation

/// The single unit of session writing (ARCHITECTURE §7, AR-2).
///
/// Every mutation of a session — from the iPhone UI, the Watch UI or the backup
/// importer — is expressed as one `SessionEvent`, and only the app-side
/// `SessionCoordinator` applies it to persistence. Watch → iPhone events travel
/// one per `WCSession.transferUserInfo` call (ARCHITECTURE §9).
///
/// `id` is the idempotency key: the coordinator ignores an event whose `id` it
/// has already applied, so a retry over WatchConnectivity never duplicates a
/// set (SPEC RF-22). Encode and decode only through `SyncCodec`, so both
/// devices agree on date and key formatting.
public struct SessionEvent: Codable, Sendable, Hashable, Identifiable {
    /// Client-generated idempotency key (AR-4: identifiers are minted by the producer).
    public let id: UUID
    public let sessionID: UUID
    /// When the user action happened, on the producing device's clock. Drives the
    /// last-write-wins rule for `setUpdated` (ARCHITECTURE §7). Sync encodes dates
    /// as ISO 8601 with whole-second precision; do not rely on sub-second ordering.
    public let occurredAt: Date
    public let source: DeviceSource
    public let kind: Kind

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        occurredAt: Date,
        source: DeviceSource,
        kind: Kind
    ) {
        self.id = id
        self.sessionID = sessionID
        self.occurredAt = occurredAt
        self.source = source
        self.kind = kind
    }

    /// What happened. Mirrors the operations the `SessionCoordinator` supports
    /// (ARCHITECTURE §7); one case per user-visible action (SPEC RF-03, RF-10,
    /// RF-11, RF-19, RF-21).
    ///
    /// Wire format (sync schema v1): a JSON object with a `type` discriminator
    /// equal to the case name plus one key per associated value, using the
    /// labels below; `nil` optionals are omitted. Adding a case or renaming a
    /// key changes the format and requires bumping `SyncSchema.currentVersion`,
    /// because an older receiver fails on the unknown `type`.
    public enum Kind: Codable, Sendable, Hashable {
        case sessionStarted(programDayID: UUID)
        case setLogged(
            sessionExerciseID: UUID,
            setID: UUID,
            index: Int,
            load: Double,
            reps: Int,
            rir: Int?,
            isWarmup: Bool
        )
        case setUpdated(setID: UUID, load: Double, reps: Int, rir: Int?)
        case setDeleted(setID: UUID)
        case exerciseSkipped(sessionExerciseID: UUID)
        case exerciseSubstituted(sessionExerciseID: UUID, newExerciseID: UUID)
        case sessionFinished(endedAt: Date)
        case sessionAbandoned(endedAt: Date)
        /// Heart-rate summary produced by the Watch's `HKWorkoutSession` at the end
        /// of a session, for display only (ARCHITECTURE §8, §9).
        ///
        /// SPEC P-6 / P12 / §7.6 and AGENTS R2: this is **transport for a display
        /// value**. Nothing in `TrainerCore/Engine` (`ProgressionRule`,
        /// `WorkoutSelector`, `DeloadPolicy`) may consume it, directly or as a
        /// tie-breaker; the coordinator only stores `avgHeartRate`/`maxHeartRate`/
        /// `hkWorkoutUUID` on the session row. `hkWorkoutUUID` is the lock that
        /// stops the iPhone from writing a second `HKWorkout` (ARCHITECTURE §8).
        case heartRateSummary(averageBPM: Double, maxBPM: Double, hkWorkoutUUID: UUID?)
    }
}

// MARK: - Wire format (sync schema v1)

extension SessionEvent.Kind {
    /// Discriminator written under the `type` key. Part of the sync schema:
    /// never rename an existing value (AGENTS §4, persisted enums).
    private enum TypeTag: String, Codable {
        case sessionStarted
        case setLogged
        case setUpdated
        case setDeleted
        case exerciseSkipped
        case exerciseSubstituted
        case sessionFinished
        case sessionAbandoned
        case heartRateSummary
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case programDayID
        case sessionExerciseID
        case setID
        case index
        case load
        case reps
        case rir
        case isWarmup
        case newExerciseID
        case endedAt
        case averageBPM
        case maxBPM
        case hkWorkoutUUID
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // An unknown tag fails here as a DecodingError, which SyncCodec reports
        // as SyncError.corrupted: a newer Kind must come with a schema bump.
        switch try container.decode(TypeTag.self, forKey: .type) {
        case .sessionStarted:
            self = try .sessionStarted(programDayID: container.decode(UUID.self, forKey: .programDayID))
        case .setLogged:
            self = try .setLogged(
                sessionExerciseID: container.decode(UUID.self, forKey: .sessionExerciseID),
                setID: container.decode(UUID.self, forKey: .setID),
                index: container.decode(Int.self, forKey: .index),
                load: container.decode(Double.self, forKey: .load),
                reps: container.decode(Int.self, forKey: .reps),
                rir: container.decodeIfPresent(Int.self, forKey: .rir),
                isWarmup: container.decode(Bool.self, forKey: .isWarmup)
            )
        case .setUpdated:
            self = try .setUpdated(
                setID: container.decode(UUID.self, forKey: .setID),
                load: container.decode(Double.self, forKey: .load),
                reps: container.decode(Int.self, forKey: .reps),
                rir: container.decodeIfPresent(Int.self, forKey: .rir)
            )
        case .setDeleted:
            self = try .setDeleted(setID: container.decode(UUID.self, forKey: .setID))
        case .exerciseSkipped:
            self = try .exerciseSkipped(
                sessionExerciseID: container.decode(UUID.self, forKey: .sessionExerciseID)
            )
        case .exerciseSubstituted:
            self = try .exerciseSubstituted(
                sessionExerciseID: container.decode(UUID.self, forKey: .sessionExerciseID),
                newExerciseID: container.decode(UUID.self, forKey: .newExerciseID)
            )
        case .sessionFinished:
            self = try .sessionFinished(endedAt: container.decode(Date.self, forKey: .endedAt))
        case .sessionAbandoned:
            self = try .sessionAbandoned(endedAt: container.decode(Date.self, forKey: .endedAt))
        case .heartRateSummary:
            self = try .heartRateSummary(
                averageBPM: container.decode(Double.self, forKey: .averageBPM),
                maxBPM: container.decode(Double.self, forKey: .maxBPM),
                hkWorkoutUUID: container.decodeIfPresent(UUID.self, forKey: .hkWorkoutUUID)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sessionStarted(let programDayID):
            try container.encode(TypeTag.sessionStarted, forKey: .type)
            try container.encode(programDayID, forKey: .programDayID)
        case let .setLogged(sessionExerciseID, setID, index, load, reps, rir, isWarmup):
            try container.encode(TypeTag.setLogged, forKey: .type)
            try container.encode(sessionExerciseID, forKey: .sessionExerciseID)
            try container.encode(setID, forKey: .setID)
            try container.encode(index, forKey: .index)
            try container.encode(load, forKey: .load)
            try container.encode(reps, forKey: .reps)
            try container.encodeIfPresent(rir, forKey: .rir)
            try container.encode(isWarmup, forKey: .isWarmup)
        case let .setUpdated(setID, load, reps, rir):
            try container.encode(TypeTag.setUpdated, forKey: .type)
            try container.encode(setID, forKey: .setID)
            try container.encode(load, forKey: .load)
            try container.encode(reps, forKey: .reps)
            try container.encodeIfPresent(rir, forKey: .rir)
        case .setDeleted(let setID):
            try container.encode(TypeTag.setDeleted, forKey: .type)
            try container.encode(setID, forKey: .setID)
        case .exerciseSkipped(let sessionExerciseID):
            try container.encode(TypeTag.exerciseSkipped, forKey: .type)
            try container.encode(sessionExerciseID, forKey: .sessionExerciseID)
        case let .exerciseSubstituted(sessionExerciseID, newExerciseID):
            try container.encode(TypeTag.exerciseSubstituted, forKey: .type)
            try container.encode(sessionExerciseID, forKey: .sessionExerciseID)
            try container.encode(newExerciseID, forKey: .newExerciseID)
        case .sessionFinished(let endedAt):
            try container.encode(TypeTag.sessionFinished, forKey: .type)
            try container.encode(endedAt, forKey: .endedAt)
        case .sessionAbandoned(let endedAt):
            try container.encode(TypeTag.sessionAbandoned, forKey: .type)
            try container.encode(endedAt, forKey: .endedAt)
        case let .heartRateSummary(averageBPM, maxBPM, hkWorkoutUUID):
            try container.encode(TypeTag.heartRateSummary, forKey: .type)
            try container.encode(averageBPM, forKey: .averageBPM)
            try container.encode(maxBPM, forKey: .maxBPM)
            try container.encodeIfPresent(hkWorkoutUUID, forKey: .hkWorkoutUUID)
        }
    }
}
