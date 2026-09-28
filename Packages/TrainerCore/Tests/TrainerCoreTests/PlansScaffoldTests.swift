import Foundation
import Testing
@testable import TrainerCore

// Andaime da onda de telas da 2.3 (docs/V23-UI-CONTRACT.md §3.1): confere a parte de `TrainerCore/Plans` que o
// arquiteto já escreveu de verdade (dia da semana, intensidade do aeróbico, demanda e ordem dos planos). O
// encaixe (`WeeklyFit`) e a tabela de consequências (`PlanCombination`) são da `plans-core`, com testes próprios.

/// Um caso da classificação da intensidade (SPEC §7.15 M3).
struct PlansScaffoldIntensityCase: Sendable, CustomTestStringConvertible {
    let slug: String
    let sets: Int
    let repMax: Int
    let expected: CardioIntensity

    var testDescription: String {
        "\(slug) \(sets) × até \(repMax) min"
    }
}

let plansScaffoldIntensityCases: [PlansScaffoldIntensityCase] = [
    PlansScaffoldIntensityCase(slug: "brisk-walk", sets: 1, repMax: 45, expected: .moderate),
    PlansScaffoldIntensityCase(slug: "run-intervals", sets: 4, repMax: 4, expected: .vigorous),
    PlansScaffoldIntensityCase(slug: "stationary-bike", sets: 1, repMax: 75, expected: .light),
    PlansScaffoldIntensityCase(slug: "jump-rope", sets: 1, repMax: 40, expected: .vigorous),
    PlansScaffoldIntensityCase(slug: "elliptical", sets: 2, repMax: 10, expected: .vigorous),
    PlansScaffoldIntensityCase(slug: "easy-run", sets: 1, repMax: 59, expected: .moderate),
]

@Test("M3 intensidade do aeróbico pelo formato da sessão", arguments: plansScaffoldIntensityCases)
func plansScaffoldCardioIntensity(_ testCase: PlansScaffoldIntensityCase) {
    let intensity = CardioIntensity.classify(slug: testCase.slug, sets: testCase.sets, repMax: testCase.repMax)
    #expect(intensity == testCase.expected)
}

@Test("M4 a semana do encaixe começa na segunda e se repete (domingo fica a 1 dia da segunda)")
func plansScaffoldWeekday() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12)))
    let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 12)))

    #expect(PlanWeekday.of(monday, calendar: calendar) == .monday)
    #expect(PlanWeekday.of(sunday, calendar: calendar) == .sunday)
    #expect(PlanWeekday.sunday.next == .monday)
    #expect(PlanWeekday.sunday.distance(to: .monday) == 1)
    #expect(PlanWeekday.monday.distance(to: .wednesday) == 2)
    #expect(PlanWeekday.monday.distance(to: .friday) == 3)
    #expect(PlanWeekday.allCases.map(\.shortName) == ["Seg", "Ter", "Qua", "Qui", "Sex", "Sáb", "Dom"])
}

@Test("M1 o plano principal é o de força; o Cardio vem por último")
func plansScaffoldActivePlanOrder() {
    let cardio = ProgramTemplate(name: "Cardio", goal: .endurance)
    let hypertrophy = ProgramTemplate(name: "Hipertrofia — Equilibrado", goal: .hypertrophy)
    let longevity = ProgramTemplate(name: "Longevidade", goal: .longevity)

    let first: [ProgramGoal] = ActivePlanOrder.sorted([cardio, hypertrophy]).map(\.effectiveGoal)
    let second: [ProgramGoal] = ActivePlanOrder.sorted([cardio, longevity]).map(\.effectiveGoal)
    #expect(first == [.hypertrophy, .endurance])
    #expect(second == [.longevity, .endurance])
    #expect(ActivePlanOrder.maxActivePlans == 2)
}

@Test("M3 demanda: dia com aeróbico é de cardio; dia de força com pernas é de pernas")
func plansScaffoldDemand() {
    let squat = ExerciseDefinition(
        slug: "barbell-back-squat",
        name: "Agachamento livre",
        primaryMuscles: [.quads, .glutes],
        equipment: .barbell,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        movementPattern: .squat
    )
    let bench = ExerciseDefinition(
        slug: "barbell-bench-press",
        name: "Supino reto com barra",
        primaryMuscles: [.chest],
        equipment: .barbell,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        movementPattern: .horizontalPush
    )
    let intervals = ExerciseDefinition(
        slug: "run-intervals",
        name: "Intervalos de corrida",
        primaryMuscles: [.quads, .glutes],
        equipment: .bodyweight,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        movementPattern: .cardio
    )
    let upper = ProgramDayTemplate(name: "Dia A — Superior", order: 0, exercises: [
        ExerciseTarget(exerciseID: bench.id, order: 0),
    ])
    let lower = ProgramDayTemplate(name: "Dia B — Inferior", order: 1, exercises: [
        ExerciseTarget(exerciseID: squat.id, order: 0),
    ])
    let cardioDay = ProgramDayTemplate(name: "Dia C — Intervalos", order: 2, exercises: [
        ExerciseTarget(exerciseID: intervals.id, order: 0, sets: 4, repMin: 3, repMax: 4),
        ExerciseTarget(exerciseID: squat.id, order: 1),
    ])
    let program = ProgramTemplate(name: "Teste", days: [cardioDay, lower, upper], goal: .hypertrophy)
    let catalog: [UUID: ExerciseDefinition] = [squat.id: squat, bench.id: bench, intervals.id: intervals]

    let demand = PlanDemand.from(program: program, exercises: catalog, sessionsPerWeek: 9)

    #expect(demand.sessions.map(\.dayName) == ["Dia A — Superior", "Dia B — Inferior", "Dia C — Intervalos"])
    #expect(demand.sessions.map(\.kind) == [.strength, .strength, .cardio])
    #expect(demand.sessions.map(\.isLowerBody) == [false, true, false])
    #expect(demand.sessions[2].cardioIntensity == .vigorous)
    #expect(demand.sessions[2].primaryMuscles.isEmpty)
    #expect(demand.sessionsPerWeek == 3)
    #expect(!demand.isCardio)
}

@Test("M4 o lugar da semana guarda o dia previsto; sem ele, os campos novos ficam vazios")
func plansScaffoldPlannedSlotDay() {
    let programID = UUID()
    let dayID = UUID()
    let bare = PlannedSlot(weekday: .monday, programID: programID, indexInWeek: 0, kind: .strength, orderInDay: 0)
    let full = PlannedSlot(
        weekday: .thursday,
        programID: programID,
        indexInWeek: 2,
        kind: .cardio,
        orderInDay: 1,
        programDayID: dayID,
        dayName: "Dia B — Intervalos 4 × 4",
        cardioIntensity: .vigorous
    )
    let schedule = WeekSchedule(slots: [full, bare])

    #expect(bare.programDayID == nil)
    #expect(bare.dayName.isEmpty)
    #expect(bare.cardioIntensity == nil)
    #expect(full.programDayID == dayID)
    #expect(schedule.slots.map(\.weekday) == [.monday, .thursday])
    #expect(schedule.restDays == [.tuesday, .wednesday, .friday, .saturday, .sunday])
}

@Test("W2 o progresso da semana de um plano guarda feitas e previstas")
func plansScaffoldPlanWeekProgress() {
    let programID = UUID()
    let progress = PlanWeekProgress(programID: programID, goal: .endurance, completed: 1, perWeek: 3)

    #expect(progress.programID == programID)
    #expect(progress.goal == .endurance)
    #expect(progress.completed == 1)
    #expect(progress.perWeek == 3)
}
