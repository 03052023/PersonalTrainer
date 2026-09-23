import SwiftData
import SwiftUI

/// Ponto de entrada do app iPhone (T1.1). Monta o `AppEnvironment` real uma vez por processo
/// (store persistente + seed do bundle, ARCHITECTURE §11) e o injeta nas views: `.environment`
/// para os serviços e `.modelContainer` para os `@Query` do histórico (ARCHITECTURE §3).
@main
@MainActor
struct PersonalTrainerApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .modelContainer(environment.modelContainer)
        }
    }
}
