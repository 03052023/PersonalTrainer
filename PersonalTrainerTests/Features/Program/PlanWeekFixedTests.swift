import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T10.6, SPEC §7.17 X4 e DESIGN §9.3 ponto 5: as atividades fixas na semana da aba Plano, em tabela. A fixa
/// aparece no dia dela, depois das sessões ("Ter · Dia B — Inferior + Pilates"; dia só com fixa: "Ter ·
/// Pilates"), sem cor de objetivo, e o dia com ela não é de descanso. O encaixe em si é do núcleo
/// (`WeeklyFit`); aqui só o texto.
@MainActor
final class PlanWeekFixedTests: XCTestCase {
    private typealias Programs = GoalPlanTestPrograms
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private let balancedID = GoalPlanCatalog.hypertrophyBalancedID
    private let cardioID = GoalPlanCatalog.enduranceCardioID

    private var goals: [UUID: ProgramGoal] {
        [balancedID: .hypertrophy, cardioID: .endurance]
    }

    private var slots: [PlannedSlot] {
        [
            PlannedSlot(weekday: .monday, programID: balancedID, indexInWeek: 0, kind: .strength, orderInDay: 0, dayName: "Dia A — Superior"),
            PlannedSlot(weekday: .tuesday, programID: balancedID, indexInWeek: 1, kind: .strength, orderInDay: 0, dayName: "Dia B — Inferior"),
            PlannedSlot(weekday: .thursday, programID: cardioID, indexInWeek: 0, kind: .cardio, orderInDay: 0, dayName: "Dia A — Base contínua", cardioIntensity: .moderate),
        ]
    }

    private var fixed: [FixedActivityDemand] {
        [
            FixedActivityDemand(id: UUID(), name: "Pilates", weekday: .tuesday, role: .light, minutes: 50),
            FixedActivityDemand(id: UUID(), name: "Natação", weekday: .wednesday, role: .cardio, cardioIntensity: .moderate, minutes: 45),
            FixedActivityDemand(id: UUID(), name: "Futebol ou esporte com bola", weekday: .thursday, role: .cardio, cardioIntensity: .vigorous, minutes: 60),
            FixedActivityDemand(id: UUID(), name: "Ioga ou alongamento", weekday: .thursday, role: .light, minutes: 30),
        ]
    }

    func testX4_weekTextShowsFixed() throws {
        let schedule = WeekSchedule(slots: slots, fixed: fixed)

        let rows = PlanWeekText.weekRows(schedule, goals: goals)

        XCTAssertEqual(rows.map(\.text), [
            "Seg · Dia A — Superior",
            "Ter · Dia B — Inferior + Pilates",
            "Qua · Natação",
            "Qui · Cardio moderado + Futebol ou esporte com bola + Ioga ou alongamento",
            "Sex · descanso",
            "Sáb · descanso",
            "Dom · descanso",
        ])
        XCTAssertEqual(
            rows.map(\.isRest),
            [false, false, false, false, true, true, true],
            "Um dia só com fixa não é de descanso"
        )
        let tuesday = try XCTUnwrap(rows.first { $0.day == .tuesday })
        XCTAssertEqual(tuesday.goals, [.hypertrophy], "A fixa não tem ponto de cor")
        XCTAssertEqual(tuesday.spokenText, "terça: Dia B — Inferior e Pilates")
        let wednesday = try XCTUnwrap(rows.first { $0.day == .wednesday })
        XCTAssertTrue(wednesday.goals.isEmpty, "Dia só com fixa: nenhum ponto")
        XCTAssertEqual(wednesday.spokenText, "quarta: Natação")
        let thursday = try XCTUnwrap(rows.first { $0.day == .thursday })
        XCTAssertEqual(thursday.goals, [.endurance])
    }

    /// Sem fixas, a semana é a de sempre (M4).
    func testX4_weekTextWithoutFixedUnchanged() {
        let schedule = WeekSchedule(slots: slots)

        let rows = PlanWeekText.weekRows(schedule, goals: goals)

        XCTAssertEqual(rows.map(\.text), [
            "Seg · Dia A — Superior",
            "Ter · Dia B — Inferior",
            "Qua · descanso",
            "Qui · Cardio moderado",
            "Sex · descanso",
            "Sáb · descanso",
            "Dom · descanso",
        ])
        XCTAssertEqual(rows.map(\.isRest), [false, false, true, false, true, true, true])
    }

    /// A aba Plano, com dois planos, lê a semana do planejador e mostra as fixas dela.
    func testX4_planTabWeekShowsFixed() {
        let repository = GoalPlanTestRepository(programs: Programs.seed(activeIDs: [balancedID, cardioID]))
        let planner = GoalPlanTestPlanner()
        planner.scheduleToReturn = WeekSchedule(slots: slots, notes: [.noFullRestDay], fixed: fixed)
        let fixedNow = now
        let model = PlanTabModel(
            programs: repository,
            catalog: GoalPlanTestCatalog(),
            planner: planner,
            coordinator: nil,
            now: { fixedNow }
        )

        model.refresh()

        XCTAssertEqual(model.weekRows.map(\.text), [
            "Seg · Dia A — Superior",
            "Ter · Dia B — Inferior + Pilates",
            "Qua · Natação",
            "Qui · Cardio moderado + Futebol ou esporte com bola + Ioga ou alongamento",
            "Sex · descanso",
            "Sáb · descanso",
            "Dom · descanso",
        ])
        XCTAssertEqual(model.weekNotes, ["Sem um dia de descanso completo."])
        XCTAssertFalse(model.showsNotFit)
    }

    /// DESIGN §6 e §9.3 ponto 6: nenhum texto da semana com fixas vira frase de efeito.
    func testX4_weekTextHasNoSlogans() {
        let rows = PlanWeekText.weekRows(WeekSchedule(slots: slots, fixed: fixed), goals: goals)
        for row in rows {
            XCTAssertFalse(row.text.contains("!"), row.text)
            XCTAssertFalse(row.spokenText.contains("!"), row.spokenText)
        }
    }
}
