import SwiftUI

/// O botão grande da sessão guiada, preso embaixo da ficha (SPEC RF-44 i; DESIGN §13): acima dele, a linha
/// "Agora: Agachamento livre · série 2 de 3" (durante o descanso, "A seguir: série 3") e a meta de hoje em SF
/// Rounded ("10 repetições · 60 kg"); o botão diz "Marcar série", "Marcar como feito" ou "Concluir a sessão".
///
/// View pura: recebe os textos prontos do `ActiveSessionViewModel` (via `SessionGuide`) e só chama `onTap`.
/// Durante o descanso o botão continua ativo: marcar adianta.
struct SessionGuideBar: View {
    private let line: String
    private let target: String?
    private let buttonTitle: String
    private let isEnabled: Bool
    private let onTap: () -> Void

    init(line: String, target: String?, buttonTitle: String, isEnabled: Bool, onTap: @escaping () -> Void) {
        self.line = line
        self.target = target
        self.buttonTitle = buttonTitle
        self.isEnabled = isEnabled
        self.onTap = onTap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let target {
                    Text(target)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            Button(buttonTitle, action: onTap)
                .buttonStyle(.primary)
                .disabled(!isEnabled)
                .accessibilityHint(Text(accessibilityHint))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            // Fundo opaco: a ficha rola por baixo do botão sem aparecer através dele; o fio separa.
            ZStack(alignment: .top) {
                Theme.background
                Theme.line.frame(height: 0.5)
            }
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var accessibilityHint: String {
        guard let target else {
            return line
        }
        return "\(line). \(target)"
    }
}

#Preview("Sessão guiada") {
    VStack {
        Spacer()
        SessionGuideBar(
            line: "Agora: Agachamento livre · série 2 de 3",
            target: "10 repetições · 60 kg",
            buttonTitle: "Marcar série",
            isEnabled: true,
            onTap: {}
        )
    }
    .paperBackground()
}
