import SwiftUI
import TrainerCore

/// Painel do exercício selecionado: nome (com "Trocar", RF-34), prescrição com "Por quê?"
/// (RF-32), notas da máquina, séries já feitas (toque corrige ou apaga, RF-19) e o registro da
/// próxima série (`SetEntryView`, T1.6). Sem `draft` (exercício pulado) mostra só o aviso; não
/// há série a registrar.
///
/// A prescrição aparece só aqui; o `SetEntryView` mostra apenas "Série X de N".
struct CurrentExercisePanel: View {
    let exercise: SessionExerciseModel
    let prescriptionSummary: String
    /// `nil` quando não há próxima série (exercício pulado).
    let draft: Binding<SetDraft>?
    let references: ReferenceCatalog
    /// "Trocar" só aparece antes da 1ª série do exercício (decidido pelo ViewModel).
    let canSubstitute: Bool
    let onComplete: () -> Void
    let onSubstitute: () -> Void
    /// Recebe o `uuid` da `SetLogModel` tocada.
    let onEditSet: (UUID) -> Void

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
                        Button {
                            onEditSet(setLog.uuid)
                        } label: {
                            CompletedSetRow(
                                setLog: setLog,
                                number: number(of: setLog),
                                loadUnit: loadUnit,
                                isEditable: true
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Toque para corrigir ou apagar a série.")
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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(exercise.exerciseName)
                    .font(.title2.weight(.semibold))
                    .strikethrough(exercise.wasSkipped)
                Spacer(minLength: 0)
                if canSubstitute {
                    Button {
                        onSubstitute()
                    } label: {
                        Label("Trocar", systemImage: "arrow.triangle.2.circlepath")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Escolhe outro exercício só para este treino.")
                }
            }

            if exercise.substitutedFromUUID != nil {
                Label("Trocado neste treino", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Nota e "Por quê?" numa linha própria: com Dynamic Type grande a prescrição usa a
            // largura toda em vez de disputar espaço com o botão.
            prescriptionText
            HStack(spacing: 8) {
                noteBadge
                whyButton
            }

            if let notes = exercise.exercise?.machineNotes, !notes.isEmpty {
                Label(notes, systemImage: "gearshape")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var prescriptionText: some View {
        Text(prescriptionSummary)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Prescrição: \(prescriptionSummary)")
    }

    @ViewBuilder
    private var noteBadge: some View {
        if let note = exercise.note {
            Text(note.portugueseLabel)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.15), in: Capsule())
        }
    }

    /// RF-32: a regra por trás da nota. O `WhyButton` se esconde se o tópico não tem referências.
    @ViewBuilder
    private var whyButton: some View {
        if let note = exercise.note {
            WhyButton(topic: ReferenceCatalog.topic(for: note), catalog: references)
        }
    }

    private var sortedSets: [SetLogModel] {
        exercise.sets.sorted { $0.index < $1.index }
    }

    /// Posição 1-based na lista, não `index + 1`: depois de apagar uma série (RF-19) os
    /// índices gravados podem ter lacunas e a lista leria "1, 3".
    private func number(of setLog: SetLogModel) -> Int {
        (sortedSets.firstIndex { $0.uuid == setLog.uuid } ?? 0) + 1
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
                references: .empty,
                canSubstitute: false,
                onComplete: {},
                onSubstitute: {},
                onEditSet: { _ in }
            )
        }
    } else {
        Text("Preview indisponível")
    }
}

#Preview("Antes da 1ª série (Trocar)") {
    if let fixture = SessionPreviewSupport.makeFixture(),
       let exercise = fixture.untouchedExercise {
        ScrollView {
            CurrentExercisePanel(
                exercise: exercise,
                prescriptionSummary: fixture.viewModel.prescriptionSummary(for: exercise),
                draft: nil,
                references: .empty,
                canSubstitute: true,
                onComplete: {},
                onSubstitute: {},
                onEditSet: { _ in }
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
            references: .empty,
            canSubstitute: false,
            onComplete: {},
            onSubstitute: {},
            onEditSet: { _ in }
        )
    } else {
        Text("Preview indisponível")
    }
}
