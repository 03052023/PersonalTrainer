import SwiftUI
import TrainerCore

/// Folha "Trocar exercício" da sessão (SPEC RF-34): até 5 substitutos com o mesmo padrão de
/// movimento (ordenados pelo planner) e "Ver todos os exercícios", que troca o conteúdo da
/// folha pelo `ExercisePickerView` do catálogo com os substitutos em "Sugeridos".
///
/// Só escolhe: quem troca é o `ActiveSessionViewModel` (planner + coordinator). A troca vale só
/// para este treino; o histórico de carga de cada exercício é separado (P3).
struct SubstituteExerciseSheet: View {
    private let exerciseName: String
    private let suggestions: [ExerciseDefinition]
    private let allExercises: [ExerciseDefinition]
    private let references: ReferenceCatalog
    private let onPick: (ExerciseDefinition) -> Void
    private let onCancel: () -> Void

    /// Lista completa no lugar dos substitutos. Troca de conteúdo, e não folha sobre folha:
    /// escolher na lista completa fecha tudo de uma vez.
    @State private var isShowingAll = false

    /// Chave de tópico do contrato de `ReferenceCatalog`.
    private static let whyTopic = "topic.substitution"

    init(
        exerciseName: String,
        suggestions: [ExerciseDefinition],
        allExercises: [ExerciseDefinition],
        references: ReferenceCatalog,
        onPick: @escaping (ExerciseDefinition) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.exerciseName = exerciseName
        self.suggestions = suggestions
        self.allExercises = allExercises
        self.references = references
        self.onPick = onPick
        self.onCancel = onCancel
    }

    var body: some View {
        if isShowingAll {
            ExercisePickerView(
                exercises: allExercises,
                title: "Todos os exercícios",
                highlighted: suggestions,
                onPick: onPick,
                onCancel: { isShowingAll = false }
            )
        } else {
            suggestionsList
        }
    }

    private var suggestionsList: some View {
        NavigationStack {
            List {
                Section {
                    if suggestions.isEmpty {
                        Text("Nenhum substituto com o mesmo padrão de movimento no catálogo.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(suggestions, id: \.id) { exercise in
                            Button {
                                onPick(exercise)
                            } label: {
                                SubstituteRow(exercise: exercise)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Mesmo padrão de movimento")
                } footer: {
                    Text("A troca vale só para este treino. O exercício novo tem histórico de carga próprio e começa em calibração se você nunca o fez.")
                }

                if !allExercises.isEmpty {
                    Section {
                        Button {
                            isShowingAll = true
                        } label: {
                            Label("Ver todos os exercícios", systemImage: "list.bullet")
                                .frame(minHeight: 44)
                        }
                    }
                }

                // RF-32: por que trocar por mesmo padrão de movimento mantém o estímulo. A seção
                // some junto com o botão quando o tópico não tem referências.
                if !references.references(for: Self.whyTopic).isEmpty {
                    Section {
                        WhyButton(topic: Self.whyTopic, catalog: references)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        onCancel()
                    }
                }
            }
        }
    }

    private var title: String {
        exerciseName.isEmpty ? "Trocar exercício" : "Trocar \(exerciseName)"
    }
}

/// Uma linha: nome, padrão de movimento e equipamento. Altura ≥ 44 pt para o toque.
private struct SubstituteRow: View {
    let exercise: ExerciseDefinition

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts: [String] = []
        if let pattern = exercise.movementPattern {
            parts.append(pattern.displayName)
        }
        parts.append(Self.equipmentLabel(exercise.equipment))
        return parts.joined(separator: " · ")
    }

    /// Rótulo pt-BR do equipamento. Função privada, e não extensão de `Equipment`, para não
    /// colidir com um rótulo que outra feature (catálogo) declare no mesmo tipo.
    private static func equipmentLabel(_ equipment: Equipment) -> String {
        switch equipment {
        case .barbell:
            return "Barra"
        case .dumbbell:
            return "Halteres"
        case .machine:
            return "Máquina"
        case .cable:
            return "Polia"
        case .bodyweight:
            return "Peso corporal"
        case .smith:
            return "Smith"
        case .kettlebell:
            return "Kettlebell"
        }
    }
}

// MARK: - Previews

private enum SubstitutePreviewData {
    static let dumbbellBench = ExerciseDefinition(
        slug: "supino-halteres",
        name: "Supino com halteres",
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .shoulders],
        equipment: .dumbbell,
        loadUnit: .kilograms,
        loadIncrement: 2,
        movementPattern: .horizontalPush
    )

    static let machineChestPress = ExerciseDefinition(
        slug: "supino-maquina",
        name: "Supino na máquina",
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps],
        equipment: .machine,
        loadUnit: .level,
        loadIncrement: 1,
        movementPattern: .horizontalPush
    )

    static let pushUp = ExerciseDefinition(
        slug: "flexao",
        name: "Flexão de braços",
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .core],
        equipment: .bodyweight,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        movementPattern: .horizontalPush
    )
}

#Preview("Com substitutos") {
    SubstituteExerciseSheet(
        exerciseName: "Supino reto",
        suggestions: [
            SubstitutePreviewData.dumbbellBench,
            SubstitutePreviewData.machineChestPress,
            SubstitutePreviewData.pushUp,
        ],
        allExercises: [
            SubstitutePreviewData.dumbbellBench,
            SubstitutePreviewData.machineChestPress,
            SubstitutePreviewData.pushUp,
        ],
        references: .empty,
        onPick: { _ in },
        onCancel: {}
    )
}

#Preview("Sem substitutos") {
    SubstituteExerciseSheet(
        exerciseName: "Cadeira extensora",
        suggestions: [],
        allExercises: [SubstitutePreviewData.dumbbellBench],
        references: .empty,
        onPick: { _ in },
        onCancel: {}
    )
}
