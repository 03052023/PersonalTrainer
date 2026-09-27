import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Testes da linha da tela Hoje com a medida do exercício (SPEC RF-43) e a leitura por voz,
/// movidos de `Session/MeasureAndRIRTextTests.swift` na versão 2.2 (docs/V22-CONTRACT.md §1) para
/// que cada arquivo de teste tenha uma tarefa dona só: este é da tarefa `home`, que reescreve a
/// `PrescriptionRow` (a meta de hoje em palavras, sem RIR) e atualiza estes testes junto.
@MainActor
final class PrescriptionRowMeasureTests: XCTestCase {

    func testRF43_prescriptionRow_summary_perMeasure() {
        let plank = makePlanned(slug: "plank", repMin: 20, repMax: 40, load: 0, restSeconds: 60)

        XCTAssertEqual(PrescriptionRow.summary(for: plank), "3 × 20–40 · 0 kg · RIR 2 · 1 min", "sem medida, repetições")
        XCTAssertEqual(PrescriptionRow.summary(for: plank, measure: .seconds), "3 × 20–40 s · 0 kg · RIR 2 · 1 min")
        XCTAssertEqual(PrescriptionRow.summary(for: plank, measure: .steps), "3 × 20–40 passos · 0 kg · RIR 2 · 1 min")
    }

    func testRF41_prescriptionRow_spokenSummary() {
        let squat = makePlanned(slug: "agachamento-livre", repMin: 8, repMax: 12, load: 60, restSeconds: 120)
        let calibration = makePlanned(slug: "supino-reto", repMin: 8, repMax: 12, load: nil, restSeconds: 90)

        XCTAssertEqual(
            PrescriptionRow.spokenSummary(for: squat),
            "3 séries de 8 a 12 repetições, 60 kg, parar com 2 repetições de reserva, descanso de 2 minutos"
        )
        XCTAssertEqual(
            PrescriptionRow.spokenSummary(for: calibration, measure: .reps),
            "3 séries de 8 a 12 repetições, carga a definir na primeira série, parar com 2 repetições de reserva, descanso de 1 minuto e 30 segundos"
        )
    }

    // MARK: - Fixtures

    private func makePlanned(slug: String, repMin: Int, repMax: Int, load: Double?, restSeconds: Int) -> PlannedExercise {
        let exercise = ExerciseDefinition(
            slug: slug,
            name: slug,
            primaryMuscles: [.core],
            equipment: .bodyweight,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )
        return PlannedExercise(
            id: UUID(),
            exercise: exercise,
            target: ExerciseTarget(exerciseID: exercise.id, order: 0, sets: 3, repMin: repMin, repMax: repMax, restSeconds: restSeconds),
            prescription: ExercisePrescription(
                exerciseID: exercise.id,
                load: load,
                sets: 3,
                repMin: repMin,
                repMax: repMax,
                targetReps: repMin,
                targetRIR: 2,
                restSeconds: restSeconds,
                note: .hold
            )
        )
    }
}
