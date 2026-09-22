import Foundation

public struct ExerciseHistoryEntry: Codable, Sendable, Hashable {
    public let sessionID: UUID
    public let date: Date
    public let sets: [SetResult]
    public let wasDeload: Bool

    public init(
        sessionID: UUID,
        date: Date,
        sets: [SetResult] = [],
        wasDeload: Bool = false
    ) {
        self.sessionID = sessionID
        self.date = date
        self.sets = sets
        self.wasDeload = wasDeload
    }
}
