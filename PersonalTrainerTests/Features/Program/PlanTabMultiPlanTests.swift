import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T9.6, SPEC RF-45 e §7.15 M4, M8, M9: a aba Plano com dois planos ativos. Cada plano com a semana dele
/// e o próximo dia (S8), "Sua semana" com os nomes dos dias (`weekSchedule`), "Tirar este plano" (nunca
/// o último) e, com um plano, "Adicionar um plano".
@MainActor
final class PlanTabMultiPlanTests: XCTestCase {
    private typealias Programs = GoalPlanTestPrograms
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private let balancedID = GoalPlanCatalog.hypertrophyBalancedID
    private let cardioID = GoalPlanCatalog.enduranceCardioID

    func testPlanTab_removePlan() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeIDs: [balancedID, cardioID]))
        let model = makeModel(repository, planner: GoalPlanTestPlanner())
        model.refresh()

        XCTAssertTrue(model.hasTwoPlans)
        XCTAssertEqual(model.activePrograms.map(\.id), [balancedID, cardioID], "O principal primeiro (M1)")
        XCTAssertEqual(model.titleText, "Hipertrofia + Cardio")
        XCTAssertTrue(model.canRemovePlans)
        XCTAssertFalse(model.canAddPlan, "Com dois planos, não se acrescenta outro")
        XCTAssertTrue(model.canEditDays)
        let cardio = try XCTUnwrap(model.activePrograms.last)
        XCTAssertEqual(model.remainingProgram(after: cardio)?.id, balancedID)

        XCTAssertTrue(model.removePlan(programID: cardioID))

        XCTAssertEqual(repository.calls, [.removeActivePlan(cardioID)], "Uma escrita só")
        XCTAssertEqual(model.activePrograms.map(\.id), [balancedID], "Relê depois de tirar")
        XCTAssertFalse(model.hasTwoPlans)
        XCTAssertTrue(model.canAddPlan)
        XCTAssertFalse(model.canRemovePlans, "Nunca tira o último (M8)")
        XCTAssertFalse(model.removePlan(programID: balancedID))
        XCTAssertEqual(repository.calls, [.removeActivePlan(cardioID)])
    }

    func testPlanTab_removePlan_blockedDuringSession() throws {
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
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeIDs: [balancedID, cardioID]))
        let model = makeModel(repository, planner: GoalPlanTestPlanner(), coordinator: GoalPlanTestCoordinator(activeSession: session))
        model.refresh()

        XCTAssertFalse(model.canRemovePlans)
        XCTAssertFalse(model.removePlan(programID: cardioID))
        XCTAssertTrue(repository.calls.isEmpty)
        withExtendedLifetime(container) {}
    }

    func testPlanTab_removePlan_failureShowsMessage() {
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeIDs: [balancedID, cardioID]))
        repository.writeError = GoalPlanTestError.boom
        let model = makeModel(repository, planner: GoalPlanTestPlanner())
        model.refresh()

        XCTAssertFalse(model.removePlan(programID: cardioID))
        XCTAssertEqual(model.errorMessage, "Não foi possível tirar o plano. Tente de novo.")
        XCTAssertTrue(model.hasTwoPlans)
    }

    func testPlanTab_weekShowsDayNames() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeIDs: [balancedID, cardioID]))
        let planner = GoalPlanTestPlanner()
        planner.scheduleToReturn = WeekSchedule(
            slots: [
                PlannedSlot(weekday: .monday, programID: balancedID, indexInWeek: 0, kind: .strength, orderInDay: 0, dayName: "Dia A — Superior"),
                PlannedSlot(weekday: .tuesday, programID: cardioID, indexInWeek: 0, kind: .cardio, orderInDay: 0, dayName: "Dia A — Base contínua", cardioIntensity: .moderate),
                PlannedSlot(weekday: .thursday, programID: balancedID, indexInWeek: 1, kind: .strength, orderInDay: 0, dayName: "Dia B — Inferior"),
                PlannedSlot(weekday: .thursday, programID: cardioID, indexInWeek: 1, kind: .cardio, orderInDay: 1, dayName: "Dia C — Longo e leve", cardioIntensity: .light),
            ],
            notes: [.strengthBeforeCardio(.thursday)]
        )
        let balanced = try XCTUnwrap(repository.programs.first { $0.id == balancedID })
        let cardio = try XCTUnwrap(repository.programs.first { $0.id == cardioID })
        let balancedDayB = try XCTUnwrap(balanced.days.first { $0.order == 1 })
        let cardioDayA = try XCTUnwrap(cardio.days.first { $0.order == 0 })
        planner.nextPlansByProgramID = [
            balancedID: SessionPlan(programID: balancedID, programName: balanced.name, programDayID: balancedDayB.id, programDayName: balancedDayB.name, exercises: [], generatedAt: now),
            cardioID: SessionPlan(programID: cardioID, programName: cardio.name, programDayID: cardioDayA.id, programDayName: cardioDayA.name, exercises: [], generatedAt: now),
        ]
        let model = makeModel(repository, planner: planner)

        model.refresh()

        XCTAssertEqual(model.weekRows.map(\.text), [
            "Seg · Dia A — Superior",
            "Ter · Cardio moderado",
            "Qua · descanso",
            "Qui · Dia B — Inferior + Cardio leve",
            "Sex · descanso",
            "Sáb · descanso",
            "Dom · descanso",
        ])
        XCTAssertEqual(model.weekNotes, ["Na quinta, faça a força antes do cardio."])
        XCTAssertFalse(model.showsNotFit)
        XCTAssertEqual(planner.weekScheduleCalls, [now], "Relógio injetado (SPEC P11)")
        XCTAssertTrue(planner.requestedDates.isEmpty, "Com dois planos, o próximo dia vem de cada plano (S8)")
        XCTAssertEqual(model.nextDayID, balancedDayB.id, "O próximo do principal")
        XCTAssertTrue(model.isNext(cardioDayA), "Cada plano marca o próximo dele")
        XCTAssertEqual(model.orderedDays(of: cardio).filter { model.isNext($0) }.map(\.id), [cardioDayA.id])
        XCTAssertEqual(model.planSubtitle(for: balanced), "Equilibrado · 4 dias por semana")
        XCTAssertEqual(model.planSubtitle(for: cardio), "3 dias por semana")
    }

    func testPlanTab_twoPlansWithoutWeek_showsNotFit() {
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeIDs: [balancedID, cardioID]))
        let planner = GoalPlanTestPlanner()
        planner.scheduleToReturn = nil
        let model = makeModel(repository, planner: planner)

        model.refresh()

        XCTAssertTrue(model.weekRows.isEmpty)
        XCTAssertTrue(model.showsNotFit)
        XCTAssertEqual(PlanWeekText.notFitInPlanTab, "Seus planos não cabem nos dias escolhidos. Ajuste em Seus dias.")
    }

    func testPlanTab_singlePlan_noWeekSchedule() {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let planner = GoalPlanTestPlanner()
        let model = makeModel(repository, planner: planner)

        model.refresh()

        XCTAssertFalse(model.hasTwoPlans)
        XCTAssertTrue(planner.weekScheduleCalls.isEmpty, "Com um plano só não há encaixe (M4)")
        XCTAssertFalse(model.showsNotFit)
        XCTAssertTrue(model.canAddPlan)
        XCTAssertFalse(model.canEditDays)
        XCTAssertNil(model.makeDaysFlow())
        XCTAssertEqual(model.titleText, "Hipertrofia")
    }

    func testPlanTab_withoutPlanner_noAddPlan() {
        let model = makeModel(GoalPlanTestRepository(programs: Programs.seed()), planner: nil)

        model.refresh()

        XCTAssertFalse(model.canAddPlan, "Sem planejador não há como conferir a semana")
    }

    // MARK: - Fábrica

    private func makeModel(
        _ repository: GoalPlanTestRepository,
        planner: GoalPlanTestPlanner?,
        coordinator: GoalPlanTestCoordinator? = nil
    ) -> PlanTabModel {
        let fixedNow = now
        return PlanTabModel(
            programs: repository,
            catalog: GoalPlanTestCatalog(),
            planner: planner,
            coordinator: coordinator,
            now: { fixedNow }
        )
    }
}
