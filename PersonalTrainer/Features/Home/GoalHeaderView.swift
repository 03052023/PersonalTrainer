import SwiftUI
import TrainerCore

/// Topo da Home (DESIGN §9.1): a flor com a pétala do objetivo ativo preenchida, o nome do
/// objetivo em New York e o subtítulo humano ("Ficar mais forte"). Nada fica acima disto.
///
/// Sem programa ativo, a flor aparece só em contorno e o texto convida a escolher um objetivo.
struct GoalHeaderView: View {
    let goal: ProgramGoal?

    /// DESIGN §9.1: "a flor (cerca de 56 pt)".
    static let flowerSize: CGFloat = 56

    init(goal: ProgramGoal?) {
        self.goal = goal
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            FlowerView(activeGoal: goal, size: Self.flowerSize)
                // O texto ao lado já diz o objetivo; o VoiceOver não precisa ouvi-lo duas vezes.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal?.displayName ?? "Magister")
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(goal?.subtitle ?? "Escolha um objetivo na aba Programa.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(accessibilityText))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityText: String {
        guard let goal else {
            return "Nenhum objetivo ativo. Escolha um objetivo na aba Programa."
        }
        return "Objetivo ativo: \(goal.displayName). \(goal.subtitle)"
    }
}
