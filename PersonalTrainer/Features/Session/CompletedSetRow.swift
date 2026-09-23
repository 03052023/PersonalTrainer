import SwiftUI
import TrainerCore

/// Uma série já registrada: "1 · 60 kg × 10 · RIR 2", com selo quando é aquecimento.
struct CompletedSetRow: View {
    let setLog: SetLogModel
    let loadUnit: LoadUnit

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
        }
        .padding(.vertical, 4)
        .frame(minHeight: 32)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        var text = "\(setLog.index + 1) · \(loadText) × \(setLog.reps)"
        if let rir = setLog.rir {
            text += " · RIR \(rir)"
        }
        return text
    }

    /// Mesma convenção de `SetDraft.prescriptionSummary` para placas e nível.
    private var loadText: String {
        switch loadUnit {
        case .kilograms:
            return LoadFormatter.kilograms(setLog.load)
        case .plates:
            return "\(Int(setLog.load.rounded())) placas"
        case .level:
            return "nível \(Int(setLog.load.rounded()))"
        }
    }
}

#Preview {
    if let fixture = SessionPreviewSupport.makeFixture() {
        VStack(alignment: .leading) {
            ForEach(fixture.completedSets, id: \.uuid) { setLog in
                CompletedSetRow(setLog: setLog, loadUnit: .kilograms)
            }
        }
        .padding()
    } else {
        Text("Preview indisponível")
    }
}
