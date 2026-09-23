import Foundation

/// Falhas ao converter `@Model` em tipos de `TrainerCore`.
///
/// Os raw values são gravados só pelo app, então um valor desconhecido indica store
/// corrompido ou downgrade de versão; os mappers falham explicitamente em vez de
/// inventar um padrão (AGENTS §4, "Erros").
enum MappingError: Error, Equatable {
    /// Um campo `*Raw` não corresponde a nenhum case conhecido do enum de domínio.
    case invalidRawValue(model: String, field: String, value: String)

    /// `ProgramExerciseModel.exercise` está `nil` (relação anulada); o `ExerciseTarget`
    /// exige `exerciseID` e não há cópia do UUID nesse modelo (ARCHITECTURE §5).
    case missingExercise(programExerciseUUID: UUID)
}
