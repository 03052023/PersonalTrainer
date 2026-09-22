import Foundation

public struct ExerciseTarget: Codable, Sendable, Hashable {
    public let id: UUID
    public let exerciseID: UUID
    public let order: Int
    public let sets: Int
    public let repMin: Int
    public let repMax: Int
    public let targetRIR: Int
    public let restSeconds: Int
    public let startingLoad: Double?

    public init(
        id: UUID = UUID(),
        exerciseID: UUID,
        order: Int,
        sets: Int = 3,
        repMin: Int = 8,
        repMax: Int = 12,
        targetRIR: Int = 2,
        restSeconds: Int = 120,
        startingLoad: Double? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.order = order
        self.sets = sets
        self.repMin = repMin
        self.repMax = repMax
        self.targetRIR = targetRIR
        self.restSeconds = restSeconds
        self.startingLoad = startingLoad
    }
}
