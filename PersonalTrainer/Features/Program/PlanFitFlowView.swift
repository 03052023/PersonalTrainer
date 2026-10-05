import SwiftUI
import TrainerCore

/// As páginas do fluxo da semana com dois planos (SPEC §7.15 M4, M5, M7, M9; DESIGN §13):
/// (a) "O que muda": a flor com os dois objetivos, os grupos "Ganha", "Fica igual" e "Custa", cada frase
///     com "Por quê?", e o aviso de grande sobreposição (M7);
/// (b) "Seus dias": os dias de segunda a domingo e, só com um plano de Cardio e outro que não é, as duas
///     chaves (M9, B9);
/// (c) "Sua semana": se cabe, a semana e o botão principal; se não, o motivo e as saídas, cada uma com a
///     semana dela e "Escolher esta" (M5).
///
/// Uma tela só, com a página em `PlanFitFlowModel.page`: o botão de voltar do topo volta uma página e, na
/// primeira, chama `onCancel` (quem apresenta fecha ou volta à lista de objetivos). `onDone` vem depois de
/// gravar. Toda escrita vai pelo modelo (AGENTS R4).
struct PlanFitFlowView: View {
    @Bindable private var model: PlanFitFlowModel
    private let references: ReferenceCatalog
    /// "Voltar" quando o fluxo foi empurrado da folha "Seu objetivo"; "Cancelar" quando é a raiz.
    private let firstPageBackTitle: String
    private let onCancel: () -> Void
    private let onDone: () -> Void

    private static let flowerSize: CGFloat = 56

    init(
        model: PlanFitFlowModel,
        references: ReferenceCatalog,
        firstPageBackTitle: String = "Voltar",
        onCancel: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.model = model
        self.references = references
        self.firstPageBackTitle = firstPageBackTitle
        self.onCancel = onCancel
        self.onDone = onDone
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                pageContent
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .paperBackground()
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .navigationTitle(model.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(model.isFirstPage ? firstPageBackTitle : "Voltar") {
                    goBack()
                }
            }
        }
        .alert("Não foi possível continuar", isPresented: $model.isPresentingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Páginas

    @ViewBuilder
    private var pageContent: some View {
        switch model.page {
        case .consequences:
            consequencesPage
        case .days:
            daysPage
        case .week:
            weekPage
        }
    }

    /// (a) "O que muda" (M7).
    private var consequencesPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 14) {
                FlowerView(activeGoals: model.goals, size: Self.flowerSize)
                    .accessibilityHidden(true)
                Text(model.goals.joinedDisplayName)
                    .font(.system(.title2, design: .serif, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(model.goals.spokenDisplayName))
                    .accessibilityAddTraits(.isHeader)
            }
            if model.showsOverlapWarning {
                Label(PlanWeekText.overlapWarning, systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            ForEach(model.consequenceGroups) { group in
                consequenceGroup(group)
            }
        }
    }

    private func consequenceGroup(_ group: PlanFitFlowModel.ConsequenceGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(group.title)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                consequenceRow(item)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkCard()
    }

    /// Frase com o sinal (+, =, −) e o "Por quê?" do tópico, fora do rótulo de outro botão.
    private func consequenceRow(_ item: PlanConsequence) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(PlanWeekText.sign(item.kind))
                .font(.body.weight(.semibold))
                .fontDesign(.rounded)
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 14, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                WhyButton(topic: item.referenceTopic, catalog: references)
            }
        }
    }

    /// (b) "Seus dias" (M9).
    private var daysPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(PlanWeekText.daysQuestion)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                ChipFlowLayout(spacing: 8) {
                    ForEach(PlanWeekday.allCases, id: \.self) { day in
                        dayChip(day)
                    }
                }
            }
            // B9 (2.4): as duas chaves só com um plano de Cardio e outro que não é; com dois planos de
            // força elas nada mudariam.
            if model.showsDayToggles {
                VStack(alignment: .leading, spacing: 14) {
                    toggleRow(
                        title: PlanWeekText.twoSessionsToggle,
                        hint: PlanWeekText.twoSessionsHint,
                        isOn: $model.allowsTwoSessionsPerDay
                    )
                    Divider()
                    toggleRow(
                        title: PlanWeekText.lightCardioToggle,
                        hint: PlanWeekText.lightCardioHint,
                        isOn: $model.allowsLightCardioAfterStrength
                    )
                }
                .padding(14)
                .inkCard()
            }
        }
    }

    private func dayChip(_ day: PlanWeekday) -> some View {
        let isOn = model.isAvailable(day)
        return Button {
            model.toggle(day)
        } label: {
            Text(day.shortName)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Theme.accent : Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isOn ? Theme.accentSoft : Theme.surface, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isOn ? Theme.accent : Theme.line, lineWidth: 1)
                )
                // Alvo de toque de 44 pt com o desenho menor (HIG).
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.name))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggleRow(title: String, hint: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Theme.accent)
    }

    /// (c) "Sua semana" (M4, M5).
    @ViewBuilder
    private var weekPage: some View {
        if model.didFailToCheck {
            Text(PlanWeekText.checkFailed)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if model.fits {
            VStack(alignment: .leading, spacing: 12) {
                Text(PlanWeekText.fitsText)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !model.weekRows.isEmpty {
                    WeekScheduleView(rows: model.weekRows, notes: model.weekNotes)
                        .padding(14)
                        .inkCard()
                }
            }
        } else if model.result != nil {
            notFittingWeek
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
    }

    private var notFittingWeek: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let problem = model.problemText {
                Text(problem)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.showsNoAlternative {
                Text(PlanWeekText.noAlternative)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(PlanWeekText.alternativesTitle)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(model.alternatives.enumerated()), id: \.offset) { _, alternative in
                    alternativeCard(alternative)
                }
            }
        }
    }

    private func alternativeCard(_ alternative: FitAlternative) -> some View {
        let goals = model.goalsByProgramID
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(PlanWeekText.changes(of: alternative, goals: goals).enumerated()), id: \.offset) { _, change in
                    Text(change)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(PlanWeekText.spokenChanges(of: alternative, goals: goals)))
            WeekScheduleView(
                rows: PlanWeekText.weekRows(alternative.schedule, goals: goals),
                notes: PlanWeekText.notes(alternative.schedule)
            )
            Button {
                choose(alternative)
            } label: {
                Text(PlanWeekText.chooseAlternative)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.accentSoft, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canChooseAlternative)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkCard()
    }

    // MARK: - Rodapé

    @ViewBuilder
    private var footer: some View {
        switch model.page {
        case .consequences, .days:
            footerButton(title: "Continuar", isEnabled: model.canContinue) {
                model.next()
            }
        case .week:
            if model.didFailToCheck {
                footerButton(title: "Tentar de novo", isEnabled: true) {
                    model.checkFit()
                }
            } else if model.fits {
                footerButton(title: model.confirmTitle, isEnabled: model.canConfirm) {
                    confirm()
                }
            }
        }
    }

    private func footerButton(title: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            if model.page == .week && model.isSessionInProgress && model.candidate != nil {
                Text("Termine a sessão em andamento para adicionar.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: action) {
                Text(title)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.primary)
            .disabled(!isEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    // MARK: - Ações

    private func goBack() {
        if !model.back() {
            onCancel()
        }
    }

    private func confirm() {
        if model.confirm() == .saved {
            onDone()
        }
    }

    private func choose(_ alternative: FitAlternative) {
        if model.choose(alternative) == .saved {
            onDone()
        }
    }
}
