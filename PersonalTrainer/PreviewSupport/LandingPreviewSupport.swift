import Foundation
import SwiftUI
import TrainerCore

// Doubles e fixtures só para os #Preview da feature Landing (AGENTS R9: previews usam fakes).
// Tudo privado ao arquivo e prefixado por "Landing" para não colidir com doubles de outras
// features; por isso os previews do Início vivem aqui, e não em cada arquivo de view.

// MARK: - Previews

#Preview("Início — sessão pendente") {
    LandingPreviewFixture.makeLanding(
        planner: LandingPreviewFixture.planner(pendingCount: 1),
        coordinator: LandingPreviewCoordinator()
    )
}

#Preview("Início — duas sessões (dois planos)") {
    LandingPreviewFixture.makeLanding(
        planner: LandingPreviewFixture.planner(pendingCount: 2, activeGoals: [.hypertrophy, .endurance]),
        coordinator: LandingPreviewCoordinator()
    )
}

#Preview("Início — sessão em andamento") {
    LandingPreviewFixture.makeLanding(
        planner: LandingPreviewFixture.planner(pendingCount: 1),
        coordinator: LandingPreviewCoordinator(activeSession: LandingPreviewFixture.makeInProgressSession())
    )
}

#Preview("Início — tudo feito hoje") {
    LandingPreviewFixture.makeLanding(
        planner: LandingPreviewFixture.planner(pendingCount: 0, isDoneToday: true),
        coordinator: LandingPreviewCoordinator()
    )
}

#Preview("Início — dia de descanso") {
    LandingPreviewFixture.makeLanding(
        planner: LandingPreviewFixture.planner(pendingCount: 0, isRestDay: true, activeGoals: [.hypertrophy, .endurance]),
        coordinator: LandingPreviewCoordinator()
    )
}

#Preview("Início — sem objetivo") {
    LandingPreviewFixture.makeLanding(
        planner: LandingPreviewFixture.planner(pendingCount: 0, activeGoals: []),
        coordinator: LandingPreviewCoordinator()
    )
}

#Preview("Metas da semana") {
    NavigationStack {
        WeeklyGoalsView(
            model: LandingPreviewFixture.makeModel(
                planner: LandingPreviewFixture.planner(pendingCount: 1, activeGoals: [.longevity]),
                coordinator: LandingPreviewCoordinator()
            ),
            references: LandingPreviewFixture.references
        )
    }
}

// MARK: - Fixtures

@MainActor
private enum LandingPreviewFixture {
    /// Data fixa (SPEC P11): previews determinísticos. Quarta-feira, 30/09/2026, 07:00 em São Paulo
    /// ("Bom dia"); a sessão de exemplo da semana cai na segunda-feira.
    static let referenceDate = Date(timeIntervalSince1970: 1_790_762_400)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
        return calendar
    }()

    static let references = ReferenceLibrary.load(bundle: .main)

    static func makeLanding(planner: any SessionPlanning, coordinator: any SessionCoordinating) -> LandingView {
        LandingView(
            model: makeModel(planner: planner, coordinator: coordinator),
            references: references,
            onOpenToday: {},
            onOpenSession: { _ in }
        )
    }

    static func makeModel(planner: any SessionPlanning, coordinator: any SessionCoordinating) -> LandingViewModel {
        LandingViewModel(planner: planner, coordinator: coordinator, now: { referenceDate }, calendar: calendar)
    }

    /// Um planejador com `pendingCount` sessões pendentes hoje (0, 1 ou 2), o bastante para ver
    /// todos os estados do caminho (RF-49 ponto 2). Com `isDoneToday`, a sessão de hoje já foi feita.
    static func planner(
        pendingCount: Int,
        isRestDay: Bool = false,
        isDoneToday: Bool = false,
        activeGoals: [ProgramGoal] = [.hypertrophy]
    ) -> any SessionPlanning {
        let plans = (0..<max(pendingCount, activeGoals.isEmpty ? 0 : 1)).map { index in
            makePlan(dayName: index == 0 ? "Dia A — Superior" : "Dia B — Base contínua", suffix: index)
        }
        let sessions = plans.enumerated().map { index, plan in
            TodaySession(
                plan: plan,
                goal: activeGoals[safe: index] ?? activeGoals.first ?? .hypertrophy,
                isDoneToday: isDoneToday
            )
        }
        let overview = TodayOverview(sessions: sessions, isRestDay: isRestDay)
        let week = WeeklyFrequency.weekInterval(containing: referenceDate, weekStartsOnMonday: true, calendar: calendar)
        let frequency = WeeklyFrequencyReport(
            weekStart: week.start,
            weekEnd: week.end,
            entries: MuscleGroup.allCases.map { WeeklyFrequencyEntry(muscle: $0, completed: $0 == .chest ? 2 : 1, target: 2) }
        )
        let plansProgress = activeGoals.enumerated().map { index, goal in
            PlanWeekProgress(programID: plans[safe: index]?.programID ?? UUID(), goal: goal, completed: 2, perWeek: 4)
        }
        let summaries: [SessionSummary] = [
            SessionSummary(
                programDayID: UUID(),
                startedAt: referenceDate.addingTimeInterval(-2 * 86_400),
                endedAt: referenceDate.addingTimeInterval(-2 * 86_400 + 3_000),
                status: .completed,
                primaryMusclesTrained: [.chest, .triceps],
                workingSetCount: 9
            ),
        ]
        return LandingPreviewPlanner(
            overview: overview,
            activeGoals: activeGoals,
            completedSummaries: summaries,
            frequencyReport: frequency,
            plansProgress: plansProgress
        )
    }

    private static func makePlan(dayName: String, suffix: Int) -> SessionPlan {
        let exercise = ExerciseDefinition(
            slug: "agachamento-livre-\(suffix)",
            name: "Agachamento livre",
            primaryMuscles: [.quads, .glutes],
            equipment: .barbell,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )
        let target = ExerciseTarget(exerciseID: exercise.id, order: 0, sets: 3, repMin: 6, repMax: 10, targetRIR: 2, restSeconds: 180, startingLoad: 60)
        return SessionPlan(
            programID: UUID(),
            programName: "Programa",
            programDayID: UUID(),
            programDayName: dayName,
            exercises: [
                PlannedExercise(
                    id: UUID(),
                    exercise: exercise,
                    target: target,
                    prescription: ExercisePrescription(
                        exerciseID: exercise.id, load: 60, sets: 3, repMin: 6, repMax: 10,
                        targetReps: 8, targetRIR: 2, restSeconds: 180, note: .hold
                    )
                ),
            ],
            generatedAt: referenceDate
        )
    }

    /// Sessão `inProgress` fora de qualquer container: o preview só lê `uuid` e `programDayName`.
    static func makeInProgressSession() -> WorkoutSessionModel {
        WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A — Superior",
            statusRaw: SessionStatus.inProgress.rawValue,
            startedAt: referenceDate.addingTimeInterval(-900),
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: DeviceSource.iphone.rawValue
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Doubles

@MainActor
private final class LandingPreviewPlanner: SessionPlanning {
    private let overview: TodayOverview
    private let activeGoals: [ProgramGoal]
    private let completedSummaries: [SessionSummary]
    private let frequencyReport: WeeklyFrequencyReport
    private let plansProgress: [PlanWeekProgress]

    init(
        overview: TodayOverview,
        activeGoals: [ProgramGoal],
        completedSummaries: [SessionSummary],
        frequencyReport: WeeklyFrequencyReport,
        plansProgress: [PlanWeekProgress]
    ) {
        self.overview = overview
        self.activeGoals = activeGoals
        self.completedSummaries = completedSummaries
        self.frequencyReport = frequencyReport
        self.plansProgress = plansProgress
    }

    func nextPlan(now: Date) throws -> SessionPlan? {
        overview.sessions.first?.plan
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        nil
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        UUID()
    }

    func activeProgramGoal() throws -> ProgramGoal? {
        activeGoals.first
    }

    func activeProgramGoals() throws -> [ProgramGoal] {
        activeGoals
    }

    func todayOverview(now: Date) throws -> TodayOverview {
        overview
    }

    func completedSessionSummaries() throws -> [SessionSummary] {
        completedSummaries
    }

    func weeklyFrequency(now: Date) throws -> WeeklyFrequencyReport {
        frequencyReport
    }

    func planWeekProgress(now: Date) throws -> [PlanWeekProgress] {
        plansProgress
    }
}

@MainActor
private final class LandingPreviewCoordinator: SessionCoordinating {
    let activeSession: WorkoutSessionModel?

    init(activeSession: WorkoutSessionModel? = nil) {
        self.activeSession = activeSession
    }

    func session(withID id: UUID) -> WorkoutSessionModel? {
        guard let activeSession, activeSession.uuid == id else { return nil }
        return activeSession
    }

    func startSession(plan: SessionPlan, now: Date, source: DeviceSource) throws -> UUID {
        UUID()
    }

    func apply(_ event: SessionEvent) throws {}

    var eventsApplied: AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
