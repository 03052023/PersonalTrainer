import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Textos compartilhados da versão 2.2 (docs/V22-CONTRACT.md §2.3): a meta de hoje em palavras
/// (SPEC RF-44, RF-46) e o selo leigo da nota (DESIGN §7). Só funções puras.
@MainActor
final class TodayTargetTextTests: XCTestCase {

    // MARK: - Meta de hoje

    func testRF44_goal_usesTargetRepsAndFallsBackToRepMin() {
        XCTAssertEqual(TodayTargetText.goal(targetReps: 9, repMin: 8), 9)
        XCTAssertEqual(TodayTargetText.goal(targetReps: 0, repMin: 8), 8, "sessões antigas sem meta gravada usam repMin")
    }

    // MARK: - RF-46 peso do corpo sem carga

    func testRF46_loadDisplay_bodyweightWithoutLoadIsHidden() {
        XCTAssertEqual(TodayTargetText.loadDisplay(load: nil, unit: .kilograms, equipment: .bodyweight), .hidden)
        XCTAssertEqual(TodayTargetText.loadDisplay(load: 0, unit: .kilograms, equipment: .bodyweight), .hidden)
    }

    func testRF46_loadDisplay_bodyweightWithExtraLoad() {
        XCTAssertEqual(
            TodayTargetText.loadDisplay(load: 2.5, unit: .kilograms, equipment: .bodyweight),
            .extra("+ 2,5 kg extra")
        )
    }

    func testRF46_loadDisplay_loadedExercises() {
        XCTAssertEqual(TodayTargetText.loadDisplay(load: nil, unit: .kilograms, equipment: .barbell), .toChoose, "P2 sem carga")
        XCTAssertEqual(TodayTargetText.loadDisplay(load: nil, unit: .kilograms, equipment: nil), .toChoose)
        XCTAssertEqual(TodayTargetText.loadDisplay(load: 62.5, unit: .kilograms, equipment: .barbell), .load("62,5 kg"))
        XCTAssertEqual(TodayTargetText.loadDisplay(load: 5, unit: .kilograms, equipment: .household), .load("5 kg"), "mochila mostra a carga")
    }

    /// SPEC RF-46 (2.3, D3): 0 num exercício com equipamento é "sem carga externa": nunca "0 kg" nem
    /// "nível 0" na tela Hoje e no Histórico.
    func testRF46_loadDisplay_zeroOnEquipmentShowsNoLoad() {
        XCTAssertEqual(TodayTargetText.loadDisplay(load: 0, unit: .kilograms, equipment: .machine), .hidden)
        XCTAssertEqual(TodayTargetText.loadDisplay(load: 0, unit: .level, equipment: .machine), .hidden)
        XCTAssertEqual(TodayTargetText.loadDisplay(load: 0, unit: .kilograms, equipment: .barbell), .hidden)
        XCTAssertEqual(TodayTargetText.row(sets: 3, goal: 12, measure: .reps, load: .hidden), "3 séries de 12")
        XCTAssertEqual(
            TodayTargetText.row(
                sets: 1,
                goal: 45,
                measure: .minutes,
                load: TodayTargetText.loadDisplay(load: 0, unit: .level, equipment: .machine)
            ),
            "45 min"
        )
    }

    func testLoadText_perUnit() {
        XCTAssertEqual(TodayTargetText.loadText(60, unit: .kilograms), "60 kg")
        XCTAssertEqual(TodayTargetText.loadText(62.5, unit: .kilograms), "62,5 kg")
        XCTAssertEqual(TodayTargetText.loadText(1250, unit: .kilograms), "1250 kg", "sem separador de milhar")
        XCTAssertEqual(TodayTargetText.loadText(1, unit: .plates), "1 placa")
        XCTAssertEqual(TodayTargetText.loadText(4, unit: .plates), "4 placas")
        XCTAssertEqual(TodayTargetText.loadText(7, unit: .level), "nível 7")
    }

    // MARK: - Linha da tela Hoje

    func testRow_matchesMockup() {
        XCTAssertEqual(TodayTargetText.row(sets: 3, goal: 3, measure: .reps, load: .load("62,5 kg")), "3 séries de 3 · 62,5 kg")
        XCTAssertEqual(TodayTargetText.row(sets: 3, goal: 5, measure: .reps, load: .hidden), "3 séries de 5")
        XCTAssertEqual(TodayTargetText.row(sets: 2, goal: 15, measure: .seconds, load: .hidden), "2 séries de 15 s")
        XCTAssertEqual(
            TodayTargetText.row(sets: 3, goal: 30, measure: .steps, load: .load("22,5 kg")),
            "3 séries de 30 passos · 22,5 kg"
        )
        XCTAssertEqual(TodayTargetText.row(sets: 4, goal: 6, measure: .reps, load: .toChoose), "4 séries de 6 · sem carga")
        XCTAssertEqual(
            TodayTargetText.row(sets: 3, goal: 5, measure: .reps, load: .extra("+ 2,5 kg extra")),
            "3 séries de 5 · + 2,5 kg extra"
        )
        XCTAssertEqual(TodayTargetText.row(sets: 1, goal: 8, measure: .reps, load: .hidden), "1 série de 8")
    }

    /// SPEC RF-46 (2.4; achado B11 da 2.3): a tela Hoje diz "sem carga", como a ficha e a folha de
    /// informações; "escolha a carga" saiu de todas as telas.
    func testRF46_todayRowSaysSemCarga() {
        XCTAssertEqual(TodayTargetText.toChooseText, "sem carga")
        XCTAssertEqual(TodayTargetText.loadLabel(.toChoose), "sem carga")
        XCTAssertEqual(TodayTargetText.row(sets: 3, goal: 8, measure: .reps, load: .toChoose), "3 séries de 8 · sem carga")
        XCTAssertEqual(
            TodayTargetText.spokenRow(sets: 3, goal: 8, measure: .reps, load: .toChoose),
            "3 séries de 8 repetições, sem carga"
        )
        XCTAssertEqual(
            TodayTargetText.row(sets: 3, goal: 30, measure: .steps, load: .toChoose),
            "3 séries de 30 passos · sem carga"
        )
        XCTAssertEqual(TodayTargetText.loadLabel(.toChoose), SessionSheetText.loadLabel(.toChoose), "a mesma palavra da ficha")
        XCTAssertEqual(TodayTargetText.row(sets: 1, goal: 30, measure: .minutes, load: .toChoose), "30 min", "aeróbico sem nível não diz nada")
    }

    // MARK: - Letra grande da ficha

    func testHeadline_matchesMockup() {
        XCTAssertEqual(TodayTargetText.headline(goal: 3, measure: .reps, load: .load("62,5 kg")), "3 repetições · 62,5 kg")
        XCTAssertEqual(TodayTargetText.headline(goal: 5, measure: .reps, load: .hidden), "5 repetições")
        XCTAssertEqual(TodayTargetText.headline(goal: 15, measure: .seconds, load: .hidden), "15 segundos")
        XCTAssertEqual(TodayTargetText.headline(goal: 30, measure: .steps, load: .load("22,5 kg")), "30 passos · 22,5 kg")
        XCTAssertEqual(TodayTargetText.headline(goal: 6, measure: .reps, load: .toChoose), "6 repetições · sem carga")
        XCTAssertEqual(TodayTargetText.headline(goal: 1, measure: .reps, load: .hidden), "1 repetição")
    }

    func testAmount_singularAndPlural() {
        XCTAssertEqual(TodayTargetText.amount(1, measure: .seconds), "1 segundo")
        XCTAssertEqual(TodayTargetText.amount(1, measure: .steps), "1 passo")
        XCTAssertEqual(TodayTargetText.compactAmount(1, measure: .steps), "1 passo")
        XCTAssertEqual(TodayTargetText.compactAmount(40, measure: .seconds), "40 s")
    }

    func testSpoken_hasNoSymbols() {
        XCTAssertEqual(
            TodayTargetText.spokenRow(sets: 3, goal: 3, measure: .reps, load: .load("62,5 kg")),
            "3 séries de 3 repetições, 62,5 kg"
        )
        XCTAssertEqual(
            TodayTargetText.spokenHeadline(goal: 5, measure: .reps, load: .extra("+ 2,5 kg extra")),
            "5 repetições, mais 2,5 kg extra"
        )
        XCTAssertEqual(TodayTargetText.spokenHeadline(goal: 15, measure: .seconds, load: .hidden), "15 segundos")
    }

    // MARK: - Descanso

    func testRestAndDetail() {
        XCTAssertEqual(TodayTargetText.rest(seconds: 240), "4 min")
        XCTAssertEqual(TodayTargetText.rest(seconds: 150), "2 min 30 s")
        XCTAssertEqual(TodayTargetText.rest(seconds: 45), "45 s")
        XCTAssertEqual(TodayTargetText.rest(seconds: 0), "sem descanso")
        XCTAssertEqual(TodayTargetText.detail(sets: 3, restSeconds: 240), "3 séries · descanso 4 min")
        XCTAssertEqual(TodayTargetText.detail(sets: 1, restSeconds: 0), "1 série · sem descanso")
    }

    // MARK: - Selo leigo (DESIGN §7)

    func testBadgeText_isLayAndHoldHasNone() {
        XCTAssertEqual(PrescriptionNote.calibrate.badgeText, "Primeira vez")
        XCTAssertEqual(PrescriptionNote.increase.badgeText, "Carga maior")
        XCTAssertNil(PrescriptionNote.hold.badgeText, "manter não tem novidade: sem selo")
        XCTAssertEqual(PrescriptionNote.retry.badgeText, "Tentar de novo")
        XCTAssertEqual(PrescriptionNote.decrease.badgeText, "Carga menor")
        XCTAssertEqual(PrescriptionNote.returning.badgeText, "Retorno")
        XCTAssertEqual(PrescriptionNote.deload.badgeText, "Semana leve")
    }

    /// SPEC §7.14 F6 e F3 (2.4): nos intervalos do Cardio sem nível, `increase` diz "Mais um bloco"; com um
    /// nível registrado, "Nível maior"; nos outros exercícios e nas outras notas, nada muda.
    func testF6_badgeMoreBlocks() {
        XCTAssertEqual(PrescriptionNote.increase.badgeText(isCardio: true, hasLevel: false), "Mais um bloco")
        XCTAssertEqual(PrescriptionNote.increase.badgeText(isCardio: true, hasLevel: true), "Nível maior")
        XCTAssertEqual(
            PrescriptionNote.increase.badgeText(isCardio: true, hasLevel: true, loadUnit: .kilograms),
            "Carga maior",
            "aeróbico com carga em kg (raro) sobe a carga"
        )
        XCTAssertEqual(PrescriptionNote.increase.badgeText(isCardio: false, hasLevel: false), "Carga maior", "força: como sempre")
        XCTAssertEqual(PrescriptionNote.increase.badgeText(isCardio: false, hasLevel: true), "Carga maior")
        XCTAssertEqual(PrescriptionNote.calibrate.badgeText(isCardio: true, hasLevel: false), "Primeira vez")
        XCTAssertEqual(PrescriptionNote.deload.badgeText(isCardio: true, hasLevel: false), "Semana leve")
        XCTAssertNil(PrescriptionNote.hold.badgeText(isCardio: true, hasLevel: false), "manter continua sem selo")
        XCTAssertEqual(PrescriptionNote.increase.badgeText, "Carga maior", "o selo antigo fica como está")
    }

    // MARK: - Conteúdo da folha

    func testRF47_contentFromPlan_resolvesGoalAndLoadDisplay() {
        let pushUp = ExerciseDefinition(
            slug: "push-up",
            name: "Flexão",
            primaryMuscles: [.chest],
            equipment: .bodyweight,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )
        let planned = PlannedExercise(
            id: UUID(),
            exercise: pushUp,
            target: ExerciseTarget(exerciseID: pushUp.id, order: 0, sets: 3, repMin: 8, repMax: 12, restSeconds: 90),
            prescription: ExercisePrescription(
                exerciseID: pushUp.id,
                load: nil,
                sets: 3,
                repMin: 8,
                repMax: 12,
                targetReps: 0,
                targetRIR: 3,
                restSeconds: 90,
                note: .calibrate
            )
        )

        let content = ExerciseInfoContent(planned: planned, measure: .reps, lastSession: nil)

        XCTAssertEqual(content.id, planned.id)
        XCTAssertEqual(content.exerciseID, pushUp.id)
        XCTAssertEqual(content.targetReps, 8, "meta 0 cai em repMin")
        XCTAssertEqual(content.loadDisplay, .hidden, "RF-46: peso do corpo na primeira vez não pede carga")
        XCTAssertNil(content.lastSession)
    }
}
