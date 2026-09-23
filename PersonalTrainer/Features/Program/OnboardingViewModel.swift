import Foundation
import Observation
import os
import TrainerCore

/// Estado do onboarding do primeiro launch (T2.21, RF-35; SPEC §7.9): passo 1 escolhe o objetivo,
/// passo 2 escolhe o programa daquele objetivo (ex.: os três formatos de hipertrofia) e "Começar"
/// o ativa pelo `ProgramRepositoring` (AGENTS R4).
///
/// Se nenhum programa pronto tem o objetivo escolhido, o programa ativo (ou o primeiro) é adaptado:
/// recebe o objetivo com os padrões aplicados (`setGoal(applyDefaults: true)`) e fica ativo.
/// A marca "onboarding concluído" é da view (`@AppStorage`), não daqui: nada vai ao SwiftData.
@Observable
@MainActor
final class OnboardingViewModel {
    enum Step: Equatable {
        case goal
        case program
    }

    private(set) var step: Step = .goal
    /// Todos os programas, na ordem do repositório (ativo primeiro).
    private(set) var programs: [ProgramTemplate] = []
    private(set) var selectedGoal: ProgramGoal?
    var selectedProgramID: UUID?
    private(set) var didFailToLoad = false
    var errorMessage: String?

    private let repository: any ProgramRepositoring

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "Onboarding"
    )

    init(programs: any ProgramRepositoring) {
        self.repository = programs
    }

    var isPresentingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
            }
        }
    }

    func load() {
        do {
            programs = try repository.allPrograms()
            didFailToLoad = false
        } catch {
            programs = []
            didFailToLoad = true
            Self.logger.error("Onboarding load failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Não foi possível carregar os programas."
        }
        preselectProgram()
    }

    // MARK: - Passos

    /// Passo 1 → 2. Pré-seleciona o programa ativo se ele for do objetivo, senão o primeiro.
    func chooseGoal(_ goal: ProgramGoal) {
        selectedGoal = goal
        selectedProgramID = nil
        preselectProgram()
        step = .program
    }

    func goBack() {
        step = .goal
    }

    func selectProgram(_ programID: UUID) {
        guard candidates.contains(where: { $0.id == programID }) else { return }
        selectedProgramID = programID
    }

    /// Programas prontos do objetivo escolhido (`effectiveGoal`: sem objetivo = hipertrofia).
    var candidates: [ProgramTemplate] {
        guard let selectedGoal else { return [] }
        return programs.filter { $0.effectiveGoal == selectedGoal }
    }

    /// Programa que será adaptado quando não há programa pronto para o objetivo.
    var adaptationBase: ProgramTemplate? {
        guard candidates.isEmpty else { return nil }
        return programs.first(where: \.isActive) ?? programs.first
    }

    /// SPEC §7.9: o app prepara o corpo, mas não ensina técnica de luta.
    var showsCombatNotice: Bool {
        selectedGoal == .combat
    }

    var canStart: Bool {
        guard selectedGoal != nil else { return false }
        if candidates.isEmpty {
            return adaptationBase != nil
        }
        guard let selectedProgramID else { return false }
        return candidates.contains { $0.id == selectedProgramID }
    }

    /// Ativa a escolha. Devolve `true` em sucesso; em falha a mensagem vai para `errorMessage`
    /// e o onboarding continua aberto.
    func start() -> Bool {
        guard let goal = selectedGoal else {
            errorMessage = "Escolha um objetivo."
            return false
        }
        do {
            if candidates.isEmpty {
                guard let base = adaptationBase else {
                    errorMessage = "Nenhum programa disponível para começar."
                    return false
                }
                try repository.setGoal(programID: base.id, goal: goal, applyDefaults: true)
                if !base.isActive {
                    try repository.activate(programID: base.id)
                }
            } else {
                guard
                    let selectedProgramID,
                    let chosen = candidates.first(where: { $0.id == selectedProgramID })
                else {
                    errorMessage = "Escolha um programa."
                    return false
                }
                // Reativar o que já está ativo não muda nada; evita uma escrita à toa.
                if !chosen.isActive {
                    try repository.activate(programID: chosen.id)
                }
            }
            return true
        } catch {
            Self.logger.error("Onboarding start failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Não foi possível ativar o programa. Tente de novo."
            return false
        }
    }

    private func preselectProgram() {
        let options = candidates
        if let selectedProgramID, options.contains(where: { $0.id == selectedProgramID }) {
            return
        }
        selectedProgramID = options.first(where: \.isActive)?.id ?? options.first?.id
    }
}
