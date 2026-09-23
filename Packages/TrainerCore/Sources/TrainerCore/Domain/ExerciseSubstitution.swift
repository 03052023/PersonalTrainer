import Foundation

/// Substitutos de um exercício para o botão "Trocar" (SPEC RF-34): mesmo padrão de movimento,
/// ordenados por semelhança. Função pura e determinística: o mesmo catálogo (em qualquer ordem)
/// produz a mesma lista.
///
/// Ordenação, da chave mais forte para a mais fraca:
/// 1. Pontuação (`score`), decrescente:
///    - +3 se o grupo primário principal do exercício (o primeiro de `primaryMuscles`) está entre os
///      grupos primários do candidato;
///    - +1 por grupo primário em comum além desse;
///    - +2 se o `equipment` é o mesmo;
///    - +1 se `isUnilateral` é igual;
///    - +1 se `loadUnit` é igual.
/// 2. Afinidade de equipamento (`equipmentAffinity`), decrescente: desempata candidatos de mesma
///    pontuação preferindo equipamento parecido (TASKS T2.19). Sem ela, supino com barra teria
///    halteres, máquina e flexão empatados e a ordem alfabética poria "Flexão" primeiro, contra o
///    exemplo de RF-34 (barra → halteres → máquina → flexão).
/// 3. Nome, crescente, comparado sem distinção de maiúsculas e acentos (`folding` sem locale) e,
///    persistindo o empate, pela ordem Unicode do nome original. Não usa collation de locale pt_BR
///    porque ela depende do ICU da plataforma; esta comparação dá o mesmo resultado no iOS, no Linux
///    do CI e no Windows e ordena nomes em português como esperado ("Elevação" junto de "elevação").
/// 4. `id.uuidString`, crescente.
public enum ExerciseSubstitution {
    /// Até `limit` substitutos de `exercise` em `catalog`, do mais parecido ao menos parecido.
    ///
    /// - Exclui o próprio exercício (pelo `id`) e os ids em `excluding` (ex.: exercícios já presentes
    ///   no dia). `ExerciseDefinition` não tem flag de arquivado: quem chama filtra arquivados antes.
    /// - Exige o mesmo `movementPattern`; exercício sem padrão não tem substitutos (`[]`).
    /// - `limit <= 0` devolve `[]`. Ids repetidos no catálogo contam uma vez (vale a primeira ocorrência).
    public static func candidates(
        for exercise: ExerciseDefinition,
        in catalog: [ExerciseDefinition],
        excluding: Set<UUID> = [],
        limit: Int = 5
    ) -> [ExerciseDefinition] {
        guard limit > 0, let pattern = exercise.movementPattern else { return [] }

        var seen: Set<UUID> = [exercise.id]
        seen.formUnion(excluding)
        var ranked: [RankedCandidate] = []
        for candidate in catalog where candidate.movementPattern == pattern {
            guard seen.insert(candidate.id).inserted else { continue }
            ranked.append(
                RankedCandidate(
                    exercise: candidate,
                    score: score(of: candidate, against: exercise),
                    affinity: equipmentAffinity(candidate.equipment, exercise.equipment),
                    foldedName: foldedName(candidate.name)
                )
            )
        }

        ranked.sort(by: RankedCandidate.precedes)
        return ranked.prefix(limit).map(\.exercise)
    }

    /// Pontuação de semelhança de `candidate` com `exercise` (regras no comentário do tipo).
    /// Não olha o padrão de movimento: o filtro por padrão acontece antes.
    static func score(of candidate: ExerciseDefinition, against exercise: ExerciseDefinition) -> Int {
        let candidatePrimary = Set(candidate.primaryMuscles)
        var sharedPrimary = candidatePrimary.intersection(exercise.primaryMuscles)
        var score = 0
        if let mainPrimary = exercise.primaryMuscles.first, sharedPrimary.contains(mainPrimary) {
            score += 3
            sharedPrimary.remove(mainPrimary)
        }
        score += sharedPrimary.count
        if candidate.equipment == exercise.equipment { score += 2 }
        if candidate.isUnilateral == exercise.isUnilateral { score += 1 }
        if candidate.loadUnit == exercise.loadUnit { score += 1 }
        return score
    }

    /// Desempate por equipamento parecido: 2 = mesma família (peso livre, carga guiada ou peso
    /// corporal), 1 = famílias diferentes mas ambos com carga externa, 0 = só um deles é peso corporal.
    static func equipmentAffinity(_ lhs: Equipment, _ rhs: Equipment) -> Int {
        let lhsFamily = EquipmentFamily(lhs)
        let rhsFamily = EquipmentFamily(rhs)
        if lhsFamily == rhsFamily { return 2 }
        if lhsFamily != .bodyweight && rhsFamily != .bodyweight { return 1 }
        return 0
    }

    private static func foldedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// Família de equipamento para `ExerciseSubstitution.equipmentAffinity`.
private enum EquipmentFamily: Equatable {
    /// Barra, halteres e kettlebell: o praticante estabiliza a carga.
    case freeWeight
    /// Máquina, polia e smith: a trajetória é guiada.
    case guided
    case bodyweight

    init(_ equipment: Equipment) {
        switch equipment {
        case .barbell, .dumbbell, .kettlebell: self = .freeWeight
        case .machine, .cable, .smith: self = .guided
        case .bodyweight: self = .bodyweight
        }
    }
}

/// Candidato com as chaves de ordenação já calculadas.
private struct RankedCandidate {
    let exercise: ExerciseDefinition
    let score: Int
    let affinity: Int
    let foldedName: String

    /// Ordem total: pontuação e afinidade decrescentes, depois nome e `uuidString` crescentes.
    static func precedes(_ lhs: RankedCandidate, _ rhs: RankedCandidate) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.affinity != rhs.affinity { return lhs.affinity > rhs.affinity }
        if lhs.foldedName != rhs.foldedName { return lhs.foldedName < rhs.foldedName }
        if lhs.exercise.name != rhs.exercise.name { return lhs.exercise.name < rhs.exercise.name }
        return lhs.exercise.id.uuidString < rhs.exercise.id.uuidString
    }
}
