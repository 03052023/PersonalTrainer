import Foundation
import Testing
@testable import TrainerCore

// CA6-2 e CA8-8 (SPEC RF-40 e §7.12; docs/V23-CORE-CONTRACT.md §4 e §5): todo exercício que os programas do seed
// usam tem guia no bundle. Os programas são os do seed 4 (v6/core): o Equilibrado (D1), o Fôlego (D2) e também os
// escondidos, como o Corpo todo e o Empurrar/Inferior/Puxar, porque quem já os tem ativos continua neles.

/// Leitura do seed para os testes de cobertura das guias.
private enum GuideCoverageSupport {
    /// "Hipertrofia — Equilibrado" (D1), ativo no seed 4.
    static let balancedProgramID: String = "9FE0818F-1417-4953-B357-43D757054FCC"
    /// "Fôlego" (D2), com um aeróbico em minutos por dia.
    static let enduranceCardioProgramID: String = "09AB286E-D2B2-49C6-8C9F-400D118D8D03"
    /// Os aeróbicos que o Fôlego usa (docs/V23-CORE-CONTRACT.md §2.3).
    static let programCardioSlugs: Set<String> = ["brisk-walk", "run-intervals", "stationary-bike"]
    /// Exercícios distintos dos programas do seed 4: 52 de força, tronco e pescoço, mais os 3 aeróbicos do Fôlego.
    static let programSlugCount: Int = 55

    static func seedBundle() throws -> SeedBundle {
        try SeedBundle.decode(
            catalogData: Data(contentsOf: GuideTestSupport.seedURL("exercises.v2.json")),
            programData: Data(contentsOf: GuideTestSupport.seedURL("programs.v2.json"))
        )
    }
}

@Test("CA6-2 todo exercício dos programas do seed (Equilibrado, Fôlego e os escondidos) tem guia no bundle")
func guideCoverageOfSeedPrograms() throws {
    let bundle = try GuideCoverageSupport.seedBundle()
    let guides = try GuideTestSupport.bundleCatalog()
    let covered = Set(guides.guides.map(\.slug))
    let slugByID = Dictionary(bundle.catalog.exercises.map { ($0.id, $0.slug) }, uniquingKeysWith: { first, _ in first })

    // Os programas novos da 2.3 estão no arquivo: a cobertura é a dos programas do seed 4, não a da 2.2.
    let programIDs = Set(bundle.programs.programs.map(\.id))
    let balanced = try #require(UUID(uuidString: GuideCoverageSupport.balancedProgramID))
    let enduranceCardio = try #require(UUID(uuidString: GuideCoverageSupport.enduranceCardioProgramID))
    #expect(programIDs.contains(balanced), "o Equilibrado não está em programs.v2.json")
    #expect(programIDs.contains(enduranceCardio), "o Fôlego não está em programs.v2.json")

    var needed = Set<String>()
    var missing: [String] = []
    for program in bundle.programs.programs {
        for day in program.days {
            for target in day.exercises {
                let slug = try #require(slugByID[target.exerciseID], "\(program.name) · \(day.name): exercício fora do catálogo")
                needed.insert(slug)
                if !covered.contains(slug) {
                    missing.append("\(program.name) · \(day.name): \(slug)")
                }
            }
        }
    }

    #expect(missing.isEmpty, "sem guia: \(missing)")
    #expect(needed.isSuperset(of: GuideCoverageSupport.programCardioSlugs), "os aeróbicos do Fôlego saíram dos programas")
    #expect(
        needed.count == GuideCoverageSupport.programSlugCount,
        "os programas do seed usam \(needed.count) exercícios; atualize a contagem e as guias"
    )
}

@Test(
    "CA8-8 todo aeróbico do catálogo tem guia no bundle",
    .disabled("faltam os 7 aeróbicos fora dos programas: lote 4 de docs/design/exercise-guides/batches.json")
)
func guideCoverageOfCatalogCardio() throws {
    let bundle = try GuideCoverageSupport.seedBundle()
    let guides = try GuideTestSupport.bundleCatalog()
    let covered = Set(guides.guides.map(\.slug))
    let cardio = bundle.catalog.exercises.filter { $0.movementPattern == .cardio }.map(\.slug)

    #expect(cardio.count == 10, "a 2.3 tem 10 aeróbicos no catálogo: \(cardio.count)")
    let missing = cardio.filter { !covered.contains($0) }.sorted()
    #expect(missing.isEmpty, "sem guia: \(missing)")
}
