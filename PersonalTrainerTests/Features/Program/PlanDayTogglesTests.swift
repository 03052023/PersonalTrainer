import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T10.6, SPEC §7.15 M5 e M9, achado B9 da 2.3: as duas chaves de "Seus dias" ("Aceito 2 sessões no mesmo
/// dia" e "Cardio leve depois da força") só aparecem quando um dos planos é de Cardio (`endurance`, o único
/// plano de aeróbico) e o outro não é. Com dois planos de força elas nada mudariam, porque duas forças nunca
/// dividem o dia; o que já estava gravado nas preferências continua.
@MainActor
final class PlanDayTogglesTests: XCTestCase {
    private typealias Programs = GoalPlanTestPrograms
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private let balancedID = GoalPlanCatalog.hypertrophyBalancedID
    private let strengthID = GoalPlanCatalog.strengthID
    private let cardioID = GoalPlanCatalog.enduranceCardioID
    private let longevityID = GoalPlanCatalog.longevityID
    private let combatID = GoalPlanCatalog.combatID

    func testB9_dayTogglesOnlyWithCardioAndStrength() {
        let table: [(first: UUID, second: UUID, shows: Bool)] = [
            (balancedID, cardioID, true),
            (cardioID, balancedID, true),
            (strengthID, cardioID, true),
            (longevityID, cardioID, true),
            (combatID, cardioID, true),
            (balancedID, strengthID, false),
            (balancedID, longevityID, false),
            (strengthID, combatID, false),
            (longevityID, combatID, false),
        ]
        for row in table {
            let flow = makeDaysFlow(ids: [row.first, row.second], planner: GoalPlanTestPlanner())
            XCTAssertEqual(flow.pages, [.days, .week])
            XCTAssertEqual(flow.showsDayToggles, row.shows, "\(flow.goals.map(\.displayName))")
        }
    }

    /// Também no fluxo de adicionar um plano (folha "Seu objetivo"): a mesma conta, pelos dois objetivos.
    func testB9_addFlowUsesTheSameRule() throws {
        let repository = GoalPlanTestRepository(programs: Programs.seed())
        let current = try XCTUnwrap(repository.programs.first { $0.id == balancedID })
        let cardio = try XCTUnwrap(repository.programs.first { $0.id == cardioID })
        let strength = try XCTUnwrap(repository.programs.first { $0.id == strengthID })

        XCTAssertTrue(makeAddFlow(repository, current: current, candidate: cardio).showsDayToggles)
        XCTAssertFalse(makeAddFlow(repository, current: current, candidate: strength).showsDayToggles)
    }

    /// As chaves escondidas não apagam o que já estava gravado: salvar os dias devolve as preferências como
    /// estavam, com a chave ligada.
    func testB9_hiddenTogglesKeepStoredPreferences() throws {
        let planner = GoalPlanTestPlanner()
        planner.preferences = WeekPreferences(allowsTwoSessionsPerDay: true, allowsLightCardioAfterStrength: true)
        planner.fitResult = FitResult(schedule: WeekSchedule(slots: [
            PlannedSlot(weekday: .monday, programID: balancedID, indexInWeek: 0, kind: .strength, orderInDay: 0, dayName: "Dia A — Superior"),
            PlannedSlot(weekday: .wednesday, programID: strengthID, indexInWeek: 0, kind: .strength, orderInDay: 0, dayName: "Dia A — Agachamento e supino"),
        ]))
        let flow = makeDaysFlow(ids: [balancedID, strengthID], planner: planner)

        XCTAssertFalse(flow.showsDayToggles)
        XCTAssertTrue(flow.allowsTwoSessionsPerDay, "O que estava gravado continua")
        XCTAssertTrue(flow.allowsLightCardioAfterStrength)

        flow.next()
        XCTAssertEqual(flow.confirm(), .saved)

        let saved = try XCTUnwrap(planner.savedPreferences.last)
        XCTAssertTrue(saved.allowsTwoSessionsPerDay)
        XCTAssertTrue(saved.allowsLightCardioAfterStrength)
    }

    /// M5: "e cabem N nos seus dias" só quando os lugares de 2 por dia contam (força + aeróbico); com dois
    /// planos de força, a frase fala em dias, mesmo com a chave gravada.
    func testB9_problemTextCountsTwoPerDayOnlyWithToggles() {
        let notFitting = FitResult(schedule: nil, problems: [.notEnoughDays(needed: 13, available: 12)], alternatives: [])
        let twoPerDay = WeekPreferences(allowsTwoSessionsPerDay: true)

        let mixed = GoalPlanTestPlanner()
        mixed.preferences = twoPerDay
        mixed.fitResult = notFitting
        let mixedFlow = makeDaysFlow(ids: [balancedID, cardioID], planner: mixed)
        mixedFlow.next()
        XCTAssertEqual(mixedFlow.problemText, "São 13 sessões, e cabem 12 nos seus dias.")

        let bothStrength = GoalPlanTestPlanner()
        bothStrength.preferences = twoPerDay
        bothStrength.fitResult = notFitting
        let strengthFlow = makeDaysFlow(ids: [balancedID, strengthID], planner: bothStrength)
        strengthFlow.next()
        XCTAssertEqual(strengthFlow.problemText, "São 13 sessões para 12 dias.")
    }

    // MARK: - Fábricas

    private var clock: () -> Date {
        let fixedNow = now
        return { fixedNow }
    }

    /// "Seus dias" da aba Plano com os dois planos de `ids` ativos.
    private func makeDaysFlow(ids: [UUID], planner: GoalPlanTestPlanner) -> PlanFitFlowModel {
        let all = Programs.seed(activeIDs: Set(ids))
        let repository = GoalPlanTestRepository(programs: all)
        return PlanFitFlowModel(
            purpose: .editDays(programs: all.filter { $0.isActive }),
            programs: repository,
            planner: planner,
            now: clock
        )
    }

    private func makeAddFlow(
        _ repository: GoalPlanTestRepository,
        current: ProgramTemplate,
        candidate: ProgramTemplate
    ) -> PlanFitFlowModel {
        PlanFitFlowModel(
            purpose: .addPlan(current: current, candidate: candidate),
            programs: repository,
            planner: GoalPlanTestPlanner(),
            now: clock
        )
    }
}
