import Foundation
import TrainerCore

/// Plano do próximo treino calculado por `SessionPlanning` (SPEC §7.2/§7.3).
/// DTO puro: nada aqui é persistido. Ao iniciar a sessão, cada `PlannedExercise` vira um
/// `SessionExerciseModel` com a prescrição copiada como snapshot (ARCHITECTURE §5, AR-10).
struct SessionPlan: Sendable, Hashable {
    let programID: UUID
    let programName: String
    let programDayID: UUID
    let programDayName: String
    /// Ordenado por `target.order`.
    let exercises: [PlannedExercise]
    let generatedAt: Date
}

/// Um exercício do plano com a prescrição já calculada pelo motor.
struct PlannedExercise: Sendable, Hashable, Identifiable {
    /// Gerado pelo planejador; torna-se `SessionExerciseModel.uuid` quando a sessão é iniciada,
    /// para que a UI possa referenciar o exercício antes e depois do início com o mesmo id.
    let id: UUID
    let exercise: ExerciseDefinition
    let target: ExerciseTarget
    let prescription: ExercisePrescription
}
