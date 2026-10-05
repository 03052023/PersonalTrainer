import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T10.6, SPEC RF-16 e RF-43 (pendência B-2 da 2.1): o editor de um exercício limita o máximo da faixa pela
/// medida dele, 50 repetições, 300 segundos, 100 passos ou 180 minutos, e a mensagem de validação diz a
/// unidade. O limite de 50 recusava o "Longo e leve" do Cardio (45 a 75 min).
@MainActor
final class TargetDraftMeasureTests: XCTestCase {
    private typealias Draft = ProgramDetailViewModel.TargetDraft

    private func makeDraft(
        repMin: Int,
        repMax: Int,
        measure: ExerciseMeasure
    ) -> Draft {
        let target = ExerciseTarget(
            exerciseID: UUID(),
            order: 0,
            sets: 3,
            repMin: repMin,
            repMax: repMax,
            targetRIR: 2,
            restSeconds: 60
        )
        return Draft(target: target, loadUnit: .kilograms, loadIncrement: 2.5, isBodyweight: false, measure: measure)
    }

    func testRF16_rangeLimitByMeasure() {
        let table: [(measure: ExerciseMeasure, limit: Int)] = [
            (.reps, 50),
            (.seconds, 300),
            (.steps, 100),
            (.minutes, 180),
        ]
        for row in table {
            XCTAssertEqual(Draft.maxLimit(for: row.measure), row.limit, "\(row.measure)")

            // Um máximo gravado acima do teto volta para o teto, sem quebrar a faixa.
            let wild = makeDraft(repMin: 8, repMax: 500, measure: row.measure)
            XCTAssertEqual(wild.repMaxLimit, row.limit, "\(row.measure)")
            XCTAssertEqual(wild.repMax, row.limit, "\(row.measure)")
            XCTAssertEqual(wild.repMin, 8)
            XCTAssertEqual(wild.repMaxRange, 9...row.limit, "\(row.measure)")
            XCTAssertEqual(wild.repMinRange, 1...(row.limit - 1), "\(row.measure)")
            XCTAssertNil(wild.validationMessage, "\(row.measure)")

            // No teto, o stepper do máximo não passa dele.
            let atLimit = makeDraft(repMin: row.limit - 1, repMax: row.limit, measure: row.measure)
            XCTAssertEqual(atLimit.repMaxRange, row.limit...row.limit, "\(row.measure)")
        }
    }

    /// O "Longo e leve" do Cardio (45–75 min) e as isometrias longas cabem; em repetições, 75 volta a 50.
    func testRF16_longRangesFitTheirMeasure() {
        let long = makeDraft(repMin: 45, repMax: 75, measure: .minutes)
        XCTAssertEqual(long.repMin, 45)
        XCTAssertEqual(long.repMax, 75)
        XCTAssertNil(long.validationMessage)

        let plank = makeDraft(repMin: 60, repMax: 120, measure: .seconds)
        XCTAssertEqual(plank.repMax, 120)
        XCTAssertNil(plank.validationMessage)

        let carry = makeDraft(repMin: 40, repMax: 80, measure: .steps)
        XCTAssertEqual(carry.repMax, 80)
        XCTAssertNil(carry.validationMessage)

        let reps = makeDraft(repMin: 45, repMax: 75, measure: .reps)
        XCTAssertEqual(reps.repMax, 50, "Em repetições o teto continua 50")
    }

    func testRF16_validationMessageByMeasure() {
        let table: [(measure: ExerciseMeasure, limit: Int, message: String)] = [
            (.reps, 50, "A faixa de repetições deve ter o mínimo menor que o máximo, entre 1 e 50."),
            (.seconds, 300, "A faixa de segundos deve ter o mínimo menor que o máximo, entre 1 e 300."),
            (.steps, 100, "A faixa de passos deve ter o mínimo menor que o máximo, entre 1 e 100."),
            (.minutes, 180, "A faixa de minutos deve ter o mínimo menor que o máximo, entre 1 e 180."),
        ]
        for row in table {
            var draft = makeDraft(repMin: 10, repMax: 20, measure: row.measure)
            XCTAssertNil(draft.validationMessage, "\(row.measure)")

            draft.repMax = row.limit
            XCTAssertNil(draft.validationMessage, "No teto vale: \(row.measure)")

            draft.repMax = row.limit + 1
            XCTAssertEqual(draft.validationMessage, row.message, "Acima do teto: \(row.measure)")

            draft.repMax = 20
            draft.repMin = 20
            XCTAssertEqual(draft.validationMessage, row.message, "Mínimo igual ao máximo: \(row.measure)")

            draft.repMin = 0
            XCTAssertEqual(draft.validationMessage, row.message, "Mínimo abaixo de 1: \(row.measure)")
        }
    }

    /// DESIGN §6: a mensagem diz o fato e a unidade, sem exclamação.
    func testRF16_validationMessageHasNoSlogans() {
        for measure in ExerciseMeasure.allCases {
            var draft = makeDraft(repMin: 10, repMax: 20, measure: measure)
            draft.repMax = 1_000
            let message = draft.validationMessage ?? ""
            XCTAssertFalse(message.isEmpty, "\(measure)")
            XCTAssertFalse(message.contains("!"), message)
        }
    }
}
