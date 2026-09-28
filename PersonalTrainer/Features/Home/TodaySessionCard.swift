import SwiftUI
import TrainerCore

/// Um cartão da tela Hoje com dois planos (SPEC §7.15 M6; DESIGN §9.7):
/// - sessão por fazer: o `PlanCard` de sempre, com o objetivo no rótulo pequeno, o menu de dias daquele
///   plano, "5 exercícios · ≈ 55 min" (ou "30 min" no cardio) e as linhas; se não é a do botão
///   principal, "Começar esta", menor;
/// - feita hoje: "✓ Feito hoje" com "A seguir: …", compacto.
///
/// View pura: toques saem pelos fechamentos; quem planeja e começa é o `HomeViewModel`.
struct TodaySessionCard: View {
    let card: HomeTodayCard
    let references: ReferenceCatalog
    let canChooseDay: Bool
    let isHomeModeOn: Bool
    /// `nil` esconde o interruptor "Em casa" (ele fica só no primeiro cartão).
    let onToggleHomeMode: ((Bool) -> Void)?
    let onSelectDay: (UUID) -> Void
    let onSelectAutomatic: () -> Void
    let onSelectExercise: (PlannedExercise) -> Void
    /// "Começar esta" nos cartões que dá para começar e que não são o do botão principal.
    let onStart: () -> Void

    init(
        card: HomeTodayCard,
        references: ReferenceCatalog,
        canChooseDay: Bool,
        isHomeModeOn: Bool,
        onToggleHomeMode: ((Bool) -> Void)?,
        onSelectDay: @escaping (UUID) -> Void,
        onSelectAutomatic: @escaping () -> Void,
        onSelectExercise: @escaping (PlannedExercise) -> Void,
        onStart: @escaping () -> Void
    ) {
        self.card = card
        self.references = references
        self.canChooseDay = canChooseDay
        self.isHomeModeOn = isHomeModeOn
        self.onToggleHomeMode = onToggleHomeMode
        self.onSelectDay = onSelectDay
        self.onSelectAutomatic = onSelectAutomatic
        self.onSelectExercise = onSelectExercise
        self.onStart = onStart
    }

    var body: some View {
        if card.isDoneToday && !card.isStartable {
            doneCard
        } else {
            VStack(alignment: .leading, spacing: 10) {
                PlanCard(
                    plan: card.plan,
                    days: card.days,
                    selectedDayID: card.selectedDayID,
                    references: references,
                    canChooseDay: canChooseDay,
                    isHomeModeOn: isHomeModeOn,
                    onToggleHomeMode: onToggleHomeMode,
                    onSelectDay: onSelectDay,
                    onSelectAutomatic: onSelectAutomatic,
                    onSelectExercise: onSelectExercise,
                    customTitle: cardTitle,
                    customDetail: TodayPlansText.detailText(for: card.plan),
                    customDetailSpoken: TodayPlansText.detailSpokenText(for: card.plan)
                )
                if card.isStartable && !card.isPrimary {
                    startThisButton
                }
            }
        }
    }

    /// "Cardio"; "Cardio · feito hoje" quando a pessoa escolheu treinar de novo.
    private var cardTitle: String {
        if card.isDoneToday {
            return "\(card.goal.displayName) · feito hoje"
        }
        return card.goal.displayName
    }

    private var doneCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.goal.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
            Text(TodayPlansText.doneToday)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(TodayPlansText.upNext(card.plan))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(card.goal.displayName): feito hoje. \(TodayPlansText.upNext(card.plan))."))
    }

    /// Menor que o "Começar" principal (DESIGN §9.7), com alvo de 44 pt.
    private var startThisButton: some View {
        Button(action: onStart) {
            Text(TodayPlansText.startThis)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.accentSoft, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(card.plan.exercises.isEmpty)
        .accessibilityLabel(Text("Começar a sessão de \(card.goal.displayName)"))
    }
}
