import SwiftUI

/// Cartão da primeira sessão (SPEC RF-41 c): explica o RIR uma única vez, antes da primeira
/// série, e some em "Entendi". Quem guarda que já foi visto é a `ActiveSessionView`
/// (`@AppStorage("hasSeenRIRExplainer")`); este cartão só mostra o texto e avisa o toque.
struct RIRIntroCard: View {
    private let onAcknowledge: () -> Void

    init(onAcknowledge: @escaping () -> Void) {
        self.onAcknowledge = onAcknowledge
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Antes da primeira série")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("O que é RIR")
                .font(.system(.title3, design: .serif).weight(.semibold))

            Text("Ao terminar cada série, conte quantas repetições você ainda faria com boa técnica. Esse número é o RIR, as repetições em reserva. Junto com as repetições, ele ajusta a sua próxima sessão.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(RIRText.scale, id: \.self) { line in
                    Text(line)
                        .monospacedDigit()
                }
            }
            .font(.body.weight(.medium))

            Text("Na dúvida, chute para baixo: entre dois números, registre o menor.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onAcknowledge()
            } label: {
                Text("Entendi")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("O cartão não aparece de novo.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.textSecondary.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ScrollView {
        RIRIntroCard(onAcknowledge: {})
            .padding()
    }
}

#Preview("Dynamic Type AX5") {
    ScrollView {
        RIRIntroCard(onAcknowledge: {})
            .padding()
    }
    .dynamicTypeSize(.accessibility5)
}
