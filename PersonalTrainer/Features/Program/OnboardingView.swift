import SwiftUI
import TrainerCore

/// Onboarding do primeiro launch (T2.21, RF-35, SPEC §7.9): passo 1 escolhe o objetivo em cinco
/// cartões com "Por quê?"; passo 2 escolhe o programa daquele objetivo. "Começar" ativa a escolha;
/// "Pular" mantém o programa ativo atual. Os dois marcam `hasCompletedOnboarding` em
/// `@AppStorage` (UserDefaults, sem SwiftData) e chamam `onDone`.
///
/// Apresentado pelo integrador em `.sheet`; o gesto de dispensa fica desligado para que toda saída
/// passe por "Começar" ou "Pular" e a marca seja gravada.
struct OnboardingView: View {
    @State private var model: OnboardingViewModel
    private let references: ReferenceCatalog
    private let onDone: () -> Void

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init(programs: any ProgramRepositoring, references: ReferenceCatalog, onDone: @escaping () -> Void) {
        self.references = references
        self.onDone = onDone
        self._model = State(initialValue: OnboardingViewModel(programs: programs))
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.step {
                case .goal:
                    goalStep
                case .program:
                    programStep
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // `if` dentro do item (ViewBuilder), não em volta dele: evita depender de
                // `buildIf` no ToolbarContentBuilder.
                ToolbarItem(placement: .topBarLeading) {
                    if model.step == .program {
                        Button("Voltar") {
                            model.goBack()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Pular") {
                        finish()
                    }
                }
            }
            .alert("Não foi possível continuar", isPresented: $model.isPresentingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            model.load()
        }
    }

    // MARK: - Passo 1: objetivo

    private var goalStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Qual é o seu objetivo?")
                        .font(.largeTitle.weight(.bold))
                    Text("O objetivo define repetições, esforço e descanso do seu programa. Dá para trocar depois na aba Programa.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                ForEach(ProgramGoal.allCases, id: \.self) { goal in
                    goalCard(goal)
                }
            }
            .padding(16)
        }
    }

    /// Cartão com dois alvos de toque: o cartão escolhe; o "Por quê?" abre as referências.
    private func goalCard(_ goal: ProgramGoal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                model.chooseGoal(goal)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(goal.displayName)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(GoalPickerView.summary(for: goal))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            WhyButton(topic: goal.referenceTopic, catalog: references)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Passo 2: programa

    private var programStep: some View {
        List {
            Section {
                if let goal = model.selectedGoal {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Escolha o programa")
                            .font(.title2.weight(.bold))
                        Text("Objetivo: \(goal.displayName)")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                if model.showsCombatNotice {
                    Label(
                        "O app prepara o corpo para a luta, mas não ensina técnica. Técnica exige aula presencial.",
                        systemImage: "info.circle"
                    )
                    .font(.subheadline)
                }
            }

            if model.candidates.isEmpty {
                adaptationSection
            } else {
                Section {
                    ForEach(model.candidates, id: \.id) { program in
                        programRow(program)
                    }
                } footer: {
                    if model.candidates.count > 1 {
                        Text("Os formatos diferem em onde fica o volume maior; os demais grupos ficam em manutenção.")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            startButton
        }
    }

    private func programRow(_ program: ProgramTemplate) -> some View {
        let isSelected = model.selectedProgramID == program.id
        return Button {
            model.selectProgram(program.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(program.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    // Resumo só quando há mais de uma opção (ex.: formatos de hipertrofia, RF-35).
                    if model.candidates.count > 1, let summary = program.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Text(ProgramListViewModel.dayCountText(program.days.count))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Nenhum programa pronto para o objetivo: o atual é adaptado com os padrões do objetivo.
    @ViewBuilder
    private var adaptationSection: some View {
        Section {
            if let base = model.adaptationBase {
                VStack(alignment: .leading, spacing: 6) {
                    Text(base.name)
                        .font(.body.weight(.semibold))
                    Text("Ainda não há programa pronto para este objetivo. \"Começar\" adapta este programa: repetições, RIR e descanso passam a seguir o objetivo escolhido.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text("Nenhum programa disponível. Toque em Pular para continuar.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var startButton: some View {
        Button {
            if model.start() {
                finish()
            }
        } label: {
            Text("Começar")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!model.canStart)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func finish() {
        hasCompletedOnboarding = true
        onDone()
    }
}
