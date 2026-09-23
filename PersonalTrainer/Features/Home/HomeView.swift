import SwiftUI

/// Tela inicial (SPEC F1, RF-01, RF-02): próximo treino e botão Iniciar/Retomar.
///
/// A Home não conhece `ActiveSessionView` (TASKS T1.4): devolve o `uuid` da sessão em
/// `onOpenSession` e o `RootView` decide para onde navegar. O ViewModel chega por `init`;
/// nada aqui lê o `AppEnvironment` do ambiente nem escreve no `ModelContext` (AGENTS R4).
struct HomeView: View {
    @Bindable private var model: HomeViewModel
    private let onOpenSession: (UUID) -> Void

    init(model: HomeViewModel, onOpenSession: @escaping (UUID) -> Void) {
        self.model = model
        self.onOpenSession = onOpenSession
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
            // Fechamento isolado ao MainActor e capturando só o ViewModel (classe @MainActor,
            // portanto Sendable): a struct da view não precisa cruzar a fronteira do @Sendable.
            .refreshable { @MainActor [model] in
                model.refresh()
            }
            .safeAreaInset(edge: .bottom) {
                primaryButton
            }
            .navigationTitle("Treino")
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
            PlanCard(plan: plan)
        } else if model.didFailToLoad {
            ContentUnavailableView(
                "Não foi possível carregar o treino",
                systemImage: "exclamationmark.triangle",
                description: Text("Puxe para baixo para tentar de novo.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        } else {
            ContentUnavailableView(
                "Nenhum programa ativo",
                systemImage: "figure.strengthtraining.traditional",
                description: Text("Quando houver um programa ativo, o próximo treino aparece aqui.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
        }
    }

    /// Botão principal ≥ 56 pt (uso na academia, SPEC §2). "Retomar" quando há sessão ativa (S3).
    private var primaryButton: some View {
        Button {
            if let sessionID = model.startSession() {
                onOpenSession(sessionID)
            }
        } label: {
            Text(model.activeSessionID == nil ? "Iniciar treino" : "Retomar treino")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.plan == nil && model.activeSessionID == nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
