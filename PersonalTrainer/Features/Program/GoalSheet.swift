import SwiftUI
import TrainerCore

/// Folha "Seu objetivo" (SPEC RF-45; DESIGN §13; mockup "Escolher o objetivo"): a flor grande,
/// os 5 objetivos na ordem das pétalas e, no tocado, os formatos (só Hipertrofia), a prévia do
/// Dia A, o "Por quê?" e, no Combate, o aviso de técnica (SPEC §7.9). O botão diz o que vai
/// acontecer ("Trocar para Hipertrofia").
///
/// Abre do topo da tela Hoje, da aba Plano (`.change`), no primeiro uso (`.firstUse`, dentro do
/// `OnboardingView`) e, desde a 2.3, pelo "Adicionar um plano" da aba Plano (`.add`). Tem a própria
/// `NavigationStack`. Só chama `onFinish`: quem apresenta fecha a folha. Toda escrita vai pelo
/// `GoalSheetModel` e pelo `PlanFitFlowModel`, que usam o `ProgramRepositoring` e o `SessionPlanning`
/// (AGENTS R4).
///
/// Vários planos (SPEC §7.15 M7, M8): com um plano ativo e outro objetivo tocado, dois botões, "Trocar
/// para X" e "Adicionar X ao seu plano"; com dois ativos, só "Trocar para X", com "O plano de Y também
/// sai." quando a troca tira os dois. "Adicionar" empurra o fluxo "O que muda", "Seus dias" e "Sua
/// semana" (`PlanFitFlowView`). Sem `planner`, a folha não oferece "Adicionar".
struct GoalSheet: View {
    enum Mode: Sendable, Hashable {
        /// Trocar de objetivo: "Cancelar" e "Trocar para …" (e "Adicionar …" com um plano ativo).
        case change
        /// Primeiro uso: "Começar" e "Pular", sem o gesto de fechar.
        case firstUse
        /// Adicionar um segundo plano (aba Plano): "Cancelar" e "Adicionar X ao seu plano".
        case add
    }

    @State private var model: GoalSheetModel
    /// O fluxo de adicionar, montado ao tocar "Adicionar X ao seu plano".
    @State private var addFlow: PlanFitFlowModel?
    @State private var isShowingAddFlow = false
    private let references: ReferenceCatalog
    private let isSessionInProgress: Bool
    private let onFinish: (_ didChange: Bool) -> Void

    /// DESIGN §13: "a flor grande".
    private static let largeFlowerSize: CGFloat = 92
    /// Flor pequena de cada linha, com a pétala daquele objetivo.
    private static let rowFlowerSize: CGFloat = 30

    init(
        programs: any ProgramRepositoring,
        catalog: (any CatalogRepositoring)?,
        references: ReferenceCatalog,
        mode: Mode = .change,
        isSessionInProgress: Bool = false,
        planner: (any SessionPlanning)? = nil,
        now: @escaping () -> Date = { Date() },
        onFinish: @escaping (_ didChange: Bool) -> Void
    ) {
        self.references = references
        self.isSessionInProgress = isSessionInProgress
        self.onFinish = onFinish
        self._model = State(initialValue: GoalSheetModel(
            programs: programs,
            catalog: catalog,
            mode: mode,
            isSessionInProgress: isSessionInProgress,
            planner: planner,
            now: now
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.mode == .firstUse {
                        firstUseHeader
                    }
                    FlowerView(activeGoals: model.flowerGoals, size: Self.largeFlowerSize)
                        .frame(maxWidth: .infinity)
                        // As linhas abaixo já dizem o objetivo escolhido.
                        .accessibilityHidden(true)
                    goalList
                }
                .padding(16)
            }
            .paperBackground()
            .safeAreaInset(edge: .bottom) {
                footer
            }
            // M8: "Adicionar X ao seu plano" empurra o fluxo curto nesta mesma pilha.
            .navigationDestination(isPresented: $isShowingAddFlow) {
                if let addFlow {
                    PlanFitFlowView(
                        model: addFlow,
                        references: references,
                        firstPageBackTitle: "Voltar",
                        onCancel: {
                            isShowingAddFlow = false
                        },
                        onDone: {
                            model.finishAfterAdd()
                            onFinish(true)
                        }
                    )
                }
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // `if` dentro do item (ViewBuilder), não em volta dele: evita depender de
                // `buildIf` no ToolbarContentBuilder.
                ToolbarItem(placement: .cancellationAction) {
                    if model.mode != .firstUse {
                        Button("Cancelar") {
                            finish(didChange: false)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.mode == .firstUse {
                        Button("Pular") {
                            finish(didChange: false)
                        }
                    }
                }
            }
            .alert("Não foi possível continuar", isPresented: $model.isPresentingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .tint(Theme.accent)
        // RF-45: no primeiro uso, toda saída passa por "Começar" ou "Pular".
        .interactiveDismissDisabled(model.mode == .firstUse)
        .onAppear {
            model.load()
        }
        .onChange(of: isSessionInProgress) { _, newValue in
            model.isSessionInProgress = newValue
            addFlow?.isSessionInProgress = newValue
        }
        // Fechar com o gesto na troca (ou ao adicionar) equivale a "Cancelar": `onFinish(false)` uma
        // vez só.
        .onDisappear {
            if model.mode != .firstUse && !model.hasFinished {
                model.markFinished()
                onFinish(false)
            }
        }
    }

    // MARK: - Partes

    /// "Seu objetivo" na troca; no primeiro uso o título grande fica no conteúdo.
    private var navigationTitleText: String {
        switch model.mode {
        case .change: return "Seu objetivo"
        case .firstUse: return ""
        case .add: return PlanWeekText.addPlanButton
        }
    }

    private var firstUseHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Qual é o seu objetivo?")
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("O objetivo define o seu plano: os dias e os exercícios de cada sessão.")
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var goalList: some View {
        if model.hasLoaded && model.didFailToLoad {
            Text("Não foi possível carregar os objetivos. Feche e tente de novo.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        VStack(spacing: 8) {
            ForEach(model.plans.entries) { entry in
                goalRow(entry)
            }
        }
    }

    /// Linha de um objetivo. O cabeçalho é um botão; formatos e "Por quê?" são botões separados,
    /// fora do rótulo dele (botões aninhados não funcionam no SwiftUI).
    private func goalRow(_ entry: GoalPlanCatalog.Entry) -> some View {
        let isSelected = model.selectedGoal == entry.goal
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                model.select(entry.goal)
            } label: {
                rowHeader(entry)
            }
            .buttonStyle(.plain)
            .disabled(!model.isSelectable(entry))
            .accessibilityLabel(Text(model.accessibilityText(for: entry)))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isSelected && entry.isAvailable {
                details(for: entry)
                    .padding(.leading, Self.rowFlowerSize + 12)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkCard(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Color.clear, lineWidth: 1.5)
        )
        .opacity(model.isSelectable(entry) ? 1 : 0.6)
    }

    private func rowHeader(_ entry: GoalPlanCatalog.Entry) -> some View {
        HStack(alignment: .center, spacing: 12) {
            FlowerView(activeGoal: entry.goal, size: Self.rowFlowerSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(entry.goal.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if entry.isCurrent {
                        Text("· atual")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(entry.goal.color)
                    }
                }
                Text(entry.goal.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(entry.dayCountText)
                .font(.footnote)
                .fontDesign(.rounded)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func details(for entry: GoalPlanCatalog.Entry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if entry.formats.count > 1 {
                ChipFlowLayout(spacing: 6) {
                    ForEach(entry.formats) { format in
                        formatChip(format)
                    }
                }
            }
            if let preview = model.preview {
                Text(preview.text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            WhyButton(topic: entry.goal.referenceTopic, catalog: references)
            if entry.goal == .combat {
                // SPEC §7.9: o app prepara o corpo, mas não ensina técnica de luta.
                Label(
                    "O app prepara o corpo para a luta, mas não ensina técnica. Técnica exige aula presencial.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func formatChip(_ format: GoalPlanCatalog.Format) -> some View {
        let isOn = format.id == model.selectedProgramID
        return Button {
            model.selectFormat(format.id)
        } label: {
            Text(GoalPlanCatalog.chipText(format))
                .font(.footnote.weight(isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Theme.accent : Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isOn ? Theme.accentSoft : Theme.background, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isOn ? Theme.accent : Theme.textSecondary.opacity(0.35), lineWidth: 1)
                )
                // Alvo de toque de 44 pt com o desenho menor (HIG).
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Formato: \(GoalPlanCatalog.spokenChipText(format))"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text(model.footnote)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let warning = model.changeWarning {
                // M8: com dois planos, trocar para um terceiro objetivo tira os dois.
                Text(warning)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.showsSessionBlock {
                Text(model.sessionBlockText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.mode == .add {
                Button {
                    openAddFlow()
                } label: {
                    Text(model.confirmTitle)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.primary)
                .disabled(!model.canAdd)
            } else {
                Button {
                    confirm()
                } label: {
                    Text(model.confirmTitle)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.primary)
                .disabled(!model.canConfirm)
                if model.showsAddButton {
                    addButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    /// Segundo botão da troca (M8): menos peso que o principal, com alvo de 44 pt.
    private var addButton: some View {
        Button {
            openAddFlow()
        } label: {
            Text(model.addTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canAdd)
        .opacity(model.canAdd ? 1 : 0.5)
    }

    // MARK: - Ações

    /// Monta o fluxo de adicionar para o objetivo tocado e o empurra na pilha da folha.
    private func openAddFlow() {
        guard let flow = model.makeAddFlow() else { return }
        addFlow = flow
        isShowingAddFlow = true
    }

    private func confirm() {
        switch model.confirm() {
        case .changed:
            onFinish(true)
        case .unchanged:
            onFinish(false)
        case .refused, .failed:
            break
        }
    }

    private func finish(didChange: Bool) {
        model.markFinished()
        onFinish(didChange)
    }
}
