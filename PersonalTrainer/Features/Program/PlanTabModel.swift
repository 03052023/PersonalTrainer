import Foundation
import Observation
import os
import TrainerCore

/// Estado da aba Plano (SPEC RF-45; mockup "Plano"): o plano do objetivo ativo, a semana inteira
/// para consultar (dias com os exercícios, o próximo marcado) e se há sessão em andamento.
///
/// Só lê: programas pelo `ProgramRepositoring`, nomes pelo `CatalogRepositoring`, o próximo dia
/// pelo `SessionPlanning.nextPlan(now:)` (que não grava nada) e a sessão em andamento pelo
/// `SessionCoordinating`. O relógio chega por `now` (SPEC P11).
@Observable
@MainActor
final class PlanTabModel {
    private(set) var plans = GoalPlanCatalog(programs: [])
    /// Dia que `nextPlan(now:)` escolheu, se for do programa ativo.
    private(set) var nextDayID: UUID?
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

    /// Relê tudo. Chamado ao aparecer e depois da folha "Seu objetivo".
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
        loadNextDay()
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

    private func loadNextDay() {
        guard let planner, let active = activeProgram else {
            nextDayID = nil
            return
        }
        do {
            let plan = try planner.nextPlan(now: now())
            if let plan, plan.programID == active.id {
                nextDayID = plan.programDayID
            } else {
                nextDayID = nil
            }
        } catch {
            // Sem a marca "próxima"; a semana continua visível.
            nextDayID = nil
            Self.logger.error("Plan tab next plan failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Para a tela

    var activeProgram: ProgramTemplate? {
        plans.activeProgram
    }

    var goal: ProgramGoal? {
        activeProgram?.effectiveGoal
    }

    /// Dias na ordem de `order` (SPEC S1).
    var days: [ProgramDayTemplate] {
        (activeProgram?.days ?? []).sorted { $0.order < $1.order }
    }

    /// "3 dias por semana"; na Hipertrofia com formatos, "Mais pernas e glúteos · 4 dias por semana".
    var subtitle: String {
        formattedSubtitle(separator: " · ")
    }

    /// Leitura do VoiceOver do subtítulo, sem o "·": "Mais pernas e glúteos, 4 dias por semana".
    var spokenSubtitle: String {
        formattedSubtitle(separator: ", ")
    }

    private func formattedSubtitle(separator: String) -> String {
        let weekly = GoalPlanCatalog.weeklyText(activeProgram?.days.count ?? 0)
        if let format = plans.activeFormat {
            return "\(format.title)\(separator)\(weekly)"
        }
        return weekly
    }

    /// Com sessão em andamento, a folha abre com a troca bloqueada.
    var isSessionInProgress: Bool {
        coordinator?.activeSession != nil
    }

    func isNext(_ day: ProgramDayTemplate) -> Bool {
        day.id == nextDayID
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
}
