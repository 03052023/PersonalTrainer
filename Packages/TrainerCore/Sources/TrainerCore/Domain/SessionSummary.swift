import Foundation

public struct SessionSummary: Codable, Sendable, Hashable {
    public let id: UUID
    public let programDayID: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let status: SessionStatus
    public let primaryMusclesTrained: Set<MuscleGroup>
    public let workingSetCount: Int

    public init(
        id: UUID = UUID(),
        programDayID: UUID,
        startedAt: Date,
        endedAt: Date? = nil,
        status: SessionStatus = .inProgress,
        primaryMusclesTrained: Set<MuscleGroup> = [],
        workingSetCount: Int = 0
    ) {
        self.id = id
        self.programDayID = programDayID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.primaryMusclesTrained = primaryMusclesTrained
        self.workingSetCount = workingSetCount
    }
}
