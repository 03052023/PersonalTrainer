import SwiftUI
import TrainerCore

/// Onde a troca acontece: muda só o rodapé (quanto tempo a troca vale e como trabalhar outro
/// músculo).
enum SubstituteContext {
    /// Sessão em andamento: a troca vale só para esta sessão.
    case session
    /// Editor do dia do programa: a troca fica no programa.
    case program
}

/// Folha "Trocar exercício" (SPEC RF-34), usada na sessão e no editor do programa. Mostra **só**
/// os substitutos deste exercício (mesmo padrão de movimento e ao menos um grupo primário em
/// comum, `ExerciseSubstitution`), do mais ao menos parecido, na ordem em que chegam. Não há
/// catálogo inteiro aqui (pedido do usuário, 2026-09-24): para trabalhar outro músculo, a pessoa
/// adiciona um exercício ao dia e apaga este.
///
/// Só escolhe: quem troca é quem apresenta a folha (sessão ou editor). O histórico de carga de
/// cada exercício é separado (P3).
struct SubstituteExerciseSheet: View {
    private let exerciseName: String
    private let suggestions: [ExerciseDefinition]
    private let references: ReferenceCatalog
    private let context: SubstituteContext
    private let onPick: (ExerciseDefinition) -> Void
    private let onCancel: () -> Void

    /// Chave de tópico do contrato de `ReferenceCatalog`.
    private static let whyTopic = "topic.substitution"

    init(
        exerciseName: String,
        suggestions: [ExerciseDefinition],
        references: ReferenceCatalog,
        context: SubstituteContext = .session,
        onPick: @escaping (ExerciseDefinition) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.exerciseName = exerciseName
        self.suggestions = suggestions
        self.references = references
        self.context = context
        self.onPick = onPick
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if suggestions.isEmpty {
                        Text("Nenhum exercício parecido com este no catálogo.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { pair in
                            Button {
                                onPick(pair.element)
                            } label: {
                                SubstituteRow(exercise: pair.element, isClosest: pair.offset == 0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Do mais parecido ao menos parecido")
                } footer: {
                    Text(footerText)
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

    private var footerText: String {
        let history = "O exercício novo tem histórico de carga próprio e começa em calibração se você nunca o fez."
        switch context {
        case .session:
            return "A troca vale só para esta sessão. \(history) Para trabalhar outro músculo, ajuste o dia na aba Programa."
        case .program:
            return "A troca fica no programa. \(history) Para trabalhar outro músculo, use \"Adicionar exercício\" e apague este."
        }
    }
}

/// Uma linha: nome, padrão de movimento e equipamento; o primeiro da lista leva o selo "Mais
/// parecido". Altura ≥ 44 pt para o toque.
private struct SubstituteRow: View {
    let exercise: ExerciseDefinition
    let isClosest: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.body)
                    .foregroundStyle(Color.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if isClosest {
                    Text("Mais parecido")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
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
        references: .empty,
        onPick: { _ in },
        onCancel: {}
    )
}

#Preview("No programa, sem substitutos") {
    SubstituteExerciseSheet(
        exerciseName: "Cadeira extensora",
        suggestions: [],
        references: .empty,
        context: .program,
        onPick: { _ in },
        onCancel: {}
    )
}
