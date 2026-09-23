import Foundation

/// Resultado de `SeedLoader.loadIfNeeded`. Só contagens: quem chama decide se registra em log
/// ou ignora. `skipped == true` significa que `UserSettingsModel.schemaSeedVersion` já estava
/// em `SeedLoader.currentSeedVersion` e nada foi lido do bundle nem gravado no store.
struct SeedLoadReport: Equatable, Sendable {
    /// Exercícios do seed sem `ExerciseModel` de mesmo `slug`, inseridos via
    /// `ExerciseMapper.model(from:)`.
    let insertedExercises: Int

    /// Exercícios que já existiam e tiveram os campos de catálogo copiados do seed
    /// (`isArchived` e `machineNotes` preservados). Conta todos os existentes, mesmo os
    /// que não mudaram: o loader não compara campo a campo.
    let updatedExercises: Int

    /// Programas inseridos. É 0 sempre que já existia algum `ProgramModel` no store
    /// (edições do usuário prevalecem, ARCHITECTURE §11).
    let insertedPrograms: Int

    /// `true` quando o seed instalado já estava na versão corrente; o store não foi tocado.
    let skipped: Bool

    init(insertedExercises: Int, updatedExercises: Int, insertedPrograms: Int, skipped: Bool) {
        self.insertedExercises = insertedExercises
        self.updatedExercises = updatedExercises
        self.insertedPrograms = insertedPrograms
        self.skipped = skipped
    }
}
