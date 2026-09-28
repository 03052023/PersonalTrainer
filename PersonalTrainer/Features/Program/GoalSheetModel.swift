import Foundation
import Observation
import os
import TrainerCore

/// Estado da folha "Seu objetivo" (SPEC RF-45, §7.15 M7 e M8; DESIGN §13): os 5 objetivos do
/// `GoalPlanCatalog`, o objetivo e o formato tocados, a prévia do Dia A, a troca e, desde a 2.3, o
/// começo do fluxo de adicionar um segundo plano.
///
/// Trocar (M8):
/// - com um plano ativo, é uma única escrita, `ProgramRepositoring.activate` (fica só o escolhido; S2
///   recomeça no Dia A; P3 é por exercício, então as cargas ficam);
/// - com dois, trocar o formato da Hipertrofia, ou o plano de um objetivo que já está ativo, troca só
///   aquele plano e mantém o outro (`removeActivePlan` do antigo e `addActivePlan` do novo, nessa ordem);
///   trocar para um terceiro objetivo deixa só ele, com o aviso "O plano de Y também sai.".
///
/// Adicionar (M8) só existe com um plano ativo, um objetivo diferente tocado e o planejador presente: o
/// modelo monta o `PlanFitFlowModel`, que confere a semana e grava. Nada aqui chama `setGoal`, renomeia,
/// duplica ou apaga (AGENTS R4: a escrita vai só pelo repositório).
@Observable
@MainActor
final class GoalSheetModel {
    /// O que um toque no botão principal fez.
    enum ConfirmOutcome: Equatable {
        /// Ativou outro programa.
        case changed
        /// Primeiro uso com a escolha que já estava ativa: nada a gravar.
        case unchanged
        /// Botão bloqueado (escolha atual, sessão em andamento, nada escolhido ou já concluído).
        case refused
        /// A escrita falhou; a mensagem está em `errorMessage`.
        case failed
    }

    /// A prévia "Dia A: …" do plano tocado.
    struct DayPreview: Equatable {
        let dayName: String
        let exercises: String

        var text: String { "\(dayName): \(exercises)" }
    }

    let mode: GoalSheet.Mode
    /// Com sessão em andamento a troca e o acréscimo ficam bloqueados (RF-45, M8).
    var isSessionInProgress: Bool
    private(set) var plans = GoalPlanCatalog(programs: [])
    private(set) var selectedGoal: ProgramGoal?
    private(set) var selectedProgramID: UUID?
    private(set) var hasLoaded = false
    private(set) var didFailToLoad = false
    /// Verdadeiro depois de trocar, adicionar, cancelar ou pular: a folha não grava de novo.
    private(set) var hasFinished = false
    var errorMessage: String?

    private let programs: any ProgramRepositoring
    private let exerciseCatalog: (any CatalogRepositoring)?
    /// Sem planejador não há como conferir a semana: a folha não oferece "Adicionar".
    private let planner: (any SessionPlanning)?
    private let now: () -> Date
    /// Nomes do catálogo inteiro, arquivados inclusive (um plano pode apontar para um arquivado).
    private var exerciseNames: [UUID: String] = [:]

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "GoalSheet"
    )

    init(
        programs: any ProgramRepositoring,
        catalog: (any CatalogRepositoring)?,
        mode: GoalSheet.Mode,
        isSessionInProgress: Bool,
        planner: (any SessionPlanning)? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.programs = programs
        self.exerciseCatalog = catalog
        self.mode = mode
        self.isSessionInProgress = isSessionInProgress
        self.planner = planner
        self.now = now
    }

    var isPresentingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
            }
        }
    }

    // MARK: - Leitura

    /// Relê programas e nomes. Mantém a escolha feita se ela ainda existe; senão, começa no
    /// objetivo e no programa do plano principal (ao adicionar, sem escolha).
    func load() {
        defer { hasLoaded = true }
        do {
            let all = try programs.allPrograms()
            plans = GoalPlanCatalog(programs: all)
            didFailToLoad = false
        } catch {
            plans = GoalPlanCatalog(programs: [])
            didFailToLoad = true
            Self.logger.error("Goal sheet load failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Não foi possível carregar os objetivos."
        }
        loadExerciseNames()
        keepOrResetSelection()
    }

    private func loadExerciseNames() {
        guard let exerciseCatalog else {
            exerciseNames = [:]
            return
        }
        do {
            let everything = try exerciseCatalog.allExercises(includeArchived: true)
            exerciseNames = Dictionary(everything.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        } catch {
            // Sem nomes, a folha só não mostra a prévia do Dia A.
            exerciseNames = [:]
            Self.logger.error("Goal sheet catalog load failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func keepOrResetSelection() {
        if
            let goal = selectedGoal,
            let entry = plans.entry(for: goal),
            let programID = selectedProgramID,
            entry.programIDs.contains(programID),
            isSelectable(entry)
        {
            return
        }
        switch mode {
        case .add:
            // Adicionar começa sem escolha: os objetivos já ativos não entram.
            selectedGoal = nil
            selectedProgramID = nil
        case .change, .firstUse:
            if
                let active = plans.activeProgram,
                let entry = plans.entry(for: active.effectiveGoal),
                entry.programIDs.contains(active.id)
            {
                selectedGoal = entry.goal
                selectedProgramID = active.id
            } else {
                selectedGoal = nil
                selectedProgramID = nil
            }
        }
    }

    // MARK: - Escolha

    /// Dá para tocar neste objetivo: tem plano pronto e, ao adicionar, ainda não está ativo (M1).
    func isSelectable(_ entry: GoalPlanCatalog.Entry) -> Bool {
        guard entry.isAvailable else { return false }
        if mode == .add {
            return !entry.isCurrent
        }
        return true
    }

    /// Toca num objetivo. Tocar de novo no mesmo mantém o formato escolhido; objetivo sem plano
    /// pronto (ou já ativo, ao adicionar) não é escolhível.
    func select(_ goal: ProgramGoal) {
        guard !hasFinished, goal != selectedGoal else { return }
        guard
            let entry = plans.entry(for: goal),
            isSelectable(entry),
            let programID = entry.defaultProgramID
        else {
            return
        }
        selectedGoal = goal
        selectedProgramID = programID
    }

    /// Toca num formato (chips da Hipertrofia).
    func selectFormat(_ programID: UUID) {
        guard
            !hasFinished,
            let goal = selectedGoal,
            let entry = plans.entry(for: goal),
            entry.format(id: programID) != nil
        else {
            return
        }
        selectedProgramID = programID
    }

    var selectedEntry: GoalPlanCatalog.Entry? {
        guard let selectedGoal else { return nil }
        return plans.entry(for: selectedGoal)
    }

    var selectedProgram: ProgramTemplate? {
        plans.program(id: selectedProgramID)
    }

    /// A escolha é um programa que já está ativo.
    var isCurrentSelection: Bool {
        guard let selectedProgramID else { return false }
        return plans.activePrograms.contains { $0.id == selectedProgramID }
    }

    /// Com dois planos ativos, o plano do objetivo tocado, que a troca substitui mantendo o outro (M8).
    var replacedProgram: ProgramTemplate? {
        guard plans.activePrograms.count >= 2, let selectedGoal, !isCurrentSelection else {
            return nil
        }
        return plans.activePlan(for: selectedGoal)
    }

    /// Com dois planos ativos e um terceiro objetivo tocado, o objetivo do outro plano, que sai junto (M8).
    var alsoLeavingGoal: ProgramGoal? {
        guard
            mode == .change,
            plans.activePrograms.count >= 2,
            selectedProgram != nil,
            !isCurrentSelection,
            replacedProgram == nil
        else {
            return nil
        }
        return plans.activePrograms.dropFirst().first?.effectiveGoal
    }

    /// "O plano de Cardio também sai." acima do botão.
    var changeWarning: String? {
        alsoLeavingGoal.map { PlanWeekText.alsoLeaves($0) }
    }

    /// Flor grande do topo: na troca, só o tocado; ao adicionar, os ativos e o tocado juntos.
    var flowerGoals: [ProgramGoal] {
        switch mode {
        case .change, .firstUse:
            return selectedGoal.map { [$0] } ?? []
        case .add:
            var goals = plans.activeGoals
            if let selectedGoal, !goals.contains(selectedGoal) {
                goals.append(selectedGoal)
            }
            return goals
        }
    }

    /// Mostra "Termine a sessão em andamento para …" embaixo do botão.
    var showsSessionBlock: Bool {
        isSessionInProgress && !(mode == .firstUse && isCurrentSelection)
    }

    var sessionBlockText: String {
        mode == .add
            ? "Termine a sessão em andamento para adicionar."
            : "Termine a sessão em andamento para trocar."
    }

    /// RF-45: "Trocar" desabilitado quando a escolha é a atual ou com sessão em andamento. No
    /// primeiro uso, "Começar" também vale para a escolha atual (não grava nada). Ao adicionar, o botão
    /// principal é o de adicionar (`canAdd`).
    var canConfirm: Bool {
        guard !hasFinished, selectedProgram != nil else { return false }
        switch mode {
        case .change:
            return !isSessionInProgress && !isCurrentSelection
        case .firstUse:
            return isCurrentSelection || !isSessionInProgress
        case .add:
            return false
        }
    }

    /// "Trocar para Hipertrofia"; "Trocar para Mais pernas e glúteos" quando só muda o formato;
    /// "Começar" no primeiro uso; "Adicionar Cardio ao seu plano" ao adicionar.
    var confirmTitle: String {
        switch mode {
        case .firstUse:
            return "Começar"
        case .change:
            guard let entry = selectedEntry else {
                return "Escolha um objetivo"
            }
            if
                plans.activeGoals.contains(entry.goal),
                !isCurrentSelection,
                entry.formats.count > 1,
                let format = entry.format(id: selectedProgramID)
            {
                return "Trocar para \(format.title)"
            }
            return "Trocar para \(entry.goal.displayName)"
        case .add:
            guard let entry = selectedEntry else {
                return "Escolha um objetivo"
            }
            return PlanWeekText.addTitle(entry.goal)
        }
    }

    // MARK: - Adicionar (M8)

    /// Um plano ativo, um objetivo diferente tocado e o planejador presente.
    private var canOfferAdd: Bool {
        guard
            mode != .firstUse,
            planner != nil,
            plans.activePrograms.count == 1,
            let active = plans.activeProgram,
            let selectedGoal,
            selectedGoal != active.effectiveGoal,
            selectedProgram != nil
        else {
            return false
        }
        return true
    }

    /// Na troca, o segundo botão "Adicionar X ao seu plano" (DESIGN §13).
    var showsAddButton: Bool {
        mode == .change && canOfferAdd
    }

    /// "Adicionar Cardio ao seu plano"; vazio sem objetivo tocado.
    var addTitle: String {
        selectedGoal.map { PlanWeekText.addTitle($0) } ?? ""
    }

    var canAdd: Bool {
        !hasFinished && !isSessionInProgress && canOfferAdd
    }

    /// O fluxo "O que muda" → "Seus dias" → "Sua semana" para o plano tocado. `nil` quando não dá para
    /// adicionar.
    func makeAddFlow() -> PlanFitFlowModel? {
        guard
            canAdd,
            let planner,
            let current = plans.activeProgram,
            let candidate = selectedProgram
        else {
            return nil
        }
        return PlanFitFlowModel(
            purpose: .addPlan(current: current, candidate: candidate),
            programs: programs,
            planner: planner,
            now: now,
            isSessionInProgress: isSessionInProgress
        )
    }

    /// O fluxo de adicionar gravou: a folha não grava mais nada.
    func finishAfterAdd() {
        hasFinished = true
    }

    /// Frase acima do botão (RF-45).
    var footnote: String {
        switch mode {
        case .change:
            return "Suas cargas ficam guardadas: cada exercício tem o próprio histórico. A próxima sessão aparece na tela Hoje."
        case .firstUse:
            return "A primeira sessão será o Dia A. Dá para trocar de objetivo depois, no topo da tela Hoje."
        case .add:
            return "Antes de adicionar, você vê o que muda e confere os seus dias."
        }
    }

    /// Prévia do primeiro dia do plano tocado, com os nomes dos exercícios na ordem. `nil` sem
    /// catálogo de exercícios ou sem nenhum nome conhecido.
    var preview: DayPreview? {
        guard
            let program = selectedProgram,
            !exerciseNames.isEmpty,
            let firstDay = program.days.min(by: { $0.order < $1.order })
        else {
            return nil
        }
        let names = firstDay.exercises
            .sorted { $0.order < $1.order }
            .compactMap { exerciseNames[$0.exerciseID] }
        guard !names.isEmpty else { return nil }
        return DayPreview(
            dayName: GoalPlanCatalog.shortDayName(firstDay.name),
            exercises: names.joined(separator: ", ") + "."
        )
    }

    /// Leitura do VoiceOver de uma linha: "Hipertrofia. Ganhar massa muscular. 3 ou 4 dias. Atual."
    func accessibilityText(for entry: GoalPlanCatalog.Entry) -> String {
        var parts = [entry.goal.displayName, entry.goal.subtitle, entry.dayCountText]
        if entry.isCurrent {
            parts.append("Atual")
        }
        return parts.joined(separator: ". ") + "."
    }

    // MARK: - Ações

    /// Botão principal. Com um plano ativo, uma única chamada a `activate(programID:)`; com dois, troca
    /// só o plano do objetivo tocado quando ele já está ativo (M8).
    func confirm() -> ConfirmOutcome {
        guard canConfirm, let programID = selectedProgramID else {
            return .refused
        }
        if isCurrentSelection {
            hasFinished = true
            return .unchanged
        }
        do {
            if let replaced = replacedProgram {
                try replaceActivePlan(replaced.id, with: programID)
            } else {
                try programs.activate(programID: programID)
            }
            hasFinished = true
            return .changed
        } catch {
            Self.logger.error("Goal change failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Não foi possível trocar o objetivo. Tente de novo."
            return .failed
        }
    }

    /// M8: tira o antigo e acrescenta o novo, nessa ordem. Se acrescentar falhar, tenta devolver o
    /// antigo, para a pessoa não ficar sem o plano que tinha.
    private func replaceActivePlan(_ oldID: UUID, with newID: UUID) throws {
        try programs.removeActivePlan(programID: oldID)
        do {
            try programs.addActivePlan(programID: newID)
        } catch {
            do {
                try programs.addActivePlan(programID: oldID)
            } catch let restoreError {
                Self.logger.error("Restoring plan failed: \(String(describing: restoreError), privacy: .public)")
            }
            throw error
        }
    }

    /// "Cancelar", "Pular" ou o gesto de fechar: nada é gravado.
    func markFinished() {
        hasFinished = true
    }
}
