import SwiftUI
import TrainerCore

/// "Metas da semana" (SPEC RF-52, §7.16; DESIGN §9.2): sessões de cada plano, músculos, aeróbico,
/// passos (só com Longevidade ou Cardio, W7), sono e, com a Longevidade ativa, equilíbrio e
/// mobilidade. Só leitura (W6): nada aqui muda o plano nem a prescrição, e a tela nunca pede
/// permissão ao Saúde (AGENTS §7) — só relê o que `LandingViewModel.openWeeklyGoals()` já leu.
struct WeeklyGoalsView: View {
    @Bindable var model: LandingViewModel
    let references: ReferenceCatalog

    var body: some View {
        List {
            Section {
                if sessionGoals.isEmpty {
                    Text("Escolha um objetivo para ter metas de treino.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(sessionGoals, id: \.self) { goal in
                        WeeklyGoalRow(goal: goal, references: references)
                    }
                }
            } header: {
                Text(weekRangeText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(nil)
            }

            if let musclesGoal {
                Section {
                    WeeklyGoalRow(goal: musclesGoal, references: references)
                    muscleGrid
                }
            }

            Section {
                ForEach(otherGoals, id: \.self) { goal in
                    WeeklyGoalRow(goal: goal, references: references)
                }
            } footer: {
                if showsHealthFooter {
                    Text("Aeróbico, passos e sono vêm do app Saúde.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Metas da semana")
        .task { @MainActor [model] in
            await model.openWeeklyGoals()
        }
    }

    // MARK: - Peças

    private var muscleGrid: some View {
        let entries = WeeklyFrequencyCard.visibleEntries(model.muscleFrequency)
        return LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
            spacing: 8
        ) {
            ForEach(entries, id: \.muscle) { entry in
                HStack(spacing: 4) {
                    Circle()
                        .fill(entry.completed >= entry.target ? Theme.inkMuted : Theme.line)
                        .frame(width: 6, height: 6)
                    Text(WeeklyGoalsText.muscleDetailText(entry))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Dados derivados

    private var sessionGoals: [WeeklyGoal] {
        model.weeklyGoals.filter { $0.kind == .planSessions }
    }

    private var musclesGoal: WeeklyGoal? {
        model.weeklyGoals.first { $0.kind == .muscles }
    }

    private var otherGoals: [WeeklyGoal] {
        model.weeklyGoals.filter { $0.kind != .planSessions && $0.kind != .muscles }
    }

    /// W4: quando alguma meta de Saúde não tem dado, o rodapé explica de onde ele viria.
    private var showsHealthFooter: Bool {
        model.weeklyGoals.contains {
            ($0.kind == .aerobic || $0.kind == .steps || $0.kind == .sleep) && !$0.hasData
        }
    }

    /// "22 set. – 28 set." (mesmo formato de `WeeklyFrequencyCard.weekRangeText`, DESIGN §9.2).
    private var weekRangeText: String {
        WeeklyFrequencyCard.weekRangeText(model.muscleFrequency, calendar: .autoupdatingCurrent)
    }
}
