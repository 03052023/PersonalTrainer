import SwiftUI
import TrainerCore

/// Topo da Home (DESIGN §9.1, §9.7; docs/V22-CONTRACT.md §3.3, §2.5): a flor com a pétala do objetivo
/// ativo preenchida, o nome do objetivo em New York, o subtítulo humano e a pílula "Trocar ›"
/// (sem objetivo, "Escolher ›"). O topo inteiro é um botão que abre "Seu objetivo" (SPEC RF-45);
/// nada fica acima disto.
///
/// Com dois planos (SPEC §7.15 M2, M6): a flor com as duas pétalas cheias e "Hipertrofia + Cardio", o
/// principal primeiro, sem subtítulo.
///
/// `onChangeGoal == nil` (o padrão do `init`, para quem ainda não liga a folha): o topo mostra o
/// objetivo, mas não é botão, e a pílula não aparece — não há ação nenhuma para prometer. Com o
/// fechamento presente, o botão fica desabilitado enquanto uma sessão está em andamento
/// (`isSessionInProgress`), porque trocar de objetivo no meio de uma sessão não teria efeito.
struct GoalHeaderView: View {
    /// Objetivos ativos, o principal primeiro. Vazio: nenhum objetivo escolhido.
    let goals: [ProgramGoal]
    let isSessionInProgress: Bool
    let onChangeGoal: (() -> Void)?

    /// DESIGN §9.1: "a flor (cerca de 56 pt)".
    static let flowerSize: CGFloat = 56

    init(
        goal: ProgramGoal?,
        isSessionInProgress: Bool = false,
        onChangeGoal: (() -> Void)? = nil
    ) {
        self.goals = goal.map { [$0] } ?? []
        self.isSessionInProgress = isSessionInProgress
        self.onChangeGoal = onChangeGoal
    }

    /// Vários planos (SPEC §7.15): uma pétala cheia por objetivo ativo.
    init(
        goals: [ProgramGoal],
        isSessionInProgress: Bool = false,
        onChangeGoal: (() -> Void)? = nil
    ) {
        self.goals = goals
        self.isSessionInProgress = isSessionInProgress
        self.onChangeGoal = onChangeGoal
    }

    /// O objetivo do plano principal.
    var goal: ProgramGoal? {
        goals.first
    }

    var body: some View {
        if let onChangeGoal {
            Button(action: onChangeGoal) {
                content(showsPill: true)
            }
            .buttonStyle(.plain)
            .disabled(isSessionInProgress)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(accessibilityText))
            .accessibilityHint(
                isSessionInProgress
                    ? Text("Termine a sessão em andamento para trocar de objetivo")
                    : Text("Toque duas vezes para trocar de objetivo")
            )
        } else {
            content(showsPill: false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(accessibilityText))
        }
    }

    private func content(showsPill: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            FlowerView(activeGoals: goals, size: Self.flowerSize)
                // O texto ao lado já diz o objetivo; o VoiceOver não precisa ouvi-lo duas vezes.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(titleText)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitleText {
                    Text(subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if showsPill {
                pill
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// "Hipertrofia"; "Hipertrofia + Cardio" com dois planos; "Magister" sem objetivo.
    private var titleText: String {
        guard !goals.isEmpty else {
            return "Magister"
        }
        return goals.joinedDisplayName
    }

    /// O subtítulo humano com um plano; nenhum com dois (o nome já diz os dois).
    private var subtitleText: String? {
        switch goals.count {
        case 0:
            return "Escolha um objetivo"
        case 1:
            return goals[0].subtitle
        default:
            return nil
        }
    }

    /// "Trocar ›" (`accentSoft` com texto `accent`); sem objetivo, "Escolher ›" (DESIGN §9.1).
    private var pill: some View {
        HStack(spacing: 3) {
            Text(goal == nil ? "Escolher" : "Trocar")
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.accentSoft, in: Capsule())
        .foregroundStyle(Theme.accent)
    }

    private var accessibilityText: String {
        switch goals.count {
        case 0:
            return "Nenhum objetivo ativo. Escolha um objetivo."
        case 1:
            return "Objetivo: \(goals[0].displayName). \(goals[0].subtitle)"
        default:
            return "Objetivos: \(goals.spokenDisplayName)."
        }
    }
}
