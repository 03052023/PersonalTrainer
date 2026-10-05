import Foundation
import Testing
@testable import TrainerCore

// MARK: - Fixtures

// An arbitrary fixed instant (2025-09-23T04:00:00Z): `WeeklyGoals` never reads the dates of a report, so it is only an opaque stamp here.
private let weekStart = Date(timeIntervalSince1970: 1_758_600_000)
private let weekEnd = weekStart.addingTimeInterval(7 * 86_400)

private func frequencyReport(_ entries: [(MuscleGroup, Int, Int)]) -> WeeklyFrequencyReport {
    WeeklyFrequencyReport(
        weekStart: weekStart,
        weekEnd: weekEnd,
        entries: entries.map { WeeklyFrequencyEntry(muscle: $0.0, completed: $0.1, target: $0.2) }
    )
}

/// A frequency report with every `MuscleGroup` at the default target (2), all untrained: a neutral
/// stand-in for tests that only care about another goal.
private let emptyFrequencyReport = frequencyReport(MuscleGroup.allCases.map { ($0, 0, 2) })

private func healthReport(
    aerobicMinutes: Int? = nil,
    stepsAverage: Int? = nil,
    sleepHours: Double? = nil
) -> HealthReport? {
    guard aerobicMinutes != nil || stepsAverage != nil || sleepHours != nil else {
        return nil
    }
    return HealthReport(
        weekStart: weekStart,
        aerobic: AerobicWeekSummary(
            moderateMinutes: aerobicMinutes ?? 0,
            vigorousMinutes: 0,
            moderateEquivalentMinutes: aerobicMinutes ?? 0,
            target: 150,
            perDay: []
        ),
        vo2Max: nil,
        recovery: RecoverySummary(
            hrv7: nil, hrv28: nil, restingHR7: nil, restingHR28: nil,
            sleep7: sleepHours, sleep28: nil, nightsWithData7: 0, alerts: []
        ),
        steps: StepsSummary(average7: stepsAverage, target: 7_000),
        suggestions: []
    )
}

private func input(
    plans: [PlanWeekProgress] = [],
    activeGoals: [ProgramGoal] = [],
    frequency: WeeklyFrequencyReport = emptyFrequencyReport,
    health: HealthReport? = nil,
    longevityDone: Set<String> = []
) -> WeeklyGoalsInput {
    WeeklyGoalsInput(
        plans: plans,
        activeGoals: activeGoals,
        frequency: frequency,
        health: health,
        longevityDone: longevityDone
    )
}

private func plan(_ goal: ProgramGoal, completed: Int, perWeek: Int, id: UUID = UUID()) -> PlanWeekProgress {
    PlanWeekProgress(programID: id, goal: goal, completed: completed, perWeek: perWeek)
}

// MARK: - W2: order

@Test("W2 um plano sem Longevidade: sessões, músculos, aeróbico, sono — sem passos nem equilíbrio/mobilidade")
func weeklyGoalsOrderOnePlanNoLongevity() {
    let goals = WeeklyGoals.goals(input(
        plans: [plan(.hypertrophy, completed: 3, perWeek: 4)],
        activeGoals: [.hypertrophy],
        health: healthReport(aerobicMinutes: 90, stepsAverage: 6_000, sleepHours: 7.2)
    ))

    #expect(goals.map(\.kind) == [.planSessions, .muscles, .aerobic, .sleep])
}

@Test("W2 dois planos: o principal vem primeiro, na ordem recebida (Cardio ativa os passos)")
func weeklyGoalsOrderTwoPlansPrincipalFirst() {
    let hypertrophyID = UUID()
    let cardioID = UUID()
    let goals = WeeklyGoals.goals(input(
        plans: [
            plan(.hypertrophy, completed: 2, perWeek: 4, id: hypertrophyID),
            plan(.endurance, completed: 1, perWeek: 2, id: cardioID),
        ],
        activeGoals: [.hypertrophy, .endurance]
    ))

    let sessionRows = goals.filter { $0.kind == .planSessions }
    #expect(sessionRows.map(\.programID) == [hypertrophyID, cardioID])
    #expect(sessionRows.map(\.planGoal) == [.hypertrophy, .endurance])
    #expect(goals.map(\.kind) == [.planSessions, .planSessions, .muscles, .aerobic, .steps, .sleep])
}

@Test("W2 com a Longevidade ativa, equilíbrio e mobilidade fecham a lista, depois do sono")
func weeklyGoalsOrderLongevityPutsBalanceAndMobilityLast() {
    let goals = WeeklyGoals.goals(input(
        plans: [plan(.longevity, completed: 2, perWeek: 3)],
        activeGoals: [.longevity]
    ))

    #expect(goals.map(\.kind) == [.planSessions, .muscles, .aerobic, .steps, .sleep, .balance, .mobility])
}

@Test("W2 sem plano ativo, não há linha de sessões, e as outras metas continuam")
func weeklyGoalsOrderNoActivePlanSkipsSessions() {
    let goals = WeeklyGoals.goals(input())

    #expect(!goals.contains { $0.kind == .planSessions })
    #expect(goals.map(\.kind) == [.muscles, .aerobic, .sleep])
}

// MARK: - W2.1: sessions per plan

@Test("W2 sessões por plano: feito e meta vêm de PlanWeekProgress; o tópico é o do objetivo do plano")
func weeklyGoalsSessionsMatchPlanWeekProgress() {
    let goals = WeeklyGoals.goals(input(
        plans: [
            plan(.hypertrophy, completed: 3, perWeek: 4),
            plan(.endurance, completed: 5, perWeek: 2),
        ],
        activeGoals: [.hypertrophy, .endurance]
    ))
    let sessions = goals.filter { $0.kind == .planSessions }

    #expect(sessions[0].done == 3)
    #expect(sessions[0].target == 4)
    #expect(sessions[0].referenceTopic == "goal.hypertrophy")
    #expect(sessions[0].isMet == false)

    #expect(sessions[1].done == 5)
    #expect(sessions[1].target == 2)
    #expect(sessions[1].referenceTopic == "goal.endurance")
    #expect(sessions[1].isMet, "5 de 2: passou da meta, mas continua cumprida (W3)")
}

@Test("W2 plano sem dias (perWeek 0) não vira meta zero: o piso é 1")
func weeklyGoalsSessionsFloorsZeroPerWeekToOne() {
    let goals = WeeklyGoals.goals(input(
        plans: [plan(.hypertrophy, completed: 0, perWeek: 0)],
        activeGoals: [.hypertrophy]
    ))

    #expect(goals.first?.target == 1)
}

// MARK: - W2.2: muscles

@Test("W2 músculos: a marca pesa pela soma das metas; o número é a contagem de grupos cumpridos")
func weeklyGoalsMusclesWeightedFractionAndMetCount() throws {
    let goals = WeeklyGoals.goals(input(
        frequency: frequencyReport([
            (.chest, 1, 2),   // not met: min = 1
            (.back, 2, 2),    // met: min = 2
            (.quads, 3, 2),   // met, exceeds: min = 2 (capped at target)
            (.core, 5, 0),    // target 0: excluded from both the mark and the count
        ])
    ))
    let muscles = try #require(goals.first { $0.kind == .muscles })

    #expect(muscles.done == 2, "2 grupos cumpridos: costas e quadríceps")
    #expect(muscles.target == 3, "3 grupos com meta > 0")
    #expect(muscles.fraction == (1.0 + 2.0 + 2.0) / (2.0 + 2.0 + 2.0))
    #expect(muscles.referenceTopic == "topic.frequency")
}

@Test("W2 músculos: sem nenhum grupo com meta > 0, a linha some")
func weeklyGoalsMusclesAbsentWithoutAnyTarget() {
    let goals = WeeklyGoals.goals(input(
        frequency: frequencyReport([(.chest, 3, 0), (.back, 1, 0)])
    ))

    #expect(!goals.contains { $0.kind == .muscles })
}

// MARK: - W3: fraction and "cheia"

@Test("W3 a fração da marca nunca passa de 1, mesmo quando o feito ultrapassa a meta")
func weeklyGoalFractionIsClamped() {
    let goal = WeeklyGoal(kind: .aerobic, done: 400, target: 150, referenceTopic: "topic.aerobic")

    #expect(goal.fraction == 1)
    #expect(goal.isMet)
    #expect(goal.done == 400, "o número real continua aparecendo, só a marca satura")
}

@Test("W3 sem meta cumprida, a fração e isMet refletem a razão exata")
func weeklyGoalFractionBelowTarget() {
    let goal = WeeklyGoal(kind: .aerobic, done: 90, target: 150, referenceTopic: "topic.aerobic")

    #expect(goal.fraction == 90.0 / 150.0)
    #expect(!goal.isMet)
}

// MARK: - W4: sem dados

@Test("W4 sem o app Saúde conectado, aeróbico e sono aparecem sem dados")
func weeklyGoalsNoHealthAppMakesAerobicAndSleepDataless() throws {
    let goals = WeeklyGoals.goals(input(health: nil))

    let aerobic = try #require(goals.first { $0.kind == .aerobic })
    let sleep = try #require(goals.first { $0.kind == .sleep })
    #expect(!aerobic.hasData)
    #expect(aerobic.done == nil)
    #expect(!sleep.hasData)
    #expect(sleep.done == nil)
}

@Test("W4 com o Saúde conectado mas sem registro na janela, passos e sono ficam sem dados")
func weeklyGoalsHealthConnectedButEmptyWindowMakesStepsAndSleepDataless() throws {
    let goals = WeeklyGoals.goals(input(
        activeGoals: [.longevity],
        health: healthReport(aerobicMinutes: 40, stepsAverage: nil, sleepHours: nil)
    ))

    let aerobic = try #require(goals.first { $0.kind == .aerobic })
    let steps = try #require(goals.first { $0.kind == .steps })
    let sleep = try #require(goals.first { $0.kind == .sleep })
    #expect(aerobic.hasData, "o aeróbico tem número mesmo com poucos minutos")
    #expect(!steps.hasData)
    #expect(!sleep.hasData)
}

// MARK: - W5: reference topics exist in the real catalog

@Test("W5 os tópicos das Metas da semana existem em references.v1.json")
func weeklyGoalsReferenceTopicsExistInRealCatalog() throws {
    let catalog = try loadWeeklyGoalsReferenceCatalog()
    let topics = ["topic.frequency", "topic.aerobic", "topic.steps", "topic.sleep", "goal.longevity"]

    for topic in topics {
        #expect(!catalog.references(for: topic).isEmpty, "tópico sem referência: \(topic)")
    }
    for goal in ProgramGoal.allCases {
        #expect(!catalog.references(for: goal.referenceTopic).isEmpty, "\(goal.referenceTopic)")
    }
}

// MARK: - W7: steps only with Longevity or Cardio

struct StepsVisibilityCase: Sendable, CustomTestStringConvertible {
    let activeGoals: [ProgramGoal]
    let expected: Bool

    var testDescription: String {
        activeGoals.isEmpty ? "nenhum objetivo" : activeGoals.map(\.rawValue).joined(separator: "+")
    }
}

let stepsVisibilityCases: [StepsVisibilityCase] = [
    StepsVisibilityCase(activeGoals: [], expected: false),
    StepsVisibilityCase(activeGoals: [.hypertrophy], expected: false),
    StepsVisibilityCase(activeGoals: [.strength], expected: false),
    StepsVisibilityCase(activeGoals: [.combat], expected: false),
    StepsVisibilityCase(activeGoals: [.longevity], expected: true),
    StepsVisibilityCase(activeGoals: [.endurance], expected: true),
    StepsVisibilityCase(activeGoals: [.hypertrophy, .endurance], expected: true),
    StepsVisibilityCase(activeGoals: [.longevity, .strength], expected: true),
    StepsVisibilityCase(activeGoals: [.strength, .combat], expected: false),
]

@Test("W7 passos só com Longevidade ou Cardio entre os objetivos ativos", arguments: stepsVisibilityCases)
func weeklyGoalsShowsStepsOnlyWithLongevityOrCardio(_ testCase: StepsVisibilityCase) {
    #expect(WeeklyGoals.showsSteps(activeGoals: testCase.activeGoals) == testCase.expected)

    let goals = WeeklyGoals.goals(input(
        activeGoals: testCase.activeGoals,
        health: healthReport(stepsAverage: 6_500)
    ))
    #expect(goals.contains { $0.kind == .steps } == testCase.expected)
}

// MARK: - Helpers

/// Repository root derived from this file's location (five components below it), as in
/// `SeedBundleTests`/`ReferenceCatalogTests`; `URL(fileURLWithPath:)` normalizes Windows separators.
private func weeklyGoalsRepositoryRootURL() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        url.deleteLastPathComponent()
    }
    return url
}

private func loadWeeklyGoalsReferenceCatalog() throws -> ReferenceCatalog {
    let url = weeklyGoalsRepositoryRootURL()
        .appendingPathComponent("PersonalTrainer", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("Seed", isDirectory: true)
        .appendingPathComponent("references.v1.json", isDirectory: false)
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ReferenceCatalog.self, from: data)
}
