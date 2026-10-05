import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T9.3: `LandingViewModel` (SPEC RF-49, RF-52, §7.16; DESIGN §9.1/§9.2; docs/V23-UI-CONTRACT.md
/// §4.3). Cobre a saudação por horário, as marcas de "Esta semana", a frase de fato, os estados do
/// caminho para o treino de hoje e as Metas da semana (nunca pedem autorização ao Saúde, AGENTS §7).
/// Doubles próprios (`LandingTestPlanner`, `LandingTestCoordinator`); relógio e calendário fixos
/// (SPEC P11).
@MainActor
final class LandingViewModelTests: XCTestCase {
    /// Gregoriano, UTC fixo, semana começando na segunda (como `WeeklyFrequency`, SPEC §7.4).
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    /// Segunda-feira, 2026-09-28, 10:00 UTC.
    private let monday = Date(timeIntervalSince1970: 1_790_589_600)

    // MARK: - RF-49: saudação por horário

    func testRF49_greetingByHour() {
        XCTAssertEqual(LandingText.greeting(hour: 4), "Boa noite", "4h59: ainda noite")
        XCTAssertEqual(LandingText.greeting(hour: 5), "Bom dia", "5h00: começa a manhã")
        XCTAssertEqual(LandingText.greeting(hour: 11), "Bom dia", "11h59: ainda manhã")
        XCTAssertEqual(LandingText.greeting(hour: 12), "Boa tarde", "12h00: começa a tarde")
        XCTAssertEqual(LandingText.greeting(hour: 17), "Boa tarde", "17h59: ainda tarde")
        XCTAssertEqual(LandingText.greeting(hour: 18), "Boa noite", "18h00: começa a noite")
        XCTAssertEqual(LandingText.greeting(hour: 23), "Boa noite")
        XCTAssertEqual(LandingText.greeting(hour: 0), "Boa noite")
    }

    // MARK: - RF-49: marcas da semana e frase

    func testRF49_weekMarks_mondayToSunday() throws {
        let programDayID = UUID()
        // Segunda e quarta contam; abandonada (sem série de trabalho não conta) e sem série ficam
        // fora; a semana seguinte também fica fora.
        let mondaySession = session(startedAt: monday, status: .completed, workingSets: 3, programDayID: programDayID)
        let wednesdaySession = session(
            startedAt: monday.addingTimeInterval(2 * 86_400), status: .completed, workingSets: 1, programDayID: programDayID
        )
        let abandonedSession = session(
            startedAt: monday.addingTimeInterval(3 * 86_400), status: .abandoned, workingSets: 0, programDayID: programDayID
        )
        let noWorkingSetsSession = session(
            startedAt: monday.addingTimeInterval(4 * 86_400), status: .completed, workingSets: 0, programDayID: programDayID
        )
        let nextWeekSession = session(
            startedAt: monday.addingTimeInterval(7 * 86_400), status: .completed, workingSets: 2, programDayID: programDayID
        )

        let (marks, sentence) = LandingViewModel.weekMarksAndSentence(
            summaries: [mondaySession, wednesdaySession, abandonedSession, noWorkingSetsSession, nextWeekSession],
            now: monday.addingTimeInterval(3 * 3_600),
            calendar: calendar
        )

        XCTAssertEqual(marks, [true, false, true, false, false, false, false])
        XCTAssertEqual(sentence, "2 sessões nesta semana.")
    }

    func testRF49_weekSentence() {
        XCTAssertEqual(LandingText.weekSentence(sessionCount: 0), "Nenhuma sessão nesta semana ainda.")
        XCTAssertEqual(LandingText.weekSentence(sessionCount: 1), "1 sessão nesta semana.")
        XCTAssertEqual(LandingText.weekSentence(sessionCount: 2), "2 sessões nesta semana.")
        XCTAssertEqual(LandingText.weekSentence(sessionCount: 5), "5 sessões nesta semana.")
    }

    func testRF49_dateText() {
        XCTAssertEqual(LandingText.dateText(monday, calendar: calendar), "segunda-feira, 28 de setembro")
        let sunday = monday.addingTimeInterval(6 * 86_400)
        XCTAssertEqual(LandingText.dateText(sunday, calendar: calendar), "domingo, 4 de outubro")
    }

    func testRF49_refreshFillsDateGreetingAndGoals() {
        let planner = LandingTestPlanner()
        planner.activeGoals = [.hypertrophy]
        let model = LandingViewModel(
            planner: planner,
            coordinator: LandingTestCoordinator(),
            now: { self.monday },
            calendar: calendar
        )

        model.refresh()

        XCTAssertEqual(model.dateText, "segunda-feira, 28 de setembro")
        XCTAssertEqual(model.greeting, "Bom dia", "10h00 no calendário da pessoa")
        XCTAssertEqual(model.todayWeekdayIndex, 0, "segunda-feira")
        XCTAssertEqual(model.activeGoals, [.hypertrophy])
    }

    func testRF49_weekMarksAccessibilityLabel() {
        let none = Array(repeating: false, count: 7)
        XCTAssertEqual(LandingText.weekMarksAccessibilityLabel(marks: none), "Esta semana: nenhuma sessão ainda.")
        XCTAssertEqual(
            LandingText.weekMarksAccessibilityLabel(marks: [true, false, true, false, false, false, false]),
            "Esta semana: sessão na segunda-feira e na quarta-feira."
        )
        XCTAssertEqual(
            LandingText.weekMarksAccessibilityLabel(marks: [false, false, false, false, false, true, false]),
            "Esta semana: sessão no sábado."
        )
        XCTAssertEqual(
            LandingText.weekMarksAccessibilityLabel(marks: [true, false, true, false, false, true, false]),
            "Esta semana: sessão na segunda-feira, na quarta-feira e no sábado."
        )
    }

    func testRF49_readFailureKeepsThePath() {
        let plan = makePlan(dayName: "Dia A — Superior", exerciseCount: 5, estimatedMinutes: 55)
        let planner = LandingTestPlanner()
        planner.activeGoals = [.hypertrophy]
        planner.overview = TodayOverview(sessions: [TodaySession(plan: plan, goal: .hypertrophy, isDoneToday: false)])
        planner.summariesError = LandingTestError.unreadable
        let model = LandingViewModel(
            planner: planner,
            coordinator: LandingTestCoordinator(),
            now: { self.monday },
            calendar: calendar
        )

        model.refresh()

        XCTAssertEqual(model.weekReadErrorMessage, "Não foi possível ler a semana.")
        XCTAssertEqual(model.weekMarks, Array(repeating: false, count: 7))
        XCTAssertEqual(model.pathState, .todaySessions(label: "Dia A — Superior", subtitle: "5 exercícios · ≈ 55 min"))
    }

    // MARK: - RF-49: estados do caminho

    func testRF49_path_inProgress() {
        let activeSession = makeActiveSession(dayName: "Dia A — Superior")

        let state = LandingViewModel.computePathState(
            activeSession: activeSession,
            hasActiveGoal: true,
            overview: .empty
        )

        XCTAssertEqual(state, .inProgress(sessionID: activeSession.uuid, label: "Sessão em andamento: Dia A — Superior"))
    }

    func testRF49_path_todaySessions() {
        let plan = makePlan(dayName: "Dia A — Superior", exerciseCount: 5, estimatedMinutes: 55)
        let overview = TodayOverview(sessions: [TodaySession(plan: plan, goal: .hypertrophy, isDoneToday: false)])

        let state = LandingViewModel.computePathState(activeSession: nil, hasActiveGoal: true, overview: overview)

        XCTAssertEqual(state, .todaySessions(label: "Dia A — Superior", subtitle: "5 exercícios · ≈ 55 min"))
    }

    func testRF49_path_twoSessions() {
        let first = makePlan(dayName: "Dia A — Superior", exerciseCount: 5, estimatedMinutes: 55)
        let second = makePlan(dayName: "Dia B — Base contínua", exerciseCount: 1, estimatedMinutes: 30)
        let overview = TodayOverview(sessions: [
            TodaySession(plan: first, goal: .hypertrophy, isDoneToday: false),
            TodaySession(plan: second, goal: .endurance, isDoneToday: false),
        ])

        let state = LandingViewModel.computePathState(activeSession: nil, hasActiveGoal: true, overview: overview)

        XCTAssertEqual(
            state,
            .todaySessions(label: "Dia A — Superior + Dia B — Base contínua", subtitle: "2 sessões · ≈ 85 min")
        )
    }

    func testRF49_path_allDone() {
        let plan = makePlan(dayName: "Dia A — Superior", exerciseCount: 5, estimatedMinutes: 55)
        let overview = TodayOverview(sessions: [TodaySession(plan: plan, goal: .hypertrophy, isDoneToday: true)])

        let state = LandingViewModel.computePathState(activeSession: nil, hasActiveGoal: true, overview: overview)

        XCTAssertEqual(state, .allDone)
    }

    func testRF49_path_restDay() {
        let overview = TodayOverview(sessions: [], isRestDay: true)

        let state = LandingViewModel.computePathState(activeSession: nil, hasActiveGoal: true, overview: overview)

        XCTAssertEqual(state, .restDay)
    }

    func testRF49_path_noGoal() {
        let state = LandingViewModel.computePathState(activeSession: nil, hasActiveGoal: false, overview: .empty)

        XCTAssertEqual(state, .noGoal)
    }

    func testRF49_path_inProgressWinsOverEverythingElse() {
        // Sessão em andamento vence mesmo sem objetivo ativo formalmente lido ainda (defensivo).
        let activeSession = makeActiveSession(dayName: "Dia C — Pernas")

        let state = LandingViewModel.computePathState(activeSession: activeSession, hasActiveGoal: false, overview: .empty)

        XCTAssertEqual(state, .inProgress(sessionID: activeSession.uuid, label: "Sessão em andamento: Dia C — Pernas"))
    }

    // MARK: - RF-52: Metas da semana nunca pedem autorização

    func testRF52_goalsScreenReadsHealthWithoutAsking() async {
        let planner = LandingTestPlanner()
        planner.activeGoals = [.hypertrophy]
        var loadHealthCallCount = 0
        // `LandingViewModel` só conhece este fechamento: nunca chama autorização por conta própria
        // (AGENTS §7). A montagem real do integrador passa `healthModel.loadIfStale()`, que só lê o
        // que já foi autorizado (`HealthViewModelTests` cobre essa regra na origem).
        let model = LandingViewModel(
            planner: planner,
            coordinator: LandingTestCoordinator(),
            now: { self.monday },
            calendar: calendar,
            healthReport: { nil },
            loadHealth: { loadHealthCallCount += 1 }
        )

        await model.openWeeklyGoals()

        XCTAssertEqual(loadHealthCallCount, 1, "abrir as Metas lê o Saúde uma vez")
    }

    func testRF52_noPlanShowsChooseGoal() {
        let planner = LandingTestPlanner()
        planner.activeGoals = []
        let model = LandingViewModel(
            planner: planner,
            coordinator: LandingTestCoordinator(),
            now: { self.monday },
            calendar: calendar
        )

        model.refresh()

        XCTAssertFalse(model.weeklyGoals.contains { $0.kind == .planSessions })
        XCTAssertEqual(model.pathState, .noGoal)
    }

    func testRF52_weekRangeText() {
        let start = calendar.startOfDay(for: monday)
        let end = start.addingTimeInterval(7 * 86_400)

        XCTAssertEqual(
            LandingText.weekRangeText(weekStart: start, weekEnd: end, calendar: calendar),
            "28 set. – 4 out."
        )
    }

    func testRF52_frequencyReadFailureKeepsTheGoalsAndTheMondayWeek() {
        let planner = LandingTestPlanner()
        planner.activeGoals = [.hypertrophy]
        planner.plansProgress = [PlanWeekProgress(programID: UUID(), goal: .hypertrophy, completed: 1, perWeek: 3)]
        planner.frequencyError = LandingTestError.unreadable
        let model = LandingViewModel(
            planner: planner,
            coordinator: LandingTestCoordinator(),
            now: { self.monday },
            calendar: calendar
        )

        model.refresh()

        XCTAssertEqual(model.weekRangeText, "28 set. – 4 out.", "sem a leitura, vale a semana de segunda a domingo")
        XCTAssertFalse(model.weeklyGoals.contains { $0.kind == .muscles }, "sem grupos, a meta de músculos some (W2)")
        XCTAssertTrue(model.weeklyGoals.contains { $0.kind == .planSessions })
    }

    func testRefresh_populatesWeeklyGoalsFromThePlanner() {
        let planner = LandingTestPlanner()
        planner.activeGoals = [.hypertrophy]
        planner.plansProgress = [PlanWeekProgress(programID: UUID(), goal: .hypertrophy, completed: 2, perWeek: 4)]
        let model = LandingViewModel(
            planner: planner,
            coordinator: LandingTestCoordinator(),
            now: { self.monday },
            calendar: calendar
        )

        model.refresh()

        let sessions = model.weeklyGoals.filter { $0.kind == .planSessions }
        XCTAssertEqual(sessions.map(\.done), [2])
        XCTAssertEqual(sessions.map(\.target), [4])
    }

    // MARK: - Suporte

    private func session(
        startedAt: Date,
        status: SessionStatus,
        workingSets: Int,
        programDayID: UUID
    ) -> SessionSummary {
        SessionSummary(
            programDayID: programDayID,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3_600),
            status: status,
            primaryMusclesTrained: [.chest],
            workingSetCount: workingSets
        )
    }

    private func makeActiveSession(dayName: String) -> WorkoutSessionModel {
        WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: dayName,
            statusRaw: SessionStatus.inProgress.rawValue,
            startedAt: monday,
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: DeviceSource.iphone.rawValue
        )
    }

    private func makePlan(dayName: String, exerciseCount: Int, estimatedMinutes: Int) -> SessionPlan {
        let exercise = ExerciseDefinition(
            slug: "exercicio",
            name: "Exercício",
            primaryMuscles: [.chest],
            equipment: .barbell,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )
        let target = ExerciseTarget(exerciseID: exercise.id, order: 0, sets: 3, repMin: 8, repMax: 12, targetRIR: 2, restSeconds: 90, startingLoad: 40)
        let prescription = ExercisePrescription(
            exerciseID: exercise.id, load: 40, sets: 3, repMin: 8, repMax: 12,
            targetReps: 8, targetRIR: 2, restSeconds: 90, note: .hold
        )
        let exercises = (0..<exerciseCount).map { index in
            PlannedExercise(id: UUID(), exercise: exercise, target: target, prescription: prescription)
        }
        return SessionPlan(
            programID: UUID(),
            programName: "Programa",
            programDayID: UUID(),
            programDayName: dayName,
            exercises: exercises,
            generatedAt: monday,
            estimatedMinutes: estimatedMinutes
        )
    }
}

// MARK: - Doubles

private enum LandingTestError: Error {
    case unreadable
}

@MainActor
private final class LandingTestPlanner: SessionPlanning {
    var activeGoals: [ProgramGoal] = []
    var overview = TodayOverview.empty
    var completedSummaries: [SessionSummary] = []
    var frequencyReport = WeeklyFrequencyReport(weekStart: .distantPast, weekEnd: .distantPast, entries: [])
    var plansProgress: [PlanWeekProgress] = []
    /// Quando definido, a leitura correspondente lança, para testar o caminho de falha (RF-49 ponto 5).
    var summariesError: (any Error)?
    var frequencyError: (any Error)?

    func nextPlan(now: Date) throws -> SessionPlan? { overview.sessions.first?.plan }
    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? { nil }
    func startSession(from plan: SessionPlan, now: Date) throws -> UUID { UUID() }
    func activeProgramGoal() throws -> ProgramGoal? { activeGoals.first }
    func activeProgramGoals() throws -> [ProgramGoal] { activeGoals }
    func todayOverview(now: Date) throws -> TodayOverview { overview }
    func completedSessionSummaries() throws -> [SessionSummary] {
        if let summariesError {
            throw summariesError
        }
        return completedSummaries
    }
    func weeklyFrequency(now: Date) throws -> WeeklyFrequencyReport {
        if let frequencyError {
            throw frequencyError
        }
        return frequencyReport
    }
    func planWeekProgress(now: Date) throws -> [PlanWeekProgress] { plansProgress }
}

@MainActor
private final class LandingTestCoordinator: SessionCoordinating {
    var activeSession: WorkoutSessionModel?

    func session(withID id: UUID) -> WorkoutSessionModel? {
        guard let activeSession, activeSession.uuid == id else { return nil }
        return activeSession
    }

    func startSession(plan: SessionPlan, now: Date, source: DeviceSource) throws -> UUID { UUID() }
    func apply(_ event: SessionEvent) throws {}

    var eventsApplied: AsyncStream<SessionEvent> {
        AsyncStream { continuation in continuation.finish() }
    }
}
