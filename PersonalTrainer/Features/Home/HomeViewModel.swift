import Foundation
import Observation
import os
import TrainerCore

/// Estado da tela Hoje (SPEC F1, RF-01, RF-02, S4, §7.15 M6; TASKS T1.4, T2.14).
///
/// Com um plano ativo, tudo fica como na 2.2: o próximo plano, os dias e o objetivo do programa ativo
/// pelo `SessionPlanning`. Com dois (SPEC §7.15 M6), a tela mostra as sessões do dia pelo
/// `todayOverview(now:)`: um cartão por sessão, a força antes do aeróbico, "Feito hoje", o dia de
/// descanso com "Treinar mesmo assim" e a faixa de quando os planos não cabem.
///
/// A sessão em andamento vem do `SessionCoordinating`; nada aqui toca o `ModelContext` (AGENTS R4). O
/// relógio chega por `now` (SPEC P11): nada aqui lê a data do sistema. Quem liga Home → Sessão é o
/// `RootView`, pelo id devolvido por `startSession()`.
@Observable
@MainActor
final class HomeViewModel {
    /// Treino exibido: o próximo da rotação (S1–S2) ou o dia escolhido à mão (S4). Com dois planos, o
    /// que o "Começar" abre (M6: a primeira sessão de hoje ainda não feita ou, sem ela, a próxima do
    /// principal). `nil` quando não há programa ativo ou a última leitura falhou.
    private(set) var plan: SessionPlan?
    /// `uuid` da sessão `inProgress`, se houver (SPEC S3): o botão vira "Retomar".
    private(set) var activeSessionID: UUID?
    /// Dias do programa ativo, ordenados por `order`, para o menu do nome do dia (T2.14).
    private(set) var days: [ProgramDayTemplate] = []
    /// Objetivo do programa ativo (SPEC §7.9) para o selo do card; `nil` sem programa ativo.
    private(set) var goal: ProgramGoal?
    /// Objetivos dos planos ativos, o principal primeiro (SPEC §7.15 M1). Com dois, a tela é a de M6.
    private(set) var goals: [ProgramGoal] = []
    /// Dia escolhido à mão (SPEC S4); `nil` = automático (próximo da rotação). Vale até o treino
    /// ser iniciado ou retomado, até "Automático" ou até o dia sumir do programa. Sobrevive a
    /// `refresh()` de propósito: trocar de aba chama `onAppear` e não pode desfazer a escolha
    /// sem o usuário perceber (ele iniciaria o dia errado). Com dois planos, cada cartão guarda o seu.
    private(set) var selectedDayID: UUID?
    /// Mensagem pt-BR para o `.alert` da view; a view zera ao fechar o alerta.
    var errorMessage: String?
    /// Verdadeiro enquanto a última leitura (`refresh()`) tiver falhado. Separado de
    /// `errorMessage` porque fechar o alerta zera a mensagem, e sem isto a tela passaria a
    /// dizer "Nenhum programa ativo" para uma falha de leitura (o programa pode existir).
    private(set) var didFailToLoad = false
    /// Modo casa (SPEC RF-42): o interruptor "Em casa" do cartão. Espelho da chave
    /// `PlannerSettings.homeModeKey`, relido a cada `refresh()` porque o Ajustes grava a mesma.
    private(set) var isHomeMode = false
    /// Com dois planos: o dia de hoje (M6). `nil` com um plano ou se a leitura falhou.
    private(set) var overview: TodayOverview?
    /// "Treinar mesmo assim": mostra as outras sessões num dia de descanso (ou quando os planos não
    /// cabem) e deixa começar de novo depois de tudo feito. Vale até começar uma sessão.
    private(set) var isTrainingAnyway = false

    /// Com dois planos, o dia escolhido à mão de cada cartão (id do programa → id do dia) e o plano dele.
    private var manualDayIDs: [UUID: UUID] = [:]
    private var manualPlans: [UUID: SessionPlan] = [:]
    /// Com dois planos, os dias de cada plano para o menu de cada cartão.
    private var daysByProgramID: [UUID: [ProgramDayTemplate]] = [:]

    private let planner: any SessionPlanning
    private let coordinator: any SessionCoordinating
    private let now: () -> Date
    /// Onde fica a chave do modo casa; o planner lê a mesma (`PlannerSettings.load(from:)`).
    private let defaults: UserDefaults

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "Home"
    )

    /// - Parameter defaults: o app usa `.standard`, a mesma suite que o `SessionPlanner` lê. Os
    ///   testes passam uma suite isolada.
    init(
        planner: any SessionPlanning,
        coordinator: any SessionCoordinating,
        now: @escaping () -> Date,
        defaults: UserDefaults = .standard
    ) {
        self.planner = planner
        self.coordinator = coordinator
        self.now = now
        self.defaults = defaults
        self.isHomeMode = PlannerSettings.load(from: defaults).homeModeEnabled
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

    /// SPEC RF-45: com sessão em andamento, trocar de objetivo não teria efeito (a sessão já
    /// começou com o programa antigo). O topo da Home e o menu de dias usam o mesmo critério.
    var isSessionInProgress: Bool {
        activeSessionID != nil
    }

    /// Dois planos ativos: a tela Hoje é a de M6. Com um, fica como na 2.2.
    var isMultiPlan: Bool {
        goals.count >= 2
    }

    /// Objetivos do topo: os dois com dois planos; senão, o do programa ativo.
    var headerGoals: [ProgramGoal] {
        if isMultiPlan {
            return goals
        }
        return goal.map { [$0] } ?? []
    }

    /// Relê sessão ativa, dias, objetivo e o plano (o do dia escolhido, se houver; senão o da
    /// rotação); com dois planos, o dia de hoje (M6). Em falha do plano, ele é descartado (nunca
    /// iniciar a partir de um plano possivelmente desatualizado) e a mensagem vai para `errorMessage`.
    func refresh() {
        isHomeMode = PlannerSettings.load(from: defaults).homeModeEnabled
        activeSessionID = coordinator.activeSession?.uuid
        if activeSessionID != nil {
            // Com treino em andamento a escolha manual não tem mais efeito: o botão só retoma, e
            // ao terminar a rotação já segue do dia registrado (S4).
            selectedDayID = nil
            clearManualDays()
        }
        loadProgramInfo()
        if isMultiPlan {
            selectedDayID = nil
            loadToday()
        } else {
            clearMultiPlan()
            loadSinglePlan()
        }
    }

    /// Mostra o plano de um dia escolhido à mão (SPEC S4) e o guarda como escolha até iniciar.
    /// A rotação segue a partir desse dia porque a sessão registrada nele passa a ser a
    /// referência de S2; nada é gravado aqui. Em falha, o plano atual é mantido. Com dois planos, a
    /// escolha vale para o cartão do plano do dia.
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
            if isMultiPlan {
                manualDayIDs[manualPlan.programID] = dayID
                manualPlans[manualPlan.programID] = manualPlan
                plan = primaryPlan()
            } else {
                selectedDayID = dayID
                plan = manualPlan
            }
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

    /// Com dois planos: volta o cartão de um plano ao próximo da rotação (S2, S8).
    func selectAutomaticDay(forProgramID programID: UUID) {
        manualDayIDs[programID] = nil
        manualPlans[programID] = nil
        refresh()
    }

    /// Interruptor "Em casa" (SPEC RF-42): grava a chave que o planner lê e relê o plano, mantendo
    /// o dia escolhido à mão, se houver. O programa não muda: desligar volta os exercícios dele.
    /// Uma sessão já em andamento continua como começou; só o "Trocar" dela passa a oferecer
    /// alternativas de casa (§7.13 H2).
    func setHomeMode(_ enabled: Bool) {
        defaults.set(enabled, forKey: PlannerSettings.homeModeKey)
        isHomeMode = enabled
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
            errorMessage = "Nenhum objetivo escolhido. Toque em Escolher, no topo da tela Hoje."
            return nil
        }
        return start(plan)
    }

    /// Com dois planos, "Começar esta" num cartão: começa a sessão daquele plano. Com sessão em
    /// andamento, só retoma.
    func startSession(programID: UUID) -> UUID? {
        if let activeSessionID {
            return activeSessionID
        }
        guard let card = todayCards.first(where: { $0.id == programID && $0.isStartable }) else {
            return nil
        }
        return start(card.plan)
    }

    /// "Treinar mesmo assim" (M6): mostra as outras sessões e deixa começar uma delas.
    func trainAnyway() {
        guard showsTrainAnyway else { return }
        isTrainingAnyway = true
        plan = primaryPlan()
    }

    /// Conteúdo da folha "Informações do exercício" (SPEC RF-47; docs/V22-CONTRACT.md §2.2) a
    /// partir do plano, antes de a sessão existir. `measure` vem de `\.exerciseTraits` (SPEC
    /// RF-43): a view lê o ambiente, porque o ViewModel não guarda esse catálogo. Falha ao ler
    /// "da última vez" some da folha em vez de travar a tela (fica só no log).
    func infoContent(for planned: PlannedExercise, measure: ExerciseMeasure) -> ExerciseInfoContent {
        let lastSession: ExerciseLastSession?
        do {
            lastSession = try planner.lastSession(forExerciseID: planned.exercise.id)
        } catch {
            lastSession = nil
            Self.logger.error("Falha ao ler a última sessão do exercício: \(String(describing: error), privacy: .public)")
        }
        return ExerciseInfoContent(planned: planned, measure: measure, lastSession: lastSession)
    }

    // MARK: - Dois planos (SPEC §7.15 M6)

    /// Os cartões de hoje, na ordem do dia (a força antes do aeróbico). Vazio com um plano.
    /// - Dia com sessões: as de hoje; quando os planos não cabem, a do principal e, com "Treinar mesmo
    ///   assim", a do outro.
    /// - Dia de descanso: nenhum, até "Treinar mesmo assim", que mostra a próxima de cada plano.
    var todayCards: [HomeTodayCard] {
        guard isMultiPlan, let overview else {
            return []
        }
        let canStart = activeSessionID == nil
        var hasPrimary = false
        var cards: [HomeTodayCard] = []
        for session in visibleSessions(overview) {
            let isStartable = canStart && (!session.isDoneToday || isTrainingAnyway)
            let isPrimary = isStartable && !hasPrimary
            if isPrimary {
                hasPrimary = true
            }
            cards.append(HomeTodayCard(
                session: session,
                plan: manualPlans[session.id] ?? session.plan,
                days: daysByProgramID[session.id] ?? [],
                selectedDayID: manualDayIDs[session.id],
                isStartable: isStartable,
                isPrimary: isPrimary
            ))
        }
        return cards
    }

    /// O cartão que o "Começar" principal abre.
    var primaryCard: HomeTodayCard? {
        todayCards.first { $0.isPrimary }
    }

    /// Hoje não tem nenhuma sessão na semana ideal (M6).
    var isRestDay: Bool {
        isMultiPlan && overview?.isRestDay == true
    }

    /// As sessões de hoje já foram feitas.
    var isAllDoneToday: Bool {
        guard isMultiPlan, let overview, !overview.isRestDay, !overview.sessions.isEmpty else {
            return false
        }
        return overview.sessions.allSatisfy(\.isDoneToday)
    }

    /// Os planos não cabem mais nos dias escolhidos (M6).
    var showsNotFitBanner: Bool {
        isMultiPlan && overview?.fitsWeek == false
    }

    /// "Treinar mesmo assim": num dia de descanso, com os planos fora da semana ou com tudo feito.
    var showsTrainAnyway: Bool {
        guard isMultiPlan, let overview, activeSessionID == nil, !isTrainingAnyway else {
            return false
        }
        if overview.isRestDay {
            return !overview.otherSessions.isEmpty
        }
        if !overview.fitsWeek && !overview.otherSessions.isEmpty {
            return true
        }
        return !overview.sessions.isEmpty && overview.sessions.allSatisfy(\.isDoneToday)
    }

    /// "Hoje: Superior + Cardio leve 25 min" sobre os cartões; `nil` num dia de descanso.
    var todayLine: String? {
        TodayPlansText.todayLine(todayPlans)
    }

    var spokenTodayLine: String? {
        TodayPlansText.spokenTodayLine(todayPlans)
    }

    /// Os planos das sessões de hoje (com o dia escolhido à mão, quando houver).
    private var todayPlans: [SessionPlan] {
        guard isMultiPlan, let overview, !overview.isRestDay else {
            return []
        }
        return overview.sessions.map { manualPlans[$0.id] ?? $0.plan }
    }

    private func visibleSessions(_ overview: TodayOverview) -> [TodaySession] {
        if overview.isRestDay {
            return isTrainingAnyway ? overview.otherSessions : []
        }
        guard !overview.fitsWeek, isTrainingAnyway else {
            return overview.sessions
        }
        let shown = Set(overview.sessions.map(\.id))
        return overview.sessions + overview.otherSessions.filter { !shown.contains($0.id) }
    }

    /// M6: o cartão principal; sem ele, a próxima do plano principal (para o "Começar" do diálogo, C5).
    private func primaryPlan() -> SessionPlan? {
        if let card = primaryCard {
            return card.plan
        }
        guard let overview else {
            return nil
        }
        let all = overview.sessions + overview.otherSessions
        let principal = goals.first
        guard let session = all.first(where: { $0.goal == principal }) ?? all.first else {
            return nil
        }
        return manualPlans[session.id] ?? session.plan
    }

    // MARK: - Leitura

    /// Dias e objetivos são complementares ao plano: uma falha aqui só esconde o menu de dias e o
    /// selo do objetivo (e fica no log), sem transformar a Home inteira em "não carregou". Sem os
    /// objetivos, a tela fica como com um plano só.
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
        do {
            goals = try planner.activeProgramGoals()
        } catch {
            goals = []
            Self.logger.error("Falha ao ler os objetivos dos planos ativos: \(String(describing: error), privacy: .public)")
        }
    }

    /// Um plano: o do dia escolhido, se ainda existir; senão, o da rotação.
    private func loadSinglePlan() {
        do {
            plan = try currentPlan(now: now())
            didFailToLoad = false
        } catch {
            plan = nil
            didFailToLoad = true
            errorMessage = Self.message(for: error, fallback: "Não foi possível carregar a próxima sessão.")
        }
    }

    /// Dois planos: o dia de hoje (M6), os dias escolhidos à mão de novo com o relógio atual e os dias
    /// de cada plano para os menus.
    private func loadToday() {
        let date = now()
        do {
            let today = try planner.todayOverview(now: date)
            overview = today
            replanManualDays(now: date)
            loadDaysByProgram(for: today)
            plan = primaryPlan()
            didFailToLoad = false
        } catch {
            overview = nil
            plan = nil
            didFailToLoad = true
            errorMessage = Self.message(for: error, fallback: "Não foi possível carregar as sessões de hoje.")
        }
    }

    /// Replaneja os dias escolhidos à mão; um dia que sumiu do plano volta ao automático.
    private func replanManualDays(now date: Date) {
        for (programID, dayID) in manualDayIDs {
            do {
                if let manualPlan = try planner.plan(forDayID: dayID, now: date), manualPlan.programID == programID {
                    manualPlans[programID] = manualPlan
                } else {
                    manualDayIDs[programID] = nil
                    manualPlans[programID] = nil
                }
            } catch {
                manualDayIDs[programID] = nil
                manualPlans[programID] = nil
                Self.logger.error("Falha ao replanejar o dia escolhido: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func loadDaysByProgram(for today: TodayOverview) {
        var result: [UUID: [ProgramDayTemplate]] = [:]
        for session in today.sessions + today.otherSessions where result[session.id] == nil {
            do {
                result[session.id] = try planner.days(ofProgramID: session.id).sorted { $0.order < $1.order }
            } catch {
                result[session.id] = []
                Self.logger.error("Falha ao ler os dias de um plano: \(String(describing: error), privacy: .public)")
            }
        }
        daysByProgramID = result
    }

    private func clearManualDays() {
        manualDayIDs = [:]
        manualPlans = [:]
    }

    /// Voltou a um plano só: nada do dia com dois planos fica guardado.
    private func clearMultiPlan() {
        overview = nil
        isTrainingAnyway = false
        clearManualDays()
        daysByProgramID = [:]
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

    // MARK: - Início de sessão

    private func start(_ plan: SessionPlan) -> UUID? {
        // SPEC S2/RF-33: um dia ainda sem exercícios não vira sessão (ela sairia vazia). O botão da
        // Home já fica desabilitado; isto cobre o "Começar" do diálogo (C5). No modo casa o dia
        // pode ficar vazio porque nenhum exercício tem opção em casa (§7.13 H2).
        guard !plan.exercises.isEmpty else {
            errorMessage = Self.emptyDayMessage(for: plan)
            return nil
        }
        do {
            let sessionID = try planner.startSession(from: plan, now: now())
            activeSessionID = sessionID
            // A escolha manual foi consumida: ao voltar, a Home mostra a rotação a partir dela (S4).
            selectedDayID = nil
            manualDayIDs[plan.programID] = nil
            manualPlans[plan.programID] = nil
            isTrainingAnyway = false
            return sessionID
        } catch {
            // Se outra parte do app (ou o relógio, em M3) já abriu uma sessão, a Home passa a
            // oferecer "Retomar" em vez de insistir em iniciar.
            if let inProgressID = Self.inProgressSessionID(from: error) {
                activeSessionID = inProgressID
                selectedDayID = nil
            }
            errorMessage = Self.message(for: error, fallback: "Não foi possível iniciar a sessão.")
            return nil
        }
    }

    // MARK: - Mensagens pt-BR

    /// Texto do dia sem exercício, no cartão e no alerta do "Começar". No modo casa com exercícios
    /// que saíram (§7.13 H2), a saída é desligar "Em casa" ou escolher outro dia; fora dele, o dia
    /// ainda não tem exercícios no programa (RF-33).
    nonisolated static func emptyDayMessage(for plan: SessionPlan) -> String {
        if plan.isHomeMode && !plan.homeNotices.isEmpty {
            return "Nenhum exercício deste dia tem opção em casa. Desligue Em casa ou escolha outro dia."
        }
        return "Este dia ainda não tem exercícios. Escolha os exercícios dele na aba Plano."
    }

    private static func message(for error: any Error, fallback: String) -> String {
        if let planningError = error as? PlanningError {
            switch planningError {
            case .noActiveProgram:
                return "Nenhum objetivo escolhido. Toque em Escolher, no topo da tela Hoje."
            case .programHasNoDays:
                return "O programa ativo não tem dias."
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
