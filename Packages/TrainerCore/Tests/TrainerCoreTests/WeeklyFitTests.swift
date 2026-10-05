import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.15 M3, M4 e M5 (docs/V23-UI-CONTRACT.md §4.5): o encaixe semanal de dois planos. As semanas esperadas
// foram conferidas à mão e por uma implementação de referência independente (busca exaustiva, os mesmos
// critérios na mesma ordem).

// MARK: - Demandas de teste

/// Demandas com os mesmos grupos dos planos do seed (o Equilibrado alterna Superior e Inferior; o Cardio tem a
/// base contínua moderada, o 4 × 4 forte e o longo leve).
enum FitFixture {
    static let upper: Set<MuscleGroup> = [.chest, .back, .shoulders, .biceps, .triceps]
    static let lower: Set<MuscleGroup> = [.quads, .hamstrings, .glutes, .calves, .core]
    static let fullBody: Set<MuscleGroup> = [.back, .chest, .glutes, .quads, .shoulders]

    static let balancedID = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
    static let cardioID = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!

    static func strength(_ name: String, _ muscles: Set<MuscleGroup>) -> PlanSessionDemand {
        PlanSessionDemand(
            programDayID: UUID(),
            dayName: name,
            kind: .strength,
            primaryMuscles: muscles,
            isLowerBody: !muscles.isDisjoint(with: PlanDemand.lowerBodyGroups)
        )
    }

    static func cardio(_ name: String, _ intensity: CardioIntensity) -> PlanSessionDemand {
        PlanSessionDemand(programDayID: UUID(), dayName: name, kind: .cardio, cardioIntensity: intensity)
    }

    static func plan(_ id: String, _ goal: ProgramGoal, _ name: String, _ sessions: [PlanSessionDemand]) -> PlanDemand {
        PlanDemand(programID: UUID(uuidString: id)!, goal: goal, name: name, sessions: sessions, sessionsPerWeek: sessions.count)
    }

    static let balanced = PlanDemand(
        programID: balancedID,
        goal: .hypertrophy,
        name: "Equilibrado",
        sessions: [strength("A", upper), strength("B", lower), strength("C", upper), strength("D", lower)],
        sessionsPerWeek: 4
    )
    static let cardioPlan = PlanDemand(
        programID: cardioID,
        goal: .endurance,
        name: "Cardio",
        sessions: [cardio("A", .moderate), cardio("B", .vigorous), cardio("C", .light)],
        sessionsPerWeek: 3
    )
    static let strengthPlan = plan("A0000000-0000-0000-0000-000000000001", .strength, "Força", [
        strength("A", fullBody),
        strength("B", fullBody.union([.hamstrings])),
        strength("C", [.back, .chest, .glutes, .hamstrings, .quads]),
    ])
    static let chestA = plan("A0000000-0000-0000-0000-00000000000A", .hypertrophy, "Peito A", [strength("A", [.chest])])
    static let chestB = plan("A0000000-0000-0000-0000-00000000000B", .strength, "Peito B", [strength("A", [.chest])])
    static let legs = plan("A0000000-0000-0000-0000-0000000000C1", .strength, "Pernas", [strength("A", [.quads, .glutes])])
    static let sprints = plan("A0000000-0000-0000-0000-0000000000C2", .endurance, "Tiros", [cardio("A", .vigorous)])
    static let upperOnly = plan("A0000000-0000-0000-0000-0000000000C3", .hypertrophy, "Superior", [strength("A", upper)])
    static let easyCardio = plan("A0000000-0000-0000-0000-0000000000C4", .endurance, "Leve", [cardio("A", .light)])
    static let quadsAndHamstrings = plan("A0000000-0000-0000-0000-0000000000D1", .strength, "Quad dois", [
        strength("A", [.quads]),
        strength("B", [.hamstrings]),
    ])
    static let twoSprints = plan("A0000000-0000-0000-0000-0000000000D2", .endurance, "Tiros dois", [
        cardio("A", .vigorous),
        cardio("B", .vigorous),
    ])
    static let quadsTwice = plan("A0000000-0000-0000-0000-0000000000D3", .strength, "Quad quad", [
        strength("A", [.quads]),
        strength("B", [.quads]),
    ])
    static let twoDayHypertrophy = plan("A0000000-0000-0000-0000-0000000000E1", .hypertrophy, "Hip dois", [
        strength("A", upper),
        strength("B", lower),
    ])
    static let twoDayStrength = plan("A0000000-0000-0000-0000-0000000000E2", .strength, "For dois", [
        strength("A", fullBody),
        strength("B", fullBody),
    ])
    static let fiveDayHypertrophy = plan("A0000000-0000-0000-0000-0000000000F1", .hypertrophy, "Hip cinco", [
        strength("A", upper),
        strength("B", lower),
        strength("C", upper),
        strength("D", lower),
        strength("E", upper),
    ])

    static let mondayToSaturday: Set<PlanWeekday> = WeekPreferences.defaultAvailableDays
    static let everyDay: Set<PlanWeekday> = Set(PlanWeekday.allCases)
}

/// Um lugar da semana, com o nome do plano no lugar do id (as semanas esperadas ficam legíveis).
struct FitSlotRow: Sendable, Hashable {
    let weekday: PlanWeekday
    let plan: String
    let indexInWeek: Int
    let kind: PlanSessionKind
    let orderInDay: Int
    let dayName: String
    let intensity: CardioIntensity?

    init(
        _ weekday: PlanWeekday,
        _ plan: String,
        _ indexInWeek: Int,
        _ kind: PlanSessionKind,
        _ orderInDay: Int,
        _ dayName: String,
        _ intensity: CardioIntensity? = nil
    ) {
        self.weekday = weekday
        self.plan = plan
        self.indexInWeek = indexInWeek
        self.kind = kind
        self.orderInDay = orderInDay
        self.dayName = dayName
        self.intensity = intensity
    }
}

func fitRows(_ schedule: WeekSchedule?, _ plans: [PlanDemand]) -> [FitSlotRow] {
    let names = Dictionary(plans.map { ($0.programID, $0.name) }, uniquingKeysWith: { first, _ in first })
    return (schedule?.slots ?? []).map { slot in
        FitSlotRow(
            slot.weekday,
            names[slot.programID] ?? "?",
            slot.indexInWeek,
            slot.kind,
            slot.orderInDay,
            slot.dayName,
            slot.cardioIntensity
        )
    }
}

/// A semana do Equilibrado + Cardio de segunda a sábado com 2 por dia: 7 sessões em 6 dias, um dia com as duas.
let balancedWithCardioWeek: [FitSlotRow] = [
    FitSlotRow(.monday, "Equilibrado", 0, .strength, 0, "A"),
    FitSlotRow(.monday, "Cardio", 0, .cardio, 1, "A", .moderate),
    FitSlotRow(.tuesday, "Equilibrado", 1, .strength, 0, "B"),
    FitSlotRow(.wednesday, "Cardio", 1, .cardio, 0, "B", .vigorous),
    FitSlotRow(.thursday, "Equilibrado", 2, .strength, 0, "C"),
    FitSlotRow(.friday, "Cardio", 2, .cardio, 0, "C", .light),
    FitSlotRow(.saturday, "Equilibrado", 3, .strength, 0, "D"),
]

/// A mesma dupla nos 7 dias, sem nenhum dia com duas sessões.
let balancedWithCardioEveryDayWeek: [FitSlotRow] = [
    FitSlotRow(.monday, "Equilibrado", 0, .strength, 0, "A"),
    FitSlotRow(.tuesday, "Cardio", 0, .cardio, 0, "A", .moderate),
    FitSlotRow(.wednesday, "Equilibrado", 1, .strength, 0, "B"),
    FitSlotRow(.thursday, "Cardio", 1, .cardio, 0, "B", .vigorous),
    FitSlotRow(.friday, "Equilibrado", 2, .strength, 0, "C"),
    FitSlotRow(.saturday, "Equilibrado", 3, .strength, 0, "D"),
    FitSlotRow(.sunday, "Cardio", 2, .cardio, 0, "C", .light),
]

// MARK: - M4 em tabela

/// Um caso de M4: os planos, as preferências e a semana esperada (vazia quando não cabe).
struct WeeklyFitCase: Sendable, CustomTestStringConvertible {
    let label: String
    let plans: [PlanDemand]
    let preferences: WeekPreferences
    let fits: Bool
    let rows: [FitSlotRow]
    let notes: [FitNote]

    var testDescription: String {
        label
    }
}

let weeklyFitCases: [WeeklyFitCase] = [
    WeeklyFitCase(
        label: "Equilibrado + Cardio de segunda a sábado, com 2 por dia aceito",
        plans: [FitFixture.balanced, FitFixture.cardioPlan],
        preferences: WeekPreferences(allowsTwoSessionsPerDay: true),
        fits: true,
        rows: balancedWithCardioWeek,
        notes: [.strengthBeforeCardio(.monday)]
    ),
    WeeklyFitCase(
        label: "o mesmo sem aceitar 2 por dia não cabe (7 sessões, 6 dias)",
        plans: [FitFixture.balanced, FitFixture.cardioPlan],
        preferences: WeekPreferences(),
        fits: false,
        rows: [],
        notes: []
    ),
    WeeklyFitCase(
        label: "com os 7 dias e 2 por dia, a escolha fica com nenhum dia de duas sessões",
        plans: [FitFixture.balanced, FitFixture.cardioPlan],
        preferences: WeekPreferences(availableDays: FitFixture.everyDay, allowsTwoSessionsPerDay: true),
        fits: true,
        rows: balancedWithCardioEveryDayWeek,
        notes: [.noFullRestDay]
    ),
    WeeklyFitCase(
        label: "Equilibrado sozinho: menos pares de dias seguidos com força e, no empate, o que começa mais cedo",
        plans: [FitFixture.balanced],
        preferences: WeekPreferences(),
        fits: true,
        rows: [
            FitSlotRow(.monday, "Equilibrado", 0, .strength, 0, "A"),
            FitSlotRow(.tuesday, "Equilibrado", 1, .strength, 0, "B"),
            FitSlotRow(.thursday, "Equilibrado", 2, .strength, 0, "C"),
            FitSlotRow(.saturday, "Equilibrado", 3, .strength, 0, "D"),
        ],
        notes: []
    ),
    WeeklyFitCase(
        label: "Cardio sozinho: menos pares de dias seguidos com aeróbico",
        plans: [FitFixture.cardioPlan],
        preferences: WeekPreferences(),
        fits: true,
        rows: [
            FitSlotRow(.monday, "Cardio", 0, .cardio, 0, "A", .moderate),
            FitSlotRow(.wednesday, "Cardio", 1, .cardio, 0, "B", .vigorous),
            FitSlotRow(.friday, "Cardio", 2, .cardio, 0, "C", .light),
        ],
        notes: []
    ),
    WeeklyFitCase(
        label: "48 h: dois treinos de peito em segunda e quarta cabem",
        plans: [FitFixture.chestA, FitFixture.chestB],
        preferences: WeekPreferences(availableDays: [.monday, .wednesday]),
        fits: true,
        rows: [
            FitSlotRow(.monday, "Peito A", 0, .strength, 0, "A"),
            FitSlotRow(.wednesday, "Peito B", 0, .strength, 0, "A"),
        ],
        notes: []
    ),
    WeeklyFitCase(
        label: "48 h: domingo e segunda são dias seguidos",
        plans: [FitFixture.chestA, FitFixture.chestB],
        preferences: WeekPreferences(availableDays: [.monday, .sunday]),
        fits: false,
        rows: [],
        notes: []
    ),
    WeeklyFitCase(
        label: "véspera de pernas: o forte vai depois das pernas",
        plans: [FitFixture.sprints, FitFixture.legs],
        preferences: WeekPreferences(availableDays: [.monday, .tuesday]),
        fits: true,
        rows: [
            FitSlotRow(.monday, "Pernas", 0, .strength, 0, "A"),
            FitSlotRow(.tuesday, "Tiros", 0, .cardio, 0, "A", .vigorous),
        ],
        notes: []
    ),
    WeeklyFitCase(
        label: "véspera de pernas também do domingo para a segunda",
        plans: [FitFixture.legs, FitFixture.sprints],
        preferences: WeekPreferences(availableDays: [.monday, .sunday]),
        fits: true,
        rows: [
            FitSlotRow(.monday, "Tiros", 0, .cardio, 0, "A", .vigorous),
            FitSlotRow(.sunday, "Pernas", 0, .strength, 0, "A"),
        ],
        notes: []
    ),
    WeeklyFitCase(
        label: "no mesmo dia, a força antes do aeróbico",
        plans: [FitFixture.sprints, FitFixture.upperOnly],
        preferences: WeekPreferences(availableDays: [.tuesday], allowsTwoSessionsPerDay: true),
        fits: true,
        rows: [
            FitSlotRow(.tuesday, "Superior", 0, .strength, 0, "A"),
            FitSlotRow(.tuesday, "Tiros", 0, .cardio, 1, "A", .vigorous),
        ],
        notes: [.strengthBeforeCardio(.tuesday)]
    ),
    WeeklyFitCase(
        label: "nunca duas forças no mesmo dia, nem com 2 por dia aceito",
        plans: [FitFixture.chestA, FitFixture.legs],
        preferences: WeekPreferences(availableDays: [.monday], allowsTwoSessionsPerDay: true),
        fits: false,
        rows: [],
        notes: []
    ),
    WeeklyFitCase(
        label: "cardio leve depois da força num dia que não é de pernas",
        plans: [FitFixture.upperOnly, FitFixture.easyCardio],
        preferences: WeekPreferences(availableDays: [.monday], allowsLightCardioAfterStrength: true),
        fits: true,
        rows: [
            FitSlotRow(.monday, "Superior", 0, .strength, 0, "A"),
            FitSlotRow(.monday, "Leve", 0, .cardio, 1, "A", .light),
        ],
        notes: [.strengthBeforeCardio(.monday)]
    ),
    WeeklyFitCase(
        label: "cardio leve depois da força não vale em dia de pernas",
        plans: [FitFixture.legs, FitFixture.easyCardio],
        preferences: WeekPreferences(availableDays: [.monday], allowsLightCardioAfterStrength: true),
        fits: false,
        rows: [],
        notes: []
    ),
    WeeklyFitCase(
        label: "cardio leve depois da força não vale para o cardio forte",
        plans: [FitFixture.upperOnly, FitFixture.sprints],
        preferences: WeekPreferences(availableDays: [.monday], allowsLightCardioAfterStrength: true),
        fits: false,
        rows: [],
        notes: []
    ),
    WeeklyFitCase(
        label: "órbita: com 1 cardio por semana, o forte da semana seguinte não pode cair no domingo antes das pernas",
        plans: [FitFixture.legs, FitFixture.cardioPlan],
        preferences: WeekPreferences(availableDays: [.monday, .sunday], sessionsPerWeek: [FitFixture.cardioID: 1]),
        fits: true,
        rows: [
            FitSlotRow(.monday, "Cardio", 0, .cardio, 0, "A", .moderate),
            FitSlotRow(.sunday, "Pernas", 0, .strength, 0, "A"),
        ],
        notes: []
    ),
    WeeklyFitCase(
        label: "Equilibrado + Força não cabem de segunda a sábado",
        plans: [FitFixture.balanced, FitFixture.strengthPlan],
        preferences: WeekPreferences(),
        fits: false,
        rows: [],
        notes: []
    ),
]

@Test("M4 a semana ideal em tabela", arguments: weeklyFitCases)
func weeklyFitTable(_ testCase: WeeklyFitCase) {
    let result = WeeklyFit.fit(testCase.plans, preferences: testCase.preferences)

    #expect(result.fits == testCase.fits)
    #expect(fitRows(result.schedule, testCase.plans) == testCase.rows)
    #expect((result.schedule?.notes ?? []) == testCase.notes)
    if testCase.fits {
        #expect(result.problems.isEmpty)
        #expect(result.alternatives.isEmpty)
    } else {
        #expect(!result.problems.isEmpty)
    }
}

@Test("M4 cada lugar traz o id, o nome e a intensidade do dia previsto nesta semana")
func weeklyFitSlotsCarryThePlannedDay() throws {
    let plans = [FitFixture.balanced, FitFixture.cardioPlan]
    let result = WeeklyFit.fit(plans, preferences: WeekPreferences(allowsTwoSessionsPerDay: true))
    let schedule = try #require(result.schedule)
    let sessionsByDay = Dictionary(
        (FitFixture.balanced.sessions + FitFixture.cardioPlan.sessions).map { ($0.programDayID, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    #expect(schedule.slots.count == 7)
    for slot in schedule.slots {
        let dayID = try #require(slot.programDayID)
        let session = try #require(sessionsByDay[dayID])
        #expect(slot.dayName == session.dayName)
        #expect(slot.kind == session.kind)
        #expect(slot.cardioIntensity == session.cardioIntensity)
    }
    #expect(schedule.slots(on: .monday).map(\.kind) == [.strength, .cardio])
    #expect(schedule.restDays == [.sunday])
}

@Test("M3 M4 a fase: com o Equilibrado começando no C, a semana começa pelo C")
func weeklyFitStartsAtThePhase() throws {
    let phaseDay = FitFixture.balanced.sessions[2].programDayID
    let started = FitFixture.balanced.startingAt(programDayID: phaseDay)

    #expect(started.sessions.map(\.dayName) == ["C", "D", "A", "B"])
    #expect(started.sessionsPerWeek == 4)
    #expect(FitFixture.balanced.startingAt(programDayID: UUID()).sessions == FitFixture.balanced.sessions)
    #expect(FitFixture.balanced.startingAt(programDayID: FitFixture.balanced.sessions[0].programDayID) == FitFixture.balanced)

    let result = WeeklyFit.fit([started], preferences: WeekPreferences())
    #expect(fitRows(result.schedule, [started]) == [
        FitSlotRow(.monday, "Equilibrado", 0, .strength, 0, "C"),
        FitSlotRow(.tuesday, "Equilibrado", 1, .strength, 0, "D"),
        FitSlotRow(.thursday, "Equilibrado", 2, .strength, 0, "A"),
        FitSlotRow(.saturday, "Equilibrado", 3, .strength, 0, "B"),
    ])
    let schedule = try #require(result.schedule)
    #expect(schedule.slots.first?.programDayID == phaseDay)
}

@Test("M4 determinismo: a mesma entrada dá a mesma semana, em qualquer ordem dos planos")
func weeklyFitIsDeterministic() {
    let preferences = WeekPreferences(allowsTwoSessionsPerDay: true)
    let first = WeeklyFit.fit([FitFixture.balanced, FitFixture.cardioPlan], preferences: preferences)
    let again = WeeklyFit.fit([FitFixture.balanced, FitFixture.cardioPlan], preferences: preferences)
    let reversed = WeeklyFit.fit([FitFixture.cardioPlan, FitFixture.balanced], preferences: preferences)

    #expect(first == again)
    #expect(first == reversed)
    let notFitting = WeeklyFit.fit([FitFixture.cardioPlan, FitFixture.balanced], preferences: WeekPreferences())
    #expect(notFitting == WeeklyFit.fit([FitFixture.balanced, FitFixture.cardioPlan], preferences: WeekPreferences()))
}

@Test("M4 a saída Menos sessões nas preferências vale mais que a da demanda")
func weeklyFitUsesTheSessionsPerWeekOfThePreferences() {
    let preferences = WeekPreferences(sessionsPerWeek: [FitFixture.cardioID: 2])
    let result = WeeklyFit.fit([FitFixture.cardioPlan], preferences: preferences)

    #expect(result.schedule?.slots.count == 2)
    let zero = WeeklyFit.fit([FitFixture.cardioPlan], preferences: WeekPreferences(sessionsPerWeek: [FitFixture.cardioID: 0]))
    #expect(zero.schedule?.slots.count == 1, "o mínimo é 1")
}

// MARK: - M5

/// Um caso dos motivos de M5.
struct FitProblemCase: Sendable, CustomTestStringConvertible {
    let label: String
    let plans: [PlanDemand]
    let preferences: WeekPreferences
    let problems: [FitProblem]

    var testDescription: String {
        label
    }
}

let fitProblemCases: [FitProblemCase] = [
    FitProblemCase(
        label: "faltam lugares: 7 sessões para 6 dias",
        plans: [FitFixture.balanced, FitFixture.cardioPlan],
        preferences: WeekPreferences(),
        problems: [.notEnoughDays(needed: 7, available: 6)]
    ),
    FitProblemCase(
        label: "faltam lugares: duas forças nunca dividem o dia, então contam 1 lugar por dia mesmo com 2 por dia aceito (B9)",
        plans: [FitFixture.chestA, FitFixture.legs],
        preferences: WeekPreferences(availableDays: [.monday], allowsTwoSessionsPerDay: true),
        problems: [.notEnoughDays(needed: 2, available: 1)]
    ),
    FitProblemCase(
        label: "caberia sem os 48 h",
        plans: [FitFixture.chestA, FitFixture.chestB],
        preferences: WeekPreferences(availableDays: [.monday, .sunday]),
        problems: [.muscleRecovery]
    ),
    FitProblemCase(
        label: "caberia sem a véspera de pernas",
        plans: [FitFixture.quadsAndHamstrings, FitFixture.twoSprints],
        preferences: WeekPreferences(availableDays: [.monday, .tuesday], allowsTwoSessionsPerDay: true),
        problems: [.cardioBeforeLegs]
    ),
    FitProblemCase(
        label: "precisaria tirar as duas regras",
        plans: [FitFixture.quadsTwice, FitFixture.twoSprints],
        preferences: WeekPreferences(availableDays: [.monday, .tuesday], allowsTwoSessionsPerDay: true),
        problems: [.muscleRecovery, .cardioBeforeLegs]
    ),
    FitProblemCase(
        label: "Equilibrado + Força nos 7 dias: sobra lugar, falta descanso entre os mesmos músculos",
        plans: [FitFixture.balanced, FitFixture.strengthPlan],
        preferences: WeekPreferences(availableDays: FitFixture.everyDay, allowsTwoSessionsPerDay: true),
        problems: [.muscleRecovery]
    ),
]

@Test("M5 o motivo é o primeiro que vale", arguments: fitProblemCases)
func weeklyFitProblems(_ testCase: FitProblemCase) {
    let result = WeeklyFit.fit(testCase.plans, preferences: testCase.preferences)

    #expect(!result.fits)
    #expect(result.problems == testCase.problems)
    // Toda saída oferecida cabe, com a semana que ela mostra.
    for alternative in result.alternatives {
        let check = WeeklyFit.fit(testCase.plans, preferences: alternative.preferences)
        #expect(check.schedule == alternative.schedule)
        #expect(check.fits)
    }
}

@Test("M5 as saídas na ordem, cada uma com as preferências e a semana que resultam dela")
func weeklyFitAlternativesInOrder() throws {
    let plans = [FitFixture.balanced, FitFixture.cardioPlan]
    let result = WeeklyFit.fit(plans, preferences: WeekPreferences())

    #expect(result.alternatives.map(\.changes) == [
        [.addDays([.sunday])],
        [.allowTwoSessionsPerDay],
        [.allowLightCardioAfterStrength],
        [.fewerSessions(programID: FitFixture.cardioID, perWeek: 2)],
    ])
    try #require(result.alternatives.count == 4)
    let addSunday = result.alternatives[0]
    #expect(addSunday.preferences.availableDays == FitFixture.everyDay)
    #expect(fitRows(addSunday.schedule, plans) == balancedWithCardioEveryDayWeek)
    #expect(addSunday.schedule.notes == [.noFullRestDay])

    let twoPerDay = result.alternatives[1]
    #expect(twoPerDay.preferences.allowsTwoSessionsPerDay)
    #expect(fitRows(twoPerDay.schedule, plans) == balancedWithCardioWeek)

    let lightAfterStrength = result.alternatives[2]
    #expect(lightAfterStrength.preferences.allowsLightCardioAfterStrength)
    #expect(!lightAfterStrength.preferences.allowsTwoSessionsPerDay)
    #expect(fitRows(lightAfterStrength.schedule, plans) == balancedWithCardioWeek)

    let fewer = result.alternatives[3]
    #expect(fewer.preferences.sessionsPerWeek == [FitFixture.cardioID: 2])
    #expect(fitRows(fewer.schedule, plans) == [
        FitSlotRow(.monday, "Equilibrado", 0, .strength, 0, "A"),
        FitSlotRow(.tuesday, "Equilibrado", 1, .strength, 0, "B"),
        FitSlotRow(.wednesday, "Cardio", 0, .cardio, 0, "A", .moderate),
        FitSlotRow(.thursday, "Equilibrado", 2, .strength, 0, "C"),
        FitSlotRow(.friday, "Equilibrado", 3, .strength, 0, "D"),
        FitSlotRow(.saturday, "Cardio", 1, .cardio, 0, "B", .vigorous),
    ])
}

@Test("M5 os dias a acrescentar são o menor conjunto, e Hipertrofia + Força não ganham saída de cardio")
func weeklyFitSmallestDaysAndNoCardioExitForTwoStrengthPlans() {
    let plans = [FitFixture.twoDayHypertrophy, FitFixture.twoDayStrength]
    let result = WeeklyFit.fit(plans, preferences: WeekPreferences(availableDays: [.monday, .tuesday, .wednesday]))

    #expect(result.problems == [.notEnoughDays(needed: 4, available: 3)])
    #expect(result.alternatives.map(\.changes) == [[.addDays([.thursday, .saturday])]])
    #expect(fitRows(result.alternatives.first?.schedule, plans) == [
        FitSlotRow(.monday, "Hip dois", 0, .strength, 0, "A"),
        FitSlotRow(.tuesday, "Hip dois", 1, .strength, 0, "B"),
        FitSlotRow(.thursday, "For dois", 0, .strength, 0, "A"),
        FitSlotRow(.saturday, "For dois", 1, .strength, 0, "B"),
    ])

    // O Equilibrado e a Força do seed não cabem de jeito nenhum: sem saída.
    let seedLike = WeeklyFit.fit([FitFixture.balanced, FitFixture.strengthPlan], preferences: WeekPreferences())
    #expect(seedLike.problems == [.notEnoughDays(needed: 7, available: 6)])
    #expect(seedLike.alternatives.isEmpty)
}

@Test("M5 saída que já está nas preferências não aparece")
func weeklyFitSkipsExitsAlreadyChosen() {
    let legsAndLight = WeeklyFit.fit(
        [FitFixture.legs, FitFixture.easyCardio],
        preferences: WeekPreferences(availableDays: [.monday], allowsLightCardioAfterStrength: true)
    )
    #expect(legsAndLight.alternatives.map(\.changes) == [[.addDays([.tuesday])], [.allowTwoSessionsPerDay]])

    let twoStrength = WeeklyFit.fit(
        [FitFixture.chestA, FitFixture.legs],
        preferences: WeekPreferences(availableDays: [.monday], allowsTwoSessionsPerDay: true)
    )
    #expect(twoStrength.alternatives.map(\.changes) == [[.addDays([.tuesday])]])

    let onlyEve = WeeklyFit.fit(
        [FitFixture.quadsAndHamstrings, FitFixture.twoSprints],
        preferences: WeekPreferences(availableDays: [.monday, .tuesday], allowsTwoSessionsPerDay: true)
    )
    let sprintsID = FitFixture.twoSprints.programID
    #expect(onlyEve.alternatives.map(\.changes) == [
        [.addDays([.wednesday])],
        [.fewerSessions(programID: sprintsID, perWeek: 1)],
    ])
}

@Test("M5 quando nenhuma saída sozinha faz caber, aparecem os pares, na ordem 1+2, 1+3, 1+4")
func weeklyFitPairsWhenNoSingleExitFits() {
    let plans = [FitFixture.fiveDayHypertrophy, FitFixture.cardioPlan]
    let result = WeeklyFit.fit(plans, preferences: WeekPreferences(availableDays: [.monday, .tuesday, .wednesday]))

    #expect(result.problems == [.notEnoughDays(needed: 8, available: 3)])
    #expect(result.alternatives.map(\.changes) == [
        [.addDays([.thursday, .friday]), .allowTwoSessionsPerDay],
        [.addDays([.thursday, .friday, .saturday]), .allowLightCardioAfterStrength],
        [.addDays([.thursday, .friday, .saturday, .sunday]), .fewerSessions(programID: FitFixture.cardioID, perWeek: 2)],
    ])
    for alternative in result.alternatives {
        #expect(WeeklyFit.fit(plans, preferences: alternative.preferences).schedule == alternative.schedule)
    }
}

@Test("M5 dois planos de força contam 1 por dia")
func weeklyFitTwoStrengthPlansCountOnePlacePerDay() {
    // B9 da 2.3: com dois planos de força, o "2 por dia" não abre lugar, porque duas forças nunca dividem o dia.
    let twoStrength = WeeklyFit.fit(
        [FitFixture.twoDayHypertrophy, FitFixture.twoDayStrength],
        preferences: WeekPreferences(availableDays: [.monday, .tuesday, .wednesday], allowsTwoSessionsPerDay: true)
    )
    #expect(twoStrength.problems == [.notEnoughDays(needed: 4, available: 3)])

    let oneDay = WeeklyFit.fit(
        [FitFixture.chestA, FitFixture.legs],
        preferences: WeekPreferences(availableDays: [.monday], allowsTwoSessionsPerDay: true)
    )
    #expect(oneDay.problems == [.notEnoughDays(needed: 2, available: 1)])

    // Força + aeróbico: o 2 por dia dobra os lugares.
    let mixed = WeeklyFit.fit(
        [FitFixture.balanced, FitFixture.cardioPlan],
        preferences: WeekPreferences(availableDays: [.monday, .tuesday, .wednesday], allowsTwoSessionsPerDay: true)
    )
    #expect(mixed.problems == [.notEnoughDays(needed: 7, available: 6)])

    // Sem o 2 por dia, 1 lugar por dia, como antes.
    let mixedOnePerDay = WeeklyFit.fit(
        [FitFixture.balanced, FitFixture.cardioPlan],
        preferences: WeekPreferences(availableDays: [.monday, .tuesday, .wednesday])
    )
    #expect(mixedOnePerDay.problems == [.notEnoughDays(needed: 7, available: 3)])
}

// MARK: - X4 atividades fixas fora do app

/// Fixas de teste, montadas como o app monta (`OutsideActivities.fixedDemands`).
enum FixedFitFixture {
    static func demand(
        _ suffix: String,
        _ kind: OutsideActivityKind,
        _ weekday: PlanWeekday,
        _ intensity: CardioIntensity? = nil,
        minute: Int = 19 * 60
    ) -> FixedActivityDemand {
        let activity = FixedOutsideActivity(
            id: UUID(uuidString: "F1000000-0000-0000-0000-\(suffix)")!,
            kind: kind,
            weekday: weekday,
            startMinuteOfDay: minute,
            minutes: kind.defaultMinutes,
            intensity: intensity ?? kind.defaultIntensity
        )
        return OutsideActivities.fixedDemands([activity])[0]
    }

    static let crossMonday = demand("000000000001", .cross, .monday)
    static let crossTuesday = demand("000000000002", .cross, .tuesday)
    static let crossThursday = demand("000000000003", .cross, .thursday)
    static let crossSunday = demand("000000000004", .cross, .sunday)
    static let spinningMonday = demand("000000000011", .spinning, .monday)
    static let spinningTuesday = demand("000000000012", .spinning, .tuesday)
    static let spinningWednesday = demand("000000000013", .spinning, .wednesday)
    static let spinningSunday = demand("000000000014", .spinning, .sunday)
    static let fightTuesday = demand("000000000021", .fightClass, .tuesday)
    static let pilatesTuesday = demand("000000000031", .pilates, .tuesday)
    static let pilatesSunday = demand("000000000032", .pilates, .sunday)
    static let yogaSunday = demand("000000000033", .yoga, .sunday, minute: 8 * 60)
}

/// Um caso de X4: os planos, as preferências, as fixas e a semana esperada (ou os motivos, quando não cabe).
struct FixedFitCase: Sendable, CustomTestStringConvertible {
    let label: String
    let plans: [PlanDemand]
    let preferences: WeekPreferences
    let fixed: [FixedActivityDemand]
    let rows: [FitSlotRow]
    let notes: [FitNote]
    /// Vazio quando cabe.
    let problems: [FitProblem]

    var testDescription: String {
        label
    }
}

let fixedFitCases: [FixedFitCase] = [
    FixedFitCase(
        label: "cross fixo na terça: a força de plano com grupo em comum não fica na segunda, na terça nem na quarta",
        plans: [FitFixture.upperOnly],
        preferences: WeekPreferences(availableDays: [.monday, .tuesday, .wednesday, .thursday]),
        fixed: [FixedFitFixture.crossTuesday],
        rows: [FitSlotRow(.thursday, "Superior", 0, .strength, 0, "A")],
        notes: [],
        problems: []
    ),
    FixedFitCase(
        label: "spinning forte fixo na segunda impede pernas na terça",
        plans: [FitFixture.legs],
        preferences: WeekPreferences(availableDays: [.tuesday, .wednesday]),
        fixed: [FixedFitFixture.spinningMonday],
        rows: [FitSlotRow(.wednesday, "Pernas", 0, .strength, 0, "A")],
        notes: [],
        problems: []
    ),
    FixedFitCase(
        label: "só a terça livre: o spinning forte da segunda deixa as pernas sem lugar pela véspera",
        plans: [FitFixture.legs],
        preferences: WeekPreferences(availableDays: [.tuesday]),
        fixed: [FixedFitFixture.spinningMonday],
        rows: [],
        notes: [],
        problems: [.cardioBeforeLegs]
    ),
    FixedFitCase(
        label: "a véspera vale do domingo para a segunda",
        plans: [FitFixture.legs],
        preferences: WeekPreferences(availableDays: [.monday]),
        fixed: [FixedFitFixture.spinningSunday],
        rows: [],
        notes: [],
        problems: [.cardioBeforeLegs]
    ),
    FixedFitCase(
        label: "pilates fixo não impede nada, mas tira o descanso completo",
        plans: [FitFixture.balanced, FitFixture.cardioPlan],
        preferences: WeekPreferences(allowsTwoSessionsPerDay: true),
        fixed: [FixedFitFixture.pilatesTuesday, FixedFitFixture.pilatesSunday],
        rows: balancedWithCardioWeek,
        notes: [.noFullRestDay, .strengthBeforeCardio(.monday)],
        problems: []
    ),
    FixedFitCase(
        label: "duas fixas que se chocam não invalidam a semana",
        plans: [FitFixture.easyCardio],
        preferences: WeekPreferences(availableDays: FitFixture.everyDay),
        fixed: [
            FixedFitFixture.crossMonday, FixedFitFixture.crossTuesday,
            FixedFitFixture.spinningWednesday, FixedFitFixture.crossThursday,
        ],
        rows: [FitSlotRow(.friday, "Leve", 0, .cardio, 0, "A", .light)],
        notes: [],
        problems: []
    ),
    FixedFitCase(
        label: "força de plano com aula de luta fixa no mesmo dia: sem as chaves, não cabe",
        plans: [FitFixture.upperOnly],
        preferences: WeekPreferences(availableDays: [.tuesday]),
        fixed: [FixedFitFixture.fightTuesday],
        rows: [],
        notes: [],
        problems: [.notEnoughDays(needed: 1, available: 1)]
    ),
    FixedFitCase(
        label: "força de plano com aula de luta fixa: com Cardio leve depois da força, cabe",
        plans: [FitFixture.upperOnly],
        preferences: WeekPreferences(availableDays: [.tuesday], allowsLightCardioAfterStrength: true),
        fixed: [FixedFitFixture.fightTuesday],
        rows: [FitSlotRow(.tuesday, "Superior", 0, .strength, 0, "A")],
        notes: [.strengthBeforeCardio(.tuesday)],
        problems: []
    ),
    FixedFitCase(
        label: "força de plano com aula de luta fixa: com 2 por dia, cabe",
        plans: [FitFixture.upperOnly],
        preferences: WeekPreferences(availableDays: [.tuesday], allowsTwoSessionsPerDay: true),
        fixed: [FixedFitFixture.fightTuesday],
        rows: [FitSlotRow(.tuesday, "Superior", 0, .strength, 0, "A")],
        notes: [.strengthBeforeCardio(.tuesday)],
        problems: []
    ),
    FixedFitCase(
        label: "Cardio leve depois da força não vale com spinning forte fixo no dia",
        plans: [FitFixture.upperOnly],
        preferences: WeekPreferences(availableDays: [.tuesday], allowsLightCardioAfterStrength: true),
        fixed: [FixedFitFixture.spinningTuesday],
        rows: [],
        notes: [],
        problems: [.notEnoughDays(needed: 1, available: 1)]
    ),
    FixedFitCase(
        label: "aeróbico de plano com cross fixo no mesmo dia: o cross é de pernas, então Cardio leve depois da força não basta",
        plans: [FitFixture.easyCardio],
        preferences: WeekPreferences(availableDays: [.tuesday], allowsLightCardioAfterStrength: true),
        fixed: [FixedFitFixture.crossTuesday],
        rows: [],
        notes: [],
        problems: [.notEnoughDays(needed: 1, available: 1)]
    ),
    FixedFitCase(
        label: "aeróbico de plano com cross fixo no mesmo dia: com 2 por dia, cabe",
        plans: [FitFixture.easyCardio],
        preferences: WeekPreferences(availableDays: [.tuesday], allowsTwoSessionsPerDay: true),
        fixed: [FixedFitFixture.crossTuesday],
        rows: [FitSlotRow(.tuesday, "Leve", 0, .cardio, 0, "A", .light)],
        notes: [.strengthBeforeCardio(.tuesday)],
        problems: []
    ),
]

@Test("X4 o encaixe com atividades fixas em tabela", arguments: fixedFitCases)
func weeklyFitWithFixedActivities(_ testCase: FixedFitCase) {
    let result = WeeklyFit.fit(testCase.plans, preferences: testCase.preferences, fixed: testCase.fixed)

    #expect(result.fits == testCase.problems.isEmpty)
    #expect(fitRows(result.schedule, testCase.plans) == testCase.rows)
    #expect((result.schedule?.notes ?? []) == testCase.notes)
    #expect(result.problems == testCase.problems)
    if let schedule = result.schedule {
        #expect(schedule.fixed == testCase.fixed)
        #expect(schedule.slots.allSatisfy { slot in testCase.plans.contains { $0.programID == slot.programID } })
    }
    // Toda saída oferecida cabe com as mesmas fixas, com a semana que ela mostra.
    for alternative in result.alternatives {
        let check = WeeklyFit.fit(testCase.plans, preferences: alternative.preferences, fixed: testCase.fixed)
        #expect(check.fits)
        #expect(check.schedule == alternative.schedule)
    }
}

@Test("X4 sem fixas, as mesmas semanas de antes")
func weeklyFitWithoutFixedIsUnchanged() {
    let crossFree = WeeklyFit.fit(
        [FitFixture.upperOnly],
        preferences: WeekPreferences(availableDays: [.monday, .tuesday, .wednesday, .thursday])
    )
    #expect(fitRows(crossFree.schedule, [FitFixture.upperOnly]) == [FitSlotRow(.monday, "Superior", 0, .strength, 0, "A")])
    #expect(crossFree.schedule?.fixed.isEmpty == true)

    let plans = [FitFixture.balanced, FitFixture.cardioPlan]
    let preferences = WeekPreferences(allowsTwoSessionsPerDay: true)
    #expect(WeeklyFit.fit(plans, preferences: preferences, fixed: []) == WeeklyFit.fit(plans, preferences: preferences))
}

@Test("X4 WeekSchedule.fixed traz as fixas na ordem de fixedDemands, e os lugares continuam só de planos")
func weeklyFitScheduleCarriesTheFixed() throws {
    let plans = [FitFixture.balanced, FitFixture.cardioPlan]
    let pilates = FixedOutsideActivity(
        id: UUID(uuidString: "F2000000-0000-0000-0000-000000000001")!,
        kind: .pilates, weekday: .tuesday, startMinuteOfDay: 19 * 60, minutes: 50, intensity: .light
    )
    let yoga = FixedOutsideActivity(
        id: UUID(uuidString: "F2000000-0000-0000-0000-000000000002")!,
        kind: .yoga, weekday: .sunday, startMinuteOfDay: 8 * 60, minutes: 50, intensity: .light
    )
    let demands = OutsideActivities.fixedDemands([yoga, pilates])
    #expect(demands.map(\.id) == [pilates.id, yoga.id])

    let result = WeeklyFit.fit(plans, preferences: WeekPreferences(allowsTwoSessionsPerDay: true), fixed: demands)
    let schedule = try #require(result.schedule)

    #expect(schedule.fixed == demands)
    #expect(schedule.fixed(on: .tuesday).map(\.name) == ["Pilates"])
    #expect(schedule.fixed(on: .sunday).map(\.name) == ["Ioga ou alongamento"])
    #expect(schedule.fixed(on: .monday).isEmpty)
    #expect(schedule.slots.count == 7)
    #expect(fitRows(schedule, plans) == balancedWithCardioWeek)
    #expect(schedule.restDays == [.sunday], "os dias de descanso contam só as sessões de plano")
    #expect(schedule.notes == [.noFullRestDay, .strengthBeforeCardio(.monday)])
}

@Test("X4 determinismo: a mesma entrada com fixas dá a mesma semana, em qualquer ordem dos planos e das fixas")
func weeklyFitWithFixedIsDeterministic() {
    let fixed = [FixedFitFixture.pilatesTuesday, FixedFitFixture.spinningWednesday, FixedFitFixture.yogaSunday]
    let shuffled = [FixedFitFixture.yogaSunday, FixedFitFixture.pilatesTuesday, FixedFitFixture.spinningWednesday]
    let preferences = WeekPreferences(allowsTwoSessionsPerDay: true)

    let first = WeeklyFit.fit([FitFixture.balanced, FitFixture.cardioPlan], preferences: preferences, fixed: fixed)
    let again = WeeklyFit.fit([FitFixture.balanced, FitFixture.cardioPlan], preferences: preferences, fixed: fixed)
    let reversed = WeeklyFit.fit([FitFixture.cardioPlan, FitFixture.balanced], preferences: preferences, fixed: shuffled)

    #expect(first.fits)
    #expect(first == again)
    #expect(first == reversed)
    #expect(first.schedule?.fixed == fixed, "por dia da semana")

    let notFitting = WeeklyFit.fit([FitFixture.cardioPlan, FitFixture.balanced], preferences: WeekPreferences(), fixed: shuffled)
    #expect(notFitting == WeeklyFit.fit([FitFixture.balanced, FitFixture.cardioPlan], preferences: WeekPreferences(), fixed: fixed))
}

@Test("X4 as saídas de M5 são calculadas com as fixas")
func weeklyFitExitsWithFixedActivities() throws {
    let plans = [FitFixture.balanced, FitFixture.cardioPlan]
    let fixed = [FixedFitFixture.crossSunday]

    let result = WeeklyFit.fit(plans, preferences: WeekPreferences(), fixed: fixed)

    // Sem o cross, as quatro saídas valem (`weeklyFitAlternativesInOrder`). Com ele no domingo, treinar
    // também no domingo não resolve, e a força fica longe do sábado e da segunda (48 h).
    #expect(WeeklyFit.fit(plans, preferences: WeekPreferences()).alternatives.count == 4)
    #expect(result.problems == [.notEnoughDays(needed: 7, available: 6)])
    #expect(result.alternatives.map(\.changes) == [
        [.allowTwoSessionsPerDay],
        [.fewerSessions(programID: FitFixture.cardioID, perWeek: 1)],
    ])
    try #require(result.alternatives.count == 2)
    let twoPerDay = result.alternatives[0]
    #expect(fitRows(twoPerDay.schedule, plans) == [
        FitSlotRow(.monday, "Cardio", 0, .cardio, 0, "A", .moderate),
        FitSlotRow(.tuesday, "Equilibrado", 0, .strength, 0, "A"),
        FitSlotRow(.wednesday, "Equilibrado", 1, .strength, 0, "B"),
        FitSlotRow(.wednesday, "Cardio", 1, .cardio, 1, "B", .vigorous),
        FitSlotRow(.thursday, "Equilibrado", 2, .strength, 0, "C"),
        FitSlotRow(.friday, "Equilibrado", 3, .strength, 0, "D"),
        FitSlotRow(.saturday, "Cardio", 2, .cardio, 0, "C", .light),
    ])
    #expect(twoPerDay.schedule.notes == [.noFullRestDay, .strengthBeforeCardio(.wednesday)])
    for alternative in result.alternatives {
        #expect(alternative.schedule.fixed == fixed)
        #expect(WeeklyFit.fit(plans, preferences: alternative.preferences, fixed: fixed).schedule == alternative.schedule)
    }
}

// MARK: - Planos do seed

@Test("M3 M4 o Equilibrado e o Cardio do seed viram a demanda esperada e cabem com 2 por dia")
func weeklyFitWithTheSeedPrograms() throws {
    let bundle = try weeklyFitSeedBundle()
    let catalog = Dictionary(bundle.catalog.exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let balancedProgram = try #require(bundle.programs.programs.first { $0.id == UUID(uuidString: "9FE0818F-1417-4953-B357-43D757054FCC") })
    let cardioProgram = try #require(bundle.programs.programs.first { $0.id == UUID(uuidString: "09AB286E-D2B2-49C6-8C9F-400D118D8D03") })

    let balanced = PlanDemand.from(program: balancedProgram, exercises: catalog)
    let cardio = PlanDemand.from(program: cardioProgram, exercises: catalog)

    #expect(balanced.sessions.map(\.kind) == [.strength, .strength, .strength, .strength])
    #expect(balanced.sessions.map(\.isLowerBody) == [false, true, false, true])
    #expect(cardio.isCardio)
    #expect(cardio.sessions.map(\.cardioIntensity) == [.moderate, .vigorous, .light])
    #expect(cardio.sessions.map(\.dayName) == ["Dia A — Base contínua", "Dia B — Intervalos 4 × 4", "Dia C — Longo e leve"])

    let result = WeeklyFit.fit([cardio, balanced], preferences: WeekPreferences(allowsTwoSessionsPerDay: true))
    let schedule = try #require(result.schedule)
    #expect(schedule.slots.map(\.weekday) == [.monday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
    #expect(schedule.slots.map(\.dayName) == [
        "Dia A — Superior", "Dia A — Base contínua", "Dia B — Inferior", "Dia B — Intervalos 4 × 4",
        "Dia C — Superior", "Dia C — Longo e leve", "Dia D — Inferior",
    ])
    #expect(schedule.notes == [.strengthBeforeCardio(.monday)])
}

private func weeklyFitSeedBundle() throws -> SeedBundle {
    var root = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        root.deleteLastPathComponent()
    }
    let seed = root
        .appendingPathComponent("PersonalTrainer", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("Seed", isDirectory: true)
    return try SeedBundle.decode(
        catalogData: Data(contentsOf: seed.appendingPathComponent("exercises.v2.json", isDirectory: false)),
        programData: Data(contentsOf: seed.appendingPathComponent("programs.v2.json", isDirectory: false))
    )
}
