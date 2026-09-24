import Foundation
import TrainerCore

/// `WorkoutSessionModel` → `SessionSummary`, a entrada do seletor de treino.
///
/// Funções puras: não tocam `ModelContext`.
enum SessionSummaryMapper {
    /// - `workingSetCount` = séries com `isWarmup == false` (SPEC P1).
    /// - Um grupo entra em `primaryMusclesTrained` se algum exercício o tem como primário
    ///   **e** registrou ≥ 1 série de trabalho (SPEC §7.4). Secundários não contam.
    /// - Os grupos vêm do `ExerciseModel` relacionado; se a relação foi anulada, do
    ///   `catalog` (uuid → definição) passado por quem chama.
    /// - `isDeload` é copiado da sessão (SPEC §7.5): sem ele o `DeloadScheduler` nunca veria a
    ///   semana leve começar nem terminar.
    static func summary(
        from session: WorkoutSessionModel,
        catalog: [UUID: ExerciseDefinition] = [:]
    ) throws -> SessionSummary {
        guard let status = session.status else {
            throw MappingError.invalidRawValue(
                model: "WorkoutSessionModel",
                field: "statusRaw",
                value: session.statusRaw
            )
        }

        var primaryMusclesTrained: Set<MuscleGroup> = []
        var workingSetCount = 0

        for sessionExercise in session.exercises {
            let workingSets = sessionExercise.sets.filter { !$0.isWarmup }.count
            guard workingSets > 0 else {
                continue
            }
            workingSetCount += workingSets

            let primaryMuscles: [MuscleGroup]
            if let exercise = sessionExercise.exercise {
                primaryMuscles = exercise.primaryMuscles
            } else if let definition = catalog[sessionExercise.exerciseUUID] {
                primaryMuscles = definition.primaryMuscles
            } else {
                primaryMuscles = []
            }
            primaryMusclesTrained.formUnion(primaryMuscles)
        }

        return SessionSummary(
            id: session.uuid,
            programDayID: session.programDayUUID,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            status: status,
            primaryMusclesTrained: primaryMusclesTrained,
            workingSetCount: workingSetCount,
            isDeload: session.isDeload
        )
    }
}
