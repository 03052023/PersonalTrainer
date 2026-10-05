import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T9.6, SPEC RF-45 e §7.15 M1, M8: a folha "Seu objetivo" com dois planos ativos. "Trocar para X"
/// deixa só X; trocar o formato da Hipertrofia (ou o plano de um objetivo já ativo) troca só aquele
/// plano; ao adicionar, os objetivos já ativos não entram.
@MainActor
final class GoalSheetMultiPlanTests: XCTestCase {
    private typealias Programs = GoalPlanTestPrograms
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private let balancedID = GoalPlanCatalog.hypertrophyBalancedID
    private let cardioID = GoalPlanCatalog.enduranceCardioID

    func testM8_changeWithTwoActiveWarnsSecondLeaves() {
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeIDs: [balancedID, cardioID]))
        let model = makeModel(repository)
        model.load()

        XCTAssertEqual(model.plans.activeGoals, [.hypertrophy, .endurance], "O principal primeiro (M1)")
        XCTAssertEqual(model.selectedGoal, .hypertrophy, "Abre no plano principal")
        XCTAssertTrue(model.isCurrentSelection)
        XCTAssertFalse(model.canConfirm)
        XCTAssertNil(model.changeWarning)
        XCTAssertFalse(model.showsAddButton, "Com dois planos, só Trocar")

        // O objetivo do segundo plano também é a escolha atual.
        model.select(.endurance)
        XCTAssertTrue(model.isCurrentSelection)
        XCTAssertFalse(model.canConfirm)

        model.select(.strength)
        XCTAssertEqual(model.confirmTitle, "Trocar para Força")
        XCTAssertEqual(model.changeWarning, "O plano de Cardio também sai.")
        XCTAssertFalse(model.showsAddButton)
        XCTAssertTrue(model.canConfirm)

        XCTAssertEqual(model.confirm(), .changed)
        XCTAssertEqual(repository.calls, [.activate(GoalPlanCatalog.strengthID)], "Trocar deixa um plano só")
        XCTAssertEqual(repository.activeIDs, [GoalPlanCatalog.strengthID])
    }

    func testM8_formatChangeKeepsSecondPlan() {
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeIDs: [balancedID, cardioID]))
        let model = makeModel(repository)
        model.load()

        model.selectFormat(GoalPlanCatalog.hypertrophyLowerFocusID)

        XCTAssertEqual(model.confirmTitle, "Trocar para Mais pernas e glúteos")
        XCTAssertNil(model.changeWarning, "O Cardio continua")
        XCTAssertEqual(model.replacedProgram?.id, balancedID)
        XCTAssertEqual(model.confirm(), .changed)
        XCTAssertEqual(
            repository.calls,
            [.removeActivePlan(balancedID), .addActivePlan(GoalPlanCatalog.hypertrophyLowerFocusID)],
            "Tira o antigo e acrescenta o novo, nessa ordem"
        )
        XCTAssertEqual(repository.activeIDs, [GoalPlanCatalog.hypertrophyLowerFocusID, cardioID])
    }

    func testM8_formatChange_failedAdd_restoresOldPlan() {
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeIDs: [balancedID, cardioID]))
        repository.addError = GoalPlanTestError.boom
        repository.addFailures = 1
        let model = makeModel(repository)
        model.load()
        model.selectFormat(GoalPlanCatalog.hypertrophyUpperFocusID)

        XCTAssertEqual(model.confirm(), .failed)
        XCTAssertEqual(model.errorMessage, "Não foi possível trocar o objetivo. Tente de novo.")
        XCTAssertEqual(repository.calls, [
            .removeActivePlan(balancedID),
            .addActivePlan(GoalPlanCatalog.hypertrophyUpperFocusID),
            .addActivePlan(balancedID),
        ])
        XCTAssertEqual(repository.activeIDs, [balancedID, cardioID], "A pessoa fica com os planos que tinha")
    }

    func testM8_onePlan_offersChangeAndAdd() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let model = makeModel(repository)
        model.load()

        XCTAssertFalse(model.showsAddButton, "O objetivo atual não se acrescenta")
        model.select(.endurance)
        XCTAssertEqual(model.confirmTitle, "Trocar para Cardio")
        XCTAssertTrue(model.showsAddButton)
        XCTAssertTrue(model.canAdd)
        XCTAssertEqual(model.addTitle, "Adicionar Cardio ao seu plano")
        XCTAssertNil(model.changeWarning)

        // Trocar continua deixando um plano só (RF-45).
        XCTAssertEqual(model.confirm(), .changed)
        XCTAssertEqual(repository.calls, [.activate(cardioID)])
    }

    func testM8_withoutPlanner_noAddButton() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let model = GoalSheetModel(programs: repository, catalog: nil, mode: .change, isSessionInProgress: false)
        model.load()
        model.select(.endurance)

        XCTAssertFalse(model.showsAddButton, "Sem planejador não há como conferir a semana")
        XCTAssertNil(model.makeAddFlow())
    }

    func testM8_addMode_hidesActiveGoalsAndStartsEmpty() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let model = makeModel(repository, mode: .add)
        model.load()

        XCTAssertNil(model.selectedGoal, "Adicionar começa sem escolha")
        XCTAssertEqual(model.confirmTitle, "Escolha um objetivo")
        XCTAssertFalse(model.canAdd)
        let hypertrophy = try XCTUnwrap(model.plans.entry(for: .hypertrophy))
        XCTAssertFalse(model.isSelectable(hypertrophy), "O objetivo já ativo não se acrescenta (M1)")
        model.select(.hypertrophy)
        XCTAssertNil(model.selectedGoal)

        model.select(.longevity)
        XCTAssertEqual(model.confirmTitle, "Adicionar Longevidade ao seu plano")
        XCTAssertTrue(model.canAdd)
        XCTAssertFalse(model.canConfirm, "Ao adicionar, não há troca")
        XCTAssertEqual(model.confirm(), .refused)
        XCTAssertEqual(model.flowerGoals, [.hypertrophy, .longevity])
        XCTAssertNotNil(model.makeAddFlow())
        XCTAssertTrue(repository.calls.isEmpty, "Montar o fluxo não grava nada")
    }

    /// M1: ao adicionar, a flor da folha põe primeiro o objetivo que seria o principal, mesmo quando é o
    /// plano que vai entrar (Cardio ativo + Hipertrofia tocada).
    func testM1_addMode_flowerGoalsFollowPlanOrder() {
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeID: cardioID))
        let model = makeModel(repository, mode: .add)
        model.load()

        XCTAssertEqual(model.flowerGoals, [.endurance], "Sem escolha, só o ativo")
        model.select(.hypertrophy)
        XCTAssertEqual(model.flowerGoals, [.hypertrophy, .endurance])
        XCTAssertEqual(model.confirmTitle, "Adicionar Hipertrofia ao seu plano")
    }

    func testM1_catalogWithTwoActivePlans() throws {
        let catalog = GoalPlanCatalog(programs: Programs.seed(activeIDs: [cardioID, GoalPlanCatalog.strengthID]))

        XCTAssertEqual(catalog.activePrograms.map(\.id), [GoalPlanCatalog.strengthID, cardioID], "Força antes do Cardio (M1)")
        XCTAssertEqual(catalog.activeProgram?.id, GoalPlanCatalog.strengthID)
        XCTAssertEqual(catalog.activeGoal, .strength)
        XCTAssertEqual(catalog.activePlan(for: .endurance)?.id, cardioID)
        XCTAssertNil(catalog.activePlan(for: .combat))
        XCTAssertEqual(catalog.entries.filter(\.isCurrent).map(\.goal), [.strength, .endurance], "Na ordem das pétalas")
        let hypertrophy = try XCTUnwrap(catalog.entry(for: .hypertrophy))
        XCTAssertEqual(hypertrophy.defaultProgramID, balancedID, "Sem Hipertrofia ativa, o primeiro formato")
    }

    // MARK: - Fábrica

    private func makeModel(
        _ repository: GoalPlanTestRepository,
        mode: GoalSheet.Mode = .change,
        isSessionInProgress: Bool = false
    ) -> GoalSheetModel {
        let fixedNow = now
        return GoalSheetModel(
            programs: repository,
            catalog: nil,
            mode: mode,
            isSessionInProgress: isSessionInProgress,
            planner: GoalPlanTestPlanner(),
            now: { fixedNow }
        )
    }
}
