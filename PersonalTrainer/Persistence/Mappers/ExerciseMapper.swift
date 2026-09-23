import Foundation
import TrainerCore

/// `ExerciseModel` ⇄ `ExerciseDefinition`. Funções puras: não tocam `ModelContext`.
enum ExerciseMapper {
    static func definition(from model: ExerciseModel) throws -> ExerciseDefinition {
        guard let equipment = model.equipment else {
            throw MappingError.invalidRawValue(
                model: "ExerciseModel",
                field: "equipmentRaw",
                value: model.equipmentRaw
            )
        }
        guard let loadUnit = model.loadUnit else {
            throw MappingError.invalidRawValue(
                model: "ExerciseModel",
                field: "loadUnitRaw",
                value: model.loadUnitRaw
            )
        }

        return ExerciseDefinition(
            id: model.uuid,
            slug: model.slug,
            name: model.name,
            primaryMuscles: model.primaryMuscles,
            secondaryMuscles: model.secondaryMuscles,
            equipment: equipment,
            loadUnit: loadUnit,
            loadIncrement: model.loadIncrement,
            isUnilateral: model.isUnilateral,
            machineNotes: model.machineNotes
        )
    }

    /// Para o seed (ARCHITECTURE §11). Devolve um modelo ainda não inserido; quem chama
    /// decide o `ModelContext`. `isArchived` nasce `false`: o seed nunca arquiva.
    static func model(from definition: ExerciseDefinition) -> ExerciseModel {
        ExerciseModel(
            uuid: definition.id,
            slug: definition.slug,
            name: definition.name,
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups(definition.primaryMuscles),
            secondaryMusclesRaw: SchemaV1.encodeMuscleGroups(definition.secondaryMuscles),
            equipmentRaw: definition.equipment.rawValue,
            loadUnitRaw: definition.loadUnit.rawValue,
            loadIncrement: definition.loadIncrement,
            isUnilateral: definition.isUnilateral,
            machineNotes: definition.machineNotes,
            isArchived: false
        )
    }
}
