import Foundation
import TrainerCore

/// Escrita de programas (ARCHITECTURE §3: catálogo/programa só via `*Repository`, AGENTS R4).
/// Implementação: `ProgramRepository` (Persistence/Repositories/ProgramRepository.swift, T2.6).
/// Leituras devolvem DTOs de `TrainerCore`; nenhum `@Model` sai daqui.
@MainActor
protocol ProgramRepositoring: AnyObject {
    /// Todos os programas (ativo primeiro, depois por nome).
    func allPrograms() throws -> [ProgramTemplate]
    func program(id: UUID) throws -> ProgramTemplate?

    /// Torna `id` o único programa ativo (a rotação recomeça em D1 pelo S2).
    func activate(programID: UUID) throws
    func rename(programID: UUID, to name: String) throws
    /// Troca o objetivo. Com `applyDefaults`, reescreve faixa de reps, RIR e descanso de todos os
    /// exercícios conforme `ProgramGoal.defaults` (composto vs. isolado pelo padrão de movimento).
    /// Carregadas e isometrias de pescoço (passos/segundos no campo de reps) só recebem o RIR.
    func setGoal(programID: UUID, goal: ProgramGoal, applyDefaults: Bool) throws
    /// Cópia editável com novos UUIDs (programa, dias, alvos); devolve o id da cópia (inativa).
    func duplicate(programID: UUID, name: String, now: Date) throws -> UUID
    /// Apaga um programa inativo. Lança `ProgramRepositoryError.cannotDeleteActive` para o ativo.
    func delete(programID: UUID) throws

    /// Adiciona um exercício ao fim do dia com os padrões do objetivo; devolve o id do alvo.
    /// Carregadas começam em 20–40 passos e isometrias de pescoço em 10–20 s.
    /// Lança `ProgramRepositoryError.tooManyExercises` acima de `maxExercisesPerDay` (RF-33).
    func addExercise(exerciseID: UUID, toDay dayID: UUID) throws -> UUID
    /// Remove um alvo. Lança `ProgramRepositoryError.tooFewExercises` abaixo de `minExercisesPerDay`.
    func removeTarget(id: UUID) throws
    /// Move um alvo para `newIndex` (0-based) dentro do dia e renumera `order` de 0 a n-1.
    func moveTarget(id: UUID, toIndex newIndex: Int) throws
    /// Troca o exercício de um alvo, mantendo séries/faixa/RIR/descanso (RF-34, na edição).
    func replaceExercise(targetID: UUID, with exerciseID: UUID) throws
    /// Atualiza parâmetros do alvo. Valida: sets 1…10, 1 ≤ repMin < repMax ≤ 50, RIR 0…5,
    /// descanso 15…600 s, startingLoad ≥ 0 e múltiplo do incremento (P8) ou `nil`.
    func updateTarget(id: UUID, sets: Int, repMin: Int, repMax: Int, targetRIR: Int, restSeconds: Int, startingLoad: Double?) throws
}

enum ProgramRepositoryError: Error, Equatable {
    case programNotFound(UUID)
    case dayNotFound(UUID)
    case targetNotFound(UUID)
    case exerciseNotFound(UUID)
    case cannotDeleteActive
    case tooManyExercises
    case tooFewExercises
    case invalidParameters(String)
}

/// Limites de exercícios por dia (RF-33). O padrão gerado é 5.
enum ProgramLimits {
    static let minExercisesPerDay = 1
    static let maxExercisesPerDay = 10
    static let defaultExercisesPerDay = 5
}
