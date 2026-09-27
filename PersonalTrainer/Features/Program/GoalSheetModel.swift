import Foundation
import Observation
import os
import TrainerCore

/// Estado da folha "Seu objetivo" (SPEC RF-45; DESIGN §13): os 5 objetivos do `GoalPlanCatalog`,
/// o objetivo e o formato tocados, a prévia do Dia A e a troca.
///
/// Trocar é uma única escrita, `ProgramRepositoring.activate` (S2 recomeça no Dia A; P3 é por
/// exercício, então as cargas ficam). Nada aqui chama `setGoal`, renomeia, duplica ou apaga
/// (AGENTS R4: a escrita vai só pelo repositório).
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
    /// Com sessão em andamento a troca fica bloqueada (RF-45).
    var isSessionInProgress: Bool
    private(set) var plans = GoalPlanCatalog(programs: [])
    private(set) var selectedGoal: ProgramGoal?
    private(set) var selectedProgramID: UUID?
    private(set) var hasLoaded = false
    private(set) var didFailToLoad = false
    /// Verdadeiro depois de trocar, cancelar ou pular: a folha não grava de novo.
    private(set) var hasFinished = false
    var errorMessage: String?

    private let programs: any ProgramRepositoring
    private let exerciseCatalog: (any CatalogRepositoring)?
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
        isSessionInProgress: Bool
    ) {
        self.programs = programs
        self.exerciseCatalog = catalog
        self.mode = mode
        self.isSessionInProgress = isSessionInProgress
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
    /// objetivo e no programa ativos.
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
            entry.programIDs.contains(programID)
        {
            return
        }
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

    // MARK: - Escolha

    /// Toca num objetivo. Tocar de novo no mesmo mantém o formato escolhido; objetivo sem plano
    /// pronto não é escolhível.
    func select(_ goal: ProgramGoal) {
        guard !hasFinished, goal != selectedGoal else { return }
        guard let entry = plans.entry(for: goal), let programID = entry.defaultProgramID else { return }
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

    /// A escolha é o programa que já está ativo.
    var isCurrentSelection: Bool {
        guard let selectedProgramID, let active = plans.activeProgram else { return false }
        return selectedProgramID == active.id
    }

    /// Mostra "Termine a sessão em andamento para trocar." embaixo do botão.
    var showsSessionBlock: Bool {
        isSessionInProgress && !(mode == .firstUse && isCurrentSelection)
    }

    /// RF-45: "Trocar" desabilitado quando a escolha é a atual ou com sessão em andamento. No
    /// primeiro uso, "Começar" também vale para a escolha atual (não grava nada).
    var canConfirm: Bool {
        guard !hasFinished, selectedProgram != nil else { return false }
        switch mode {
        case .change:
            return !isSessionInProgress && !isCurrentSelection
        case .firstUse:
            return isCurrentSelection || !isSessionInProgress
        }
    }

    /// "Trocar para Hipertrofia"; "Trocar para Mais pernas e glúteos" quando só muda o formato;
    /// "Começar" no primeiro uso.
    var confirmTitle: String {
        switch mode {
        case .firstUse:
            return "Começar"
        case .change:
            guard let entry = selectedEntry else {
                return "Escolha um objetivo"
            }
            if
                entry.goal == plans.activeGoal,
                !isCurrentSelection,
                entry.formats.count > 1,
                let format = entry.format(id: selectedProgramID)
            {
                return "Trocar para \(format.title)"
            }
            return "Trocar para \(entry.goal.displayName)"
        }
    }

    /// Frase acima do botão (RF-45).
    var footnote: String {
        switch mode {
        case .change:
            return "Suas cargas ficam guardadas: cada exercício tem o próprio histórico. A próxima sessão será o Dia A."
        case .firstUse:
            return "A primeira sessão será o Dia A. Dá para trocar de objetivo depois, no topo da tela Hoje."
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

    /// Botão principal. Troca = uma única chamada a `activate(programID:)`.
    func confirm() -> ConfirmOutcome {
        guard canConfirm, let programID = selectedProgramID else {
            return .refused
        }
        if isCurrentSelection {
            hasFinished = true
            return .unchanged
        }
        do {
            try programs.activate(programID: programID)
            hasFinished = true
            return .changed
        } catch {
            Self.logger.error("Goal change failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Não foi possível trocar o objetivo. Tente de novo."
            return .failed
        }
    }

    /// "Cancelar", "Pular" ou o gesto de fechar: nada é gravado.
    func markFinished() {
        hasFinished = true
    }
}
