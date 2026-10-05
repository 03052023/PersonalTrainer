import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.17 X1–X8 (RF-53; docs/V24-CONTRACT.md §4.1): as atividades fora do app no núcleo. 2026-10-05 é uma
// segunda-feira; a semana de §7.4 vai de segunda 00:00 à segunda seguinte. O encaixe com fixas (X4) está em
// WeeklyFitTests, e as Metas (W2.3, W2.6, W4) em WeeklyGoalsTests.

private let outsideUTC: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func outsideDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    outsideUTC.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private let outsideMonday = outsideDate(2026, 10, 5)
private let outsideWeek = DateInterval(start: outsideMonday, duration: 7 * 86_400)
private let outsideLegs: Set<MuscleGroup> = [.quads, .hamstrings, .glutes, .calves]

private func outsideID(_ suffix: String) -> UUID {
    UUID(uuidString: "0A000000-0000-0000-0000-\(suffix)")!
}

private func outsideEntry(
    _ kind: OutsideActivityKind,
    _ start: Date,
    minutes: Int,
    _ intensity: CardioIntensity,
    id: UUID = UUID(),
    fixedID: UUID? = nil
) -> OutsideActivityEntry {
    OutsideActivityEntry(id: id, kind: kind, start: start, minutes: minutes, intensity: intensity, fixedActivityID: fixedID)
}

// MARK: - X1

/// Uma linha da tabela X1.
struct OutsideKindRow: Sendable, CustomTestStringConvertible {
    let kind: OutsideActivityKind
    let rawValue: String
    let name: String
    let intensity: CardioIntensity
    let minutes: Int
    let role: OutsideActivityRole
    let muscles: Set<MuscleGroup>
    let aerobic: Bool

    var testDescription: String {
        rawValue
    }
}

private let allMuscleGroups: Set<MuscleGroup> = Set(MuscleGroup.allCases)

let outsideKindRows: [OutsideKindRow] = [
    OutsideKindRow(kind: .pilates, rawValue: "pilates", name: "Pilates", intensity: .light, minutes: 50, role: .light, muscles: [], aerobic: false),
    OutsideKindRow(kind: .yoga, rawValue: "yoga", name: "Ioga ou alongamento", intensity: .light, minutes: 50, role: .light, muscles: [], aerobic: false),
    OutsideKindRow(kind: .balance, rawValue: "balance", name: "Equilíbrio", intensity: .light, minutes: 10, role: .light, muscles: [], aerobic: false),
    OutsideKindRow(kind: .mobility, rawValue: "mobility", name: "Mobilidade", intensity: .light, minutes: 10, role: .light, muscles: [], aerobic: false),
    OutsideKindRow(kind: .cross, rawValue: "cross", name: "Cross ou funcional", intensity: .vigorous, minutes: 60, role: .strength, muscles: Set(MuscleGroup.allCases), aerobic: false),
    OutsideKindRow(kind: .fightClass, rawValue: "fightClass", name: "Aula de luta", intensity: .moderate, minutes: 60, role: .cardio, muscles: [], aerobic: true),
    OutsideKindRow(kind: .spinning, rawValue: "spinning", name: "Spinning ou bicicleta", intensity: .vigorous, minutes: 45, role: .cardio, muscles: [], aerobic: true),
    OutsideKindRow(kind: .teamSport, rawValue: "teamSport", name: "Futebol ou esporte com bola", intensity: .vigorous, minutes: 60, role: .cardio, muscles: [], aerobic: true),
    OutsideKindRow(kind: .swimming, rawValue: "swimming", name: "Natação", intensity: .moderate, minutes: 45, role: .cardio, muscles: [], aerobic: true),
    OutsideKindRow(kind: .dance, rawValue: "dance", name: "Dança", intensity: .moderate, minutes: 60, role: .cardio, muscles: [], aerobic: true),
    OutsideKindRow(kind: .walkRun, rawValue: "walkRun", name: "Caminhada ou corrida", intensity: .moderate, minutes: 30, role: .cardio, muscles: [], aerobic: true),
    OutsideKindRow(kind: .other, rawValue: "other", name: "Outra atividade", intensity: .moderate, minutes: 30, role: .cardio, muscles: [], aerobic: true),
]

@Test("X1 a tabela dos 12 tipos", arguments: outsideKindRows)
func outsideKindTable(_ row: OutsideKindRow) {
    #expect(row.kind.rawValue == row.rawValue)
    #expect(OutsideActivityKind(rawValue: row.rawValue) == row.kind)
    #expect(row.kind.displayName == row.name)
    #expect(row.kind.defaultIntensity == row.intensity)
    #expect(row.kind.defaultMinutes == row.minutes)
    #expect(row.kind.role == row.role)
    #expect(row.kind.primaryMuscles == row.muscles)
    #expect(row.kind.countsAsAerobic == row.aerobic)
    #expect(OutsideActivities.isValidMinutes(row.kind.defaultMinutes), "a duração sugerida cabe em X1")
}

@Test("X1 são 12 tipos, na ordem da tabela, e o cross trabalha os 10 grupos")
func outsideKindsAreTheTwelveOfTheTable() {
    #expect(OutsideActivityKind.allCases == outsideKindRows.map(\.kind))
    #expect(OutsideActivityKind.allCases.count == 12)
    #expect(OutsideActivityKind.cross.primaryMuscles == allMuscleGroups)
    #expect(allMuscleGroups.count == 10)
}

/// Uma duração e se ela é aceita (X1: 5 a 300 min).
struct OutsideMinutesCase: Sendable, CustomTestStringConvertible {
    let minutes: Int
    let valid: Bool

    var testDescription: String {
        "\(minutes) min"
    }
}

let outsideMinutesCases: [OutsideMinutesCase] = [
    OutsideMinutesCase(minutes: -5, valid: false),
    OutsideMinutesCase(minutes: 0, valid: false),
    OutsideMinutesCase(minutes: 4, valid: false),
    OutsideMinutesCase(minutes: 5, valid: true),
    OutsideMinutesCase(minutes: 50, valid: true),
    OutsideMinutesCase(minutes: 300, valid: true),
    OutsideMinutesCase(minutes: 301, valid: false),
]

@Test("X1 duração aceita", arguments: outsideMinutesCases)
func outsideMinutesRange(_ testCase: OutsideMinutesCase) {
    #expect(OutsideActivities.isValidMinutes(testCase.minutes) == testCase.valid)
}

// MARK: - X2

@Test("X2 o Feito grava o registro com a hora da fixa")
func outsideFixedDoneLogsAtTheFixedTime() throws {
    let fixedID = outsideID("000000000001")
    let entryID = outsideID("000000000002")
    let pilates = FixedOutsideActivity(
        id: fixedID, kind: .pilates, weekday: .tuesday, startMinuteOfDay: 19 * 60, minutes: 50, intensity: .light
    )

    let entry = OutsideActivities.entry(loggingFixed: pilates, on: outsideDate(2026, 10, 6, 8, 30), calendar: outsideUTC, id: entryID)

    #expect(entry.id == entryID)
    #expect(entry.kind == .pilates)
    #expect(entry.start == outsideDate(2026, 10, 6, 19))
    #expect(entry.end == outsideDate(2026, 10, 6, 19, 50))
    #expect(entry.minutes == 50)
    #expect(entry.intensity == .light)
    #expect(entry.fixedActivityID == fixedID)

    // O dia e a hora são os do calendário da pessoa: 19h em São Paulo (UTC−3) são 22h em UTC.
    var saoPaulo = Calendar(identifier: .gregorian)
    saoPaulo.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
    let local = OutsideActivities.entry(loggingFixed: pilates, on: outsideDate(2026, 10, 6, 12), calendar: saoPaulo)
    #expect(local.start == outsideDate(2026, 10, 6, 22))

    // Uma hora fora de 0…1439 fica no último minuto do dia.
    let broken = FixedOutsideActivity(kind: .yoga, weekday: .tuesday, startMinuteOfDay: 5_000, minutes: 30, intensity: .light)
    let clamped = OutsideActivities.entry(loggingFixed: broken, on: outsideDate(2026, 10, 6, 8), calendar: outsideUTC)
    #expect(clamped.start == outsideDate(2026, 10, 6, 23, 59))
}

@Test("X2 uma vez por dia")
func outsideFixedDoneOncePerDay() {
    let fixedID = outsideID("000000000011")
    let pilates = FixedOutsideActivity(
        id: fixedID, kind: .pilates, weekday: .tuesday, startMinuteOfDay: 19 * 60, minutes: 50, intensity: .light
    )
    let tuesday = outsideDate(2026, 10, 6, 8)
    let done = OutsideActivities.entry(loggingFixed: pilates, on: tuesday, calendar: outsideUTC, id: outsideID("000000000012"))

    #expect(!OutsideActivities.isLogged(pilates, on: tuesday, entries: [], calendar: outsideUTC))
    #expect(OutsideActivities.isLogged(pilates, on: tuesday, entries: [done], calendar: outsideUTC))
    #expect(OutsideActivities.isLogged(pilates, on: outsideDate(2026, 10, 6, 23, 30), entries: [done], calendar: outsideUTC))
    #expect(
        !OutsideActivities.isLogged(pilates, on: outsideDate(2026, 10, 13, 8), entries: [done], calendar: outsideUTC),
        "na terça seguinte, a fixa espera outro Feito"
    )

    // O Feito de outra fixa, ou um registro avulso igual, não marca esta.
    let other = FixedOutsideActivity(
        id: outsideID("000000000013"), kind: .pilates, weekday: .tuesday, startMinuteOfDay: 19 * 60, minutes: 50, intensity: .light
    )
    #expect(!OutsideActivities.isLogged(other, on: tuesday, entries: [done], calendar: outsideUTC))
    let loose = outsideEntry(.pilates, outsideDate(2026, 10, 6, 19), minutes: 50, .light)
    #expect(!OutsideActivities.isLogged(pilates, on: tuesday, entries: [loose], calendar: outsideUTC))

    // Apagar o registro do dia desfaz o Feito.
    let remaining = [done, loose].filter { $0.id != done.id }
    #expect(!OutsideActivities.isLogged(pilates, on: tuesday, entries: remaining, calendar: outsideUTC))
}

@Test("X2 fixas do dia em ordem")
func outsideFixedOfTheDayInOrder() {
    let football = FixedOutsideActivity(
        id: outsideID("000000000021"), kind: .teamSport, weekday: .tuesday, startMinuteOfDay: 21 * 60, minutes: 60, intensity: .vigorous
    )
    let pilatesB = FixedOutsideActivity(
        id: outsideID("000000000023"), kind: .pilates, weekday: .tuesday, startMinuteOfDay: 19 * 60, minutes: 50, intensity: .light
    )
    let pilatesA = FixedOutsideActivity(
        id: outsideID("000000000022"), kind: .pilates, weekday: .tuesday, startMinuteOfDay: 19 * 60, minutes: 50, intensity: .light
    )
    let yoga = FixedOutsideActivity(
        id: outsideID("000000000024"), kind: .yoga, weekday: .wednesday, startMinuteOfDay: 7 * 60, minutes: 50, intensity: .light
    )
    let all = [football, yoga, pilatesB, pilatesA]

    #expect(OutsideActivities.fixed(all, on: .tuesday).map(\.id) == [pilatesA.id, pilatesB.id, football.id])
    #expect(OutsideActivities.fixed(all, on: .wednesday).map(\.id) == [yoga.id])
    #expect(OutsideActivities.fixed(all, on: .monday).isEmpty)
    #expect(OutsideActivities.maxFixed == 10)
}

@Test("X2 os registros da semana vão de segunda 00:00 à segunda seguinte, pelo início")
func outsideEntriesOfTheWeek() {
    let sundayBefore = outsideEntry(.walkRun, outsideDate(2026, 10, 4, 23), minutes: 30, .moderate)
    let mondayMidnight = outsideEntry(.swimming, outsideMonday, minutes: 45, .moderate)
    let wednesday = outsideEntry(.dance, outsideDate(2026, 10, 7, 18), minutes: 60, .moderate)
    let sundayLate = outsideEntry(.yoga, outsideDate(2026, 10, 11, 23, 30), minutes: 50, .light)
    let nextMonday = outsideEntry(.teamSport, outsideDate(2026, 10, 12), minutes: 60, .vigorous)

    let week = OutsideActivities.entries([nextMonday, wednesday, sundayLate, sundayBefore, mondayMidnight], in: outsideWeek)

    #expect(week.map(\.id) == [mondayMidnight.id, wednesday.id, sundayLate.id])
}

// MARK: - X3

@Test("X3 aeróbico conta moderado 1 e forte 2, leve não")
func outsideAerobicMinutesWeighting() {
    let entries = [
        outsideEntry(.walkRun, outsideDate(2026, 10, 6, 7), minutes: 30, .moderate),        // 30
        outsideEntry(.spinning, outsideDate(2026, 10, 7, 18), minutes: 45, .vigorous),      // 2 × 45 = 90
        outsideEntry(.dance, outsideDate(2026, 10, 8, 20), minutes: 60, .light),            // leve: 0
        outsideEntry(.swimming, outsideMonday, minutes: 45, .moderate),                     // segunda 00:00: 45
        outsideEntry(.fightClass, outsideDate(2026, 10, 4, 23), minutes: 60, .moderate),    // semana anterior
        outsideEntry(.teamSport, outsideDate(2026, 10, 12), minutes: 60, .vigorous),        // semana seguinte
    ]

    #expect(OutsideActivities.aerobicMinutes(entries: entries, week: outsideWeek) == 165)
    #expect(OutsideActivities.countsTowardAerobic(entries[0]))
    #expect(OutsideActivities.countsTowardAerobic(entries[1]))
    #expect(!OutsideActivities.countsTowardAerobic(entries[2]))

    // Uma duração fora de X1 (arquivo antigo ou editado) conta até o teto de 300 min.
    let tooLong = outsideEntry(.walkRun, outsideDate(2026, 10, 9, 7), minutes: 900, .moderate)
    #expect(OutsideActivities.aerobicMinutes(entries: [tooLong], week: outsideWeek) == 300)
    let samples = OutsideActivities.aerobicSamples(entries: [tooLong], excludingOverlapWith: [])
    #expect(samples.first?.end == outsideDate(2026, 10, 9, 12))
}

@Test("X3 pilates, ioga e cross não contam")
func outsideNonAerobicKindsDoNotCount() {
    let entries = [
        outsideEntry(.pilates, outsideDate(2026, 10, 6, 19), minutes: 50, .moderate),
        outsideEntry(.yoga, outsideDate(2026, 10, 7, 7), minutes: 50, .vigorous),
        outsideEntry(.cross, outsideDate(2026, 10, 8, 18), minutes: 60, .vigorous),
        outsideEntry(.balance, outsideDate(2026, 10, 9, 8), minutes: 10, .moderate),
        outsideEntry(.mobility, outsideDate(2026, 10, 9, 9), minutes: 10, .vigorous),
    ]

    for entry in entries {
        #expect(!OutsideActivities.countsTowardAerobic(entry), "\(entry.kind.rawValue)")
        #expect(!entry.kind.countsAsAerobic, "\(entry.kind.rawValue)")
    }
    #expect(OutsideActivities.aerobicMinutes(entries: entries, week: outsideWeek) == 0)
    #expect(OutsideActivities.aerobicSamples(entries: entries, excludingOverlapWith: []).isEmpty)
}

@Test("X3 cobertura de 50 % por um treino do Saúde")
func outsideCoverageByHealthWorkout() throws {
    let entry = outsideEntry(.walkRun, outsideDate(2026, 10, 6, 18), minutes: 60, .moderate, id: outsideID("000000000031"))
    func workout(_ start: Date, _ end: Date) -> AerobicWorkoutSample {
        AerobicWorkoutSample(activity: .walking, start: start, end: end)
    }
    // 49 %: 29,4 min dos 60 cobertos.
    let fortyNine = workout(outsideDate(2026, 10, 6, 17), outsideDate(2026, 10, 6, 18).addingTimeInterval(29.4 * 60))
    // 50 %: 30 min dos 60.
    let fifty = workout(outsideDate(2026, 10, 6, 18, 30), outsideDate(2026, 10, 6, 20))
    let whole = workout(outsideDate(2026, 10, 6, 17, 50), outsideDate(2026, 10, 6, 19, 10))
    // Dois treinos de 18 min cada: nenhum cobre a metade sozinho.
    let firstPart = workout(outsideDate(2026, 10, 6, 18), outsideDate(2026, 10, 6, 18, 18))
    let secondPart = workout(outsideDate(2026, 10, 6, 18, 40), outsideDate(2026, 10, 6, 18, 58))

    let kept = OutsideActivities.aerobicSamples(entries: [entry], excludingOverlapWith: [fortyNine])
    #expect(kept.map(\.id) == [entry.id], "49 % conta")
    #expect(OutsideActivities.aerobicSamples(entries: [entry], excludingOverlapWith: [fifty]).isEmpty, "50 % não conta")
    #expect(OutsideActivities.aerobicSamples(entries: [entry], excludingOverlapWith: [whole]).isEmpty)
    #expect(OutsideActivities.aerobicSamples(entries: [entry], excludingOverlapWith: [firstPart, secondPart]).count == 1)

    let sample = try #require(kept.first)
    #expect(sample.activity == .walking)
    #expect(sample.start == entry.start)
    #expect(sample.end == entry.end)
    #expect(sample.minuteHeartRates.isEmpty)
    #expect(sample.declaredIntensity == .moderate)

    let vigorous = outsideEntry(.spinning, outsideDate(2026, 10, 7, 18), minutes: 45, .vigorous)
    let vigorousSamples = OutsideActivities.aerobicSamples(entries: [vigorous], excludingOverlapWith: [])
    #expect(vigorousSamples.first?.declaredIntensity == .vigorous)
    #expect(vigorousSamples.first?.activity == .cycling)
}

@Test("X3 os registros entram no relatório de saúde como treinos sem leitura do relógio")
func outsideSamplesEnterTheHealthReport() {
    let entries = [
        outsideEntry(.walkRun, outsideDate(2026, 10, 6, 7), minutes: 30, .moderate),
        outsideEntry(.spinning, outsideDate(2026, 10, 6, 18), minutes: 45, .vigorous),
        outsideEntry(.teamSport, outsideDate(2026, 10, 7, 20), minutes: 60, .light),
        outsideEntry(.pilates, outsideDate(2026, 10, 7, 19), minutes: 50, .moderate),
    ]
    let samples = OutsideActivities.aerobicSamples(entries: entries, excludingOverlapWith: [])
    let report = HealthCalculator.report(
        input: HealthInput(aerobicWorkouts: samples),
        targets: HealthTargets(),
        now: outsideDate(2026, 10, 8, 12),
        calendar: outsideUTC
    )

    // O spinning é "bicicleta" no Saúde (moderado pelo tipo), mas a pessoa disse forte: vale forte.
    #expect(report.aerobic.moderateMinutes == 30)
    #expect(report.aerobic.vigorousMinutes == 45)
    #expect(report.aerobic.moderateEquivalentMinutes == 120)
    #expect(OutsideActivities.aerobicMinutes(entries: entries, week: outsideWeek) == 120, "sem o Saúde, a mesma conta")
}

// MARK: - X4 (a fixa vista pelo encaixe)

@Test("X4 a fixa vista pelo encaixe: força com os grupos, aeróbico com a intensidade, leve sem nada")
func outsideFixedDemands() throws {
    let cross = FixedOutsideActivity(
        id: outsideID("000000000041"), kind: .cross, weekday: .thursday, startMinuteOfDay: 18 * 60, minutes: 60, intensity: .vigorous
    )
    let spinning = FixedOutsideActivity(
        id: outsideID("000000000042"), kind: .spinning, weekday: .tuesday, startMinuteOfDay: 7 * 60, minutes: 45, intensity: .moderate
    )
    let pilatesLate = FixedOutsideActivity(
        id: outsideID("000000000043"), kind: .pilates, weekday: .tuesday, startMinuteOfDay: 19 * 60, minutes: 50, intensity: .light
    )
    let pilatesEarly = FixedOutsideActivity(
        id: outsideID("000000000044"), kind: .pilates, weekday: .tuesday, startMinuteOfDay: 6 * 60, minutes: 50, intensity: .light
    )

    let demands = OutsideActivities.fixedDemands([cross, pilatesLate, spinning, pilatesEarly])

    #expect(demands.map(\.id) == [pilatesEarly.id, spinning.id, pilatesLate.id, cross.id])
    let crossDemand = try #require(demands.last)
    #expect(crossDemand.name == "Cross ou funcional")
    #expect(crossDemand.weekday == .thursday)
    #expect(crossDemand.role == .strength)
    #expect(crossDemand.primaryMuscles == allMuscleGroups)
    #expect(crossDemand.isLowerBody)
    #expect(crossDemand.cardioIntensity == nil)
    #expect(crossDemand.minutes == 60)

    let spinningDemand = demands[1]
    #expect(spinningDemand.role == .cardio)
    #expect(spinningDemand.cardioIntensity == .moderate, "a intensidade é a da fixa, não a sugerida")
    #expect(spinningDemand.primaryMuscles.isEmpty)
    #expect(!spinningDemand.isLowerBody)

    let pilatesDemand = demands[0]
    #expect(pilatesDemand.role == .light)
    #expect(pilatesDemand.primaryMuscles.isEmpty)
    #expect(pilatesDemand.cardioIntensity == nil)
    #expect(pilatesDemand.name == "Pilates")
}

// MARK: - X5

@Test("X5 cargas de recuperação")
func outsideRecoveryLoads() {
    let crossStart = outsideDate(2026, 10, 5, 18)
    let spinningStart = outsideDate(2026, 10, 7, 7)
    let footballStart = outsideDate(2026, 10, 8, 20)
    let entries = [
        outsideEntry(.teamSport, footballStart, minutes: 60, .vigorous),
        outsideEntry(.cross, crossStart, minutes: 60, .moderate),
        outsideEntry(.cross, outsideDate(2026, 10, 6, 18), minutes: 60, .light),
        outsideEntry(.spinning, spinningStart, minutes: 45, .vigorous),
        outsideEntry(.spinning, outsideDate(2026, 10, 9, 7), minutes: 45, .moderate),
        outsideEntry(.pilates, outsideDate(2026, 10, 9, 19), minutes: 50, .vigorous),
        outsideEntry(.walkRun, outsideDate(2026, 10, 10, 8), minutes: 30, .light),
    ]

    let loads = OutsideActivities.recoveryLoads(entries: entries)

    #expect(loads == [
        RecoveryLoad(start: crossStart, muscles: allMuscleGroups, hours: 48),
        RecoveryLoad(start: spinningStart, muscles: outsideLegs, hours: 24),
        RecoveryLoad(start: footballStart, muscles: outsideLegs, hours: 24),
    ])
    #expect(OutsideActivities.strengthRecoveryHours == 48)
    #expect(OutsideActivities.vigorousCardioRecoveryHours == 24)
    #expect(OutsideActivities.legMuscles == outsideLegs)
}

@Test("X5 sessões de inferior para A5")
func outsidePlacementSessionsForA5() throws {
    let cross = outsideEntry(.cross, outsideDate(2026, 10, 5, 18), minutes: 60, .vigorous, id: outsideID("000000000051"))
    let entries = [
        cross,
        outsideEntry(.cross, outsideDate(2026, 10, 4, 18), minutes: 60, .light),
        outsideEntry(.spinning, outsideDate(2026, 10, 5, 7), minutes: 45, .vigorous),
        outsideEntry(.pilates, outsideDate(2026, 10, 5, 12), minutes: 50, .moderate),
    ]

    let sessions = OutsideActivities.placementSessions(entries: entries)

    #expect(sessions.count == 1)
    let session = try #require(sessions.first)
    #expect(session.id == cross.id)
    #expect(session.startedAt == cross.start)
    #expect(session.endedAt == outsideDate(2026, 10, 5, 19))
    #expect(session.status == .completed)
    #expect(session.primaryMusclesTrained == allMuscleGroups)
    #expect(session.workingSetCount == 1)

    // O cross terminou às 19h: às 21h, o aeróbico de hoje fica no baixo impacto (A5).
    let now = outsideDate(2026, 10, 5, 21)
    #expect(AerobicPlacement.today(sessions: sessions, now: now) == .lowImpactOnly(hoursSinceLowerBody: 2))
    let report = HealthCalculator.report(
        input: HealthInput(recentSessions: sessions),
        targets: HealthTargets(),
        now: now,
        calendar: outsideUTC
    )
    let deficit = try #require(report.suggestions.first { $0.kind == .aerobicDeficit })
    #expect(deficit.detail.contains("último treino de pernas"))
}

// MARK: - X6

@Test("X6 contagem de equilíbrio e mobilidade na semana")
func outsideLongevityCounts() {
    let entries = [
        outsideEntry(.balance, outsideDate(2026, 10, 5, 8), minutes: 10, .light),
        outsideEntry(.balance, outsideDate(2026, 10, 9, 8), minutes: 15, .light),
        outsideEntry(.mobility, outsideDate(2026, 10, 7, 8), minutes: 10, .light),
        outsideEntry(.balance, outsideDate(2026, 10, 4, 8), minutes: 10, .light),   // semana anterior
        outsideEntry(.mobility, outsideDate(2026, 10, 12, 8), minutes: 10, .light), // semana seguinte
        outsideEntry(.pilates, outsideDate(2026, 10, 6, 19), minutes: 50, .light),
        outsideEntry(.yoga, outsideDate(2026, 10, 8, 7), minutes: 50, .light),
    ]

    let counts = OutsideActivities.longevityCounts(entries: entries, week: outsideWeek)

    #expect(counts == [CoachInput.balanceKey: 2, CoachInput.mobilityKey: 1])
    #expect(OutsideActivities.longevityCounts(entries: [], week: outsideWeek).isEmpty)
    #expect(OutsideActivities.longevityWeeklyTarget == 2)
}

@Test("X6 registro do C8")
func outsideCoachDoneEntry() throws {
    let at = outsideDate(2026, 10, 6, 9, 15)
    let id = outsideID("000000000061")

    let balance = try #require(OutsideActivities.longevityEntry(key: CoachInput.balanceKey, at: at, id: id))
    #expect(balance.id == id)
    #expect(balance.kind == .balance)
    #expect(balance.start == at)
    #expect(balance.minutes == 10)
    #expect(balance.intensity == .light)
    #expect(balance.fixedActivityID == nil)

    let mobility = try #require(OutsideActivities.longevityEntry(key: CoachInput.mobilityKey, at: at))
    #expect(mobility.kind == .mobility)
    #expect(mobility.minutes == OutsideActivities.longevityEntryMinutes)
    #expect(OutsideActivities.longevityEntry(key: "neck", at: at) == nil)

    // O registro do C8 conta nas vezes da semana, e em nada mais (leve, sem aeróbico nem recuperação).
    #expect(OutsideActivities.longevityCounts(entries: [balance, mobility], week: outsideWeek) == [
        CoachInput.balanceKey: 1, CoachInput.mobilityKey: 1,
    ])
    #expect(OutsideActivities.aerobicMinutes(entries: [balance, mobility], week: outsideWeek) == 0)
    #expect(OutsideActivities.recoveryLoads(entries: [balance, mobility]).isEmpty)
}

// MARK: - X8

@Test("X8 o arquivo das atividades tolera chaves ausentes e faz ida e volta")
func outsideLogCodable() throws {
    let empty = try JSONDecoder().decode(OutsideActivityLog.self, from: Data("{}".utf8))
    #expect(empty == OutsideActivityLog.empty)
    #expect(empty.version == OutsideActivityLog.currentVersion)

    let onlyEntries = try JSONDecoder().decode(OutsideActivityLog.self, from: Data(#"{"entries": []}"#.utf8))
    #expect(onlyEntries.fixed.isEmpty)

    let fixed = FixedOutsideActivity(
        id: outsideID("000000000081"), kind: .fightClass, weekday: .thursday, startMinuteOfDay: 20 * 60, minutes: 60, intensity: .moderate
    )
    let done = OutsideActivities.entry(loggingFixed: fixed, on: outsideDate(2026, 10, 8), calendar: outsideUTC, id: outsideID("000000000082"))
    let log = OutsideActivityLog(entries: [done], fixed: [fixed])
    let data = try JSONEncoder().encode(log)
    let decoded = try JSONDecoder().decode(OutsideActivityLog.self, from: data)
    #expect(decoded == log)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("\"fightClass\""), "o tipo vai pelo raw value estável")
}
