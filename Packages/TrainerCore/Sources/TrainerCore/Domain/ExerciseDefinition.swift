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
    /// Padrão de movimento para o botão "Trocar" (RF-34). Opcional para ler catálogos v1.
    public let movementPattern: MovementPattern?
    /// `true` para exercícios criados pelo usuário (T2.5); o seed nunca os sobrescreve.
    public let isCustom: Bool

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
        machineNotes: String? = nil,
        movementPattern: MovementPattern? = nil,
        isCustom: Bool = false
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
        self.movementPattern = movementPattern
        self.isCustom = isCustom
    }

    private enum CodingKeys: String, CodingKey {
        case id, slug, name, primaryMuscles, secondaryMuscles, equipment, loadUnit, loadIncrement
        case isUnilateral, machineNotes, movementPattern, isCustom
    }

    /// Decodificação tolerante: catálogos v1 não têm `movementPattern` nem `isCustom`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.slug = try container.decode(String.self, forKey: .slug)
        self.name = try container.decode(String.self, forKey: .name)
        self.primaryMuscles = try container.decode([MuscleGroup].self, forKey: .primaryMuscles)
        self.secondaryMuscles = try container.decodeIfPresent([MuscleGroup].self, forKey: .secondaryMuscles) ?? []
        self.equipment = try container.decode(Equipment.self, forKey: .equipment)
        self.loadUnit = try container.decode(LoadUnit.self, forKey: .loadUnit)
        self.loadIncrement = try container.decode(Double.self, forKey: .loadIncrement)
        self.isUnilateral = try container.decodeIfPresent(Bool.self, forKey: .isUnilateral) ?? false
        self.machineNotes = try container.decodeIfPresent(String.self, forKey: .machineNotes)
        self.movementPattern = try container.decodeIfPresent(MovementPattern.self, forKey: .movementPattern)
        self.isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }
}
