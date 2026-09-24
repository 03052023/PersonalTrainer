import Foundation

/// Medida e marca "de casa" de cada exercício do seed, por `slug` (SPEC RF-43, §7.13 H1). O app lê
/// `exercises.v2.json` do bundle uma vez e usa este catálogo em vez de um campo no esquema de dados.
///
/// Exercício personalizado sempre vale `ExerciseTraits.default` (RF-43: "usa reps e não entra no modo
/// casa"), mesmo que o slug coincida com um do seed; slug desconhecido também.
public struct ExerciseTraitsCatalog: Sendable, Hashable {
    /// Sem nenhum exercício: tudo vale `ExerciseTraits.default`. É o que o app usa se o JSON faltar
    /// ou não decodificar (ninguém fica em casa e tudo mede em repetições).
    public static let empty = ExerciseTraitsCatalog(traitsBySlug: [:])

    private let traitsBySlug: [String: ExerciseTraits]

    public init(traitsBySlug: [String: ExerciseTraits]) {
        self.traitsBySlug = traitsBySlug
    }

    /// Lê o JSON do catálogo do seed (`{"exercises":[{"slug", "measure"?, "atHome"?, ...}]}`). Os demais
    /// campos de cada exercício são ignorados. Slug repetido: vale a primeira ocorrência (o
    /// `SeedValidator` já recusa slug repetido no seed). JSON malformado, `slug` ausente ou `measure`
    /// desconhecida lançam o erro do `JSONDecoder` sem tradução.
    public static func decode(seedCatalogJSON data: Data) throws -> ExerciseTraitsCatalog {
        let file = try JSONDecoder().decode(SeedTraitsFile.self, from: data)
        var traitsBySlug: [String: ExerciseTraits] = [:]
        traitsBySlug.reserveCapacity(file.exercises.count)
        for entry in file.exercises where traitsBySlug[entry.slug] == nil {
            traitsBySlug[entry.slug] = entry.traits
        }
        return ExerciseTraitsCatalog(traitsBySlug: traitsBySlug)
    }

    /// Marcas do exercício do seed com este `slug`; desconhecido → `.default`.
    public func traits(forSlug slug: String) -> ExerciseTraits {
        traitsBySlug[slug] ?? .default
    }

    /// Como `traits(forSlug:)`, mas exercício personalizado sempre vale `.default` (SPEC RF-43).
    public func traits(for exercise: ExerciseDefinition) -> ExerciseTraits {
        exercise.isCustom ? .default : traits(forSlug: exercise.slug)
    }
}

/// Só o que o catálogo de marcas lê do `exercises.v2.json`.
private struct SeedTraitsFile: Decodable {
    let exercises: [SeedTraitsEntry]
}

private struct SeedTraitsEntry: Decodable {
    let slug: String
    let traits: ExerciseTraits

    private enum CodingKeys: String, CodingKey {
        case slug
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.slug = try container.decode(String.self, forKey: .slug)
        // Mesmo objeto JSON: `ExerciseTraits` lê `measure` e `atHome` com os padrões dele.
        self.traits = try ExerciseTraits(from: decoder)
    }
}
