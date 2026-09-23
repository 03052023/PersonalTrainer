import SwiftUI
import TrainerCore

/// Card "Próximo treino" da Home (SPEC F1, RF-01): dia em destaque (menu para escolher outro
/// dia, SPEC S4 / T2.14), nome do programa, selo do objetivo com "Por quê?" (SPEC §7.9, RF-32)
/// e uma `PrescriptionRow` por exercício, na ordem do plano.
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
            Text(selectedDayID == nil ? "Próximo treino" : "Treino escolhido")
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
            Text(plan.programName)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let goal {
                goalBadge(goal)
                    .padding(.top, 4)
            }
        }
    }

    /// Selo do objetivo do programa (SPEC §7.9) com o "Por quê?" do objetivo (RF-32).
    private func goalBadge(_ goal: ProgramGoal) -> some View {
        HStack(spacing: 8) {
            Label(goal.displayName, systemImage: "target")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel(Text("Objetivo: \(goal.displayName)"))
            WhyButton(topic: goal.referenceTopic, catalog: references)
        }
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
