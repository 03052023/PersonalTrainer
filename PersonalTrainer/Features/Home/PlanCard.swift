import SwiftUI
import TrainerCore

/// Cartão "Sessão de hoje" da Home (SPEC F1, RF-01; DESIGN §9.2): dia em destaque (menu para
/// escolher outro dia, SPEC S4 / T2.14), nome do programa e número de exercícios, a faixa que diz
/// por que esta sessão (`PlanBanner`, CA4-5), selo do objetivo com o símbolo dele (DESIGN §8) e
/// "Por quê?" (SPEC §7.9, RF-32), e uma `PrescriptionRow` por exercício, na ordem do plano.
///
/// View pura: a escolha de dia sai pelos fechamentos e quem planeja é o `HomeViewModel`.
struct PlanCard: View {
    let plan: SessionPlan
    let days: [ProgramDayTemplate]
    /// `nil` = próximo da rotação; senão, o dia escolhido à mão.
    let selectedDayID: UUID?
    let goal: ProgramGoal?
    let references: ReferenceCatalog
    /// Falso com treino em andamento: o botão só retoma, então trocar o dia não teria efeito.
    let canChooseDay: Bool
    let onSelectDay: (UUID) -> Void
    let onSelectAutomatic: () -> Void

    init(
        plan: SessionPlan,
        days: [ProgramDayTemplate],
        selectedDayID: UUID?,
        goal: ProgramGoal?,
        references: ReferenceCatalog,
        canChooseDay: Bool = true,
        onSelectDay: @escaping (UUID) -> Void,
        onSelectAutomatic: @escaping () -> Void
    ) {
        self.plan = plan
        self.days = days
        self.selectedDayID = selectedDayID
        self.goal = goal
        self.references = references
        self.canChooseDay = canChooseDay
        self.onSelectDay = onSelectDay
        self.onSelectAutomatic = onSelectAutomatic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let banner = PlanBanner.make(for: plan) {
                bannerView(banner)
            }
            if plan.exercises.isEmpty {
                Text("Este dia não tem exercícios.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                exerciseList
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedDayID == nil ? "Sessão de hoje" : "Sessão escolhida")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            DayPickerMenu(
                dayName: plan.programDayName,
                days: days,
                selectedDayID: selectedDayID,
                isEnabled: canChooseDay,
                onSelectDay: onSelectDay,
                onSelectAutomatic: onSelectAutomatic
            )
            Text("\(plan.programName) · \(Self.exerciseCountText(plan.exercises.count))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let goal {
                goalBadge(goal)
                    .padding(.top, 4)
            }
        }
    }

    /// Selo do objetivo do programa (SPEC §7.9) com o símbolo e a cor dele (DESIGN §4, §8: nada
    /// de `target`) e o "Por quê?" do objetivo (RF-32).
    private func goalBadge(_ goal: ProgramGoal) -> some View {
        HStack(spacing: 8) {
            Label(goal.displayName, systemImage: goal.symbolName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(goal.color.opacity(0.15), in: Capsule())
                .foregroundStyle(goal.color)
                .accessibilityLabel(Text("Objetivo: \(goal.displayName)"))
            WhyButton(topic: goal.referenceTopic, catalog: references)
        }
    }

    /// Faixa calma em `accentSoft` (DESIGN §3, §9.3): semana leve e frequência fazem parte do
    /// plano, então nada de vermelho nem de tom de alerta.
    private func bannerView(_ banner: PlanBanner) -> some View {
        Label(banner.text, systemImage: banner.symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// "1 exercício", "5 exercícios".
    static func exerciseCountText(_ count: Int) -> String {
        count == 1 ? "1 exercício" : "\(count) exercícios"
    }

    private var exerciseList: some View {
        VStack(spacing: 0) {
            ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                if index > 0 {
                    Divider()
                }
                PrescriptionRow(exercise: exercise, references: references)
                    .padding(.vertical, 10)
            }
        }
    }
}
