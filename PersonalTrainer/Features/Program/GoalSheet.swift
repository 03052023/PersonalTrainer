import SwiftUI
import TrainerCore

/// Folha "Seu objetivo" (SPEC RF-45; DESIGN §13; mockup "Escolher o objetivo"): a flor grande,
/// os 5 objetivos na ordem das pétalas e, no tocado, os formatos (só Hipertrofia), a prévia do
/// Dia A, o "Por quê?" e, no Combate, o aviso de técnica (SPEC §7.9). O botão diz o que vai
/// acontecer ("Trocar para Hipertrofia").
///
/// Abre do topo da tela Hoje, da aba Plano (`.change`) e no primeiro uso (`.firstUse`, dentro do
/// `OnboardingView`). Tem a própria `NavigationStack`. Só chama `onFinish`: quem apresenta fecha
/// a folha. Toda escrita vai pelo `GoalSheetModel`, que usa o `ProgramRepositoring` (AGENTS R4).
struct GoalSheet: View {
    enum Mode: Sendable, Hashable {
        /// Trocar de objetivo: "Cancelar" e "Trocar para …".
        case change
        /// Primeiro uso: "Começar" e "Pular", sem o gesto de fechar.
        case firstUse
    }

    @State private var model: GoalSheetModel
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
        onFinish: @escaping (_ didChange: Bool) -> Void
    ) {
        self.references = references
        self.isSessionInProgress = isSessionInProgress
        self.onFinish = onFinish
        self._model = State(initialValue: GoalSheetModel(
            programs: programs,
            catalog: catalog,
            mode: mode,
            isSessionInProgress: isSessionInProgress
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.mode == .firstUse {
                        firstUseHeader
                    }
                    FlowerView(activeGoal: model.selectedGoal, size: Self.largeFlowerSize)
                        .frame(maxWidth: .infinity)
                        // As linhas abaixo já dizem o objetivo escolhido.
                        .accessibilityHidden(true)
                    goalList
                }
                .padding(16)
            }
            .background {
                Theme.background.ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom) {
                footer
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // `if` dentro do item (ViewBuilder), não em volta dele: evita depender de
                // `buildIf` no ToolbarContentBuilder.
                ToolbarItem(placement: .cancellationAction) {
                    if model.mode == .change {
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
        }
        // Fechar com o gesto na troca equivale a "Cancelar": `onFinish(false)` uma vez só.
        .onDisappear {
            if model.mode == .change && !model.hasFinished {
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
            .disabled(!entry.isAvailable)
            .accessibilityLabel(Text(model.accessibilityText(for: entry)))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isSelected && entry.isAvailable {
                details(for: entry)
                    .padding(.leading, Self.rowFlowerSize + 12)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent : Color.clear, lineWidth: 1.5)
        )
        .opacity(entry.isAvailable ? 1 : 0.6)
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
            if model.showsSessionBlock {
                Text("Termine a sessão em andamento para trocar.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                confirm()
            } label: {
                Text(model.confirmTitle)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.primary)
            .disabled(!model.canConfirm)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Theme.background)
    }

    // MARK: - Ações

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
