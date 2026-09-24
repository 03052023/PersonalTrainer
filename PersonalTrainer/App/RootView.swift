import SwiftData
import SwiftUI

/// Raiz da navegação (T1.1, M2-CONTRACT §7; SPEC F1/F4/F5): abas "Treino" (Home), "Histórico",
/// "Programa" e "Ajustes", com a sessão ativa apresentada por cima em `fullScreenCover` e o
/// onboarding do primeiro launch em `.sheet`. Cada aba traz a própria `NavigationStack`, então
/// nada aqui as aninha em outra.
///
/// O `AppEnvironment` chega pelo ambiente (`PersonalTrainerApp` injeta com `.environment`).
/// Como `@Environment` só é legível depois do `init`, quem guarda o `HomeViewModel` em
/// `@State` é a view interna `RootTabs`, que recebe o ambiente por parâmetro.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        RootTabs(environment: environment)
    }
}

/// Abas + apresentação da sessão e do onboarding. Dona do `HomeViewModel` (um por processo), da
/// aba selecionada e do id da sessão apresentada.
private struct RootTabs: View {
    /// Item do `fullScreenCover(item:)`: só o `uuid` da sessão; a view do fluxo busca o resto.
    private struct PresentedSession: Identifiable {
        let id: UUID
    }

    private enum RootTab: Hashable {
        case training
        case history
        case program
        case settings
    }

    private let environment: AppEnvironment
    @State private var homeModel: HomeViewModel
    @State private var presentedSession: PresentedSession? = nil
    @State private var selectedTab: RootTab = .training

    /// Marca gravada pelo `OnboardingView` ao tocar "Começar" ou "Pular" (UserDefaults, sem
    /// SwiftData: M2-CONTRACT §2).
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    /// Controla a `.sheet` do onboarding. Copiado da marca no `onAppear` em vez de um `Binding`
    /// derivado: a marca só vira `true` dentro do onboarding, que fecha a sheet por `onDone`.
    @State private var isShowingOnboarding = false

    init(environment: AppEnvironment) {
        self.environment = environment
        self._homeModel = State(initialValue: HomeViewModel(
            planner: environment.planner,
            coordinator: environment.coordinator,
            now: environment.now
        ))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Iniciar e Retomar chegam pelo mesmo caminho: `HomeViewModel.startSession()`
            // devolve o id da sessão nova ou o da que já estava em andamento (SPEC S3, RF-02),
            // inclusive após relançar o app com um treino aberto (CA1-4).
            HomeView(model: homeModel, references: environment.references, onOpenSession: { sessionID in
                presentedSession = PresentedSession(id: sessionID)
            })
            .tabItem {
                Label("Treino", systemImage: "figure.strengthtraining.traditional")
            }
            .tag(RootTab.training)

            // Apagar passa pelo coordinator (único caminho de escrita de sessão, AGENTS R4); a
            // Home relê porque a rotação e as cargas derivam do histórico (T2.13, ADR 003).
            HistoryListView(references: environment.references, onDeleteSession: { sessionID in
                try environment.coordinator.deleteSession(id: sessionID)
                homeModel.refresh()
            })
            .tabItem {
                Label("Histórico", systemImage: "clock.arrow.circlepath")
            }
            .tag(RootTab.history)

            ProgramTabView(
                programs: environment.programs,
                catalog: environment.catalog,
                references: environment.references,
                now: environment.now
            )
            .tabItem {
                Label("Programa", systemImage: "list.bullet.rectangle")
            }
            .tag(RootTab.program)

            // Depois de importar um backup, programa ativo e histórico mudaram: a Home relê.
            SettingsView(
                backup: environment.backup,
                references: environment.references,
                onDataChanged: {
                    homeModel.refresh()
                },
                now: environment.now
            )
            .tabItem {
                Label("Ajustes", systemImage: "gearshape")
            }
            .tag(RootTab.settings)
        }
        // Programa ativo, dias e objetivo podem ter mudado nas outras abas: ao voltar para
        // "Treino", a Home relê (além do próprio `onAppear` dela).
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .training {
                homeModel.refresh()
            }
        }
        // A Home não recebe `onAppear` ao dispensar um cover: relê aqui para mostrar o próximo
        // treino recalculado (SPEC F4) e trocar Retomar → Iniciar.
        .fullScreenCover(item: $presentedSession, onDismiss: { homeModel.refresh() }) { presented in
            SessionFlowView(sessionID: presented.id, environment: environment, onClose: {
                presentedSession = nil
            })
        }
        // Primeiro launch (T2.21, RF-35): escolher objetivo e programa. O onboarding desliga o
        // gesto de dispensa; toda saída passa por "Começar" ou "Pular", que gravam a marca.
        .sheet(isPresented: $isShowingOnboarding) {
            OnboardingView(programs: environment.programs, references: environment.references, onDone: {
                isShowingOnboarding = false
                homeModel.refresh()
            })
        }
        .onAppear {
            if !hasCompletedOnboarding {
                isShowingOnboarding = true
            }
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    return RootView()
        .environment(environment)
        .modelContainer(environment.modelContainer)
}
