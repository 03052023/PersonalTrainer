import SwiftUI
import TrainerCore

/// Uma série já registrada: "1 · 60 kg × 10 · RIR 2" (ou "× 30 s", "× 30 passos" conforme a
/// medida, SPEC RF-43), com selo quando é aquecimento.
///
/// `number` é a posição na lista (1-based), não `setLog.index + 1`: apagar uma série (RF-19)
/// deixa lacunas nos índices gravados. Com `isEditable`, mostra um lápis indicando que o toque
/// abre a correção; o toque em si é do `Button` de quem a exibe.
struct CompletedSetRow: View {
    let setLog: SetLogModel
    let number: Int
    let loadUnit: LoadUnit
    var measure: ExerciseMeasure = .reps
    var isEditable: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Text(summary)
                .font(.body.monospacedDigit())
            if setLog.isWarmup {
                Text("Aquecimento")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2), in: Capsule())
            }
            Spacer(minLength: 0)
            if isEditable {
                Image(systemName: "pencil")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenSummary)
    }

    private var summary: String {
        var text = "\(number) · \(loadText) × \(MeasureText.amount(setLog.reps, measure: measure))"
        if let rir = setLog.rir {
            text += " · RIR \(rir)"
        }
        return text
    }

    /// "Série 1, 60 kg, 10 repetições, RIR 2, aquecimento": sem "×" e "·" lidos em voz alta.
    private var spokenSummary: String {
        var parts = [
            "Série \(number)",
            loadText,
            MeasureText.spokenAmount(setLog.reps, measure: measure),
        ]
        if let rir = setLog.rir {
            parts.append("RIR \(rir)")
        }
        if setLog.isWarmup {
            parts.append("aquecimento")
        }
        return parts.joined(separator: ", ")
    }

    /// Mesma convenção de `SetDraft.prescriptionSummary` para placas e nível.
    private var loadText: String {
        LoadStepper.displayText(for: setLog.load, unit: loadUnit)
    }
}

#Preview {
    if let fixture = SessionPreviewSupport.makeFixture() {
        VStack(alignment: .leading) {
            ForEach(fixture.completedSets, id: \.uuid) { setLog in
                CompletedSetRow(setLog: setLog, number: setLog.index + 1, loadUnit: .kilograms, isEditable: true)
            }
        }
        .padding()
    } else {
        Text("Preview indisponível")
    }
}
