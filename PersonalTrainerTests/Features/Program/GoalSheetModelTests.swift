import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T7.4, SPEC RF-45: a folha "Seu objetivo". Trocar é uma única chamada a `activate` (S2
/// recomeça no Dia A; P3 é por exercício), bloqueada com sessão em andamento e desabilitada
/// quando a escolha é a atual. Nenhuma outra escrita (nada de `setGoal`, renomear ou duplicar).
@MainActor
final class GoalSheetModelTests: XCTestCase {
    private typealias Programs = GoalPlanTestPrograms

    // MARK: - Troca

    func testRF45_sheet_activatesOnce() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let model = makeModel(repository)
        model.load()

        model.select(.combat)
        XCTAssertTrue(model.canConfirm)
        XCTAssertEqual(model.confirmTitle, "Trocar para Combate")

        XCTAssertEqual(model.confirm(), .changed)
        XCTAssertEqual(repository.calls, [.activate(GoalPlanCatalog.combatID)], "Uma escrita só, sem setGoal")

        // Toques repetidos depois da troca não gravam de novo.
        XCTAssertFalse(model.canConfirm)
        XCTAssertEqual(model.confirm(), .refused)
        model.select(.strength)
        XCTAssertEqual(model.confirm(), .refused)
        XCTAssertEqual(repository.calls, [.activate(GoalPlanCatalog.combatID)])
    }

    func testRF45_sheet_blockedDuringSession() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let model = makeModel(repository, isSessionInProgress: true)
        model.load()

        model.select(.strength)

        XCTAssertFalse(model.canConfirm)
        XCTAssertTrue(model.showsSessionBlock, "Mostra \"Termine a sessão em andamento para trocar.\"")
        XCTAssertEqual(model.confirm(), .refused)
        XCTAssertTrue(repository.calls.isEmpty)

        // A sessão terminou com a folha aberta: libera.
        model.isSessionInProgress = false
        XCTAssertTrue(model.canConfirm)
        XCTAssertFalse(model.showsSessionBlock)
        XCTAssertEqual(model.confirm(), .changed)
        XCTAssertEqual(repository.calls, [.activate(GoalPlanCatalog.strengthID)])
    }

    func testRF45_sheet_currentSelectionDisablesButton() {
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeID: GoalPlanCatalog.combatID))
        let model = makeModel(repository)
        model.load()

        XCTAssertEqual(model.selectedGoal, .combat, "Abre no objetivo atual")
        XCTAssertEqual(model.selectedProgramID, GoalPlanCatalog.combatID)
        XCTAssertTrue(model.isCurrentSelection)
        XCTAssertFalse(model.canConfirm)
        XCTAssertEqual(model.confirmTitle, "Trocar para Combate")
        XCTAssertEqual(model.confirm(), .refused)

        model.select(.hypertrophy)
        XCTAssertEqual(model.selectedProgramID, GoalPlanCatalog.hypertrophyFullBodyID, "Primeiro formato")
        XCTAssertTrue(model.canConfirm)
        XCTAssertEqual(model.confirmTitle, "Trocar para Hipertrofia")

        model.select(.combat)
        XCTAssertFalse(model.canConfirm)
        XCTAssertTrue(repository.calls.isEmpty)
    }

    func testRF45_sheet_formatChange_namesTheFormat() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let model = makeModel(repository)
        model.load()
        XCTAssertEqual(model.selectedGoal, .hypertrophy)

        model.selectFormat(GoalPlanCatalog.hypertrophyLowerFocusID)

        XCTAssertEqual(model.confirmTitle, "Trocar para Mais pernas e glúteos", "Só muda o formato")
        XCTAssertTrue(model.canConfirm)
        XCTAssertEqual(model.confirm(), .changed)
        XCTAssertEqual(repository.calls, [.activate(GoalPlanCatalog.hypertrophyLowerFocusID)])
    }

    func testRF45_sheet_formatOfAnotherGoal_isIgnored() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let model = makeModel(repository)
        model.load()
        model.select(.combat)

        model.selectFormat(GoalPlanCatalog.hypertrophyUpperFocusID)

        XCTAssertEqual(model.selectedProgramID, GoalPlanCatalog.combatID)
    }

    func testRF45_sheet_tappingSameGoal_keepsFormat() {
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeID: GoalPlanCatalog.combatID))
        let model = makeModel(repository)
        model.load()
        model.select(.hypertrophy)
        model.selectFormat(GoalPlanCatalog.hypertrophyUpperFocusID)

        model.select(.hypertrophy)

        XCTAssertEqual(model.selectedProgramID, GoalPlanCatalog.hypertrophyUpperFocusID)
        XCTAssertEqual(model.confirmTitle, "Trocar para Hipertrofia", "Outro objetivo: o botão diz o objetivo")
    }

    func testRF45_sheet_goalWithoutPlan_isNotSelectable() {
        let programs = Programs.seed().filter { $0.id != GoalPlanCatalog.enduranceID }
        let repository = GoalPlanTestRepository(programs: programs)
        let model = makeModel(repository)
        model.load()

        model.select(.endurance)

        XCTAssertEqual(model.selectedGoal, .hypertrophy, "Continua no que estava")
        XCTAssertEqual(model.plans.entry(for: .endurance)?.dayCountText, "Sem plano pronto")
    }

    func testRF45_sheet_activationFailure_showsAlertAndAllowsRetry() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        repository.writeError = GoalPlanTestError.boom
        let model = makeModel(repository)
        model.load()
        model.select(.longevity)

        XCTAssertEqual(model.confirm(), .failed)
        XCTAssertEqual(model.errorMessage, "Não foi possível trocar o objetivo. Tente de novo.")
        XCTAssertTrue(model.isPresentingError)
        model.isPresentingError = false
        XCTAssertNil(model.errorMessage)

        repository.writeError = nil
        XCTAssertEqual(model.confirm(), .changed)
        XCTAssertEqual(repository.calls, [.activate(GoalPlanCatalog.longevityID), .activate(GoalPlanCatalog.longevityID)])
    }

    func testRF45_sheet_cancel_writesNothing() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let model = makeModel(repository)
        model.load()
        model.select(.strength)

        model.markFinished()

        XCTAssertTrue(model.hasFinished)
        XCTAssertFalse(model.canConfirm)
        XCTAssertEqual(model.confirm(), .refused)
        XCTAssertTrue(repository.calls.isEmpty)
    }

    func testRF45_sheet_loadFailure_setsMessage() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        repository.readError = GoalPlanTestError.boom
        let model = makeModel(repository)

        model.load()

        XCTAssertTrue(model.didFailToLoad)
        XCTAssertEqual(model.errorMessage, "Não foi possível carregar os objetivos.")
        XCTAssertNil(model.selectedGoal)
        XCTAssertFalse(model.canConfirm)
        XCTAssertEqual(model.confirmTitle, "Escolha um objetivo")
    }

    func testRF45_sheet_reload_keepsSelection() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let model = makeModel(repository)
        model.load()
        model.select(.strength)

        model.load()

        XCTAssertEqual(model.selectedGoal, .strength)
        XCTAssertEqual(model.selectedProgramID, GoalPlanCatalog.strengthID)
    }

    // MARK: - Primeiro uso

    func testRF45_firstUse_startWithCurrent_writesNothing() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let model = makeModel(repository, mode: .firstUse)
        model.load()

        XCTAssertEqual(model.confirmTitle, "Começar")
        XCTAssertTrue(model.canConfirm, "Começar vale para a escolha atual")
        XCTAssertEqual(model.confirm(), .unchanged)
        XCTAssertTrue(repository.calls.isEmpty)
        XCTAssertTrue(model.hasFinished)
    }

    func testRF45_firstUse_startWithOtherGoal_activatesOnce() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let model = makeModel(repository, mode: .firstUse)
        model.load()
        model.select(.combat)

        XCTAssertEqual(model.confirmTitle, "Começar")
        XCTAssertEqual(model.confirm(), .changed)
        XCTAssertEqual(repository.calls, [.activate(GoalPlanCatalog.combatID)])
    }

    func testRF45_texts_footnoteAndAccessibility() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let change = makeModel(repository)
        change.load()
        XCTAssertEqual(change.footnote, "Suas cargas ficam guardadas: cada exercício tem o próprio histórico. A próxima sessão será o Dia A.")

        let firstUse = makeModel(repository, mode: .firstUse)
        XCTAssertTrue(firstUse.footnote.contains("Dia A"))

        let hypertrophy = try XCTUnwrap(change.plans.entry(for: .hypertrophy))
        XCTAssertEqual(
            change.accessibilityText(for: hypertrophy),
            "Hipertrofia. \(ProgramGoal.hypertrophy.subtitle). 3 ou 4 dias. Atual."
        )
        for entry in change.plans.entries {
            let text = change.accessibilityText(for: entry)
            XCTAssertFalse(text.contains("RIR"), text)
        }
    }

    // MARK: - Prévia do Dia A

    func testRF45_preview_listsFirstDayExercisesInOrder_includingArchived() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let model = makeModel(repository, catalog: GoalPlanTestCatalog())
        model.load()

        model.select(.combat)

        XCTAssertEqual(model.preview?.dayName, "Dia A")
        XCTAssertEqual(model.preview?.exercises, "Supino reto com barra, Supino máquina antiga, Remada baixa.")
        XCTAssertEqual(model.preview?.text, "Dia A: Supino reto com barra, Supino máquina antiga, Remada baixa.")
    }

    func testRF45_preview_withoutCatalog_isHidden() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let model = makeModel(repository, catalog: nil)
        model.load()

        XCTAssertNil(model.preview)
    }

    func testRF45_preview_catalogFailure_isHidden_withoutAlert() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let catalog = GoalPlanTestCatalog()
        catalog.readError = GoalPlanTestError.boom
        let model = makeModel(repository, catalog: catalog)

        model.load()

        XCTAssertNil(model.preview)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.didFailToLoad)
    }

    // MARK: - Fábrica

    private func makeModel(
        _ repository: GoalPlanTestRepository,
        catalog: GoalPlanTestCatalog? = nil,
        mode: GoalSheet.Mode = .change,
        isSessionInProgress: Bool = false
    ) -> GoalSheetModel {
        GoalSheetModel(
            programs: repository,
            catalog: catalog,
            mode: mode,
            isSessionInProgress: isSessionInProgress
        )
    }
}
