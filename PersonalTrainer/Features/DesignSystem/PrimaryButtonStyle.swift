import SwiftUI

/// Botão principal do Magister (DESIGN.md §9): fundo `accent`, texto `onAccent`, altura mínima de
/// 56 pt. É o único botão proeminente de uma tela (Home usa só um: "Começar"/"Retomar").
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                Theme.accent.opacity(configuration.isPressed ? 0.85 : 1),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .opacity(isEnabled ? 1 : 0.5)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    /// Atalho de uso: `Button("Começar") { … }.buttonStyle(.primary)`.
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
