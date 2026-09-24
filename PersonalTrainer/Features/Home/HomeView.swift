import SwiftUI
import TrainerCore

/// Aba "Hoje" (SPEC F1, RF-01, RF-02, S4, RF-17, RF-32, §7.11; DESIGN §9), de cima para baixo:
/// 1. o objetivo ativo (flor, nome em New York e subtítulo);
/// 2. a sessão de hoje, com a faixa que diz por que este dia (CA4-5) e o menu para escolher outro;
/// 3. o botão principal "Começar" / "Retomar", o único proeminente da tela;
/// 4. as mensagens do diálogo (SPEC §7.11), ligadas a `CoachService.handle`;
/// 5. o cartão de Saúde, sem as sugestões (elas já aparecem no diálogo, C3);
/// 6. o painel "Esta semana".
///
/// A Home não conhece `ActiveSessionView` (TASKS T1.4): devolve o `uuid` da sessão em
/// `onOpenSession` e o `RootView` decide para onde navegar. ViewModels, diálogo e referências
/// chegam por `init`; nada aqui lê o `AppEnvironment` do ambiente nem escreve no `ModelContext`
/// (AGENTS R4). O `WeeklyFrequencyCard` lê com `@Query`, então quem apresenta esta view precisa de
/// `.modelContainer` no ambiente (o app já injeta na raiz).
struct HomeView: View {
    @Bindable private var model: HomeViewModel
    private let coach: CoachService
    private let health: HealthViewModel
    private let references: ReferenceCatalog
    private let onOpenSession: (UUID) -> Void

    init(
        model: HomeViewModel,
        coach: CoachService,
        health: HealthViewModel,
        references: ReferenceCatalog,
        onOpenSession: @escaping (UUID) -> Void
    ) {
        self.model = model
        self.coach = coach
        self.health = health
        self.references = references
        self.onOpenSession = onOpenSession
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GoalHeaderView(goal: model.goal)
                    content
                    primaryButton
                    // Fechamentos literais (não referências a método): uma referência a método
                    // @MainActor perde o ator na conversão para o tipo do parâmetro.
                    CoachFeedSection(
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
                    // O cartão já abre `HealthDetailView` por `NavigationLink` quando há dados.
                    HealthCardView(model: health, references: references, showsSuggestions: false)
                    WeeklyFrequencyCard(references: references)
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
            .navigationTitle("Hoje")
            .onAppear {
                model.refresh()
            }
            .alert("Não foi possível continuar", isPresented: $model.isPresentingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
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
                goal: model.goal,
                references: references,
                canChooseDay: model.activeSessionID == nil,
                onSelectDay: { dayID in
                    model.selectDay(dayID)
                },
                onSelectAutomatic: {
                    model.selectAutomaticDay()
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
            // DESIGN §8: estado vazio com `sun.max`, fora da lista de símbolos proibidos.
            ContentUnavailableView(
                "Nenhum programa ativo",
                systemImage: "sun.max",
                description: Text("Quando houver um programa ativo, a próxima sessão aparece aqui.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        }
    }

    /// Botão principal ≥ 56 pt em `accent` (DESIGN §9.2, `PrimaryButtonStyle`; uso na academia,
    /// SPEC §2). "Retomar" quando há sessão ativa (S3).
    private var primaryButton: some View {
        Button {
            if let sessionID = model.startSession() {
                onOpenSession(sessionID)
            }
        } label: {
            Text(model.activeSessionID == nil ? "Começar" : "Retomar")
        }
        .buttonStyle(.primary)
        .disabled(model.plan == nil && model.activeSessionID == nil)
    }
}
