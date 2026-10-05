import Foundation
import Observation
import os
import TrainerCore

/// Estado da aba Plano (SPEC RF-45, §7.15 M4, M8, M9; mockup "Plano"): os planos ativos (1 ou 2), cada
/// um com a semana dele para consultar (dias com os exercícios, o próximo marcado), a semana ideal com
/// dois planos ("Sua semana", `weekSchedule`) e se há sessão em andamento.
///
/// Lê programas pelo `ProgramRepositoring`, nomes pelo `CatalogRepositoring`, o próximo dia e a semana
/// pelo `SessionPlanning` (que não grava nada) e a sessão em andamento pelo `SessionCoordinating`. A única
/// escrita é "Tirar este plano" (`removeActivePlan`, M8), pelo repositório (AGENTS R4). O relógio chega
/// por `now` (SPEC P11).
@Observable
@MainActor
final class PlanTabModel {
    private(set) var plans = GoalPlanCatalog(programs: [])
    /// O dia que o planejador dá como o próximo de cada plano ativo (id do programa → id do dia).
    private(set) var nextDayIDs: [UUID: UUID] = [:]
    /// Com dois planos, a semana ideal (M4); `nil` com um plano, quando não cabem ou sem planejador.
    private(set) var weekSchedule: WeekSchedule?
    /// A leitura da semana falhou (fica só o aviso; os planos continuam visíveis).
    private(set) var didFailToLoadWeek = false
    private(set) var hasLoaded = false
    private(set) var didFailToLoad = false
    var errorMessage: String?

    private let programs: any ProgramRepositoring
    private let catalog: any CatalogRepositoring
    private let planner: (any SessionPlanning)?
    private let coordinator: (any SessionCoordinating)?
    private let now: () -> Date
    /// Nomes do catálogo inteiro, arquivados inclusive.
    private var exerciseNames: [UUID: String] = [:]

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "PlanTab"
    )

    init(
        programs: any ProgramRepositoring,
        catalog: any CatalogRepositoring,
        planner: (any SessionPlanning)?,
        coordinator: (any SessionCoordinating)?,
        now: @escaping () -> Date
    ) {
        self.programs = programs
        self.catalog = catalog
        self.planner = planner
        self.coordinator = coordinator
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

    /// Relê tudo. Chamado ao aparecer e depois das folhas "Seu objetivo" e "Seus dias".
    func refresh() {
        defer { hasLoaded = true }
        do {
            let all = try programs.allPrograms()
            plans = GoalPlanCatalog(programs: all)
            didFailToLoad = false
        } catch {
            plans = GoalPlanCatalog(programs: [])
            didFailToLoad = true
            Self.logger.error("Plan tab load failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Não foi possível carregar o plano."
        }
        loadExerciseNames()
        loadNextDays()
        loadWeek()
    }

    private func loadExerciseNames() {
        do {
            let everything = try catalog.allExercises(includeArchived: true)
            exerciseNames = Dictionary(everything.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        } catch {
            // Sem nomes, os cartões mostram só o nome do dia.
            exerciseNames = [:]
            Self.logger.error("Plan tab catalog load failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Com um plano, o `nextPlan(now:)` de sempre; com dois, o próximo de cada um (S8).
    private func loadNextDays() {
        guard let planner, let principal = activeProgram else {
            nextDayIDs = [:]
            return
        }
        let date = now()
        if activePrograms.count == 1 {
            do {
                if let plan = try planner.nextPlan(now: date), plan.programID == principal.id {
                    nextDayIDs = [principal.id: plan.programDayID]
                } else {
                    nextDayIDs = [:]
                }
            } catch {
                // Sem a marca "próxima"; a semana continua visível.
                nextDayIDs = [:]
                Self.logger.error("Plan tab next plan failed: \(String(describing: error), privacy: .public)")
            }
            return
        }
        var result: [UUID: UUID] = [:]
        for program in activePrograms {
            do {
                if let plan = try planner.nextPlan(forProgramID: program.id, now: date), plan.programID == program.id {
                    result[program.id] = plan.programDayID
                }
            } catch {
                Self.logger.error("Plan tab next plan of a plan failed: \(String(describing: error), privacy: .public)")
            }
        }
        nextDayIDs = result
    }

    /// "Sua semana" só existe com dois planos (M4).
    private func loadWeek() {
        guard let planner, hasTwoPlans else {
            weekSchedule = nil
            didFailToLoadWeek = false
            return
        }
        do {
            weekSchedule = try planner.weekSchedule(now: now())
            didFailToLoadWeek = false
        } catch {
            weekSchedule = nil
            didFailToLoadWeek = true
            Self.logger.error("Plan tab week failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Planos

    /// Os planos ativos na ordem de M1: o principal primeiro.
    var activePrograms: [ProgramTemplate] {
        plans.activePrograms
    }

    /// O plano principal.
    var activeProgram: ProgramTemplate? {
        plans.activeProgram
    }

    var goal: ProgramGoal? {
        activeProgram?.effectiveGoal
    }

    var activeGoals: [ProgramGoal] {
        plans.activeGoals
    }

    var hasTwoPlans: Bool {
        activePrograms.count >= 2
    }

    /// "Hipertrofia + Cardio" com dois planos; o objetivo com um.
    var titleText: String {
        activeGoals.joinedDisplayName
    }

    /// Dias do plano principal na ordem de `order` (SPEC S1).
    var days: [ProgramDayTemplate] {
        activeProgram.map { orderedDays(of: $0) } ?? []
    }

    /// Dias de um plano na ordem de `order` (SPEC S1).
    func orderedDays(of program: ProgramTemplate) -> [ProgramDayTemplate] {
        program.days.sorted { $0.order < $1.order }
    }

    /// Dia que o planejador marca como o próximo do plano principal.
    var nextDayID: UUID? {
        activeProgram.flatMap { nextDayIDs[$0.id] }
    }

    /// "3 dias por semana"; na Hipertrofia com formatos, "Mais pernas e glúteos · 4 dias por semana".
    var subtitle: String {
        activeProgram.map { planSubtitle(for: $0) } ?? GoalPlanCatalog.weeklyText(0)
    }

    /// Leitura do VoiceOver do subtítulo, sem o "·": "Mais pernas e glúteos, 4 dias por semana".
    var spokenSubtitle: String {
        activeProgram.map { spokenPlanSubtitle(for: $0) } ?? GoalPlanCatalog.weeklyText(0)
    }

    func planSubtitle(for program: ProgramTemplate) -> String {
        formattedSubtitle(for: program, separator: " · ")
    }

    func spokenPlanSubtitle(for program: ProgramTemplate) -> String {
        formattedSubtitle(for: program, separator: ", ")
    }

    private func formattedSubtitle(for program: ProgramTemplate, separator: String) -> String {
        let weekly = GoalPlanCatalog.weeklyText(program.days.count)
        if let format = plans.formatOfActive(program) {
            return "\(format.title)\(separator)\(weekly)"
        }
        return weekly
    }

    /// Com sessão em andamento, a folha abre com a troca bloqueada e "Tirar este plano" fica desligado.
    var isSessionInProgress: Bool {
        coordinator?.activeSession != nil
    }

    func isNext(_ day: ProgramDayTemplate) -> Bool {
        nextDayIDs.values.contains(day.id)
    }

    /// Nomes dos exercícios do dia, na ordem, separados por " · ". Vazio sem nomes conhecidos.
    func exerciseList(for day: ProgramDayTemplate) -> String {
        orderedExerciseNames(in: day).joined(separator: " · ")
    }

    /// Leitura do VoiceOver do cartão: "Dia A — Corpo todo. Próxima sessão. Agachamento, Supino."
    func accessibilityText(for day: ProgramDayTemplate) -> String {
        var parts = [day.name]
        if isNext(day) {
            parts.append("Próxima sessão")
        }
        let names = orderedExerciseNames(in: day)
        if !names.isEmpty {
            parts.append(names.joined(separator: ", "))
        }
        return parts.joined(separator: ". ") + "."
    }

    private func orderedExerciseNames(in day: ProgramDayTemplate) -> [String] {
        day.exercises
            .sorted { $0.order < $1.order }
            .compactMap { exerciseNames[$0.exerciseID] }
    }

    // MARK: - Sua semana (M4)

    /// Objetivo de cada plano ativo pelo id do programa.
    var goalsByProgramID: [UUID: ProgramGoal] {
        Dictionary(activePrograms.map { ($0.id, $0.effectiveGoal) }, uniquingKeysWith: { first, _ in first })
    }

    /// Seg a Dom, com o nome do dia de cada sessão e "descanso" nos livres. Vazio sem semana.
    var weekRows: [PlanWeekText.WeekRow] {
        guard let weekSchedule else { return [] }
        return PlanWeekText.weekRows(weekSchedule, goals: goalsByProgramID)
    }

    var weekNotes: [String] {
        guard let weekSchedule else { return [] }
        return PlanWeekText.notes(weekSchedule)
    }

    /// Com dois planos e sem semana: os planos não cabem mais nos dias escolhidos (M6).
    var showsNotFit: Bool {
        hasTwoPlans && planner != nil && !didFailToLoadWeek && weekSchedule == nil
    }

    // MARK: - Ações (M8, M9)

    /// "Adicionar um plano" só com um plano ativo e o planejador para conferir a semana.
    var canAddPlan: Bool {
        planner != nil && activePrograms.count == 1
    }

    /// "Tirar este plano" só com dois ativos e sem sessão em andamento (M8: nunca o último).
    var canRemovePlans: Bool {
        hasTwoPlans && !isSessionInProgress
    }

    /// "Seus dias" só com dois planos e o planejador.
    var canEditDays: Bool {
        planner != nil && hasTwoPlans
    }

    /// O plano que continua quando `program` sai.
    func remainingProgram(after program: ProgramTemplate) -> ProgramTemplate? {
        activePrograms.first { $0.id != program.id }
    }

    /// "Tirar este plano" (M8), depois da confirmação: uma escrita, `removeActivePlan`, e relê.
    @discardableResult
    func removePlan(programID: UUID) -> Bool {
        guard canRemovePlans, activePrograms.contains(where: { $0.id == programID }) else {
            return false
        }
        do {
            try programs.removeActivePlan(programID: programID)
        } catch {
            Self.logger.error("Removing plan failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Não foi possível tirar o plano. Tente de novo."
            return false
        }
        refresh()
        return true
    }

    /// "Seus dias": os dias e a semana, com a conferência antes de gravar (M9).
    func makeDaysFlow() -> PlanFitFlowModel? {
        guard canEditDays, let planner else {
            return nil
        }
        return PlanFitFlowModel(
            purpose: .editDays(programs: activePrograms),
            programs: programs,
            planner: planner,
            now: now,
            isSessionInProgress: isSessionInProgress
        )
    }
}
