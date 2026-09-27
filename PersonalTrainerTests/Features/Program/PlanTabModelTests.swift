import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T7.4, SPEC RF-45: a aba Plano mostra o plano do objetivo ativo, a semana inteira com o próximo
/// dia marcado (pelo `SessionPlanning.nextPlan(now:)`, com o relógio injetado) e sabe se há sessão
/// em andamento. Só lê: nenhuma escrita no repositório.
@MainActor
final class PlanTabModelTests: XCTestCase {
    private typealias Programs = GoalPlanTestPrograms
    private let now = Date(timeIntervalSince1970: 1_758_600_000)

    func testRF45_plan_showsActivePlanWeekInOrder() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeID: GoalPlanCatalog.combatID))
        let model = makeModel(repository)

        XCTAssertFalse(model.hasLoaded)
        model.refresh()

        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(model.activeProgram?.id, GoalPlanCatalog.combatID)
        XCTAssertEqual(model.goal, .combat)
        XCTAssertEqual(model.days.map(\.order), [0, 1, 2], "Dias na ordem de `order` (S1)")
        XCTAssertEqual(model.subtitle, "3 dias por semana")
        let firstDay = try XCTUnwrap(model.days.first)
        XCTAssertEqual(model.exerciseList(for: firstDay), "Supino reto com barra · Supino máquina antiga · Remada baixa")
        XCTAssertTrue(repository.calls.isEmpty, "Só lê")
    }

    func testRF45_plan_marksNextDayFromPlanner() throws {
        let programs = Programs.seed()
        let active = try XCTUnwrap(programs.first { $0.isActive })
        let dayB = try XCTUnwrap(active.days.first { $0.order == 1 })
        let planner = GoalPlanTestPlanner(planToReturn: SessionPlan(
            programID: active.id,
            programName: active.name,
            programDayID: dayB.id,
            programDayName: dayB.name,
            exercises: [],
            generatedAt: now
        ))
        let model = makeModel(GoalPlanTestRepository(programs: programs), planner: planner)

        model.refresh()

        XCTAssertEqual(model.nextDayID, dayB.id)
        XCTAssertEqual(model.days.filter { model.isNext($0) }.map(\.id), [dayB.id], "Só um dia marcado")
        XCTAssertEqual(planner.requestedDates, [now], "Relógio injetado (SPEC P11)")
        XCTAssertTrue(model.accessibilityText(for: dayB).contains("Próxima sessão"))
    }

    func testRF45_plan_planOfAnotherProgram_marksNothing() {
        let planner = GoalPlanTestPlanner(planToReturn: SessionPlan(
            programID: UUID(),
            programName: "Outro",
            programDayID: UUID(),
            programDayName: "Dia A",
            exercises: [],
            generatedAt: now
        ))
        let model = makeModel(GoalPlanTestRepository(programs: Programs.seed()), planner: planner)

        model.refresh()

        XCTAssertNil(model.nextDayID)
    }

    func testRF45_plan_plannerFailure_keepsWeekWithoutMark() {
        let planner = GoalPlanTestPlanner()
        planner.error = GoalPlanTestError.boom
        let model = makeModel(GoalPlanTestRepository(programs: Programs.seed()), planner: planner)

        model.refresh()

        XCTAssertNil(model.nextDayID)
        XCTAssertEqual(model.days.count, 3)
        XCTAssertNil(model.errorMessage, "A falha do planejador não vira alerta")
    }

    func testRF45_plan_withoutPlanner_marksNothing() {
        let model = makeModel(GoalPlanTestRepository(programs: Programs.seed()))

        model.refresh()

        XCTAssertNil(model.nextDayID)
        XCTAssertFalse(model.isSessionInProgress)
    }

    func testRF45_plan_hypertrophyFormat_inSubtitle() {
        let model = makeModel(GoalPlanTestRepository(programs: Programs.seed(activeID: GoalPlanCatalog.hypertrophyLowerFocusID)))

        model.refresh()

        XCTAssertEqual(model.subtitle, "Mais pernas e glúteos · 4 dias por semana")
    }

    func testRF45_plan_noActiveProgram() {
        let planner = GoalPlanTestPlanner()
        let model = makeModel(GoalPlanTestRepository(programs: Programs.seed(activeID: nil)), planner: planner)

        model.refresh()

        XCTAssertNil(model.activeProgram)
        XCTAssertNil(model.goal)
        XCTAssertTrue(model.days.isEmpty)
        XCTAssertFalse(model.didFailToLoad)
        XCTAssertTrue(planner.requestedDates.isEmpty, "Sem plano ativo, não pergunta o próximo dia")
    }

    func testRF45_plan_loadFailure_setsMessage() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        repository.readError = GoalPlanTestError.boom
        let model = makeModel(repository)

        model.refresh()

        XCTAssertTrue(model.didFailToLoad)
        XCTAssertEqual(model.errorMessage, "Não foi possível carregar o plano.")
        model.isPresentingError = false
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.didFailToLoad)
    }

    func testRF45_plan_catalogFailure_showsDayNamesOnly() throws {
        let catalog = GoalPlanTestCatalog()
        catalog.readError = GoalPlanTestError.boom
        let model = makeModel(GoalPlanTestRepository(programs: Programs.seed()), catalog: catalog)

        model.refresh()

        let firstDay = try XCTUnwrap(model.days.first)
        XCTAssertEqual(model.exerciseList(for: firstDay), "")
        XCTAssertNil(model.errorMessage)
    }

    func testRF45_plan_sessionInProgress_blocksChange() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: "inProgress",
            startedAt: now,
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: "iphone"
        )
        container.mainContext.insert(session)
        let coordinator = GoalPlanTestCoordinator(activeSession: session)
        let model = makeModel(GoalPlanTestRepository(programs: Programs.seed()), coordinator: coordinator)

        XCTAssertTrue(model.isSessionInProgress)
        coordinator.activeSession = nil
        XCTAssertFalse(model.isSessionInProgress)
    }

    // MARK: - Fábrica

    private func makeModel(
        _ repository: GoalPlanTestRepository,
        catalog: GoalPlanTestCatalog? = nil,
        planner: GoalPlanTestPlanner? = nil,
        coordinator: GoalPlanTestCoordinator? = nil
    ) -> PlanTabModel {
        let fixedNow = now
        return PlanTabModel(
            programs: repository,
            catalog: catalog ?? GoalPlanTestCatalog(),
            planner: planner,
            coordinator: coordinator,
            now: { fixedNow }
        )
    }
}
