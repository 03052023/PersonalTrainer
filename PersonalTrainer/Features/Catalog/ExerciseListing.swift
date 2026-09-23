import Foundation
import TrainerCore

/// Busca, ordenação e agrupamento do catálogo, compartilhados por `CatalogListView` e
/// `ExercisePickerView`. Funções puras sobre DTOs de `TrainerCore`: testáveis sem UI e sem banco.
enum ExerciseListing {
    /// Uma seção da lista: exercícios cujo **primeiro** grupo primário é `group`.
    struct MuscleSection: Identifiable, Hashable {
        /// `nil` só para exercícios sem grupo primário (não deveria existir: o seed e o editor
        /// exigem ≥ 1), que vão para "Outros" em vez de sumir.
        let group: MuscleGroup?
        let exercises: [ExerciseDefinition]

        var id: String {
            group?.rawValue ?? "other"
        }

        var title: String {
            group?.displayName ?? "Outros"
        }
    }

    /// Busca por nome: cada palavra da consulta precisa aparecer no nome, sem diferenciar
    /// maiúsculas nem acentos ("supino halter" acha "Supino com halteres"; "gluteo" acha
    /// "Elevação pélvica — glúteo"). Consulta vazia ou só com espaços aceita tudo.
    static func matches(_ exercise: ExerciseDefinition, query: String) -> Bool {
        let tokens = query.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { token in
            exercise.name.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Ordem alfabética pt-BR, sem diferenciar maiúsculas nem acentos. Empate pelo id para a mesma
    /// entrada sempre produzir a mesma tela (SPEC P11 aplicada à UI).
    static func sorted(_ exercises: [ExerciseDefinition]) -> [ExerciseDefinition] {
        exercises.sorted { lhs, rhs in
            let order = lhs.name.compare(
                rhs.name,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: portuguese
            )
            if order != .orderedSame {
                return order == .orderedAscending
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Seções pelo primeiro grupo primário, na ordem de `MuscleGroup.allCases`; "Outros" no fim.
    /// Dentro de cada seção, a ordem de `sorted(_:)`. Seções vazias não aparecem.
    static func sections(_ exercises: [ExerciseDefinition]) -> [MuscleSection] {
        let grouped = Dictionary(grouping: exercises) { exercise -> MuscleGroup? in
            exercise.primaryMuscles.first
        }
        var result: [MuscleSection] = []
        for group in MuscleGroup.allCases {
            let key: MuscleGroup? = group
            if let members = grouped[key], !members.isEmpty {
                result.append(MuscleSection(group: group, exercises: sorted(members)))
            }
        }
        let noGroup: MuscleGroup? = nil
        if let others = grouped[noGroup], !others.isEmpty {
            result.append(MuscleSection(group: nil, exercises: sorted(others)))
        }
        return result
    }

    private static let portuguese = Locale(identifier: "pt_BR")
}
