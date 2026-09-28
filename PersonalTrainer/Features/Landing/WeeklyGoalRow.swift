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
                WhyButton(topic: goal.referenceTopic, catalog: references)
            }
            Text(WeeklyGoalsText.valueText(goal))
                .font(.subheadline)
                .foregroundStyle(goal.hasData ? Theme.textPrimary : Theme.textSecondary)
            InkMarkView(progress: goal.fraction, tint: markTint, hasData: goal.hasData)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WeeklyGoalsText.accessibilityText(goal))
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
            goal: WeeklyGoal(kind: .balance, done: 0, target: 1, referenceTopic: "goal.longevity"),
            references: references
        )
    }
}
