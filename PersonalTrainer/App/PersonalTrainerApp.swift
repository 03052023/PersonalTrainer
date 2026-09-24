import SwiftData
import SwiftUI

/// Ponto de entrada do app iPhone (T1.1). Monta o `AppEnvironment` real uma vez por processo
/// (store persistente + seed do bundle, ARCHITECTURE §11) e o injeta nas views: `.environment`
/// para os serviços e `.modelContainer` para os `@Query` do histórico (ARCHITECTURE §3).
///
/// Se o store persistente não abriu, o `RootView` mostra a tela de erro; "Tentar de novo" monta
/// o ambiente outra vez (nova tentativa de abrir o store em disco, que nunca é apagado).
@main
@MainActor
struct PersonalTrainerApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView(onRetryStoreLoad: {
                environment = AppEnvironment.live()
            })
            .environment(environment)
            .environment(\.exerciseTraits, environment.traits)
            .modelContainer(environment.modelContainer)
        }
    }
}
