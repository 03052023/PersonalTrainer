import SwiftUI
import TrainerCore

/// Stepper de carga da série (SPEC RF-03): passo = `loadIncrement` do exercício, mínimo 0.
/// Botões de 56 × 56 pt e valor grande porque o uso é na academia, com mãos suadas (RNF-06).
/// O toque longo repete o passo (`buttonRepeatBehavior`) para percorrer cargas distantes.
struct LoadStepper: View {
    @Binding var value: Double
    let increment: Double
    let unit: LoadUnit

    init(value: Binding<Double>, increment: Double, unit: LoadUnit) {
        self._value = value
        self.increment = increment
        self.unit = unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Carga")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                stepButton(
                    systemName: "minus",
                    accessibilityLabel: "Diminuir carga",
                    isEnabled: canDecrement
                ) {
                    value = LoadStepper.stepped(value, by: -increment)
                }

                Text(LoadStepper.displayText(for: value, unit: unit))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)

                stepButton(
                    systemName: "plus",
                    accessibilityLabel: "Aumentar carga",
                    isEnabled: true
                ) {
                    value = LoadStepper.stepped(value, by: increment)
                }
            }
        }
    }

    private var canDecrement: Bool {
        value > 0
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
        .buttonStyle(LoadStepperButtonStyle())
        .buttonRepeatBehavior(.enabled)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Helpers puros (testáveis sem UI)

    /// Texto do valor na unidade do exercício. Mesmo formato de `SetDraft.prescriptionSummary`,
    /// para a série e a prescrição lerem igual na mesma tela.
    nonisolated static func displayText(for value: Double, unit: LoadUnit) -> String {
        switch unit {
        case .kilograms:
            return LoadFormatter.kilograms(value)
        case .plates:
            return "\(Int(value.rounded())) placas"
        case .level:
            return "nível \(Int(value.rounded()))"
        }
    }

    /// Soma `delta` sem descer abaixo de 0 (peso corporal puro, SPEC P8). Devolve o literal 0
    /// no piso para nunca formatar "-0 kg".
    nonisolated static func stepped(_ value: Double, by delta: Double) -> Double {
        let next = value + delta
        return next <= 0 ? 0 : next
    }
}

/// Só decora: fundo circular de 56 pt e escurece ao pressionar. O `Button` cuida do toque,
/// do repeat e do estado desabilitado (opacidade aplicada pela view).
private struct LoadStepperButtonStyle: ButtonStyle {
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

private struct LoadStepperPreviewHost: View {
    @State private var value: Double
    private let increment: Double
    private let unit: LoadUnit

    init(value: Double, increment: Double, unit: LoadUnit) {
        self._value = State(initialValue: value)
        self.increment = increment
        self.unit = unit
    }

    var body: some View {
        LoadStepper(value: $value, increment: increment, unit: unit)
            .padding()
    }
}

#Preview("Kg") {
    LoadStepperPreviewHost(value: 62.5, increment: 2.5, unit: .kilograms)
}

#Preview("Placas") {
    LoadStepperPreviewHost(value: 12, increment: 1, unit: .plates)
}

#Preview("Nível") {
    LoadStepperPreviewHost(value: 7, increment: 1, unit: .level)
}

#Preview("Zero · Dynamic Type AX5") {
    LoadStepperPreviewHost(value: 0, increment: 2.5, unit: .kilograms)
        .dynamicTypeSize(.accessibility5)
}
