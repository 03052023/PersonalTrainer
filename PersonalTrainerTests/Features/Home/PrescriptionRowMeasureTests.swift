import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Testes da linha da tela Hoje com a medida do exercício (SPEC RF-43) e a leitura por voz da meta
/// de hoje (SPEC RF-01, RF-46). A versão 2.2 reescreveu a `PrescriptionRow` para mostrar só a meta
/// de hoje em palavras — sem RIR, sem faixa e sem descanso (decisão 18; docs/V22-CONTRACT.md
/// §1.5, §3.3) — e estes testes foram atualizados junto, na tarefa `home`.
@MainActor
final class PrescriptionRowMeasureTests: XCTestCase {

    func testRF43_row_perMeasure_withLoad() {
        let isometry = makePlanned(equipment: .machine, repMin: 20, repMax: 40, targetReps: 20, load: 22.5)

        XCTAssertEqual(PrescriptionRow.rowText(for: isometry), "3 séries de 20 · 22,5 kg", "sem medida, repetições")
        XCTAssertEqual(PrescriptionRow.rowText(for: isometry, measure: .seconds), "3 séries de 20 s · 22,5 kg")
        XCTAssertEqual(PrescriptionRow.rowText(for: isometry, measure: .steps), "3 séries de 20 passos · 22,5 kg")
    }

    /// SPEC RF-46: peso do corpo sem carga extra não mostra carga nenhuma, em nenhuma medida.
    func testRF46_row_bodyweightWithoutExtraLoad_hidesLoadPerMeasure() {
        let plank = makePlanned(equipment: .bodyweight, repMin: 20, repMax: 40, targetReps: 20, load: 0)

        XCTAssertEqual(PrescriptionRow.rowText(for: plank, measure: .seconds), "3 séries de 20 s")
        XCTAssertEqual(PrescriptionRow.rowText(for: plank, measure: .steps), "3 séries de 20 passos")
    }

    /// SPEC RF-41 (decisão 18): a leitura por voz não fala RIR nem faixa; primeira vez sem carga
    /// (P2) diz "escolha a carga", nunca "carga a definir" nem um número de repetições em reserva.
    func testRF01_row_spokenRowText_noRIRNoRange() {
        let squat = makePlanned(equipment: .barbell, repMin: 8, repMax: 12, targetReps: 8, load: 60)
        let calibration = makePlanned(equipment: .barbell, repMin: 8, repMax: 12, targetReps: 8, load: nil)

        XCTAssertEqual(
            PrescriptionRow.spokenRowText(for: squat),
            "3 séries de 8 repetições, 60 kg"
        )
        XCTAssertEqual(
            PrescriptionRow.spokenRowText(for: calibration, measure: .reps),
            "3 séries de 8 repetições, sem carga"
        )
    }

    // MARK: - Fixtures

    private func makePlanned(equipment: Equipment, repMin: Int, repMax: Int, targetReps: Int, load: Double?) -> PlannedExercise {
        let exercise = ExerciseDefinition(
            slug: "fixture",
            name: "Exercício fixture",
            primaryMuscles: [.core],
            equipment: equipment,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )
        return PlannedExercise(
            id: UUID(),
            exercise: exercise,
            target: ExerciseTarget(exerciseID: exercise.id, order: 0, sets: 3, repMin: repMin, repMax: repMax),
            prescription: ExercisePrescription(
                exerciseID: exercise.id,
                load: load,
                sets: 3,
                repMin: repMin,
                repMax: repMax,
                targetReps: targetReps,
                targetRIR: 2,
                restSeconds: 60,
                note: .hold
            )
        )
    }
}
