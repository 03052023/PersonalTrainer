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

    // MARK: - Dias do programa (T2.22, RF-36)

    /// Acrescenta um dia ao fim do programa; devolve o id do dia novo. Com `name` `nil`, usa
    /// "Dia " + a próxima letra livre (A, B, C…, olhando os nomes já usados no programa); com
    /// `name` não vazio, usa o texto informado (aparado). Lança
    /// `ProgramRepositoryError.tooManyDays` acima de `ProgramLimits.maxDays` (RF-36).
    func addDay(programID: UUID, name: String?) throws -> UUID
    /// Remove um dia; os alvos saem em cascata. O histórico é por sessão (snapshot de
    /// `programDayName`), então sessões antigas continuam mostrando o nome gravado na hora (S2
    /// recomeça em D1 sozinho quando o dia da última sessão some do programa). Lança
    /// `ProgramRepositoryError.tooFewDays` abaixo de `ProgramLimits.minDays`.
    func removeDay(id: UUID) throws
    /// Renomeia um dia. Nome vazio (só espaços) lança `invalidParameters`.
    func renameDay(id: UUID, to name: String) throws
    /// Move um dia para `newIndex` (0-based) dentro do programa e renumera `order` de 0 a n-1.
    func moveDay(id: UUID, toIndex newIndex: Int) throws
}

/// Requisito novo em protocolo existente (AGENTS §2, onda 3): implementação padrão para
/// conformâncias de outras tarefas que ainda não conhecem dias (ex.: doubles de teste de outra
/// feature). `ProgramRepository` e o double de preview sobrescrevem os quatro métodos; nenhum
/// caminho de produção passa por aqui.
extension ProgramRepositoring {
    func addDay(programID: UUID, name: String?) throws -> UUID {
        throw ProgramRepositoryError.invalidParameters("Este repositório não gerencia dias do programa.")
    }

    func removeDay(id: UUID) throws {
        throw ProgramRepositoryError.invalidParameters("Este repositório não gerencia dias do programa.")
    }

    func renameDay(id: UUID, to name: String) throws {
        throw ProgramRepositoryError.invalidParameters("Este repositório não gerencia dias do programa.")
    }

    func moveDay(id: UUID, toIndex newIndex: Int) throws {
        throw ProgramRepositoryError.invalidParameters("Este repositório não gerencia dias do programa.")
    }
}

enum ProgramRepositoryError: Error, Equatable {
    case programNotFound(UUID)
    case dayNotFound(UUID)
    case targetNotFound(UUID)
    case exerciseNotFound(UUID)
    case cannotDeleteActive
    case tooManyExercises
    case tooFewExercises
    /// RF-36: acima de `ProgramLimits.maxDays`.
    case tooManyDays
    /// RF-36: abaixo de `ProgramLimits.minDays`.
    case tooFewDays
    case invalidParameters(String)
}

/// Limites de exercícios por dia (RF-33). O padrão gerado é 5.
enum ProgramLimits {
    static let minExercisesPerDay = 1
    static let maxExercisesPerDay = 10
    static let defaultExercisesPerDay = 5
    /// Limites de dias por programa (RF-36).
    static let minDays = 1
    static let maxDays = 7
}
