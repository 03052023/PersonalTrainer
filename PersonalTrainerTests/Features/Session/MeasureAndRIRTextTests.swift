import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Funções de formatação da versão 2.1 (contrato V21 §B2): medida do exercício nas telas
/// (SPEC RF-43: "3 × 20–40 s", "30 passos", stepper "Segundos") e RIR explicado (SPEC RF-41:
/// significado de cada valor, escala e leitura acessível "parar com 2 repetições de reserva").
/// Só funções puras; a parte visual fica para o simulador.
///
/// Versão 2.2: a sessão não mostra mais RIR (SPEC RF-41, decisão 18) e o rascunho `SetDraft` saiu
/// com o seletor. `RIRText` e `PrescriptionSpeech` continuam enquanto outras pastas os usarem
/// (docs/V22-CONTRACT.md §2.4); o integrador apaga o que ficar sem uso.
@MainActor
final class MeasureAndRIRTextTests: XCTestCase {

    // MARK: - RF-43 MeasureText

    func testRF43_title_perMeasure() {
        XCTAssertEqual(MeasureText.title(.reps), "Repetições")
        XCTAssertEqual(MeasureText.title(.seconds), "Segundos")
        XCTAssertEqual(MeasureText.title(.steps), "Passos")
    }

    func testRF43_range_addsUnitOnlyOutsideReps() {
        XCTAssertEqual(MeasureText.range(min: 8, max: 12, measure: .reps), "8–12")
        XCTAssertEqual(MeasureText.range(min: 20, max: 40, measure: .seconds), "20–40 s")
        XCTAssertEqual(MeasureText.range(min: 20, max: 40, measure: .steps), "20–40 passos")
    }

    func testRF43_amount_perMeasure() {
        XCTAssertEqual(MeasureText.amount(10, measure: .reps), "10")
        XCTAssertEqual(MeasureText.amount(30, measure: .seconds), "30 s")
        XCTAssertEqual(MeasureText.amount(30, measure: .steps), "30 passos")
        XCTAssertEqual(MeasureText.amount(1, measure: .steps), "1 passo")
    }

    func testRF43_spokenAmount_singularAndPlural() {
        XCTAssertEqual(MeasureText.spokenAmount(10, measure: .reps), "10 repetições")
        XCTAssertEqual(MeasureText.spokenAmount(1, measure: .reps), "1 repetição")
        XCTAssertEqual(MeasureText.spokenAmount(30, measure: .seconds), "30 segundos")
        XCTAssertEqual(MeasureText.spokenAmount(1, measure: .seconds), "1 segundo")
        XCTAssertEqual(MeasureText.spokenAmount(0, measure: .steps), "0 passos")
    }

    func testRF43_spokenSetsAndRange() {
        XCTAssertEqual(
            MeasureText.spokenSetsAndRange(sets: 3, min: 8, max: 12, measure: .reps),
            "3 séries de 8 a 12 repetições"
        )
        XCTAssertEqual(
            MeasureText.spokenSetsAndRange(sets: 1, min: 20, max: 40, measure: .seconds),
            "1 série de 20 a 40 segundos"
        )
        XCTAssertEqual(
            MeasureText.spokenSetsAndRange(sets: 2, min: 10, max: 10, measure: .steps),
            "2 séries de 10 passos",
            "faixa de um número só não lê \"de 10 a 10\""
        )
        XCTAssertEqual(
            MeasureText.spokenSetsAndRange(sets: 3, min: 12, max: 8, measure: .reps),
            "3 séries de 8 a 12 repetições",
            "faixa invertida é lida em ordem"
        )
    }

    func testRF43_stepperRange_repsKeepsFiftyAndOthersGoHigher() {
        XCTAssertEqual(MeasureText.stepperRange(.reps), 0...50)
        XCTAssertTrue(MeasureText.stepperRange(.seconds).contains(120), "prancha de 2 min cabe no stepper")
        XCTAssertTrue(MeasureText.stepperRange(.steps).contains(80))
        XCTAssertEqual(MeasureText.stepperRange(.seconds).lowerBound, 0)
        XCTAssertEqual(MeasureText.stepperRange(.steps).lowerBound, 0)
    }

    func testRF12_RF43_tonnage_countsOnlyRepsExercises() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let bench: [SetResult] = [
            SetResult(load: 40, reps: 12, rir: nil, isWarmup: true, completedAt: date),
            SetResult(load: 60, reps: 10, rir: 2, isWarmup: false, completedAt: date),
            SetResult(load: 60, reps: 8, rir: 1, isWarmup: false, completedAt: date),
        ]
        let farmersWalk: [SetResult] = [
            SetResult(load: 24, reps: 30, rir: 2, isWarmup: false, completedAt: date),
        ]
        let plank: [SetResult] = [
            SetResult(load: 0, reps: 45, rir: 2, isWarmup: false, completedAt: date),
        ]

        let tonnage = MeasureText.tonnage(of: [
            (measure: .reps, sets: bench),
            (measure: .steps, sets: farmersWalk),
            (measure: .seconds, sets: plank),
        ])

        XCTAssertEqual(tonnage, 1_080, accuracy: 0.0001, "60 × 10 + 60 × 8; aquecimento, passos e segundos fora")
        XCTAssertEqual(MeasureText.tonnage(of: []), 0)
    }

    // MARK: - RF-41 RIRText

    func testRF41_meaning_eachValue() {
        XCTAssertEqual(RIRText.meaning(for: 0), "0 · nenhuma a mais")
        XCTAssertEqual(RIRText.meaning(for: 1), "1 · mais uma")
        XCTAssertEqual(RIRText.meaning(for: 2), "2 · mais duas")
        XCTAssertEqual(RIRText.meaning(for: 3), "3 · com folga")
        XCTAssertEqual(RIRText.meaning(for: 5), "5 · com folga", "RF-03: o seletor vai até 5; de 3 em diante é folga")
        XCTAssertEqual(RIRText.meaning(for: nil), "Não informado")
    }

    func testRF41_scale_matchesSpecLabels() {
        XCTAssertEqual(RIRText.scale, ["0 · nenhuma a mais", "1 · mais uma", "2 · mais duas", "3+ · com folga"])
    }

    func testRF41_spokenTarget_accessibleReading() {
        XCTAssertEqual(RIRText.spokenTarget(2), "parar com 2 repetições de reserva")
        XCTAssertEqual(RIRText.spokenTarget(1), "parar com 1 repetição de reserva")
        XCTAssertEqual(RIRText.spokenTarget(0), "parar sem repetições de reserva")
        XCTAssertEqual(RIRText.spokenTarget(4), "parar com 4 repetições de reserva")
    }

    func testRF41_spokenOption_perSegment() {
        XCTAssertEqual(RIRText.spokenOption(nil), "RIR não informado")
        XCTAssertEqual(RIRText.spokenOption(0), "RIR 0, nenhuma repetição a mais")
        XCTAssertEqual(RIRText.spokenOption(2), "RIR 2, mais duas repetições")
        XCTAssertEqual(RIRText.spokenOption(4), "RIR 4, com folga")
    }

    // MARK: - RF-41 PrescriptionSpeech

    func testRF41_prescriptionSpeech_withRest() {
        XCTAssertEqual(
            PrescriptionSpeech.text(
                sets: 3,
                repMin: 8,
                repMax: 12,
                measure: .reps,
                loadText: "60 kg",
                targetRIR: 2,
                restSeconds: 120
            ),
            "3 séries de 8 a 12 repetições, 60 kg, parar com 2 repetições de reserva, descanso de 2 minutos"
        )
    }

    func testRF41_prescriptionSpeech_restWords() {
        XCTAssertEqual(PrescriptionSpeech.rest(seconds: 120), "descanso de 2 minutos")
        XCTAssertEqual(PrescriptionSpeech.rest(seconds: 60), "descanso de 1 minuto")
        XCTAssertEqual(PrescriptionSpeech.rest(seconds: 90), "descanso de 1 minuto e 30 segundos")
        XCTAssertEqual(PrescriptionSpeech.rest(seconds: 45), "descanso de 45 segundos")
        XCTAssertEqual(PrescriptionSpeech.rest(seconds: 61), "descanso de 1 minuto e 1 segundo")
        XCTAssertEqual(PrescriptionSpeech.rest(seconds: 0), "sem descanso")
    }

    // Os testes da `PrescriptionRow` (Home) foram para `Home/PrescriptionRowMeasureTests.swift`
    // na versão 2.2 (docs/V22-CONTRACT.md §1): um arquivo de teste por tarefa.

    func testRF43_traitsCatalog_customExerciseStaysInReps() {
        let traits = ExerciseTraitsCatalog(traitsBySlug: ["plank": ExerciseTraits(measure: .seconds, atHome: true)])
        let seedPlank = ExerciseDefinition(
            slug: "plank",
            name: "Prancha",
            primaryMuscles: [.core],
            equipment: .bodyweight,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )
        let customPlank = ExerciseDefinition(
            slug: "plank",
            name: "Minha prancha",
            primaryMuscles: [.core],
            equipment: .bodyweight,
            loadUnit: .kilograms,
            loadIncrement: 2.5,
            isCustom: true
        )

        // O mesmo caminho que `PrescriptionRow` usa para achar a medida.
        XCTAssertEqual(traits.traits(for: seedPlank).measure, .seconds)
        XCTAssertEqual(traits.traits(for: customPlank).measure, .reps, "SPEC RF-43: personalizado usa reps")
    }
}
