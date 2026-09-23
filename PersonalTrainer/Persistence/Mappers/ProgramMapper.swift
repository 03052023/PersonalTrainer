import Foundation
import TrainerCore

/// `ProgramModel` → `ProgramTemplate`. Funções puras: não tocam `ModelContext`.
///
/// As relações to-many do SwiftData não garantem ordem; dias e exercícios saem
/// sempre ordenados por `order`, que é o que o seletor (SPEC S1) espera.
enum ProgramMapper {
    static func template(from model: ProgramModel) throws -> ProgramTemplate {
        let days = try model.days
            .sorted { $0.order < $1.order }
            .map { try dayTemplate(from: $0) }

        return ProgramTemplate(
            id: model.uuid,
            name: model.name,
            days: days,
            isActive: model.isActive
        )
    }

    static func dayTemplate(from model: ProgramDayModel) throws -> ProgramDayTemplate {
        let exercises = try model.exercises
            .sorted { $0.order < $1.order }
            .map { try target(from: $0) }

        return ProgramDayTemplate(
            id: model.uuid,
            name: model.name,
            order: model.order,
            exercises: exercises
        )
    }

    static func target(from model: ProgramExerciseModel) throws -> ExerciseTarget {
        guard let exercise = model.exercise else {
            throw MappingError.missingExercise(programExerciseUUID: model.uuid)
        }

        return ExerciseTarget(
            id: model.uuid,
            exerciseID: exercise.uuid,
            order: model.order,
            sets: model.sets,
            repMin: model.repMin,
            repMax: model.repMax,
            targetRIR: model.targetRIR,
            restSeconds: model.restSeconds,
            startingLoad: model.startingLoad
        )
    }

    // MARK: - ProgramTemplate → ProgramModel (seed, ARCHITECTURE §11)

    /// Monta o grafo `ProgramModel` → `ProgramDayModel` → `ProgramExerciseModel` a partir do
    /// template, com os mesmos ids do template e `createdAt` vindo de quem chama (SPEC P11).
    ///
    /// O mapper não recebe `ModelContext` e não chama `insert`. Quem chama insere a RAIZ
    /// (`context.insert(program)`) e salva: o SwiftData insere os modelos relacionados junto
    /// com o pai. Os `ExerciseModel` do dicionário já devem pertencer ao contexto de destino
    /// (inseridos ou buscados nele), porque a relação `exercise` só liga ao catálogo, nunca
    /// o cria — é assim que o `SeedLoader` o usa.
    ///
    /// - Parameter exercises: catálogo indexado pelo id que `ExerciseTarget.exerciseID` usa.
    /// - Throws: `MappingError.missingExercise(programExerciseUUID:)` com o id do target cujo
    ///   exercício não está no dicionário — o mesmo erro do sentido inverso quando a relação
    ///   está anulada. Em uso normal não acontece: `SeedValidator` garante que todo target
    ///   aponta para um exercício do catálogo.
    static func model(
        from template: ProgramTemplate,
        exercises: [UUID: ExerciseModel],
        createdAt: Date
    ) throws -> ProgramModel {
        let days = try template.days.map { day in
            try dayModel(from: day, exercises: exercises)
        }

        return ProgramModel(
            uuid: template.id,
            name: template.name,
            isActive: template.isActive,
            createdAt: createdAt,
            days: days
        )
    }

    static func dayModel(
        from template: ProgramDayTemplate,
        exercises: [UUID: ExerciseModel]
    ) throws -> ProgramDayModel {
        let programExercises = try template.exercises.map { exerciseTarget in
            try programExerciseModel(from: exerciseTarget, exercises: exercises)
        }

        return ProgramDayModel(
            uuid: template.id,
            name: template.name,
            order: template.order,
            exercises: programExercises
        )
    }

    static func programExerciseModel(
        from target: ExerciseTarget,
        exercises: [UUID: ExerciseModel]
    ) throws -> ProgramExerciseModel {
        guard let exercise = exercises[target.exerciseID] else {
            throw MappingError.missingExercise(programExerciseUUID: target.id)
        }

        return ProgramExerciseModel(
            uuid: target.id,
            order: target.order,
            sets: target.sets,
            repMin: target.repMin,
            repMax: target.repMax,
            targetRIR: target.targetRIR,
            restSeconds: target.restSeconds,
            startingLoad: target.startingLoad,
            exercise: exercise
        )
    }
}
