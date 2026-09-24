import Foundation

/// Modo casa (SPEC RF-42, §7.13): troca cada exercício do dia pelo equivalente que dá para fazer em
/// casa. Função pura e determinística: o mesmo dia e o mesmo catálogo (em qualquer ordem) dão as
/// mesmas trocas. O programa não muda; quem chama aplica as trocas só na sessão planejada, com o alvo
/// do exercício original e o histórico do exercício de casa (H4).
///
/// - H1: "de casa" = `ExerciseTraitsCatalog.traits(for:).atHome`. Exercício personalizado nunca é de
///   casa (RF-43), então também é trocado quando o modo está ligado.
/// - H2: exercício de casa fica. Senão, a lista de equivalentes é:
///   1. os de casa com o mesmo padrão de movimento e ao menos um grupo primário em comum, na ordem do
///      RF-34 (`ExerciseSubstitution`: pontuação, afinidade de equipamento, nome, id);
///   2. depois, os demais de casa com ao menos um grupo primário em comum, na mesma ordem. É a leitura
///      de "mesmo grupo primário" já usada no RF-34. Exercício de pescoço e exercício que não é de
///      pescoço nunca são equivalentes por grupo: o grupo costas do pescoço é só convenção de
///      contagem (SPEC §7.4), e uma isometria de pescoço não substitui uma puxada.
///   A lista vazia tira o exercício da sessão (`replacement == nil`).
/// - H3: os exercícios de casa que já estão no dia ficam reservados antes de qualquer troca; cada
///   troca pega o primeiro da lista que o dia ainda não usa. Esgotados os do mesmo padrão, vale o
///   próximo por grupo.
public enum HomeSubstitution {
    /// §7.13 H1–H3, na ordem dos exercícios do dia. `catalog` = catálogo não arquivado.
    public static func swaps(
        for dayExercises: [ExerciseDefinition],
        catalog: [ExerciseDefinition],
        traits: ExerciseTraitsCatalog
    ) -> [HomeSwap] {
        let homeCatalog = homeExercises(in: catalog, traits: traits)
        // H3: reservar primeiro os que ficam. Sem isso, um exercício anterior da academia poderia
        // virar justamente o exercício de casa que já está mais adiante no dia.
        var used = Set<UUID>()
        for exercise in dayExercises where isAtHome(exercise, traits: traits) {
            used.insert(exercise.id)
        }

        var swaps: [HomeSwap] = []
        swaps.reserveCapacity(dayExercises.count)
        for exercise in dayExercises {
            if isAtHome(exercise, traits: traits) {
                swaps.append(HomeSwap(originalID: exercise.id, replacement: exercise))
                continue
            }
            let replacement = equivalents(for: exercise, in: homeCatalog).first { !used.contains($0.id) }
            if let replacement {
                used.insert(replacement.id)
            }
            swaps.append(HomeSwap(originalID: exercise.id, replacement: replacement))
        }
        return swaps
    }

    /// Candidatos de casa para trocar um exercício na sessão (mesma regra do RF-34, só entre os de casa).
    public static func candidates(
        for exercise: ExerciseDefinition,
        catalog: [ExerciseDefinition],
        traits: ExerciseTraitsCatalog,
        excluding: Set<UUID> = [],
        limit: Int = 5
    ) -> [ExerciseDefinition] {
        ExerciseSubstitution.candidates(
            for: exercise,
            in: homeExercises(in: catalog, traits: traits),
            excluding: excluding,
            limit: limit
        )
    }

    // MARK: - H2

    /// Lista completa de equivalentes de casa de `exercise` (H2), do mais ao menos parecido: primeiro
    /// os do mesmo padrão, depois os que só compartilham um grupo primário. Sem repetidos e sem o
    /// próprio exercício. Exercício sem grupo primário não tem equivalente.
    static func equivalents(
        for exercise: ExerciseDefinition,
        in homeCatalog: [ExerciseDefinition]
    ) -> [ExerciseDefinition] {
        guard !exercise.primaryMuscles.isEmpty else { return [] }

        let samePattern = ExerciseSubstitution.candidates(for: exercise, in: homeCatalog, limit: Int.max)

        let primaryGroups = Set(exercise.primaryMuscles)
        let isNeck = exercise.movementPattern == .neck
        var seen = Set(samePattern.map(\.id))
        seen.insert(exercise.id)
        var sameGroup: [ExerciseDefinition] = []
        for candidate in homeCatalog where !primaryGroups.isDisjoint(with: candidate.primaryMuscles) {
            // SPEC §7.4: o "costas" do pescoço é convenção de contagem, não treino de costas.
            guard (candidate.movementPattern == .neck) == isNeck else { continue }
            guard seen.insert(candidate.id).inserted else { continue }
            sameGroup.append(candidate)
        }

        return samePattern + ExerciseSubstitution.sortedBySimilarity(sameGroup, to: exercise)
    }

    // MARK: - H1

    private static func isAtHome(_ exercise: ExerciseDefinition, traits: ExerciseTraitsCatalog) -> Bool {
        traits.traits(for: exercise).atHome
    }

    private static func homeExercises(
        in catalog: [ExerciseDefinition],
        traits: ExerciseTraitsCatalog
    ) -> [ExerciseDefinition] {
        catalog.filter { isAtHome($0, traits: traits) }
    }
}
