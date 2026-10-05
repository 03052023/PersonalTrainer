import Foundation
import Observation
import os
import TrainerCore

/// Fluxo curto da semana com dois planos (SPEC §7.15 M4, M5, M7, M8, M9; DESIGN §13), em páginas:
/// - **adicionar** um segundo plano (folha "Seu objetivo"): "O que muda" (M7), "Seus dias" (M9) e
///   "Sua semana" (M4, M5); se cabe, "Adicionar X" grava os dias e ativa o plano ao lado do atual;
/// - **Seus dias** (aba Plano, com dois planos): os dias e a semana, com a mesma conferência antes de
///   gravar.
///
/// Quando não cabe, a semana mostra o motivo e as saídas de M5, cada uma com a semana que resulta dela;
/// "Escolher esta" grava as preferências da saída (e, ao adicionar, ativa o plano).
///
/// Escritas só pelo `SessionPlanning.saveWeekPreferences` e pelo `ProgramRepositoring.addActivePlan`
/// (AGENTS R4). O relógio chega por `now` (SPEC P11). A tabela de consequências entra por fechamento, com
/// `PlanCombination` como padrão, para os testes da tela não dependerem dela.
@Observable
@MainActor
final class PlanFitFlowModel {
    enum Purpose: Equatable {
        /// Adicionar `candidate` ao lado de `current`, o plano ativo (M8).
        case addPlan(current: ProgramTemplate, candidate: ProgramTemplate)
        /// Mudar os dias dos planos ativos (M9).
        case editDays(programs: [ProgramTemplate])
    }

    enum Page: Int, Sendable, Hashable, CaseIterable {
        case consequences
        case days
        case week
    }

    enum Outcome: Equatable {
        /// Gravou os dias (e, ao adicionar, ativou o plano).
        case saved
        /// Nada a gravar: não cabe, já terminou ou há sessão em andamento.
        case refused
        /// Uma escrita falhou; a mensagem está em `errorMessage`.
        case failed
    }

    /// Um grupo de "O que muda": "Ganha", "Fica igual" ou "Custa".
    struct ConsequenceGroup: Identifiable, Hashable {
        let kind: PlanConsequenceKind
        let items: [PlanConsequence]

        var id: PlanConsequenceKind { kind }

        var title: String { PlanWeekText.groupTitle(kind) }
    }

    let purpose: Purpose
    private(set) var page: Page
    /// O rascunho da semana: começa em `weekPreferences()` e só é gravado ao confirmar.
    private(set) var preferences: WeekPreferences
    /// A última conferência (M4, M5). `nil` antes de chegar em "Sua semana" ou se ela falhou.
    private(set) var result: FitResult?
    /// A conferência falhou: a semana mostra "Não foi possível conferir a semana." e "Tentar de novo".
    private(set) var didFailToCheck = false
    /// Verdadeiro depois de gravar: nada é gravado de novo.
    private(set) var hasFinished = false
    /// Com sessão em andamento, adicionar fica bloqueado (M8); os dias podem mudar.
    var isSessionInProgress: Bool
    var errorMessage: String?

    private let programs: any ProgramRepositoring
    private let planner: any SessionPlanning
    private let now: () -> Date
    private let consequenceTable: (ProgramGoal, ProgramGoal) -> [PlanConsequence]
    private let overlapCheck: (ProgramGoal, ProgramGoal) -> Bool

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "PlanFitFlow"
    )

    init(
        purpose: Purpose,
        programs: any ProgramRepositoring,
        planner: any SessionPlanning,
        now: @escaping () -> Date,
        isSessionInProgress: Bool = false,
        consequences: @escaping (ProgramGoal, ProgramGoal) -> [PlanConsequence] = { first, second in
            PlanCombination.consequences(first, second)
        },
        isLargeOverlap: @escaping (ProgramGoal, ProgramGoal) -> Bool = { first, second in
            PlanCombination.isLargeOverlap(first, second)
        }
    ) {
        self.purpose = purpose
        self.programs = programs
        self.planner = planner
        self.now = now
        self.isSessionInProgress = isSessionInProgress
        self.consequenceTable = consequences
        self.overlapCheck = isLargeOverlap
        self.preferences = planner.weekPreferences()
        switch purpose {
        case .addPlan:
            self.page = .consequences
        case .editDays:
            self.page = .days
        }
    }

    var isPresentingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
            }
        }
    }

    // MARK: - Planos

    /// Os planos que a semana precisa encaixar, o principal primeiro.
    var plansInWeek: [ProgramTemplate] {
        switch purpose {
        case .addPlan(let current, let candidate):
            return ActivePlanOrder.sorted([current, candidate])
        case .editDays(let programs):
            return ActivePlanOrder.sorted(programs)
        }
    }

    var programIDs: [UUID] {
        plansInWeek.map(\.id)
    }

    /// Objetivos na ordem de M1: a flor do topo e o nome "Hipertrofia + Cardio".
    var goals: [ProgramGoal] {
        plansInWeek.map(\.effectiveGoal)
    }

    /// Objetivo de cada plano pelo id, para os textos da semana e das saídas.
    var goalsByProgramID: [UUID: ProgramGoal] {
        Dictionary(plansInWeek.map { ($0.id, $0.effectiveGoal) }, uniquingKeysWith: { first, _ in first })
    }

    /// O plano que vai entrar, ao adicionar.
    var candidate: ProgramTemplate? {
        if case .addPlan(_, let candidate) = purpose {
            return candidate
        }
        return nil
    }

    // MARK: - Páginas

    var pages: [Page] {
        switch purpose {
        case .addPlan:
            return [.consequences, .days, .week]
        case .editDays:
            return [.days, .week]
        }
    }

    var isFirstPage: Bool {
        page == pages.first
    }

    var title: String {
        switch page {
        case .consequences: return "O que muda"
        case .days: return PlanWeekText.yourDaysTitle
        case .week: return PlanWeekText.yourWeekTitle
        }
    }

    /// Botão "Continuar" das duas primeiras páginas.
    var canContinue: Bool {
        guard !hasFinished else { return false }
        switch page {
        case .consequences:
            return true
        case .days:
            return !preferences.availableDays.isEmpty
        case .week:
            return false
        }
    }

    /// Avança uma página. Ao chegar em "Sua semana", confere o encaixe com os dias escolhidos.
    func next() {
        guard canContinue else { return }
        switch page {
        case .consequences:
            page = .days
        case .days:
            page = .week
            checkFit()
        case .week:
            break
        }
    }

    /// Volta uma página. Falso na primeira: quem apresenta o fluxo fecha (ou volta à lista de objetivos).
    @discardableResult
    func back() -> Bool {
        guard let index = pages.firstIndex(of: page), index > 0 else {
            return false
        }
        page = pages[index - 1]
        return true
    }

    // MARK: - O que muda (M7)

    /// As consequências de combinar os dois objetivos, agrupadas na ordem "Ganha", "Fica igual", "Custa".
    /// Vazio fora de "adicionar".
    var consequenceGroups: [ConsequenceGroup] {
        guard case .addPlan(let current, let candidate) = purpose else {
            return []
        }
        let all = consequenceTable(current.effectiveGoal, candidate.effectiveGoal)
        return PlanWeekText.consequenceOrder.compactMap { (kind: PlanConsequenceKind) -> ConsequenceGroup? in
            let items = all.filter { $0.kind == kind }
            if items.isEmpty {
                return nil
            }
            return ConsequenceGroup(kind: kind, items: items)
        }
    }

    /// Grande sobreposição (Hipertrofia + Força, Força + Combate): o aviso de M7.
    var showsOverlapWarning: Bool {
        guard case .addPlan(let current, let candidate) = purpose else {
            return false
        }
        return overlapCheck(current.effectiveGoal, candidate.effectiveGoal)
    }

    // MARK: - Seus dias (M9)

    func isAvailable(_ day: PlanWeekday) -> Bool {
        preferences.availableDays.contains(day)
    }

    /// Liga ou desliga um dia. A conferência anterior deixa de valer.
    func toggle(_ day: PlanWeekday) {
        guard !hasFinished else { return }
        if preferences.availableDays.contains(day) {
            preferences.availableDays.remove(day)
        } else {
            preferences.availableDays.insert(day)
        }
        result = nil
    }

    /// "Aceito 2 sessões no mesmo dia".
    var allowsTwoSessionsPerDay: Bool {
        get { preferences.allowsTwoSessionsPerDay }
        set {
            guard !hasFinished else { return }
            preferences.allowsTwoSessionsPerDay = newValue
            result = nil
        }
    }

    /// "Cardio leve depois da força".
    var allowsLightCardioAfterStrength: Bool {
        get { preferences.allowsLightCardioAfterStrength }
        set {
            guard !hasFinished else { return }
            preferences.allowsLightCardioAfterStrength = newValue
            result = nil
        }
    }

    // MARK: - Sua semana (M4, M5)

    /// Confere o encaixe dos planos com o rascunho. Uma falha vira log e o aviso da página.
    func checkFit() {
        do {
            result = try planner.fitCheck(programIDs: programIDs, preferences: preferences, now: now())
            didFailToCheck = false
        } catch {
            result = nil
            didFailToCheck = true
            Self.logger.error("Fit check failed: \(String(describing: error), privacy: .public)")
        }
    }

    var fits: Bool {
        result?.fits ?? false
    }

    /// A semana que cabe; `nil` quando não cabe.
    var schedule: WeekSchedule? {
        guard let result, result.fits else { return nil }
        return result.schedule
    }

    /// As linhas da semana que cabe; vazio sem semana calculada.
    var weekRows: [PlanWeekText.WeekRow] {
        guard let schedule, !schedule.slots.isEmpty else { return [] }
        return PlanWeekText.weekRows(schedule, goals: goalsByProgramID)
    }

    var weekNotes: [String] {
        guard let schedule else { return [] }
        return PlanWeekText.notes(schedule)
    }

    /// O motivo em uma frase, quando não cabe.
    var problemText: String? {
        guard let result, !result.fits else { return nil }
        return PlanWeekText.problemSentence(result.problems, twoPerDay: preferences.allowsTwoSessionsPerDay)
    }

    /// As saídas de M5, na ordem, quando não cabe.
    var alternatives: [FitAlternative] {
        guard let result, !result.fits else { return [] }
        return result.alternatives
    }

    /// Não cabe e não há saída: "Esses dois planos não cabem juntos na semana. Escolha um só."
    var showsNoAlternative: Bool {
        guard let result else { return false }
        return !result.fits && result.alternatives.isEmpty
    }

    /// "Adicionar Cardio" ou "Salvar os dias".
    var confirmTitle: String {
        if let candidate {
            return PlanWeekText.addConfirmTitle(candidate.effectiveGoal)
        }
        return PlanWeekText.saveDaysTitle
    }

    private var isBlockedBySession: Bool {
        candidate != nil && isSessionInProgress
    }

    var canConfirm: Bool {
        !hasFinished && page == .week && fits && !isBlockedBySession
    }

    var canChooseAlternative: Bool {
        !hasFinished && page == .week && !isBlockedBySession
    }

    /// Botão da semana que cabe: grava os dias e, ao adicionar, ativa o plano.
    func confirm() -> Outcome {
        guard canConfirm else {
            return .refused
        }
        return save(preferences)
    }

    /// "Escolher esta": grava as preferências da saída e, ao adicionar, ativa o plano.
    func choose(_ alternative: FitAlternative) -> Outcome {
        guard canChooseAlternative, alternatives.contains(alternative) else {
            return .refused
        }
        return save(alternative.preferences)
    }

    private func save(_ chosen: WeekPreferences) -> Outcome {
        do {
            try planner.saveWeekPreferences(chosen)
        } catch {
            Self.logger.error("Saving week preferences failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Não foi possível guardar os seus dias. Tente de novo."
            return .failed
        }
        preferences = chosen
        if let candidate {
            do {
                try programs.addActivePlan(programID: candidate.id)
            } catch {
                Self.logger.error("Adding plan failed: \(String(describing: error), privacy: .public)")
                errorMessage = "Não foi possível adicionar o plano. Tente de novo."
                return .failed
            }
        }
        hasFinished = true
        return .saved
    }
}
