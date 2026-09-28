import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Textos puros da ficha da sessão (SPEC RF-44, RF-46, RF-41, RF-12; docs/V22-CONTRACT.md §3.1) e
/// os helpers dos steppers de "Corrigir série" (RF-19). A parte visual fica para o simulador.
@MainActor
final class SessionSheetTextTests: XCTestCase {

    // MARK: - Dicas (RF-44 c/d, RF-41)

    func testRF44_warmupHint_isFixedSentence() {
        XCTAssertEqual(
            SessionSheetText.warmupHint,
            "Aqueça com 1 ou 2 séries leves antes dos exercícios com carga. Não precisa marcar."
        )
    }

    func testRF44_firstTimeHint_repsUsesGoalPlusTargetRIR() {
        XCTAssertEqual(
            SessionSheetText.firstTimeHint(goal: 6, targetRIR: 3, measure: .reps),
            "Escolha uma carga que daria para levantar umas 9 vezes. Hoje faça 6."
        )
        XCTAssertEqual(
            SessionSheetText.firstTimeHint(goal: 8, targetRIR: -1, measure: .reps),
            "Escolha uma carga que daria para levantar umas 8 vezes. Hoje faça 8.",
            "RIR negativo não diminui o número"
        )
    }

    func testRF44_firstTimeHint_secondsAndStepsDoNotUseN() {
        XCTAssertEqual(
            SessionSheetText.firstTimeHint(goal: 30, targetRIR: 2, measure: .steps),
            "Escolha uma carga com a qual você aguentaria mais do que isso. Hoje faça 30 passos."
        )
        XCTAssertEqual(
            SessionSheetText.firstTimeHint(goal: 20, targetRIR: 2, measure: .seconds),
            "Escolha uma carga com a qual você aguentaria mais do que isso. Hoje faça 20 segundos."
        )
    }

    // MARK: - Campo de carga (RF-44 b/c)

    func testRF44_parseLoad_acceptsCommaAndDot() {
        XCTAssertEqual(SessionSheetText.parseLoad("62,5", allowsZero: false), 62.5)
        XCTAssertEqual(SessionSheetText.parseLoad("62.5", allowsZero: false), 62.5)
        XCTAssertEqual(SessionSheetText.parseLoad(" 40 ", allowsZero: false), 40)
        XCTAssertEqual(SessionSheetText.parseLoad("1000", allowsZero: false), 1_000)
    }

    func testRF44_parseLoad_rejectsEmptyZeroAndOutOfRange() {
        XCTAssertNil(SessionSheetText.parseLoad("", allowsZero: false))
        XCTAssertNil(SessionSheetText.parseLoad("0", allowsZero: false), "primeira vez exige carga > 0")
        XCTAssertNil(SessionSheetText.parseLoad("0,0", allowsZero: false))
        XCTAssertNil(SessionSheetText.parseLoad("1000,5", allowsZero: false))
        XCTAssertNil(SessionSheetText.parseLoad("1,2,3", allowsZero: false))
        XCTAssertNil(SessionSheetText.parseLoad(",", allowsZero: false))
    }

    func testRF46_parseLoad_bodyweightExtraAcceptsZero() {
        XCTAssertEqual(SessionSheetText.parseLoad("0", allowsZero: true), 0)
        XCTAssertEqual(SessionSheetText.parseLoad("2,5", allowsZero: true), 2.5)
        XCTAssertNil(SessionSheetText.parseLoad("", allowsZero: true))
    }

    func testRF44_isValidLoad_bounds() {
        XCTAssertTrue(SessionSheetText.isValidLoad(0.5, allowsZero: false))
        XCTAssertFalse(SessionSheetText.isValidLoad(0, allowsZero: false))
        XCTAssertTrue(SessionSheetText.isValidLoad(0, allowsZero: true))
        XCTAssertFalse(SessionSheetText.isValidLoad(-2.5, allowsZero: true))
        XCTAssertFalse(SessionSheetText.isValidLoad(.infinity, allowsZero: true))
        XCTAssertFalse(SessionSheetText.isValidLoad(.nan, allowsZero: true))
        XCTAssertFalse(SessionSheetText.isValidLoad(1_000.01, allowsZero: false))
    }

    func testRF44_editableLoadText_ptBRWithoutUnit() {
        XCTAssertEqual(SessionSheetText.editableLoadText(62.5), "62,5")
        XCTAssertEqual(SessionSheetText.editableLoadText(60), "60")
        XCTAssertEqual(SessionSheetText.editableLoadText(1_000), "1000", "sem separador de milhar no campo")
    }

    func testRF44_unitLabel_perLoadUnit() {
        XCTAssertEqual(SessionSheetText.unitLabel(.kilograms), "kg")
        XCTAssertEqual(SessionSheetText.unitLabel(.plates), "placas")
        XCTAssertEqual(SessionSheetText.unitLabel(.level), "nível")
    }

    // MARK: - Concluir com pendentes (RF-44 e)

    func testRF44_pendingTitle_singularAndPlural() {
        XCTAssertEqual(SessionSheetText.pendingTitle(count: 2), "Faltam 2 exercícios")
        XCTAssertEqual(SessionSheetText.pendingTitle(count: 1), "Falta 1 exercício")
    }

    func testRF44_pendingMessage_listsNames() {
        XCTAssertEqual(
            SessionSheetText.pendingMessage(names: ["Caminhada do fazendeiro", "Isometria de pescoço"]),
            "Caminhada do fazendeiro e Isometria de pescoço ainda não foram marcados."
        )
        XCTAssertEqual(
            SessionSheetText.pendingMessage(names: ["Barra fixa"]),
            "Barra fixa ainda não foi marcado."
        )
        XCTAssertEqual(SessionSheetText.namesList(["A", "B", "C"]), "A, B e C")
        XCTAssertEqual(SessionSheetText.namesList([]), "")
    }

    func testRF44_pendingMessage_namesTheOnesThatNeedLoad() {
        XCTAssertEqual(
            SessionSheetText.pendingMessage(names: ["Supino reto", "Barra fixa"], needingLoad: ["Supino reto"]),
            "Supino reto e Barra fixa ainda não foram marcados. Supino reto precisa da carga da primeira vez e fica de fora."
        )
        XCTAssertEqual(
            SessionSheetText.pendingMessage(names: ["Supino reto", "Terra"], needingLoad: ["Supino reto", "Terra"]),
            "Supino reto e Terra ainda não foram marcados. Supino reto e Terra precisam da carga da primeira vez e ficam de fora."
        )
        XCTAssertEqual(
            SessionSheetText.pendingMessage(names: ["Barra fixa"], needingLoad: []),
            "Barra fixa ainda não foi marcado."
        )
    }

    // MARK: - Exercício feito (RF-44 a, RF-46)

    func testRF44_doneSummary_sameLoad() {
        let sets = [logged(60, 5), logged(60, 5), logged(60, 4)]
        XCTAssertEqual(
            SessionSheetText.doneSummary(sets, unit: .kilograms, equipment: .barbell, measure: .reps),
            "5, 5, 4 · 60 kg"
        )
        XCTAssertEqual(
            SessionSheetText.spokenDoneSummary(sets, unit: .kilograms, equipment: .barbell, measure: .reps),
            "5, 5 e 4 repetições, 60 kg"
        )
    }

    func testRF46_doneSummary_bodyweightWithoutLoad() {
        let sets = [logged(0, 5), logged(0, 5), logged(0, 4)]
        XCTAssertEqual(
            SessionSheetText.doneSummary(sets, unit: .kilograms, equipment: .bodyweight, measure: .reps),
            "5, 5, 4"
        )
        XCTAssertEqual(
            SessionSheetText.doneSummary([logged(2.5, 8)], unit: .kilograms, equipment: .bodyweight, measure: .reps),
            "8 · + 2,5 kg extra"
        )
        XCTAssertEqual(
            SessionSheetText.spokenDoneSummary([logged(2.5, 8)], unit: .kilograms, equipment: .bodyweight, measure: .reps),
            "8 repetições, mais 2,5 kg extra"
        )
    }

    func testRF44_doneSummary_differentLoadsPerSet() {
        let sets = [logged(60, 5), logged(57.5, 4)]
        XCTAssertEqual(
            SessionSheetText.doneSummary(sets, unit: .kilograms, equipment: .barbell, measure: .reps),
            "5 × 60 kg, 4 × 57,5 kg"
        )
        XCTAssertEqual(
            SessionSheetText.spokenDoneSummary(sets, unit: .kilograms, equipment: .barbell, measure: .reps),
            "5 repetições com 60 kg e 4 repetições com 57,5 kg"
        )
    }

    func testRF43_doneSummary_secondsStepsAndPlates() {
        XCTAssertEqual(
            SessionSheetText.doneSummary([logged(0, 30), logged(0, 30)], unit: .kilograms, equipment: .bodyweight, measure: .seconds),
            "30, 30 s"
        )
        XCTAssertEqual(
            SessionSheetText.doneSummary([logged(22.5, 30)], unit: .kilograms, equipment: .dumbbell, measure: .steps),
            "30 passos · 22,5 kg"
        )
        XCTAssertEqual(
            SessionSheetText.doneSummary([logged(9, 8), logged(9, 8)], unit: .plates, equipment: .machine, measure: .reps),
            "8, 8 · 9 placas"
        )
        XCTAssertEqual(SessionSheetText.doneSummary([], unit: .kilograms, equipment: nil, measure: .reps), "")
    }

    // MARK: - Acessibilidade e descanso

    func testRF44_dotAndFeitoLabels() {
        XCTAssertEqual(
            SessionSheetText.dotLabel(number: 2, total: 3, reps: 5, measure: .reps),
            "Série 2 de 3, feita, 5 repetições"
        )
        XCTAssertEqual(
            SessionSheetText.dotLabel(number: 3, total: 3, reps: nil, measure: .reps),
            "Série 3 de 3, marcar como feita"
        )
        XCTAssertEqual(
            SessionSheetText.feitoLabel(exerciseName: "Agachamento livre"),
            "Marcar as séries que faltam de Agachamento livre como feitas"
        )
    }

    func testRF44_restNextUpTexts() {
        XCTAssertEqual(SessionSheetText.nextSet(number: 3, exerciseName: "Agachamento livre"), "A seguir: série 3 de Agachamento livre")
        XCTAssertEqual(SessionSheetText.nextExercise("Barra fixa"), "A seguir: Barra fixa")
    }

    // MARK: - Resumo (RF-44 h, RF-12)

    func testRF44_summaryTexts() {
        XCTAssertEqual(SessionSheetText.summaryTitle(abandoned: false), "Sessão concluída")
        XCTAssertEqual(SessionSheetText.summaryTitle(abandoned: true), "Sessão encerrada")
        XCTAssertEqual(SessionSheetText.exercisesDone(4, of: 5), "4 de 5")
        XCTAssertEqual(
            SessionSheetText.nextSession("Dia B — Salto, terra e supino"),
            "A próxima sessão já está pronta: Dia B — Salto, terra e supino."
        )
    }

    func testRF12_summaryDurationAndHeartRate() {
        XCTAssertEqual(SessionSheetText.duration(TimeInterval(54 * 60 + 59)), "54 min", "minutos truncados")
        XCTAssertEqual(SessionSheetText.duration(TimeInterval(65 * 60)), "1 h 05 min")
        XCTAssertEqual(SessionSheetText.duration(nil), "—")
        XCTAssertEqual(SessionSheetText.heartRate(average: 118.4, maximum: 164), "118 / 164 bpm")
        XCTAssertEqual(SessionSheetText.heartRate(average: 118, maximum: nil), "118 / — bpm")
        XCTAssertNil(SessionSheetText.heartRate(average: nil, maximum: 150), "sem FC, a linha some")
        XCTAssertNil(SessionSheetText.heartRate(average: 0, maximum: 0))
    }

    // MARK: - RF-41: nenhum texto da ficha fala de RIR

    func testRF41_sheetTexts_haveNoRIR() {
        let texts = [
            SessionSheetText.warmupHint,
            SessionSheetText.firstTimeHint(goal: 6, targetRIR: 3, measure: .reps),
            SessionSheetText.firstTimeHint(goal: 30, targetRIR: 2, measure: .steps),
            SessionSheetText.pendingMessage(names: ["A", "B"]),
            SessionSheetText.doneSummary([logged(60, 5)], unit: .kilograms, equipment: .barbell, measure: .reps),
            SessionSheetText.dotLabel(number: 1, total: 3, reps: 5, measure: .reps),
            SessionSheetText.feitoLabel(exerciseName: "Supino"),
            SessionSheetText.allMarked,
        ]
        for text in texts {
            XCTAssertFalse(text.contains("RIR"), text)
            XCTAssertFalse(text.contains("sobrando"), text)
            XCTAssertFalse(text.contains("antes do limite"), text)
            XCTAssertFalse(text.contains("reserva"), text)
        }
    }

    // MARK: - Steppers de "Corrigir série" (RF-19)

    func testLoadStepper_displayText() {
        XCTAssertEqual(LoadStepper.displayText(for: 60, unit: .kilograms), "60 kg")
        XCTAssertEqual(LoadStepper.displayText(for: 62.5, unit: .kilograms), "62,5 kg")
        XCTAssertEqual(LoadStepper.displayText(for: 0, unit: .kilograms), "0 kg")
        XCTAssertEqual(LoadStepper.displayText(for: 12, unit: .plates), "12 placas")
        XCTAssertEqual(LoadStepper.displayText(for: 7, unit: .level), "nível 7")
    }

    func testLoadStepper_stepped_neverGoesBelowZero() {
        XCTAssertEqual(LoadStepper.stepped(60, by: 2.5), 62.5)
        XCTAssertEqual(LoadStepper.stepped(2.5, by: -2.5), 0)
        XCTAssertEqual(LoadStepper.stepped(1, by: -2.5), 0)
        XCTAssertEqual(LoadStepper.stepped(0, by: -2.5).sign, .plus, "Nunca formatar \"-0 kg\"")
    }

    func testRepsStepper_steppedAndHighlightRange() {
        XCTAssertEqual(RepsStepper.stepped(8, by: 1, in: 0...50), 9)
        XCTAssertEqual(RepsStepper.stepped(50, by: 1, in: 0...50), 50)
        XCTAssertEqual(RepsStepper.stepped(0, by: -1, in: 0...50), 0)
        XCTAssertEqual(RepsStepper.highlightRange(repMin: 8, repMax: 12), 8...12)
        XCTAssertEqual(RepsStepper.highlightRange(repMin: 12, repMax: 8), 8...12, "faixa invertida não derruba a sessão")
    }

    func testLoadFormatter_keepsOutput() {
        XCTAssertEqual(LoadFormatter.kilograms(60), "60 kg")
        XCTAssertEqual(LoadFormatter.kilograms(62.5), "62,5 kg")
        XCTAssertEqual(LoadFormatter.kilograms(nil as Double?), "—")
    }

    // MARK: - Fixtures

    private func logged(_ load: Double, _ reps: Int) -> SessionSheetText.LoggedSet {
        SessionSheetText.LoggedSet(load: load, reps: reps)
    }
}
