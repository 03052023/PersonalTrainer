import Foundation

public struct ExerciseDefinition: Codable, Sendable, Hashable {
    public let id: UUID
    public let slug: String
    public let name: String
    public let primaryMuscles: [MuscleGroup]
    public let secondaryMuscles: [MuscleGroup]
    public let equipment: Equipment
    public let loadUnit: LoadUnit
    public let loadIncrement: Double
    public let isUnilateral: Bool
    public let machineNotes: String?

    public init(
        id: UUID = UUID(),
        slug: String,
        name: String,
        primaryMuscles: [MuscleGroup],
        secondaryMuscles: [MuscleGroup] = [],
        equipment: Equipment,
        loadUnit: LoadUnit,
        loadIncrement: Double,
        isUnilateral: Bool = false,
        machineNotes: String? = nil
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.loadUnit = loadUnit
        self.loadIncrement = loadIncrement
        self.isUnilateral = isUnilateral
        self.machineNotes = machineNotes
    }
}
