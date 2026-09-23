import SwiftUI

/// Stepper de repetições da série (SPEC RF-03). O valor fica na cor de destaque enquanto está
/// dentro da faixa prescrita (`highlightRange`), para o usuário ver de relance se cumpriu a
/// meta sem ler o cabeçalho. Botões de 56 × 56 pt (RNF-06); toque longo repete o passo.
struct RepsStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let highlightRange: ClosedRange<Int>

    init(value: Binding<Int>, range: ClosedRange<Int>, highlightRange: ClosedRange<Int>) {
        self._value = value
        self.range = range
        self.highlightRange = highlightRange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repetições")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                stepButton(
                    systemName: "minus",
                    accessibilityLabel: "Diminuir repetições",
                    isEnabled: value > range.lowerBound
                ) {
                    value = RepsStepper.stepped(value, by: -1, in: range)
                }

                Text(String(value))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isInHighlightRange ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)

                stepButton(
                    systemName: "plus",
                    accessibilityLabel: "Aumentar repetições",
                    isEnabled: value < range.upperBound
                ) {
                    value = RepsStepper.stepped(value, by: 1, in: range)
                }
            }
        }
    }

    private var isInHighlightRange: Bool {
        highlightRange.contains(value)
    }

    private func stepButton(
        systemName: String,
        accessibilityLabel: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(RepsStepperButtonStyle())
        .buttonRepeatBehavior(.enabled)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Helpers puros (testáveis sem UI)

    /// Soma `delta` e limita a `range`, para o toque longo parar no limite em vez de estourar.
    nonisolated static func stepped(_ value: Int, by delta: Int, in range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value + delta))
    }
}

/// Só decora: fundo circular de 56 pt e escurece ao pressionar. O `Button` cuida do toque,
/// do repeat e do estado desabilitado (opacidade aplicada pela view).
private struct RepsStepperButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 56, height: 56)
            .background(
                Color.accentColor.opacity(configuration.isPressed ? 0.35 : 0.15),
                in: Circle()
            )
    }
}

// MARK: - Previews

private struct RepsStepperPreviewHost: View {
    @State private var value: Int
    private let highlightRange: ClosedRange<Int>

    init(value: Int, highlightRange: ClosedRange<Int>) {
        self._value = State(initialValue: value)
        self.highlightRange = highlightRange
    }

    var body: some View {
        RepsStepper(value: $value, range: 0...50, highlightRange: highlightRange)
            .padding()
    }
}

#Preview("Dentro da faixa") {
    RepsStepperPreviewHost(value: 10, highlightRange: 8...12)
}

#Preview("Fora da faixa") {
    RepsStepperPreviewHost(value: 6, highlightRange: 8...12)
}

#Preview("Dynamic Type AX5") {
    RepsStepperPreviewHost(value: 12, highlightRange: 8...12)
        .dynamicTypeSize(.accessibility5)
}
