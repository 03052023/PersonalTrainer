import Foundation
import TrainerCore

/// `ExerciseModel` ⇄ `ExerciseDefinition`. Funções puras: não tocam `ModelContext`.
enum ExerciseMapper {
    /// - Throws: `MappingError.invalidRawValue` para `equipmentRaw`/`loadUnitRaw` desconhecidos:
    ///   sem eles o motor não calcula carga (SPEC P8).
    ///
    /// `movementPatternRaw` desconhecido NÃO é erro: vira `nil`. O padrão é opcional no domínio
    /// e só alimenta a sugestão de substitutos (RF-34); um case gravado por versão futura do app
    /// não pode impedir o catálogo nem o planejamento de abrir.
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
            machineNotes: model.machineNotes,
            movementPattern: model.movementPattern,
            isCustom: model.isCustom
        )
    }

    /// Devolve um modelo ainda não inserido; quem chama decide o `ModelContext`. `isArchived`
    /// nasce `false`; `movementPatternRaw` e `isCustom` vêm da definição (o seed grava
    /// `isCustom = false`; a criação de exercício pelo usuário, T2.5, grava `true`).
    ///
    /// Só para INSERIR um exercício que ainda não existe. `ExerciseModel` tem `uuid` e `slug`
    /// `.unique`, e `context.insert` de uma duplicata faz upsert silencioso (ARCHITECTURE §15),
    /// o que zeraria `isArchived` e sobrescreveria `machineNotes` editados pelo usuário. Para
    /// atualizar um exercício existente, buscar por `slug` e copiar campo a campo.
    static func model(from definition: ExerciseDefinition) -> ExerciseModel {
        ExerciseModel(
            uuid: definition.id,
            slug: definition.slug,
            name: definition.name,
            primaryMusclesRaw: CurrentSchema.encodeMuscleGroups(definition.primaryMuscles),
            secondaryMusclesRaw: CurrentSchema.encodeMuscleGroups(definition.secondaryMuscles),
            equipmentRaw: definition.equipment.rawValue,
            loadUnitRaw: definition.loadUnit.rawValue,
            loadIncrement: definition.loadIncrement,
            isUnilateral: definition.isUnilateral,
            machineNotes: definition.machineNotes,
            isArchived: false,
            movementPatternRaw: definition.movementPattern?.rawValue,
            isCustom: definition.isCustom
        )
    }
}
