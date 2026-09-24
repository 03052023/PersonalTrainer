import Foundation
import Observation
import os
import TrainerCore

/// Estado da tela inicial (SPEC F1, RF-01, RF-02, S4; TASKS T1.4, T2.14).
///
/// Lê o próximo plano, os dias e o objetivo do programa ativo pelo `SessionPlanning` e a sessão
/// em andamento pelo `SessionCoordinating`; nunca toca o `ModelContext` (AGENTS R4). O relógio
/// chega por `now` (SPEC P11): nada aqui lê a data do sistema. Quem liga Home → Sessão é o
/// `RootView`, pelo id devolvido por `startSession()`.
@Observable
@MainActor
final class HomeViewModel {
    /// Treino exibido: o próximo da rotação (S1–S2) ou o dia escolhido à mão (S4). `nil` quando
    /// não há programa ativo ou a última leitura falhou.
    private(set) var plan: SessionPlan?
    /// `uuid` da sessão `inProgress`, se houver (SPEC S3): o botão vira "Retomar".
    private(set) var activeSessionID: UUID?
    /// Dias do programa ativo, ordenados por `order`, para o menu do nome do dia (T2.14).
    private(set) var days: [ProgramDayTemplate] = []
    /// Objetivo do programa ativo (SPEC §7.9) para o selo do card; `nil` sem programa ativo.
    private(set) var goal: ProgramGoal?
    /// Dia escolhido à mão (SPEC S4); `nil` = automático (próximo da rotação). Vale até o treino
    /// ser iniciado ou retomado, até "Automático" ou até o dia sumir do programa. Sobrevive a
    /// `refresh()` de propósito: trocar de aba chama `onAppear` e não pode desfazer a escolha
    /// sem o usuário perceber (ele iniciaria o dia errado).
    private(set) var selectedDayID: UUID?
    /// Mensagem pt-BR para o `.alert` da view; a view zera ao fechar o alerta.
    var errorMessage: String?
    /// Verdadeiro enquanto a última leitura (`refresh()`) tiver falhado. Separado de
    /// `errorMessage` porque fechar o alerta zera a mensagem, e sem isto a tela passaria a
    /// dizer "Nenhum programa ativo" para uma falha de leitura (o programa pode existir).
    private(set) var didFailToLoad = false

    private let planner: any SessionPlanning
    private let coordinator: any SessionCoordinating
    private let now: () -> Date

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "Home"
    )

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

    /// Relê sessão ativa, dias, objetivo e o plano (o do dia escolhido, se houver; senão o da
    /// rotação). Em falha do plano, ele é descartado (nunca iniciar a partir de um plano
    /// possivelmente desatualizado) e a mensagem vai para `errorMessage`.
    func refresh() {
        activeSessionID = coordinator.activeSession?.uuid
        if activeSessionID != nil {
            // Com treino em andamento a escolha manual não tem mais efeito: o botão só retoma, e
            // ao terminar a rotação já segue do dia registrado (S4).
            selectedDayID = nil
        }
        loadProgramInfo()
        do {
            plan = try currentPlan(now: now())
            didFailToLoad = false
        } catch {
            plan = nil
            didFailToLoad = true
            errorMessage = Self.message(for: error, fallback: "Não foi possível carregar o próximo treino.")
        }
    }

    /// Mostra o plano de um dia escolhido à mão (SPEC S4) e o guarda como escolha até iniciar.
    /// A rotação segue a partir desse dia porque a sessão registrada nele passa a ser a
    /// referência de S2; nada é gravado aqui. Em falha, o plano atual é mantido.
    func selectDay(_ dayID: UUID) {
        guard activeSessionID == nil else {
            errorMessage = "Já existe uma sessão em andamento. Toque em Retomar."
            return
        }
        do {
            guard let manualPlan = try planner.plan(forDayID: dayID, now: now()) else {
                errorMessage = "Este dia não existe mais no programa ativo."
                return
            }
            selectedDayID = dayID
            plan = manualPlan
            didFailToLoad = false
        } catch {
            errorMessage = Self.message(for: error, fallback: "Não foi possível carregar o dia escolhido.")
        }
    }

    /// Volta ao próximo dia da rotação (S2), descartando a escolha manual.
    func selectAutomaticDay() {
        selectedDayID = nil
        refresh()
    }

    /// Chamar depois de cada resposta ao diálogo (SPEC §7.11). "Aplicar" (C2) muda o programa ou
    /// pede a semana leve, e "Seguir normal" (C1) a desfaz: nos dois casos o plano na tela ficou
    /// velho e é relido. As outras respostas não mudam o plano.
    func didHandleCoachAction(_ action: CoachAction) {
        switch action {
        case .apply, .keepNormal:
            refresh()
        default:
            break
        }
    }

    /// Retoma a sessão ativa (RF-02: só existe uma) ou inicia uma nova a partir do plano.
    /// Devolve o `uuid` da sessão a abrir, ou `nil` se algo impediu (mensagem em `errorMessage`).
    func startSession() -> UUID? {
        if let activeSessionID {
            selectedDayID = nil
            return activeSessionID
        }
        guard let plan else {
            errorMessage = "Nenhum programa ativo para iniciar."
            return nil
        }
        do {
            let sessionID = try planner.startSession(from: plan, now: now())
            activeSessionID = sessionID
            // A escolha manual foi consumida: ao voltar, a Home mostra a rotação a partir dela (S4).
            selectedDayID = nil
            return sessionID
        } catch {
            // Se outra parte do app (ou o relógio, em M3) já abriu uma sessão, a Home passa a
            // oferecer "Retomar" em vez de insistir em iniciar.
            if let inProgressID = Self.inProgressSessionID(from: error) {
                activeSessionID = inProgressID
                selectedDayID = nil
            }
            errorMessage = Self.message(for: error, fallback: "Não foi possível iniciar o treino.")
            return nil
        }
    }

    // MARK: - Leitura

    /// Dias e objetivo são complementares ao plano: uma falha aqui só esconde o menu de dias e o
    /// selo do objetivo (e fica no log), sem transformar a Home inteira em "não carregou".
    private func loadProgramInfo() {
        do {
            days = try planner.activeProgramDays().sorted { $0.order < $1.order }
        } catch {
            days = []
            Self.logger.error("Falha ao ler os dias do programa ativo: \(String(describing: error), privacy: .public)")
        }
        do {
            goal = try planner.activeProgramGoal()
        } catch {
            goal = nil
            Self.logger.error("Falha ao ler o objetivo do programa ativo: \(String(describing: error), privacy: .public)")
        }
    }

    /// Plano do dia escolhido, se ainda existir no programa ativo; senão, o da rotação.
    private func currentPlan(now date: Date) throws -> SessionPlan? {
        if let selectedDayID {
            if let manualPlan = try planner.plan(forDayID: selectedDayID, now: date) {
                return manualPlan
            }
            // O dia saiu do programa (edição ou troca de programa): volta ao automático.
            self.selectedDayID = nil
        }
        return try planner.nextPlan(now: date)
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
                return "Já existe uma sessão em andamento. Toque em Retomar."
            case .exerciseNotFound:
                return "Um exercício do programa não foi encontrado no catálogo."
            }
        }
        if let coordinatorError = error as? SessionCoordinatorError {
            switch coordinatorError {
            case .sessionAlreadyInProgress:
                return "Já existe uma sessão em andamento. Toque em Retomar."
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
