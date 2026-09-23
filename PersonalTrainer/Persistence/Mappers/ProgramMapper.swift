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
}
