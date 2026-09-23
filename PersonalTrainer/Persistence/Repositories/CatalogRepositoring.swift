import Foundation
import TrainerCore

/// Escrita do catálogo de exercícios (T2.5, AGENTS R4). Implementação: `CatalogRepository`.
@MainActor
protocol CatalogRepositoring: AnyObject {
    /// Catálogo ordenado por nome (pt-BR). Arquivados só com `includeArchived`.
    func allExercises(includeArchived: Bool) throws -> [ExerciseDefinition]
    func exercise(id: UUID) throws -> ExerciseDefinition?
    /// Cria exercício do usuário (`isCustom = true`, slug gerado e único). Devolve o id.
    func createExercise(_ draft: ExerciseDraft) throws -> UUID
    /// Atualiza nome, músculos, equipamento, unidade, incremento, unilateral, notas da máquina
    /// e padrão de movimento. Vale para exercícios do seed também (o seed preserva `machineNotes`).
    func updateExercise(id: UUID, with draft: ExerciseDraft) throws
    /// Arquiva (nunca apaga: o histórico aponta para ele). Some do seletor e dos substitutos.
    func setArchived(id: UUID, _ archived: Bool) throws
}

/// Campos editáveis de um exercício.
struct ExerciseDraft: Sendable, Hashable {
    var name: String
    var primaryMuscles: [MuscleGroup]
    var secondaryMuscles: [MuscleGroup]
    var equipment: Equipment
    var loadUnit: LoadUnit
    var loadIncrement: Double
    var isUnilateral: Bool
    var machineNotes: String?
    var movementPattern: MovementPattern?

    init(
        name: String = "",
        primaryMuscles: [MuscleGroup] = [],
        secondaryMuscles: [MuscleGroup] = [],
        equipment: Equipment = .machine,
        loadUnit: LoadUnit = .kilograms,
        loadIncrement: Double = 5,
        isUnilateral: Bool = false,
        machineNotes: String? = nil,
        movementPattern: MovementPattern? = nil
    ) {
        self.name = name
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment
        self.loadUnit = loadUnit
        self.loadIncrement = loadIncrement
        self.isUnilateral = isUnilateral
        self.machineNotes = machineNotes
        self.movementPattern = movementPattern
    }

    init(from definition: ExerciseDefinition) {
        self.init(
            name: definition.name,
            primaryMuscles: definition.primaryMuscles,
            secondaryMuscles: definition.secondaryMuscles,
            equipment: definition.equipment,
            loadUnit: definition.loadUnit,
            loadIncrement: definition.loadIncrement,
            isUnilateral: definition.isUnilateral,
            machineNotes: definition.machineNotes,
            movementPattern: definition.movementPattern
        )
    }

    /// Nome não vazio, ≥ 1 grupo primário, incremento finito > 0.
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !primaryMuscles.isEmpty
            && loadIncrement.isFinite && loadIncrement > 0
    }
}

enum CatalogRepositoryError: Error, Equatable {
    case exerciseNotFound(UUID)
    case invalidDraft
}
