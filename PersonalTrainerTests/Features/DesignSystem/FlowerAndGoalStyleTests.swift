import SwiftUI
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Flor Brisa e `GoalStyle` (docs/V22-CONTRACT.md §3.6, SPEC decisão 18, DESIGN §2/§4): o subtítulo
/// do Combate e a geometria das pétalas (`BrisaPetalShape`/`BrisaCenterShape`, dentro do retângulo pedido, não
/// vazias e determinísticas — mesma flor sempre que se pede o mesmo tamanho).
@MainActor
final class FlowerAndGoalStyleTests: XCTestCase {

    // MARK: - S1: subtítulo do Combate

    func testS1_subtitles() {
        XCTAssertEqual(ProgramGoal.longevity.subtitle, "Viver bem por mais tempo")
        XCTAssertEqual(ProgramGoal.hypertrophy.subtitle, "Ganhar massa muscular")
        XCTAssertEqual(ProgramGoal.strength.subtitle, "Ficar mais forte")
        XCTAssertEqual(ProgramGoal.combat.subtitle, "Potência e resistência")
        // SPEC RF-48 (2.3, D2): o objetivo `endurance` virou Fôlego, cardiovascular.
        XCTAssertEqual(ProgramGoal.endurance.subtitle, "Mais fôlego e disposição")
    }

    func testRF48_folegoNameSymbolAndPetal() {
        XCTAssertEqual(ProgramGoal.endurance.displayName, "Fôlego")
        XCTAssertEqual(ProgramGoal.endurance.rawValue, "endurance")
        XCTAssertEqual(ProgramGoal.endurance.symbolName, "wind")
        XCTAssertEqual(ProgramGoal.endurance.petalIndex, 4)
    }

    // MARK: - S10: geometria Brisa

    func testS10_petalPaths_areInsideRectAndNonEmpty() {
        for size in [CGFloat(26), CGFloat(56), CGFloat(92)] {
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            // Uma margem de meio ponto para o arredondamento de ponto flutuante da normalização, não
            // para deixar a pétala "vazar" de verdade do retângulo.
            let tolerant = rect.insetBy(dx: -0.5, dy: -0.5)

            for goal in ProgramGoal.allCases {
                let path = BrisaPetalShape(petalIndex: goal.petalIndex).path(in: rect)
                XCTAssertFalse(path.isEmpty, "\(goal) a \(size) pt não pode ficar vazia")
                XCTAssertTrue(
                    tolerant.contains(path.boundingRect),
                    "\(goal) a \(size) pt saiu do retângulo: \(path.boundingRect) fora de \(rect)"
                )
            }

            let center = BrisaCenterShape().path(in: rect)
            XCTAssertFalse(center.isEmpty, "o miolo a \(size) pt não pode ficar vazio")
            XCTAssertTrue(tolerant.contains(center.boundingRect), "o miolo a \(size) pt saiu do retângulo")
        }
    }

    func testS10_petalPaths_areDeterministic() {
        for size in [CGFloat(26), CGFloat(56), CGFloat(92)] {
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            for goal in ProgramGoal.allCases {
                let first = BrisaPetalShape(petalIndex: goal.petalIndex).path(in: rect)
                let second = BrisaPetalShape(petalIndex: goal.petalIndex).path(in: rect)
                XCTAssertEqual(first, second, "\(goal) a \(size) pt deveria sair igual sempre (nada de aleatório)")
            }
            XCTAssertEqual(BrisaCenterShape().path(in: rect), BrisaCenterShape().path(in: rect))
        }
    }
}
