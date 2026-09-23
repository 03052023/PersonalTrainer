import Foundation
import Observation

/// Estado da tela inicial (SPEC F1, RF-01, RF-02; TASKS T1.4).
///
/// Lê o próximo plano pelo `SessionPlanning` e a sessão em andamento pelo `SessionCoordinating`;
/// nunca toca o `ModelContext` (AGENTS R4). O relógio chega por `now` (SPEC P11): nada aqui lê a
/// data do sistema. Quem liga Home → Sessão é o `RootView`, pelo id devolvido por `startSession()`.
@Observable
@MainActor
final class HomeViewModel {
    /// Próximo treino calculado; `nil` quando não há programa ativo ou a última leitura falhou.
    private(set) var plan: SessionPlan?
    /// `uuid` da sessão `inProgress`, se houver (SPEC S3): o botão vira "Retomar treino".
    private(set) var activeSessionID: UUID?
    /// Mensagem pt-BR para o `.alert` da view; a view zera ao fechar o alerta.
    var errorMessage: String?
    /// Verdadeiro enquanto a última leitura (`refresh()`) tiver falhado. Separado de
    /// `errorMessage` porque fechar o alerta zera a mensagem, e sem isto a tela passaria a
    /// dizer "Nenhum programa ativo" para uma falha de leitura (o programa pode existir).
    private(set) var didFailToLoad = false

    private let planner: any SessionPlanning
    private let coordinator: any SessionCoordinating
    private let now: () -> Date

    init(
        planner: any SessionPlanning,
        coordinator: any SessionCoordinating,
        now: @escaping () -> Date
    ) {
        self.planner = planner
        self.coordinator = coordinator
        self.now = now
    }

    /// Ponte para `.alert(isPresented:)`: verdadeiro enquanto há mensagem; atribuir `false` limpa.
    var isPresentingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
            }
        }
    }

    /// Relê sessão ativa e próximo plano. Em falha, o plano é descartado (nunca iniciar a partir
    /// de um plano possivelmente desatualizado) e a mensagem vai para `errorMessage`.
    func refresh() {
        activeSessionID = coordinator.activeSession?.uuid
        do {
            plan = try planner.nextPlan(now: now())
            didFailToLoad = false
        } catch {
            plan = nil
            didFailToLoad = true
            errorMessage = Self.message(for: error, fallback: "Não foi possível carregar o próximo treino.")
        }
    }

    /// Retoma a sessão ativa (RF-02: só existe uma) ou inicia uma nova a partir do plano.
    /// Devolve o `uuid` da sessão a abrir, ou `nil` se algo impediu (mensagem em `errorMessage`).
    func startSession() -> UUID? {
        if let activeSessionID {
            return activeSessionID
        }
        guard let plan else {
            errorMessage = "Nenhum programa ativo para iniciar."
            return nil
        }
        do {
            let sessionID = try planner.startSession(from: plan, now: now())
            activeSessionID = sessionID
            return sessionID
        } catch {
            // Se outra parte do app (ou o relógio, em M3) já abriu uma sessão, a Home passa a
            // oferecer "Retomar" em vez de insistir em iniciar.
            if let inProgressID = Self.inProgressSessionID(from: error) {
                activeSessionID = inProgressID
            }
            errorMessage = Self.message(for: error, fallback: "Não foi possível iniciar o treino.")
            return nil
        }
    }

    // MARK: - Mensagens pt-BR

    private static func message(for error: any Error, fallback: String) -> String {
        if let planningError = error as? PlanningError {
            switch planningError {
            case .noActiveProgram:
                return "Nenhum programa ativo. Ative um programa para ver o próximo treino."
            case .programHasNoDays:
                return "O programa ativo não tem dias de treino."
            case .sessionAlreadyInProgress:
                return "Já existe um treino em andamento. Toque em Retomar treino."
            case .exerciseNotFound:
                return "Um exercício do programa não foi encontrado no catálogo."
            }
        }
        if let coordinatorError = error as? SessionCoordinatorError {
            switch coordinatorError {
            case .sessionAlreadyInProgress:
                return "Já existe um treino em andamento. Toque em Retomar treino."
            default:
                return fallback
            }
        }
        return fallback
    }

    private static func inProgressSessionID(from error: any Error) -> UUID? {
        if let planningError = error as? PlanningError, case .sessionAlreadyInProgress(let id) = planningError {
            return id
        }
        if let coordinatorError = error as? SessionCoordinatorError, case .sessionAlreadyInProgress(let id) = coordinatorError {
            return id
        }
        return nil
    }
}
