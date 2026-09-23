import SwiftUI
import TrainerCore

/// Linha de exercício do catálogo e do seletor: nome, equipamento e padrão de movimento, com selo
/// "Meu" para exercícios criados pelo usuário e "Arquivado" quando for o caso.
struct CatalogExerciseRow: View {
    private let exercise: ExerciseDefinition
    private let isArchived: Bool

    init(exercise: ExerciseDefinition, isArchived: Bool = false) {
        self.exercise = exercise
        self.isArchived = isArchived
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(CatalogExerciseRow.detailText(for: exercise))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if exercise.isCustom {
                badge("Meu", color: Color.accentColor)
            }
            if isArchived {
                badge("Arquivado", color: Color.secondary)
            }
        }
        // Linha inteira tocável quando usada como rótulo de `Button` numa `List`.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(isArchived ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Helper puro (testável sem UI)

    /// "Máquina · Empurrar (horizontal)"; acrescenta "unilateral" quando for o caso e omite o
    /// padrão de movimento quando o exercício ainda não tem um (catálogo v1).
    nonisolated static func detailText(for exercise: ExerciseDefinition) -> String {
        var parts = [exercise.equipment.displayName]
        if let pattern = exercise.movementPattern {
            parts.append(pattern.displayName)
        }
        if exercise.isUnilateral {
            parts.append("unilateral")
        }
        return parts.joined(separator: " · ")
    }
}
