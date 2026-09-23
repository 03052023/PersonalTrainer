import SwiftUI
import TrainerCore

/// Registro de uma série (SPEC F2, RF-03, RF-04): edita o `SetDraft` pré-preenchido pelo
/// `ActiveSessionViewModel` e avisa por `onComplete` quando o usuário toca "Concluir série".
/// View pura: não conhece coordinator nem `ModelContext` (AGENTS R4); quem persiste é o dono do
/// binding. Controles ≥ 56 pt e Dynamic Type sem quebra (RNF-06).
struct SetEntryView: View {
    @Binding var draft: SetDraft
    let onComplete: () -> Void

    init(draft: Binding<SetDraft>, onComplete: @escaping () -> Void) {
        self._draft = draft
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            LoadStepper(value: $draft.load, increment: draft.loadIncrement, unit: draft.loadUnit)

            RepsStepper(
                value: $draft.reps,
                range: 0...50,
                highlightRange: SetEntryView.highlightRange(repMin: draft.repMin, repMax: draft.repMax)
            )

            RIRPicker(selection: $draft.rir)

            Toggle("Aquecimento", isOn: $draft.isWarmup)

            completeButton
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Série \(draft.setIndex + 1) de \(draft.plannedSets)")
                .font(.title2.weight(.bold))
            Text(draft.prescriptionSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var completeButton: some View {
        // O frame vai no rótulo, não no botão: assim a área tocável e pintada tem ≥ 56 pt.
        // Sem `.controlSize(.large)`: somado ao frame ele levaria o botão a ~80 pt; a meta é
        // ~60 pt (RNF-06 pede ≥ 44), o bastante para o toque com a mão suada sem roubar a tela.
        Button(action: onComplete) {
            Text("Concluir série")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
    }

    // MARK: - Helpers puros (testáveis sem UI)

    /// `ClosedRange` exige `lowerBound <= upperBound` e aborta caso contrário; um programa com
    /// faixa invertida não pode derrubar a sessão ativa, então normalizamos aqui.
    nonisolated static func highlightRange(repMin: Int, repMax: Int) -> ClosedRange<Int> {
        min(repMin, repMax)...max(repMin, repMax)
    }
}

// MARK: - Previews

private enum SetEntryPreviewData {
    static let kilograms = SetDraft(
        load: 60,
        reps: 8,
        rir: 2,
        setIndex: 0,
        plannedSets: 3,
        loadIncrement: 2.5,
        loadUnit: .kilograms,
        repMin: 8,
        repMax: 12,
        targetReps: 8,
        targetRIR: 2,
        note: .increase
    )

    static let plates = SetDraft(
        load: 12,
        reps: 10,
        rir: nil,
        setIndex: 1,
        plannedSets: 3,
        loadIncrement: 1,
        loadUnit: .plates,
        repMin: 8,
        repMax: 12,
        targetReps: 10,
        targetRIR: 2,
        note: .hold
    )

    static let warmup = SetDraft(
        load: 40,
        reps: 12,
        rir: nil,
        isWarmup: true,
        setIndex: 0,
        plannedSets: 3,
        loadIncrement: 2.5,
        loadUnit: .kilograms,
        repMin: 8,
        repMax: 12,
        targetReps: 8,
        targetRIR: 2,
        note: .calibrate
    )
}

private struct SetEntryPreviewHost: View {
    @State private var draft: SetDraft

    init(draft: SetDraft) {
        self._draft = State(initialValue: draft)
    }

    var body: some View {
        ScrollView {
            SetEntryView(draft: $draft, onComplete: {})
                .padding()
        }
    }
}

#Preview("Kg") {
    SetEntryPreviewHost(draft: SetEntryPreviewData.kilograms)
}

#Preview("Placas") {
    SetEntryPreviewHost(draft: SetEntryPreviewData.plates)
}

#Preview("Aquecimento") {
    SetEntryPreviewHost(draft: SetEntryPreviewData.warmup)
}

#Preview("Dynamic Type XXXL") {
    SetEntryPreviewHost(draft: SetEntryPreviewData.kilograms)
        .dynamicTypeSize(.xxxLarge)
}

#Preview("Dynamic Type AX5") {
    SetEntryPreviewHost(draft: SetEntryPreviewData.kilograms)
        .dynamicTypeSize(.accessibility5)
}
