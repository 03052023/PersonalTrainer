import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T10.6, SPEC RF-53 e §7.17 X2; DESIGN §9 item 8: onde a tela Hoje põe o cartão "Também hoje". O cartão
/// em si (as linhas e o "Feito") é da `activities-ui`; aqui vale a estrutura do modelo da tela: embaixo das
/// sessões nos dois modos (um plano e dois) e, no dia de descanso, embaixo da frase.
@MainActor
final class HomeActivitiesCardTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let strengthProgramID = UUID(uuidString: "00000000-0000-0000-0000-00000000C001") ?? UUID()
    private let cardioProgramID = UUID(uuidString: "00000000-0000-0000-0000-00000000C002") ?? UUID()

    func testRF53_todayShowsActivitiesCard() {
        // Um plano só: embaixo da sessão, como na 2.2 com o cartão a mais.
        let single = HomeActivitiesTestPlanner(goals: [.hypertrophy])
        single.nextPlanToReturn = makePlan(programID: strengthProgramID, dayName: "Dia A — Superior")
        let singleModel = makeModel(single)
        XCTAssertEqual(singleModel.activitiesCardSlot, .belowSessions, "Antes de ler, o lugar é o das sessões")
        singleModel.refresh()
        XCTAssertFalse(singleModel.isMultiPlan)
        XCTAssertEqual(singleModel.activitiesCardSlot, .belowSessions)

        // Dois planos, com sessões hoje: embaixo dos cartões das sessões.
        let twoSessions = HomeActivitiesTestPlanner(goals: [.hypertrophy, .endurance])
        twoSessions.overview = TodayOverview(sessions: [
            TodaySession(plan: makePlan(programID: strengthProgramID, dayName: "Dia A — Superior"), goal: .hypertrophy, isDoneToday: false),
            TodaySession(plan: makePlan(programID: cardioProgramID, dayName: "Dia A — Base contínua"), goal: .endurance, isDoneToday: false),
        ])
        let twoModel = makeModel(twoSessions)
        twoModel.refresh()
        XCTAssertTrue(twoModel.isMultiPlan)
        XCTAssertFalse(twoModel.isRestDay)
        XCTAssertEqual(twoModel.activitiesCardSlot, .belowSessions)

        // Dois planos, tudo feito hoje: ainda embaixo das sessões.
        let allDone = HomeActivitiesTestPlanner(goals: [.hypertrophy, .endurance])
        allDone.overview = TodayOverview(sessions: [
            TodaySession(plan: makePlan(programID: strengthProgramID, dayName: "Dia B — Inferior"), goal: .hypertrophy, isDoneToday: true),
        ])
        let doneModel = makeModel(allDone)
        doneModel.refresh()
        XCTAssertTrue(doneModel.isAllDoneToday)
        XCTAssertEqual(doneModel.activitiesCardSlot, .belowSessions)

        // Dois planos, dia de descanso: embaixo da frase "Hoje é dia de descanso.".
        let restDay = HomeActivitiesTestPlanner(goals: [.hypertrophy, .endurance])
        restDay.overview = TodayOverview(
            sessions: [],
            otherSessions: [
                TodaySession(plan: makePlan(programID: strengthProgramID, dayName: "Dia A — Superior"), goal: .hypertrophy, isDoneToday: false),
            ],
            isRestDay: true
        )
        let restModel = makeModel(restDay)
        restModel.refresh()
        XCTAssertTrue(restModel.isRestDay)
        XCTAssertEqual(restModel.activitiesCardSlot, .belowRestDayText)
    }

    // MARK: - Fábricas

    private func makeModel(_ planner: HomeActivitiesTestPlanner) -> HomeViewModel {
        let fixedNow = now
        return HomeViewModel(planner: planner, coordinator: GoalPlanTestCoordinator(), now: { fixedNow })
    }

    private func makePlan(programID: UUID, dayName: String) -> SessionPlan {
        SessionPlan(
            programID: programID,
            programName: "Programa",
            programDayID: UUID(),
            programDayName: dayName,
            exercises: [],
            generatedAt: now
        )
    }
}

// MARK: - Double (privado ao arquivo)

/// Os objetivos e o dia de hoje vêm prontos. As assinaturas são exatamente as do protocolo (senão valeria o
/// padrão da extensão em silêncio).
@MainActor
private final class HomeActivitiesTestPlanner: SessionPlanning {
    var goals: [ProgramGoal]
    var overview = TodayOverview.empty
    var nextPlanToReturn: SessionPlan?

    init(goals: [ProgramGoal]) {
        self.goals = goals
    }

    func nextPlan(now: Date) throws -> SessionPlan? {
        nextPlanToReturn
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        nil
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        UUID()
    }

    func activeProgramGoal() throws -> ProgramGoal? {
        goals.first
    }

    func activeProgramGoals() throws -> [ProgramGoal] {
        goals
    }

    func todayOverview(now: Date) throws -> TodayOverview {
        overview
    }

    func days(ofProgramID programID: UUID) throws -> [ProgramDayTemplate] {
        []
    }
}
