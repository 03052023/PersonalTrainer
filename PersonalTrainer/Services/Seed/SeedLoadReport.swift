import Foundation

/// Resultado de `SeedLoader.loadIfNeeded`. Só contagens: quem chama decide se registra em log
/// ou ignora. `skipped == true` significa que `UserSettingsModel.schemaSeedVersion` já estava
/// em `SeedLoader.currentSeedVersion` e nada foi lido do bundle nem gravado no store.
struct SeedLoadReport: Equatable, Sendable {
    /// Exercícios do seed sem `ExerciseModel` de mesmo `slug` (nem de mesmo `uuid`),
    /// inseridos via `ExerciseMapper.model(from:)`.
    let insertedExercises: Int

    /// Exercícios do catálogo que já existiam e tiveram os campos de catálogo copiados do
    /// seed (`isArchived` e `machineNotes` preservados). Conta todos os existentes, mesmo os
    /// que não mudaram: o loader não compara campo a campo. Não conta exercícios criados pelo
    /// usuário (`isCustom == true`) que colidam com um slug do seed: esses nunca são tocados.
    let updatedExercises: Int

    /// Programas do seed inseridos (os de `uuid` ainda ausente do store). Em primeiro launch
    /// são todos os do seed; depois, só os que uma versão nova do seed acrescentou.
    let insertedPrograms: Int

    /// `true` quando o seed instalado já estava na versão corrente; o store não foi tocado.
    let skipped: Bool

    /// Programas do seed cujo `uuid` já existia no store e por isso não foram inseridos nem
    /// alterados (edições do usuário prevalecem, ARCHITECTURE §11).
    let skippedPrograms: Int

    init(
        insertedExercises: Int,
        updatedExercises: Int,
        insertedPrograms: Int,
        skipped: Bool,
        skippedPrograms: Int = 0
    ) {
        self.insertedExercises = insertedExercises
        self.updatedExercises = updatedExercises
        self.insertedPrograms = insertedPrograms
        self.skipped = skipped
        self.skippedPrograms = skippedPrograms
    }
}
