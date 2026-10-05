import SwiftUI
import TrainerCore

/// Uma linha das "Metas da semana" (SPEC RF-52, §7.16; DESIGN §9.2): nome, número em palavras,
/// "Por quê?" e a marca de tinta. Só leitura (W6): nada aqui muda o plano nem a prescrição.
struct WeeklyGoalRow: View {
    let goal: WeeklyGoal
    let references: ReferenceCatalog

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(WeeklyGoalsText.title(goal))
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                // Só reserva o lugar do botão real (do mesmo tamanho em qualquer tamanho de letra);
                // o botão que a pessoa toca é o do `overlay` abaixo.
                WhyButton(topic: goal.referenceTopic, catalog: references)
                    .hidden()
            }
            HStack(spacing: 6) {
                Text(WeeklyGoalsText.valueText(goal))
                    .font(.subheadline)
                    .foregroundStyle(goal.hasData ? Theme.textPrimary : Theme.textSecondary)
                // DESIGN §9.2: a meta cumprida fica com o traço inteiro e "✓".
                if goal.isMet {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.inkMuted)
                }
            }
            InkMarkView(progress: goal.fraction, tint: markTint, hasData: goal.hasData)
        }
        // RF-52 ponto 6: a linha é um elemento só ("Hipertrofia: 3 de 4 sessões nesta semana"); a
        // marca é decorativa.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WeeklyGoalsText.accessibilityText(goal))
        // O overlay vem depois do `.ignore`: o "Por quê?" continua sendo um elemento próprio do
        // VoiceOver, e não some junto com o texto da linha.
        .overlay(alignment: .topTrailing) {
            WhyButton(topic: goal.referenceTopic, catalog: references)
        }
        .padding(.vertical, 4)
    }

    /// As sessões de cada plano usam a cor do objetivo dele (DESIGN §9.2); o resto, `inkMuted`.
    private var markTint: Color {
        guard goal.kind == .planSessions, let planGoal = goal.planGoal else {
            return Theme.inkMuted
        }
        return planGoal.color
    }
}

#Preview("WeeklyGoalRow") {
    let references = ReferenceCatalog.empty
    return List {
        WeeklyGoalRow(
            goal: WeeklyGoal(
                kind: .planSessions, planGoal: .hypertrophy, done: 3, target: 4, referenceTopic: "goal.hypertrophy"
            ),
            references: references
        )
        WeeklyGoalRow(
            goal: WeeklyGoal(kind: .muscles, done: 6, target: 10, referenceTopic: "topic.frequency"),
            references: references
        )
        WeeklyGoalRow(
            goal: WeeklyGoal(kind: .aerobic, done: nil, target: 150, referenceTopic: "topic.aerobic"),
            references: references
        )
        WeeklyGoalRow(
            goal: WeeklyGoal(kind: .balance, done: 1, target: 2, referenceTopic: "goal.longevity"),
            references: references
        )
    }
}
