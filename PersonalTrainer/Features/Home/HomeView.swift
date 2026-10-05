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
/// Com dois planos (SPEC §7.15 M6; DESIGN §9.7), no lugar do 2 e do 3: a faixa de quando os planos não
/// cabem, "Hoje é dia de descanso." com "Treinar mesmo assim", a linha "Hoje: Superior + Cardio leve
/// 25 min", um cartão por sessão (a força antes do aeróbico; "✓ Feito hoje" com "A seguir: …"; o
/// segundo com "Começar esta", menor) e o "Começar" da primeira sessão pendente, o único botão
/// proeminente. Com um plano só, a tela fica como na 2.2.
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
                        goals: model.headerGoals,
                        isSessionInProgress: model.isSessionInProgress,
                        onChangeGoal: onChangeGoal
                    )
                    if model.isMultiPlan {
                        multiPlanContent
                        multiPlanPrimaryButton
                    } else {
                        content
                        primaryButton
                    }
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
            .paperBackground()
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

    // MARK: - Dois planos (SPEC §7.15 M6)

    @ViewBuilder
    private var multiPlanContent: some View {
        if model.didFailToLoad && model.overview == nil {
            ContentUnavailableView(
                "Não foi possível carregar as sessões",
                systemImage: "exclamationmark.triangle",
                description: Text("Puxe para baixo para tentar de novo.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else {
            if model.showsNotFitBanner {
                notFitBanner
            }
            if model.isRestDay {
                restDayCard
            } else if let line = model.todayLine {
                Text(line)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(model.spokenTodayLine ?? line))
            }
            if model.isAllDoneToday {
                Text(TodayPlansText.allDone)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            ForEach(Array(model.todayCards.enumerated()), id: \.element.id) { index, card in
                todaySessionCard(card, isFirst: index == 0)
            }
            if model.showsTrainAnyway {
                trainAnywayButton
            }
        }
    }

    /// Faixa calma, nunca vermelha (DESIGN §9.3): os planos não cabem mais nos dias escolhidos.
    private var notFitBanner: some View {
        Label(TodayPlansText.notFitBanner, systemImage: "calendar")
            .font(.subheadline)
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// "Hoje é dia de descanso.", sem frase depois (DESIGN §6, §9.3).
    private var restDayCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hoje")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .accessibilityHidden(true)
            Text(TodayPlansText.restDay)
                .font(.system(.title3, design: .serif, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .inkCard()
    }

    private var trainAnywayButton: some View {
        Button {
            model.trainAnyway()
        } label: {
            Text(TodayPlansText.trainAnyway)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.accentSoft, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// O interruptor "Em casa" vale para o dia todo: fica só no primeiro cartão.
    private func todaySessionCard(_ card: HomeTodayCard, isFirst: Bool) -> some View {
        let programID = card.id
        var toggleHomeMode: ((Bool) -> Void)?
        if isFirst {
            toggleHomeMode = { enabled in
                model.setHomeMode(enabled)
            }
        }
        return TodaySessionCard(
            card: card,
            references: references,
            canChooseDay: !model.isSessionInProgress,
            isHomeModeOn: model.isHomeMode,
            onToggleHomeMode: toggleHomeMode,
            onSelectDay: { dayID in
                model.selectDay(dayID)
            },
            onSelectAutomatic: {
                model.selectAutomaticDay(forProgramID: programID)
            },
            onSelectExercise: { exercise in
                infoContent = model.infoContent(for: exercise, measure: measure(for: exercise))
            },
            onStart: {
                if let sessionID = model.startSession(programID: programID) {
                    onOpenSession(sessionID)
                }
            }
        )
    }

    /// "Começar" da primeira sessão pendente (M6) ou "Retomar"; nada num dia de descanso ou com tudo
    /// feito, até "Treinar mesmo assim".
    @ViewBuilder
    private var multiPlanPrimaryButton: some View {
        if model.activeSessionID != nil {
            Button {
                if let sessionID = model.startSession() {
                    onOpenSession(sessionID)
                }
            } label: {
                Text("Retomar")
            }
            .buttonStyle(.primary)
        } else if let primary = model.primaryCard {
            let programID = primary.id
            Button {
                if let sessionID = model.startSession(programID: programID) {
                    onOpenSession(sessionID)
                }
            } label: {
                Text("Começar")
            }
            .buttonStyle(.primary)
            .disabled(primary.plan.exercises.isEmpty)
        }
    }
}
