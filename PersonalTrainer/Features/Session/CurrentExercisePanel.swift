import SwiftUI
import TrainerCore

/// Painel do exercício selecionado: nome, prescrição, notas da máquina, séries já feitas e o
/// registro da próxima série (`SetEntryView`, T1.6). Sem `draft` (exercício pulado) mostra só
/// o aviso; não há série a registrar.
struct CurrentExercisePanel: View {
    let exercise: SessionExerciseModel
    let prescriptionSummary: String
    /// `nil` quando não há próxima série (exercício pulado).
    let draft: Binding<SetDraft>?
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !sortedSets.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Séries registradas")
                        .font(.footnote.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    ForEach(sortedSets, id: \.uuid) { setLog in
                        CompletedSetRow(setLog: setLog, loadUnit: loadUnit)
                    }
                }
            }

            if exercise.wasSkipped {
                Label("Exercício pulado nesta sessão", systemImage: "forward.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            } else if let draft {
                SetEntryView(draft: draft, onComplete: onComplete)
            }
        }
        .padding(.horizontal)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(exercise.exerciseName)
                .font(.title2.weight(.semibold))
                .strikethrough(exercise.wasSkipped)
            HStack(spacing: 8) {
                Text(prescriptionSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let note = exercise.note {
                    Text(note.portugueseLabel)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }
            if let notes = exercise.exercise?.machineNotes, !notes.isEmpty {
                Label(notes, systemImage: "gearshape")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sortedSets: [SetLogModel] {
        exercise.sets.sorted { $0.index < $1.index }
    }

    private var loadUnit: LoadUnit {
        exercise.exercise?.loadUnit ?? .kilograms
    }
}

/// Rótulos pt-BR das notas de prescrição (SPEC §7.1). Privado à feature para não colidir
/// com o mesmo mapeamento em outras features.
private extension PrescriptionNote {
    var portugueseLabel: String {
        switch self {
        case .calibrate:
            return "Calibrar"
        case .increase:
            return "Subir"
        case .hold:
            return "Manter"
        case .retry:
            return "Repetir"
        case .decrease:
            return "Reduzir"
        case .returning:
            return "Retorno"
        case .deload:
            return "Deload"
        }
    }
}

#Preview("Com série a registrar") {
    if let fixture = SessionPreviewSupport.makeFixture(),
       let exercise = fixture.viewModel.selectedExercise,
       let draft = fixture.viewModel.currentDraft {
        ScrollView {
            CurrentExercisePanel(
                exercise: exercise,
                prescriptionSummary: fixture.viewModel.prescriptionSummary(for: exercise),
                draft: Binding.constant(draft),
                onComplete: {}
            )
        }
    } else {
        Text("Preview indisponível")
    }
}

#Preview("Exercício pulado") {
    if let fixture = SessionPreviewSupport.makeFixture(), let exercise = fixture.skippedExercise {
        CurrentExercisePanel(
            exercise: exercise,
            prescriptionSummary: fixture.viewModel.prescriptionSummary(for: exercise),
            draft: nil,
            onComplete: {}
        )
    } else {
        Text("Preview indisponível")
    }
}
