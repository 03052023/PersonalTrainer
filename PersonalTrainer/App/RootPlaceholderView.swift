import SwiftUI

/// Tela provisória de M0. Será substituída por `RootView` quando as features existirem.
struct RootPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Personal — em construção")
                .font(.title2)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    RootPlaceholderView()
}
