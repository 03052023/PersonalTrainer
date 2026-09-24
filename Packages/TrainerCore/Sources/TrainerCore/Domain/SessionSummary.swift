import Foundation

public struct SessionSummary: Codable, Sendable, Hashable {
    public let id: UUID
    public let programDayID: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let status: SessionStatus
    public let primaryMusclesTrained: Set<MuscleGroup>
    public let workingSetCount: Int
    /// The session was run with deload prescriptions (SPEC §7.5). `DeloadPolicy`
    /// counts these to know when one pass of the rotation at reduced load is over.
    public let isDeload: Bool

    public init(
        id: UUID = UUID(),
        programDayID: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        status: SessionStatus = .inProgress,
        primaryMusclesTrained: Set<MuscleGroup> = [],
        workingSetCount: Int = 0,
        isDeload: Bool = false
    ) {
        self.id = id
        self.programDayID = programDayID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.primaryMusclesTrained = primaryMusclesTrained
        self.workingSetCount = workingSetCount
        self.isDeload = isDeload
    }

    private enum CodingKeys: String, CodingKey {
        case id, programDayID, startedAt, endedAt, status, primaryMusclesTrained, workingSetCount
        case isDeload
    }

    /// Tolerant decoding: summaries encoded before M4 have no `isDeload`, and every
    /// session back then was a normal one.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.programDayID = try container.decode(UUID.self, forKey: .programDayID)
        self.startedAt = try container.decode(Date.self, forKey: .startedAt)
        self.endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        self.status = try container.decode(SessionStatus.self, forKey: .status)
        self.primaryMusclesTrained = try container.decode(Set<MuscleGroup>.self, forKey: .primaryMusclesTrained)
        self.workingSetCount = try container.decode(Int.self, forKey: .workingSetCount)
        self.isDeload = try container.decodeIfPresent(Bool.self, forKey: .isDeload) ?? false
    }
}
