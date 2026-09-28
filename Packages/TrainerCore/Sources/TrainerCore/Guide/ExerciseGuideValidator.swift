import Foundation

/// Validação do arquivo de guias contra o catálogo (SPEC §7.12 E1–E10; docs/V23-CORE-CONTRACT.md §2.5). As mesmas
/// regras rodam no `-Check` de docs/design/exercise-guides/render-exercise-guides.ps1; lá também se conferem tipos e
/// chaves desconhecidas, que aqui o decodificador já tratou (tipo errado lança, chave desconhecida é ignorada).
///
/// Pura e determinística: as guias em ordem do arquivo, cada uma com todos os seus problemas. As regras de
/// cinemática (E4, E5, E6, E10) só rodam numa guia sem problema de formato, porque sem ele as contas não dizem nada.
public enum ExerciseGuideValidator {
    /// Todos os problemas, com o catálogo do seed (E1 e o `works` obrigatório de E2 dependem dele).
    public static func problems(in catalog: ExerciseGuideCatalog, exercises: [ExerciseDefinition]) -> [ExerciseGuideError] {
        problems(in: catalog, exercises: exercises, checkingCatalog: true)
    }

    /// `checkingCatalog: false` pula a busca de E1 no catálogo e o `works` obrigatório, como o `-Catalog` desligado
    /// da ferramenta no vocabulário (slugs `vocab-*`, que nunca vão para o seed).
    public static func problems(
        in catalog: ExerciseGuideCatalog,
        exercises: [ExerciseDefinition],
        checkingCatalog: Bool
    ) -> [ExerciseGuideError] {
        var found: [ExerciseGuideError] = []
        if catalog.version != ExerciseGuideCatalog.currentVersion {
            found.append(ExerciseGuideError(slug: nil, rule: ExerciseGuideError.formatRule, message: "version deve ser 1"))
        }
        if catalog.rig != GuideRig.name {
            found.append(ExerciseGuideError(slug: nil, rule: "E3", message: "rig deve ser '\(GuideRig.name)'"))
        }
        if catalog.units != ExerciseGuideCatalog.statureUnits {
            found.append(ExerciseGuideError(slug: nil, rule: ExerciseGuideError.formatRule, message: "units deve ser 'stature'"))
        }
        var patterns: [String: String] = [:]
        for exercise in exercises where patterns[exercise.slug] == nil {
            patterns[exercise.slug] = exercise.movementPattern?.rawValue ?? ""
        }
        var seen = Set<String>()
        for guide in catalog.guides {
            var collector = GuideProblemCollector(slug: guide.slug.isEmpty ? nil : guide.slug)
            checkSlug(guide, patterns: patterns, checkingCatalog: checkingCatalog, seen: &seen, into: &collector)
            checkStructure(guide, into: &collector)
            checkTexts(guide, pattern: checkingCatalog ? patterns[guide.slug] : nil, into: &collector)
            if !collector.hasFormatProblem && !guide.frames.isEmpty {
                checkKinematics(guide, into: &collector)
            }
            found.append(contentsOf: collector.problems)
        }
        return found
    }

    /// Lança o primeiro problema (SPEC E8: o app registra e não mostra "Como fazer").
    public static func validate(_ catalog: ExerciseGuideCatalog, exercises: [ExerciseDefinition]) throws {
        if let first = problems(in: catalog, exercises: exercises).first {
            throw first
        }
    }

    // MARK: - E1

    static func checkSlug(
        _ guide: ExerciseGuide,
        patterns: [String: String],
        checkingCatalog: Bool,
        seen: inout Set<String>,
        into collector: inout GuideProblemCollector
    ) {
        guard !guide.slug.isEmpty else {
            collector.add("E1", "slug ausente")
            return
        }
        if !seen.insert(guide.slug).inserted {
            collector.add("E1", "slug repetido: no máximo uma guia por slug")
        }
        if checkingCatalog && patterns[guide.slug] == nil {
            collector.add("E1", "slug fora do catálogo do seed")
        }
    }

    // MARK: - E2 (textos)

    /// Comprimento visível de um texto: 0 se só tiver espaços.
    static func textLength(_ text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : text.count
    }

    static func checkTexts(_ guide: ExerciseGuide, pattern: String?, into collector: inout GuideProblemCollector) {
        if let works = guide.works {
            if textLength(works) < 1 || works.count > 60 {
                collector.add("E2", "works precisa ter de 1 a 60 caracteres (tem \(works.count))")
            } else if let first = works.trimmingCharacters(in: .whitespacesAndNewlines).first, first.isUppercase {
                collector.add("E2", "works vai no meio da frase: comece com minúscula")
            }
        } else if pattern == "cardio" || pattern == "neck" {
            // o grupo primário do aeróbico e do pescoço é convenção de contagem (SPEC §7.4)
            collector.add("E2", "works é obrigatório em exercícios de padrão \(pattern ?? "")")
        }
        if textLength(guide.a11y) < 1 || guide.a11y.count > 240 {
            collector.add("E2", "a11y precisa ter de 1 a 240 caracteres (tem \(guide.a11y.count))")
        }
        if guide.steps.count != 3 {
            collector.add("E2", "steps precisa de exatamente 3 passos")
        } else {
            for step in guide.steps where textLength(step) < 1 || step.count > 120 {
                collector.add("E2", "passo precisa ter de 1 a 120 caracteres: \(step)")
            }
        }
        if guide.mistakes.count != 2 {
            collector.add("E2", "mistakes precisa de exatamente 2 erros")
        } else {
            for mistake in guide.mistakes {
                if textLength(mistake) < 1 || mistake.count > 120 {
                    collector.add("E2", "erro comum precisa ter de 1 a 120 caracteres: \(mistake)")
                } else if !mistake.contains(": ") {
                    collector.add("E2", "erro comum no formato 'o erro: o que fazer': \(mistake)")
                }
            }
        }
    }
}

/// Problemas de uma guia, na ordem em que as regras os acham.
struct GuideProblemCollector {
    let slug: String?
    private(set) var problems: [ExerciseGuideError] = []

    init(slug: String?) {
        self.slug = slug
    }

    mutating func add(_ rule: String, _ message: String) {
        problems.append(ExerciseGuideError(slug: slug, rule: rule, message: message))
    }

    mutating func format(_ message: String) {
        add(ExerciseGuideError.formatRule, message)
    }

    var hasFormatProblem: Bool {
        problems.contains { $0.rule == ExerciseGuideError.formatRule }
    }
}
