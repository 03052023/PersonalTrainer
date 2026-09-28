import SwiftUI
import TrainerCore

/// Aba "Hoje" (SPEC F1, RF-01, RF-45, RF-46, §7.11; DESIGN §9), de cima para baixo:
/// 1. o objetivo ativo, que é um botão (flor, nome em New York e subtítulo, pílula "Trocar ›");
///    abre "Seu objetivo" por `onChangeGoal` (SPEC RF-45), desabilitado com sessão em andamento;
/// 2. o cartão "Hoje": o dia (menu para escolher outro), "5 exercícios · ≈ 55 min" com a chave
///    "Em casa" na mesma linha, e as faixas de motivo e de modo casa só quando existem;
/// 3. o botão principal "Começar" / "Retomar", o único proeminente da tela;
/// 4. só a primeira mensagem do diálogo (SPEC §7.11), com "Ver todas (N)" quando há mais;
/// 5. o cartão de Saúde, sem as sugestões (elas já aparecem no diálogo, C3).
///
/// A Home não conhece `ActiveSessionView` (TASKS T1.4): devolve o `uuid` da sessão em
/// `onOpenSession` e o `RootView` decide para onde navegar. ViewModels, diálogo e referências
/// chegam por `init`; nada aqui lê o `AppEnvironment` do ambiente nem escreve no `ModelContext`
/// (AGENTS R4).
struct HomeView: View {
    @Bindable private var model: HomeViewModel
    private let coach: CoachService
    private let health: HealthViewModel
    private let references: ReferenceCatalog
    private let onOpenSession: (UUID) -> Void
    /// `nil`: o topo mostra o objetivo, mas não é botão (docs/V22-CONTRACT.md §2.5).
    private let onChangeGoal: (() -> Void)?

    @State private var infoContent: ExerciseInfoContent?

    @Environment(\.exerciseTraits) private var traits

    init(
        model: HomeViewModel,
        coach: CoachService,
        health: HealthViewModel,
        references: ReferenceCatalog,
        onOpenSession: @escaping (UUID) -> Void,
        onChangeGoal: (() -> Void)? = nil
    ) {
        self.model = model
        self.coach = coach
        self.health = health
        self.references = references
        self.onOpenSession = onOpenSession
        self.onChangeGoal = onChangeGoal
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GoalHeaderView(
                        goal: model.goal,
                        isSessionInProgress: model.isSessionInProgress,
                        onChangeGoal: onChangeGoal
                    )
                    content
                    primaryButton
                    coachSection
                    // O cartão já abre `HealthDetailView` por `NavigationLink` quando há dados.
                    HealthCardView(model: health, references: references, showsSuggestions: false)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
            // Fechamento isolado ao MainActor e capturando só os ViewModels (classes @MainActor,
            // portanto Sendable): a struct da view não precisa cruzar a fronteira do @Sendable.
            // Puxar para baixo também relê o Saúde (a mensagem de falha do cartão pede isso).
            .refreshable { @MainActor [model, health] in
                model.refresh()
                await health.load()
            }
            // DESIGN §9.1: nada acima do objetivo. O título fica para o botão de voltar das telas
            // abertas daqui; a aba já diz "Hoje".
            .background(Theme.background)
            .navigationTitle("Hoje")
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                model.refresh()
            }
            .alert("Não foi possível continuar", isPresented: $model.isPresentingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
            .sheet(item: $infoContent) { info in
                ExerciseInfoSheet(content: info, references: references)
            }
        }
    }

    /// A falha de leitura fica visível mesmo depois de o alerta ser fechado (`didFailToLoad`
    /// não depende de `errorMessage`): "sem programa" e "não carregou" são estados distintos.
    @ViewBuilder
    private var content: some View {
        if let plan = model.plan {
            PlanCard(
                plan: plan,
                days: model.days,
                selectedDayID: model.selectedDayID,
                references: references,
                canChooseDay: !model.isSessionInProgress,
                isHomeModeOn: model.isHomeMode,
                onToggleHomeMode: { enabled in
                    model.setHomeMode(enabled)
                },
                onSelectDay: { dayID in
                    model.selectDay(dayID)
                },
                onSelectAutomatic: {
                    model.selectAutomaticDay()
                },
                onSelectExercise: { exercise in
                    infoContent = model.infoContent(for: exercise, measure: measure(for: exercise))
                }
            )
        } else if model.didFailToLoad {
            ContentUnavailableView(
                "Não foi possível carregar a sessão",
                systemImage: "exclamationmark.triangle",
                description: Text("Puxe para baixo para tentar de novo.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            // SPEC RF-45: objetivo = plano; sem objetivo ativo, o convite é escolher um.
            ContentUnavailableView(
                "Escolha um objetivo",
                systemImage: "sun.max",
                description: Text("Toque em Escolher, no topo, para ver a próxima sessão.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        }
    }

    /// Só a primeira mensagem (DESIGN §9.4); com mais de uma, "Ver todas (N)" empurra a mesma
    /// `CoachFeedSection` inteira dentro desta `NavigationStack`.
    @ViewBuilder
    private var coachSection: some View {
        // Fechamentos literais (não referências a método): uma referência a método
        // @MainActor perde o ator na conversão para o tipo do parâmetro.
        CoachFeedSection(
            messages: Array(coach.messages.prefix(1)),
            references: references,
            onAction: { action, message in
                coach.handle(action, on: message)
                model.didHandleCoachAction(action)
            },
            applyDetail: { message in
                coach.applySummary(for: message)
            }
        )
        if coach.messages.count > 1 {
            NavigationLink {
                CoachMessagesView(
                    messages: coach.messages,
                    references: references,
                    onAction: { action, message in
                        coach.handle(action, on: message)
                        model.didHandleCoachAction(action)
                    },
                    applyDetail: { message in
                        coach.applySummary(for: message)
                    }
                )
            } label: {
                Text("Ver todas (\(coach.messages.count))")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    /// Botão principal ≥ 56 pt em `accent` (DESIGN §9.2, `PrimaryButtonStyle`; uso na academia,
    /// SPEC §2). "Retomar" quando há sessão ativa (S3). Um dia sem exercícios (RF-33) não começa:
    /// a sessão sairia vazia.
    private var primaryButton: some View {
        Button {
            if let sessionID = model.startSession() {
                onOpenSession(sessionID)
            }
        } label: {
            Text(model.activeSessionID == nil ? "Começar" : "Retomar")
        }
        .buttonStyle(.primary)
        .disabled(model.activeSessionID == nil && (model.plan?.exercises.isEmpty ?? true))
    }

    /// SPEC RF-43: a medida (repetições, segundos ou passos) vem do ambiente, não do ViewModel.
    private func measure(for exercise: PlannedExercise) -> ExerciseMeasure {
        traits.traits(for: exercise.exercise).measure
    }
}
