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
///
/// Se o store persistente não abriu (`AppEnvironment.storeLoadError`), nenhuma aba aparece: só a
/// tela de erro, com "Tentar de novo" (`onRetryStoreLoad`, que monta o ambiente outra vez) e a
/// exportação dos arquivos de dados. Assim o app nunca parece uma instalação nova com o histórico
/// sumido, e nada é gravado sobre um store em memória que se perderia ao fechar.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    private let onRetryStoreLoad: (() -> Void)?

    init(onRetryStoreLoad: (() -> Void)? = nil) {
        self.onRetryStoreLoad = onRetryStoreLoad
    }

    var body: some View {
        if let storeLoadError = environment.storeLoadError {
            StoreLoadErrorView(
                message: storeLoadError,
                dataFiles: ModelContainerFactory.existingPersistentStoreFiles(),
                onRetry: onRetryStoreLoad
            )
        } else {
            RootTabs(environment: environment)
        }
    }
}

/// Tela bloqueante quando os dados não abriram (B1). Diz que nada foi apagado, pede para não
/// desinstalar, oferece tentar de novo e exportar os arquivos do store (o SQLite e a cópia feita
/// antes da migração) pelo compartilhamento do sistema, para guardar em Arquivos ou num computador.
private struct StoreLoadErrorView: View {
    let message: String
    let dataFiles: [URL]
    let onRetry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Não foi possível abrir seus dados", systemImage: "exclamationmark.triangle")
        } description: {
            VStack(spacing: 12) {
                Text("Nada foi apagado: seus treinos continuam guardados neste iPhone. Não desinstale o app. Tente abrir de novo ou exporte os arquivos de dados para guardar uma cópia.")
                Text(verbatim: message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } actions: {
            if let onRetry {
                Button("Tentar de novo") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
            }
            if !dataFiles.isEmpty {
                ShareLink(items: dataFiles) {
                    Label("Exportar arquivos de dados", systemImage: "square.and.arrow.up")
                }
            }
        }
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
    @Environment(\.scenePhase) private var scenePhase

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
        // RF-13/RF-14 (CA2-1, CA2-2): ao abrir e a cada volta ao primeiro plano, o gravador revisita
        // as sessões recentes: o treino do app Exercício e as amostras de FC do relógio costumam
        // chegar ao Saúde depois do "Finalizar". Nunca pede autorização (AGENTS §7).
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            guard newPhase == .active, let recorder = environment.healthRecorder else {
                return
            }
            let now = environment.now()
            Task {
                await recorder.reconcileRecentSessions(now: now)
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
