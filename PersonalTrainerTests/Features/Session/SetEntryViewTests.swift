import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Cobre os helpers puros do componente de registro de série (T1.6, SPEC RF-03). A parte
/// visual só é verificada em preview/CI; aqui garantimos a aritmética dos steppers e o
/// formato do texto de carga, que são o que quebraria em silêncio.
@MainActor
final class SetEntryViewTests: XCTestCase {

    // MARK: - LoadStepper

    func testLoadStepper_displayText_matchesPrescriptionSummaryFormat() {
        XCTAssertEqual(LoadStepper.displayText(for: 60, unit: .kilograms), "60 kg")
        XCTAssertEqual(LoadStepper.displayText(for: 62.5, unit: .kilograms), "62,5 kg")
        XCTAssertEqual(LoadStepper.displayText(for: 0, unit: .kilograms), "0 kg")
        XCTAssertEqual(LoadStepper.displayText(for: 12, unit: .plates), "12 placas")
        XCTAssertEqual(LoadStepper.displayText(for: 7, unit: .level), "nível 7")
    }

    func testLoadStepper_displayText_agreesWithSetDraftSummary() {
        let draft = SetDraft(
            load: 62.5,
            reps: 8,
            rir: 2,
            setIndex: 0,
            plannedSets: 3,
            prescribedLoad: 62.5,
            loadIncrement: 2.5,
            loadUnit: .kilograms,
            repMin: 8,
            repMax: 12,
            targetReps: 8,
            targetRIR: 2,
            note: .increase
        )

        let loadText = LoadStepper.displayText(for: draft.load, unit: draft.loadUnit)

        XCTAssertTrue(
            draft.prescriptionSummary.contains(loadText),
            "Stepper e cabeçalho devem mostrar a carga com o mesmo texto: \(draft.prescriptionSummary)"
        )
    }

    func testLoadStepper_stepped_addsIncrement() {
        XCTAssertEqual(LoadStepper.stepped(60, by: 2.5), 62.5)
        XCTAssertEqual(LoadStepper.stepped(62.5, by: -2.5), 60)
        XCTAssertEqual(LoadStepper.stepped(0, by: 5), 5)
    }

    func testLoadStepper_stepped_neverGoesBelowZero() {
        XCTAssertEqual(LoadStepper.stepped(2.5, by: -2.5), 0)
        XCTAssertEqual(LoadStepper.stepped(1, by: -2.5), 0)
        XCTAssertEqual(LoadStepper.stepped(0, by: -2.5), 0)
        XCTAssertEqual(LoadStepper.stepped(0, by: -2.5).sign, .plus, "Nunca formatar \"-0 kg\"")
    }

    // MARK: - RepsStepper

    func testRepsStepper_stepped_movesInsideRange() {
        XCTAssertEqual(RepsStepper.stepped(8, by: 1, in: 0...50), 9)
        XCTAssertEqual(RepsStepper.stepped(8, by: -1, in: 0...50), 7)
    }

    func testRepsStepper_stepped_clampsToRangeBounds() {
        XCTAssertEqual(RepsStepper.stepped(50, by: 1, in: 0...50), 50)
        XCTAssertEqual(RepsStepper.stepped(0, by: -1, in: 0...50), 0)
        XCTAssertEqual(RepsStepper.stepped(60, by: 1, in: 0...50), 50)
        XCTAssertEqual(RepsStepper.stepped(-3, by: -1, in: 0...50), 0)
    }

    // MARK: - SetEntryView

    func testSetEntryView_highlightRange_keepsValidBounds() {
        XCTAssertEqual(SetEntryView.highlightRange(repMin: 8, repMax: 12), 8...12)
        XCTAssertEqual(SetEntryView.highlightRange(repMin: 10, repMax: 10), 10...10)
    }

    func testSetEntryView_highlightRange_normalizesInvertedBounds() {
        XCTAssertEqual(SetEntryView.highlightRange(repMin: 12, repMax: 8), 8...12)
    }
}
