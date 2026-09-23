import SwiftUI
import TrainerCore

/// Escolha do objetivo de um programa (T2.12, SPEC §7.9): os cinco objetivos com nome, uma
/// frase e o botão "Por quê?" com as referências do objetivo (RF-32).
///
/// Ao escolher um objetivo diferente do atual, pergunta se os padrões do objetivo devem ser
/// aplicados aos exercícios (faixa de repetições, RIR e descanso). A resposta vai para
/// `onChoose(goal, applyDefaults)` e a tela volta; quem grava é o `ProgramDetailViewModel`.
/// A pergunta mora aqui, e não na tela anterior, para o alerta não disputar a animação de volta.
struct GoalPickerView: View {
    private let selected: ProgramGoal
    private let references: ReferenceCatalog
    private let onChoose: (ProgramGoal, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingGoal: ProgramGoal? = nil
    @State private var isAskingToApplyDefaults = false

    init(
        selected: ProgramGoal,
        references: ReferenceCatalog,
        onChoose: @escaping (ProgramGoal, Bool) -> Void
    ) {
        self.selected = selected
        self.references = references
        self.onChoose = onChoose
    }

    var body: some View {
        List {
            Section {
                ForEach(ProgramGoal.allCases, id: \.self) { goal in
                    row(for: goal)
                }
            } footer: {
                Text("O objetivo define a faixa de repetições, o RIR alvo e o descanso sugeridos para os exercícios.")
            }
        }
        .navigationTitle("Objetivo")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Aplicar padrões do objetivo aos exercícios?",
            isPresented: $isAskingToApplyDefaults,
            presenting: pendingGoal
        ) { goal in
            Button("Aplicar") {
                choose(goal, applyDefaults: true)
            }
            Button("Manter") {
                choose(goal, applyDefaults: false)
            }
            Button("Cancelar", role: .cancel) {}
        } message: { goal in
            Text("Aplicar reescreve faixa de repetições, RIR e descanso de todos os exercícios conforme \(goal.displayName). Manter só troca o objetivo.")
        }
    }

    /// Linha com dois alvos de toque independentes: a escolha e o "Por quê?". O estilo
    /// `.borderless` impede a `List` de transformar a linha inteira num só botão.
    private func row(for goal: ProgramGoal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                select(goal)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.displayName)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(Self.summary(for: goal))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    if goal == selected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .accessibilityAddTraits(goal == selected ? .isSelected : [])

            WhyButton(topic: goal.referenceTopic, catalog: references)
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4)
    }

    private func select(_ goal: ProgramGoal) {
        if goal == selected {
            dismiss()
        } else {
            pendingGoal = goal
            isAskingToApplyDefaults = true
        }
    }

    private func choose(_ goal: ProgramGoal, applyDefaults: Bool) {
        pendingGoal = nil
        onChoose(goal, applyDefaults)
        dismiss()
    }

    // MARK: - Texto (pt-BR)

    /// Uma frase por objetivo, coerente com a tabela da SPEC §7.9. Também usada no onboarding.
    static func summary(for goal: ProgramGoal) -> String {
        switch goal {
        case .hypertrophy:
            return "Ganhar massa muscular: 6 a 15 repetições perto da falha e 10 a 20 séries por grupo na semana."
        case .strength:
            return "Levantar mais peso: 3 a 6 repetições com cargas altas e descansos longos."
        case .endurance:
            return "Aguentar mais repetições: 12 a 20 repetições com descansos curtos."
        case .longevity:
            return "Saúde e autonomia ao envelhecer: força 2 a 3 vezes por semana, somada a aeróbico, equilíbrio e mobilidade."
        case .combat:
            return "Preparo para luta e autodefesa: força máxima, potência, pegada e tronco. O app não ensina técnica."
        }
    }
}
