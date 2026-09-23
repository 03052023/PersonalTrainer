import SwiftUI

/// Faixa horizontal de chips, um por exercício da sessão, com o progresso "2/3" (séries de
/// trabalho / prescritas). O selecionado fica destacado; o pulado, riscado. Toque seleciona.
struct ExerciseProgressList: View {
    let exercises: [SessionExerciseModel]
    let selectedExerciseID: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(exercises, id: \.uuid) { exercise in
                        ExerciseProgressChip(
                            name: exercise.exerciseName,
                            completedSets: exercise.sets.filter { !$0.isWarmup }.count,
                            plannedSets: exercise.prescribedSets,
                            isSelected: exercise.uuid == selectedExerciseID,
                            isSkipped: exercise.wasSkipped,
                            action: { onSelect(exercise.uuid) }
                        )
                        .id(exercise.uuid)
                    }
                }
                .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedExerciseID) { _, newValue in
                guard let newValue else {
                    return
                }
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

/// Um chip. Altura mínima de 44 pt para o toque (RNF de acessibilidade).
private struct ExerciseProgressChip: View {
    let name: String
    let completedSets: Int
    let plannedSets: Int
    let isSelected: Bool
    let isSkipped: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough(isSkipped)
                Text("\(completedSets)/\(plannedSets)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .frame(maxWidth: 220)
            .background(isSelected ? Color.accentColor : Color.gray.opacity(0.18), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityText: String {
        var text = "\(name), \(completedSets) de \(plannedSets) séries"
        if isSkipped {
            text += ", pulado"
        }
        return text
    }
}

#Preview {
    if let fixture = SessionPreviewSupport.makeFixture() {
        ExerciseProgressList(
            exercises: fixture.viewModel.exercises,
            selectedExerciseID: fixture.viewModel.selectedExerciseID,
            onSelect: { _ in }
        )
    } else {
        Text("Preview indisponível")
    }
}
