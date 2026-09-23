import SwiftUI

/// Ponto de entrada do companion watchOS. Criado vazio em M0 (ARCHITECTURE AR-7);
/// a UI do relógio é implementada em M3.
@main
@MainActor
struct PersonalTrainerWatchApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Personal — em construção")
                .multilineTextAlignment(.center)
                .padding()
        }
    }
}
