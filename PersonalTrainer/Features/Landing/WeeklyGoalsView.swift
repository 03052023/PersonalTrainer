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
                titleBlock
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 4, trailing: 4))
            }

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
            }
            .listRowBackground(Theme.surface)

            if let musclesGoal {
                Section {
                    WeeklyGoalRow(goal: musclesGoal, references: references)
                    muscleGrid
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                ForEach(otherGoals, id: \.self) { goal in
                    WeeklyGoalRow(goal: goal, references: references)
                }
            } footer: {
                if showsHealthFooter {
                    Text("Aeróbico, passos e sono vêm do app Saúde.")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .paperBackground()
        // O título de verdade é o `titleBlock` (New York, no papel); a barra fica só com a volta.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { @MainActor [model] in
            await model.openWeeklyGoals()
        }
    }

    // MARK: - Peças

    /// Título "Metas da semana" em New York e o intervalo da semana em `textSecondary` (DESIGN §9.2).
    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Metas da semana")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(model.weekRangeText)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Os grupos com meta em duas colunas ("Peito 1 de 2"), com um ponto de tinta por vez feita
    /// (DESIGN §9.2).
    private var muscleGrid: some View {
        let entries = WeeklyFrequencyCard.visibleEntries(model.muscleFrequency)
        return LazyVGrid(
            columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
            spacing: 8
        ) {
            ForEach(entries, id: \.muscle) { entry in
                HStack(spacing: 6) {
                    muscleDots(entry)
                    Text(WeeklyGoalsText.muscleDetailText(entry))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 4)
    }

    /// Um ponto por vez da meta: cheio nas vezes feitas, vazio nas que faltam para a meta (sem passar
    /// de 5 pontos). Decorativo: o texto ao lado já diz "1 de 2".
    private func muscleDots(_ entry: WeeklyFrequencyEntry) -> some View {
        let slots = min(max(entry.target, entry.completed), 5)
        return HStack(spacing: 3) {
            ForEach(0..<slots, id: \.self) { index in
                Circle()
                    .fill(index < entry.completed ? Theme.inkMuted : Theme.line)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
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
}
