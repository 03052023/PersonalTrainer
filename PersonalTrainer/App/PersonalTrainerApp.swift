import SwiftUI

/// Ponto de entrada do app iPhone. Em M0 mostra apenas o placeholder (TASKS.md T0.1);
/// `AppEnvironment` e o container SwiftData entram em tarefas posteriores.
@main
@MainActor
struct PersonalTrainerApp: App {
    var body: some Scene {
        WindowGroup {
            RootPlaceholderView()
        }
    }
}
