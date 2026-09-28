import Foundation
import Testing
@testable import TrainerCore

// CA6-2 e CA8-8 (docs/V23-CORE-CONTRACT.md §4 e §5): todo exercício usado nos programas do seed e todo aeróbico do
// catálogo tem guia. Fica desligado até a integração juntar os 7 lotes (62 guias); o integrador liga quando todas
// estiverem no bundle.

@Test(
    "CA6-2 todo slug de programs.v2.json e todo aeróbico do catálogo tem guia no bundle",
    .disabled("liga na integração, V23 §5")
)
func guideCoverageOfSeedPrograms() throws {
    let bundle = try SeedBundle.decode(
        catalogData: Data(contentsOf: GuideTestSupport.seedURL("exercises.v2.json")),
        programData: Data(contentsOf: GuideTestSupport.seedURL("programs.v2.json"))
    )
    let guides = try GuideTestSupport.bundleCatalog()
    let slugByID = Dictionary(bundle.catalog.exercises.map { ($0.id, $0.slug) }, uniquingKeysWith: { first, _ in first })

    var needed = Set<String>()
    for program in bundle.programs.programs {
        for day in program.days {
            for target in day.exercises {
                let slug = try #require(slugByID[target.exerciseID], "\(program.name) · \(day.name): exercício fora do catálogo")
                needed.insert(slug)
            }
        }
    }
    for exercise in bundle.catalog.exercises where exercise.movementPattern?.rawValue == "cardio" {
        needed.insert(exercise.slug)
    }

    let covered = Set(guides.guides.map(\.slug))
    let missing = needed.subtracting(covered).sorted()
    #expect(missing.isEmpty, "sem guia: \(missing)")
    #expect(needed.count == 62, "a 2.3 cobre 62 exercícios (52 dos programas e 10 aeróbicos): \(needed.count)")
}
