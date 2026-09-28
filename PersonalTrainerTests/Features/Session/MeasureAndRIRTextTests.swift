import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Funções de formatação da versão 2.1 (contrato V21 §B2): medida do exercício nas telas
/// (SPEC RF-43: "3 × 20–40 s", "30 passos", stepper "Segundos") e RIR explicado (SPEC RF-41:
/// significado de cada valor, escala e leitura acessível "parar com 2 repetições de reserva").
/// Só funções puras; a parte visual fica para o simulador.
///
/// Versão 2.2: a sessão não mostra mais RIR (SPEC RF-41, decisão 18). O rascunho `SetDraft`, o
/// `RIRText` e o `PrescriptionSpeech` saíram, com os testes deles (docs/V22-CONTRACT.md §4.6).
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

    /// SPEC RF-43 e §7.14 F1 (2.3, D4): a tabela de docs/V23-CORE-CONTRACT.md §2.4 para `.minutes`.
    func testRF43_minutesTexts() {
        XCTAssertEqual(MeasureText.title(.minutes), "Minutos")
        XCTAssertEqual(MeasureText.pluralNoun(.minutes), "minutos")
        XCTAssertEqual(MeasureText.stepperRange(.minutes), 0...300)
        XCTAssertEqual(MeasureText.range(min: 20, max: 40, measure: .minutes), "20–40 min")
        XCTAssertEqual(MeasureText.amount(30, measure: .minutes), "30 min")
        XCTAssertEqual(MeasureText.spokenAmount(1, measure: .minutes), "1 minuto")
        XCTAssertEqual(MeasureText.spokenAmount(30, measure: .minutes), "30 minutos")
        XCTAssertEqual(
            MeasureText.spokenSetsAndRange(sets: 4, min: 2, max: 4, measure: .minutes),
            "4 séries de 2 a 4 minutos"
        )
        XCTAssertEqual(TodayTargetText.amount(1, measure: .minutes), "1 minuto")
        XCTAssertEqual(TodayTargetText.amount(30, measure: .minutes), "30 minutos")
        XCTAssertEqual(TodayTargetText.compactAmount(30, measure: .minutes), "30 min")
        XCTAssertEqual(
            SessionSheetText.firstTimeHint(goal: 30, targetRIR: 3, measure: .minutes),
            "Escolha uma carga com a qual você aguentaria mais do que isso. Hoje faça 30 minutos."
        )
        XCTAssertEqual(
            SessionSheetText.doneSummary(
                [SessionSheetText.LoggedSet(load: 0, reps: 30)],
                unit: .kilograms,
                equipment: .bodyweight,
                measure: .minutes
            ),
            "30 min"
        )
        // As medidas de antes não mudam.
        XCTAssertEqual(TodayTargetText.compactAmount(30, measure: .seconds), "30 s")
        XCTAssertEqual(TodayTargetText.amount(30, measure: .steps), "30 passos")
        XCTAssertEqual(MeasureText.amount(10, measure: .reps), "10")
    }

    func testRF43_minutesDurationEstimate_countsSixtySecondsPerMinute() {
        let exercise = ExerciseDefinition(
            slug: "brisk-walk",
            name: "Caminhada rápida",
            primaryMuscles: [.quads, .glutes],
            equipment: .bodyweight,
            loadUnit: .kilograms,
            loadIncrement: 2.5,
            movementPattern: .cardio
        )
        let target = ExerciseTarget(exerciseID: exercise.id, order: 0, sets: 1, repMin: 20, repMax: 40, targetRIR: 3, restSeconds: 60)
        let planned = PlannedExercise(
            id: UUID(),
            exercise: exercise,
            target: target,
            prescription: ExercisePrescription(
                exerciseID: exercise.id,
                load: nil,
                sets: 1,
                repMin: 20,
                repMax: 40,
                targetReps: 20,
                targetRIR: 3,
                restSeconds: 60,
                note: .calibrate
            )
        )

        // 1 série × (30 min em média × 60 s + 60 s de descanso) + 120 s de preparação.
        XCTAssertEqual(SessionDurationEstimate.seconds(for: planned, measure: .minutes), 1 * (30 * 60 + 60) + 120, accuracy: 0.001)
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
