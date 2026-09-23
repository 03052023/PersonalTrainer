import SwiftData
import SwiftUI

/// Raiz da navegação (T1.1; SPEC F1/F4): abas "Treino" (Home) e "Histórico", com a sessão
/// ativa apresentada por cima em `fullScreenCover`. `ActiveSessionView` e `HistoryListView`
/// trazem as próprias `NavigationStack`s, então nada aqui as aninha em outra.
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

/// Abas + apresentação da sessão. Dona do `HomeViewModel` (um por processo) e do id da
/// sessão apresentada.
private struct RootTabs: View {
    /// Item do `fullScreenCover(item:)`: só o `uuid` da sessão; a view do fluxo busca o resto.
    private struct PresentedSession: Identifiable {
        let id: UUID
    }

    private let environment: AppEnvironment
    @State private var homeModel: HomeViewModel
    @State private var presentedSession: PresentedSession? = nil

    init(environment: AppEnvironment) {
        self.environment = environment
        self._homeModel = State(initialValue: HomeViewModel(
            planner: environment.planner,
            coordinator: environment.coordinator,
            now: environment.now
        ))
    }

    var body: some View {
        TabView {
            // Iniciar e Retomar chegam pelo mesmo caminho: `HomeViewModel.startSession()`
            // devolve o id da sessão nova ou o da que já estava em andamento (SPEC S3, RF-02),
            // inclusive após relançar o app com um treino aberto (CA1-4).
            HomeView(model: homeModel, onOpenSession: { sessionID in
                presentedSession = PresentedSession(id: sessionID)
            })
            .tabItem {
                Label("Treino", systemImage: "figure.strengthtraining.traditional")
            }

            HistoryListView()
                .tabItem {
                    Label("Histórico", systemImage: "clock.arrow.circlepath")
                }
        }
        // A Home não recebe `onAppear` ao dispensar um cover: relê aqui para mostrar o próximo
        // treino recalculado (SPEC F4) e trocar Retomar → Iniciar.
        .fullScreenCover(item: $presentedSession, onDismiss: { homeModel.refresh() }) { presented in
            SessionFlowView(sessionID: presented.id, environment: environment, onClose: {
                presentedSession = nil
            })
        }
    }
}

#Preview {
    let environment = AppEnvironment.preview()
    return RootView()
        .environment(environment)
        .modelContainer(environment.modelContainer)
}
