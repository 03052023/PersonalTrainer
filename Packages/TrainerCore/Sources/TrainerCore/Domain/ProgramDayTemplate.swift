import Foundation

public struct ProgramDayTemplate: Codable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let order: Int
    public let exercises: [ExerciseTarget]

    public init(
        id: UUID = UUID(),
        name: String,
        order: Int,
        exercises: [ExerciseTarget] = []
    ) {
        self.id = id
        self.name = name
        self.order = order
        self.exercises = exercises
    }
}
