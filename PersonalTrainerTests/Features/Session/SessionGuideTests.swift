import Foundation
import XCTest
@testable import PersonalTrainer

/// Sessão guiada (SPEC RF-44 i; docs/V23-UI-CONTRACT.md §4.4 item 1): o passo atual é o primeiro exercício
/// pendente, com a série seguinte dele, e o botão grande diz o que vai acontecer. Só a função pura `SessionGuide`.
final class SessionGuideTests: XCTestCase {
    private let squatID = UUID()
    private let benchID = UUID()
    private let walkID = UUID()

    private struct StepCase {
        let name: String
        let items: [SessionGuide.Item]
        let exerciseID: UUID?
        let setNumber: Int
        let totalSets: Int
        let action: SessionGuide.Action
        let line: String
    }

    func testRF44i_guideStepsFollowPendingExercises() {
        let cases: [StepCase] = [
            StepCase(
                name: "início: a primeira série do primeiro exercício",
                items: [squat(logged: 0), bench(logged: 0), walk(logged: 0)],
                exerciseID: squatID, setNumber: 1, totalSets: 3, action: .markSet,
                line: "Agora: Agachamento livre · série 1 de 3"
            ),
            StepCase(
                name: "série do meio",
                items: [squat(logged: 1), bench(logged: 0), walk(logged: 0)],
                exerciseID: squatID, setNumber: 2, totalSets: 3, action: .markSet,
                line: "Agora: Agachamento livre · série 2 de 3"
            ),
            StepCase(
                name: "exercício feito: passa ao próximo",
                items: [squat(logged: 3), bench(logged: 1), walk(logged: 0)],
                exerciseID: benchID, setNumber: 2, totalSets: 2, action: .markSet,
                line: "Agora: Supino reto · série 2 de 2"
            ),
            StepCase(
                name: "exercício de uma série: Marcar como feito",
                items: [squat(logged: 3), bench(logged: 2), walk(logged: 0)],
                exerciseID: walkID, setNumber: 1, totalSets: 1, action: .markDone,
                line: "Agora: Caminhada rápida"
            ),
            StepCase(
                name: "pulados ficam de fora",
                items: [squat(logged: 0, skipped: true), bench(logged: 0, skipped: true), walk(logged: 0)],
                exerciseID: walkID, setNumber: 1, totalSets: 1, action: .markDone,
                line: "Agora: Caminhada rápida"
            ),
            StepCase(
                name: "tudo feito (ou pulado): concluir",
                items: [squat(logged: 3), bench(logged: 0, skipped: true), walk(logged: 1)],
                exerciseID: nil, setNumber: 0, totalSets: 0, action: .finish,
                line: "Tudo marcado."
            ),
            StepCase(
                name: "séries a mais não reabrem o exercício",
                items: [squat(logged: 4), bench(logged: 2), walk(logged: 1)],
                exerciseID: nil, setNumber: 0, totalSets: 0, action: .finish,
                line: "Tudo marcado."
            ),
            StepCase(
                name: "sessão sem exercícios: concluir",
                items: [],
                exerciseID: nil, setNumber: 0, totalSets: 0, action: .finish,
                line: "Tudo marcado."
            ),
        ]

        for testCase in cases {
            let step = SessionGuide.step(for: testCase.items)
            XCTAssertEqual(step.exerciseID, testCase.exerciseID, testCase.name)
            XCTAssertEqual(step.setNumber, testCase.setNumber, testCase.name)
            XCTAssertEqual(step.totalSets, testCase.totalSets, testCase.name)
            XCTAssertEqual(step.action, testCase.action, testCase.name)
            XCTAssertEqual(SessionGuide.line(for: step, isResting: false, restSourceID: nil), testCase.line, testCase.name)
        }
    }

    func testRF44i_guideButtonTitles() {
        XCTAssertEqual(SessionGuide.buttonTitle(.markSet), "Marcar série")
        XCTAssertEqual(SessionGuide.buttonTitle(.markDone), "Marcar como feito")
        XCTAssertEqual(SessionGuide.buttonTitle(.finish), "Concluir a sessão")

        let titles: [String] = [
            SessionGuide.buttonTitle(SessionGuide.step(for: [squat(logged: 1)]).action),
            SessionGuide.buttonTitle(SessionGuide.step(for: [walk(logged: 0)]).action),
            SessionGuide.buttonTitle(SessionGuide.step(for: [walk(logged: 1)]).action),
        ]
        XCTAssertEqual(titles, ["Marcar série", "Marcar como feito", "Concluir a sessão"])
    }

    /// Durante o descanso, a linha mostra o que vem: a próxima série do mesmo exercício ou o próximo exercício.
    func testRF44i_guideLineDuringRest() {
        let middle = SessionGuide.step(for: [squat(logged: 2), bench(logged: 0)])
        XCTAssertEqual(SessionGuide.line(for: middle, isResting: true, restSourceID: squatID), "A seguir: série 3")

        let next = SessionGuide.step(for: [squat(logged: 3), bench(logged: 0)])
        XCTAssertEqual(SessionGuide.line(for: next, isResting: true, restSourceID: squatID), "A seguir: Supino reto")

        let done = SessionGuide.step(for: [squat(logged: 3), bench(logged: 2)])
        XCTAssertEqual(SessionGuide.line(for: done, isResting: true, restSourceID: benchID), "Tudo marcado.")
    }

    // MARK: - Fixtures

    private func squat(logged: Int, skipped: Bool = false) -> SessionGuide.Item {
        SessionGuide.Item(id: squatID, name: "Agachamento livre", prescribedSets: 3, loggedSets: logged, isSkipped: skipped)
    }

    private func bench(logged: Int, skipped: Bool = false) -> SessionGuide.Item {
        SessionGuide.Item(id: benchID, name: "Supino reto", prescribedSets: 2, loggedSets: logged, isSkipped: skipped)
    }

    private func walk(logged: Int, skipped: Bool = false) -> SessionGuide.Item {
        SessionGuide.Item(id: walkID, name: "Caminhada rápida", prescribedSets: 1, loggedSets: logged, isSkipped: skipped)
    }
}
