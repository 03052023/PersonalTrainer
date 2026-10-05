import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// SPEC §7.12 E8 (docs/V23-UI-CONTRACT.md §4.4): as guias do bundle carregam e passam na validação contra o
/// catálogo; arquivo ausente, ilegível ou reprovado vira `.empty`, sem botão "Como fazer" e sem parar nada.
///
/// `Bundle.main` é o app hospedeiro dos testes, com os JSON do seed na raiz (como no `SeedLoaderTests`).
final class ExerciseGuideLibraryTests: XCTestCase {
    func testE8_bundleGuidesLoadAndValidate() throws {
        let catalog = ExerciseGuideLibrary.load(bundle: .main)

        XCTAssertEqual(catalog.guides.count, 73, "as 55 guias aprovadas pelo dono e as 18 do lote 6")
        XCTAssertEqual(Set(catalog.guides.map(\.slug)).count, catalog.guides.count, "E1: uma guia por slug")
        XCTAssertNotNil(catalog.guide(forSlug: "barbell-back-squat"))
        XCTAssertNotNil(catalog.guide(forSlug: "brisk-walk"))
        XCTAssertNotNil(catalog.guide(forSlug: "run-intervals"))
        XCTAssertNotNil(catalog.guide(forSlug: "stationary-bike"))

        // O mesmo arquivo passa no validador do núcleo contra o catálogo do bundle.
        let guidesURL = try XCTUnwrap(Bundle.main.url(forResource: ExerciseGuideLibrary.guidesResourceName, withExtension: "json"))
        let catalogURL = try XCTUnwrap(Bundle.main.url(forResource: SeedLoader.catalogResourceName, withExtension: "json"))
        let decoded = try ExerciseGuideCatalog.decode(Data(contentsOf: guidesURL))
        let exercises = try JSONDecoder().decode(SeedExerciseCatalog.self, from: Data(contentsOf: catalogURL)).exercises
        XCTAssertEqual(ExerciseGuideValidator.problems(in: decoded, exercises: exercises), [])
    }

    func testE8_invalidFileFallsBackToEmpty() throws {
        let catalogURL = try XCTUnwrap(Bundle.main.url(forResource: SeedLoader.catalogResourceName, withExtension: "json"))
        let catalogData = try Data(contentsOf: catalogURL)
        let guidesURL = try XCTUnwrap(Bundle.main.url(forResource: ExerciseGuideLibrary.guidesResourceName, withExtension: "json"))
        let guidesData = try Data(contentsOf: guidesURL)

        // JSON que não decodifica.
        XCTAssertEqual(ExerciseGuideLibrary.load(guidesData: Data("não é json".utf8), catalogData: catalogData), .empty)

        // Catálogo que não decodifica.
        XCTAssertEqual(ExerciseGuideLibrary.load(guidesData: guidesData, catalogData: Data("{}".utf8)), .empty)

        // Decodifica, mas reprova na validação: E3 (rig errado).
        let wrongRig = Data(#"{"version": 1, "rig": "outro", "units": "stature", "guides": []}"#.utf8)
        XCTAssertEqual(ExerciseGuideLibrary.load(guidesData: wrongRig, catalogData: catalogData), .empty)

        // Decodifica, mas reprova: E1 (slug fora do catálogo).
        let decoded = try ExerciseGuideCatalog.decode(guidesData)
        let squat = try XCTUnwrap(decoded.guide(forSlug: "barbell-back-squat"))
        let unknown = ExerciseGuide(
            slug: "exercicio-que-nao-existe",
            view: squat.view,
            motion: squat.motion,
            anchor: squat.anchor,
            timing: squat.timing,
            scene: squat.scene,
            props: squat.props,
            arms: squat.arms,
            frames: squat.frames,
            cue: squat.cue,
            moving: squat.moving,
            works: squat.works,
            a11y: squat.a11y,
            steps: squat.steps,
            mistakes: squat.mistakes
        )
        let withUnknownSlug = try JSONEncoder().encode(ExerciseGuideCatalog(guides: [unknown]))
        XCTAssertEqual(ExerciseGuideLibrary.load(guidesData: withUnknownSlug, catalogData: catalogData), .empty)

        // O mesmo arquivo, sem a guia ruim, passa.
        let valid = try JSONEncoder().encode(ExerciseGuideCatalog(guides: [squat]))
        XCTAssertEqual(ExerciseGuideLibrary.load(guidesData: valid, catalogData: catalogData).guides.map(\.slug), ["barbell-back-squat"])

        // Bundle sem o arquivo (o de testes não carrega os JSON do seed).
        let testBundle = Bundle(for: ExerciseGuideLibraryTests.self)
        if testBundle.url(forResource: ExerciseGuideLibrary.guidesResourceName, withExtension: "json") == nil {
            XCTAssertEqual(ExerciseGuideLibrary.load(bundle: testBundle), .empty)
        }
    }
}
