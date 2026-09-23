import Foundation
import Observation
import os
import TrainerCore

/// Estado da raiz da aba Programa (T2.6): lista de programas com ativar, duplicar e apagar.
///
/// Toda escrita passa pelo `ProgramRepositoring` (AGENTS R4); a view nunca toca o `ModelContext`.
/// O relógio chega por `now` (SPEC P11) e só é usado para carimbar a cópia em `duplicate`.
@Observable
@MainActor
final class ProgramListViewModel {
    /// Programas na ordem do repositório (ativo primeiro, depois por nome).
    private(set) var programs: [ProgramTemplate] = []
    /// Verdadeiro enquanto a última leitura falhou: "sem programas" e "não carregou" são estados
    /// distintos, e fechar o alerta não pode transformar um no outro.
    private(set) var didFailToLoad = false
    /// Verdadeiro depois da primeira leitura: antes dela a tela mostra "carregando", não "vazio".
    private(set) var hasLoaded = false
    /// Mensagem pt-BR para o `.alert` da view; a view zera ao fechar.
    var errorMessage: String?
    /// Programa aguardando confirmação de exclusão (diálogo da view).
    var pendingDeletion: ProgramTemplate?

    private let repository: any ProgramRepositoring
    private let now: () -> Date

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "ProgramList"
    )

    init(programs: any ProgramRepositoring, now: @escaping () -> Date) {
        self.repository = programs
        self.now = now
    }

    /// Ponte para `.alert(isPresented:)`: atribuir `false` limpa a mensagem.
    var isPresentingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
            }
        }
    }

    /// Ponte para o diálogo de exclusão: atribuir `false` descarta o pedido.
    var isConfirmingDeletion: Bool {
        get { pendingDeletion != nil }
        set {
            if !newValue {
                pendingDeletion = nil
            }
        }
    }

    func refresh() {
        defer { hasLoaded = true }
        do {
            programs = try repository.allPrograms()
            didFailToLoad = false
        } catch {
            programs = []
            didFailToLoad = true
            report(error, fallback: "Não foi possível carregar os programas.")
        }
    }

    /// Torna o programa o único ativo; a rotação recomeça em D1 (SPEC S2).
    func activate(_ programID: UUID) {
        do {
            try repository.activate(programID: programID)
        } catch {
            report(error, fallback: "Não foi possível ativar o programa.")
        }
        refresh()
    }

    /// Cria uma cópia inativa e editável. Devolve o id da cópia, ou `nil` em falha.
    @discardableResult
    func duplicate(_ programID: UUID) -> UUID? {
        guard let original = programs.first(where: { $0.id == programID }) else {
            errorMessage = "Programa não encontrado."
            return nil
        }
        var copyID: UUID?
        do {
            copyID = try repository.duplicate(
                programID: programID,
                name: Self.copyName(for: original.name),
                now: now()
            )
        } catch {
            report(error, fallback: "Não foi possível duplicar o programa.")
        }
        refresh()
        return copyID
    }

    /// Pede confirmação antes de apagar. O ativo nunca é apagado (a view nem oferece a ação).
    func requestDeletion(of programID: UUID) {
        guard let program = programs.first(where: { $0.id == programID }) else { return }
        guard !program.isActive else {
            errorMessage = Self.message(for: ProgramRepositoryError.cannotDeleteActive, fallback: "")
            return
        }
        pendingDeletion = program
    }

    /// Apaga o programa pendente (depois da confirmação).
    func confirmDeletion() {
        guard let program = pendingDeletion else { return }
        pendingDeletion = nil
        do {
            try repository.delete(programID: program.id)
        } catch {
            report(error, fallback: "Não foi possível apagar o programa.")
        }
        refresh()
    }

    // MARK: - Texto (pt-BR)

    /// "Programa ABC" → "Programa ABC (cópia)".
    static func copyName(for name: String) -> String {
        "\(name) (cópia)"
    }

    /// "1 dia", "3 dias".
    static func dayCountText(_ count: Int) -> String {
        count == 1 ? "1 dia" : "\(count) dias"
    }

    private func report(_ error: any Error, fallback: String) {
        Self.logger.error("Program list operation failed: \(String(describing: error), privacy: .public)")
        errorMessage = Self.message(for: error, fallback: fallback)
    }

    static func message(for error: any Error, fallback: String) -> String {
        guard let repositoryError = error as? ProgramRepositoryError else {
            return fallback
        }
        switch repositoryError {
        case .programNotFound:
            return "Programa não encontrado."
        case .cannotDeleteActive:
            return "O programa ativo não pode ser apagado. Ative outro programa antes."
        case .dayNotFound, .targetNotFound, .exerciseNotFound, .tooManyExercises,
             .tooFewExercises, .invalidParameters:
            return fallback
        }
    }
}
