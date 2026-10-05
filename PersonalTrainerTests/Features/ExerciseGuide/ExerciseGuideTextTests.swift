import CoreGraphics
import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// "Como fazer" (SPEC RF-40, §7.12 E1, E2 e E9; docs/V23-UI-CONTRACT.md §4.4 item 4): quando o botão aparece, o
/// "Trabalha: …", o formato dos erros comuns e os sinais da animação. Só funções puras, com as guias reais do
/// bundle (`Bundle.main` é o app hospedeiro dos testes).
@MainActor
final class ExerciseGuideTextTests: XCTestCase {
    private var bundleGuides: ExerciseGuideCatalog {
        ExerciseGuideLibrary.load(bundle: .main)
    }

    func testE1_guideButtonOnlyWithGuide() throws {
        let catalog = bundleGuides
        let squat = try XCTUnwrap(ExerciseGuideText.guide(forSlug: "barbell-back-squat", isCustom: false, in: catalog))
        XCTAssertEqual(squat.slug, "barbell-back-squat")

        XCTAssertNil(
            ExerciseGuideText.guide(forSlug: "barbell-back-squat", isCustom: true, in: catalog),
            "exercício personalizado nunca mostra o botão"
        )
        XCTAssertNil(ExerciseGuideText.guide(forSlug: "meu-exercicio-1", isCustom: false, in: catalog), "sem guia, sem botão")
        XCTAssertNil(ExerciseGuideText.guide(forSlug: nil, isCustom: false, in: catalog), "exercício que sumiu do catálogo")
        XCTAssertNil(ExerciseGuideText.guide(forSlug: "", isCustom: false, in: catalog))
        XCTAssertNil(
            ExerciseGuideText.guide(forSlug: "barbell-back-squat", isCustom: false, in: .empty),
            "E8: arquivo reprovado → catálogo vazio → nenhum botão"
        )

        // Na folha "Informações do exercício", a seção segue o slug do conteúdo (RF-47).
        let content = ExerciseInfoContent(
            id: UUID(),
            exerciseID: UUID(),
            name: "Agachamento livre",
            equipment: .barbell,
            loadUnit: .kilograms,
            measure: .reps,
            machineNotes: nil,
            sets: 3,
            targetReps: 8,
            repMin: 6,
            repMax: 10,
            targetRIR: 2,
            load: 60,
            restSeconds: 150,
            note: .hold,
            lastSession: nil,
            slug: "barbell-back-squat",
            isCustom: false,
            primaryMuscles: [.quads, .glutes],
            movementPattern: .squat
        )
        XCTAssertNotNil(ExerciseGuideText.guide(forSlug: content.slug, isCustom: content.isCustom, in: catalog))
    }

    func testRF40_worksText() throws {
        let catalog = bundleGuides
        let squat = try XCTUnwrap(catalog.guide(forSlug: "barbell-back-squat"))
        let walk = try XCTUnwrap(catalog.guide(forSlug: "brisk-walk"))

        XCTAssertEqual(
            ExerciseGuideText.worksLine(guide: squat, primaryMuscles: [.quads, .glutes]),
            "Trabalha: quadríceps (frente das coxas) e glúteos",
            "sem `works`, os grupos primários do catálogo"
        )
        XCTAssertEqual(ExerciseGuideText.works(guide: squat, primaryMuscles: [.chest, .triceps, .shoulders]), "peito, tríceps e ombros")
        XCTAssertEqual(ExerciseGuideText.works(guide: squat, primaryMuscles: [.back]), "costas")
        XCTAssertNil(ExerciseGuideText.worksLine(guide: squat, primaryMuscles: []), "sem nada a dizer, a linha some")

        XCTAssertEqual(
            ExerciseGuideText.worksLine(guide: walk, primaryMuscles: [.quads, .glutes]),
            "Trabalha: coração e pulmões, com as pernas",
            "SPEC E2: `works` substitui os grupos nos aeróbicos"
        )
    }

    func testE2_mistakeSplitsErrorAndFix() {
        let parts = ExerciseGuideText.mistakeParts("Arredondar as costas: mantenha o peito aberto.")
        XCTAssertEqual(parts.mistake, "Arredondar as costas:")
        XCTAssertEqual(parts.fix, "mantenha o peito aberto.")

        let single = ExerciseGuideText.mistakeParts("Sem correção")
        XCTAssertEqual(single.mistake, "Sem correção")
        XCTAssertNil(single.fix)
    }

    /// SPEC E9: a seta aparece no começo da ida e some; o fantasma da posição inicial cresce até o fim.
    func testE9_cueAndGhostFollowTheMovement() {
        XCTAssertEqual(GuideIllustrationView.cueOpacity(at: 0, last: 1), 1)
        XCTAssertEqual(GuideIllustrationView.cueOpacity(at: 0.35, last: 1), 0, accuracy: 0.000_1)
        XCTAssertEqual(GuideIllustrationView.cueOpacity(at: 1, last: 1), 0)
        XCTAssertEqual(GuideIllustrationView.ghostOpacity(at: 0, last: 2), 0)
        XCTAssertEqual(GuideIllustrationView.ghostOpacity(at: 1, last: 2), 0.5, accuracy: 0.000_1)
        XCTAssertEqual(GuideIllustrationView.ghostOpacity(at: 2, last: 2), 1)
        XCTAssertEqual(GuideIllustrationView.ghostOpacity(at: 0, last: 0), 0, "um quadro só não tem fantasma")
    }

    /// DESIGN §12 e SPEC E9: o que se move, o lado de lá, o equipamento e a seta com contraste de pelo menos 3:1
    /// contra o fundo, nos modos claro e escuro (fórmula da WCAG, como o `Test-Contrast` da folha).
    func testRF40_guideInkContrast() {
        for dark in [false, true] {
            let ink = GuideInk.make(dark: dark)
            let strong: [GuideInk.RGB] = [ink.nearMove, ink.farMove, ink.equipment, ink.arrow]
            for color in strong {
                XCTAssertGreaterThanOrEqual(contrast(color, ink.background), 3, "modo \(dark ? "escuro" : "claro"): \(color)")
            }
            XCTAssertGreaterThan(contrast(ink.nearMove, ink.background), contrast(ink.nearStill, ink.background), "o que se move é mais forte")
        }
    }

    /// Enquadramento: a figura inteira, com o chão, cabe no quadro em todo o movimento.
    func testRF40_figureBoundsContainTheFloorAndTheBody() throws {
        let squat = try XCTUnwrap(bundleGuides.guide(forSlug: "barbell-back-squat"))
        let figure = GuideFigure(guide: squat)
        XCTAssertLessThanOrEqual(figure.bounds.minY, 0, "o chão fica dentro")
        XCTAssertGreaterThan(figure.bounds.maxY, 0.9, "a cabeça fica dentro")
        XCTAssertTrue(figure.animates)
        XCTAssertFalse(figure.moving.isEmpty)
        let camera = GuideCamera(fitting: figure.bounds, in: CGRect(x: 0, y: 0, width: 300, height: 300))
        let floor = camera.point(GuidePoint(x: 0, y: 0))
        XCTAssertLessThanOrEqual(floor.y, 300)
        XCTAssertGreaterThan(camera.scale, 0)
    }

    // MARK: - WCAG

    private func contrast(_ a: GuideInk.RGB, _ b: GuideInk.RGB) -> Double {
        let la = luminance(a)
        let lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private func luminance(_ color: GuideInk.RGB) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.040_45 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
    }
}
