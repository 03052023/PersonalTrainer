import Foundation
import Testing
@testable import TrainerCore

// MARK: - Fixed instants (SPEC P11: tests never read the clock)

// 2024-01-01 is a Monday. All values are Unix seconds.
private let mondayJan1 = Date(timeIntervalSince1970: 1_704_067_200)          // 2024-01-01T00:00:00Z
private let mondayJan1Noon = Date(timeIntervalSince1970: 1_704_110_400)      // 2024-01-01T12:00:00Z
private let wednesdayJan3 = Date(timeIntervalSince1970: 1_704_295_800)       // 2024-01-03T15:30:00Z
private let sundayJan7 = Date(timeIntervalSince1970: 1_704_585_600)          // 2024-01-07T00:00:00Z
private let sundayJan7LastSecond = Date(timeIntervalSince1970: 1_704_671_999) // 2024-01-07T23:59:59Z
private let mondayJan8 = Date(timeIntervalSince1970: 1_704_672_000)          // 2024-01-08T00:00:00Z
private let mondayJan15 = Date(timeIntervalSince1970: 1_705_276_800)         // 2024-01-15T00:00:00Z
private let sundayDec31 = Date(timeIntervalSince1970: 1_703_980_800)         // 2023-12-31T00:00:00Z
private let thursdayDec28 = Date(timeIntervalSince1970: 1_703_757_600)       // 2023-12-28T10:00:00Z

// America/Sao_Paulo is UTC−3 all year since 2019 (no DST).
private let saoPauloMondayJan1Midnight = Date(timeIntervalSince1970: 1_704_078_000) // 2024-01-01T03:00:00Z
private let saoPauloMondayJan8Midnight = Date(timeIntervalSince1970: 1_704_682_800) // 2024-01-08T03:00:00Z
private let mondayJan1OneAMUTC = Date(timeIntervalSince1970: 1_704_070_800)          // Sun 2023-12-31 22:00 in São Paulo
private let saoPauloSundayJan7LateEvening = Date(timeIntervalSince1970: 1_704_682_740) // Sun 2024-01-07 23:59 in São Paulo = Mon 02:59Z

// MARK: - Helpers

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func saoPauloCalendar() throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
    return calendar
}

private let programDayID = UUID()

private func session(
    startedAt: Date,
    status: SessionStatus = .completed,
    muscles: Set<MuscleGroup>,
    workingSets: Int = 9,
    id: UUID = UUID()
) -> SessionSummary {
    SessionSummary(
        id: id,
        programDayID: programDayID,
        startedAt: startedAt,
        endedAt: startedAt.addingTimeInterval(3_600),
        status: status,
        primaryMusclesTrained: muscles,
        workingSetCount: workingSets
    )
}

private func completed(_ report: WeeklyFrequencyReport, _ muscle: MuscleGroup) -> Int? {
    report.entries.first { $0.muscle == muscle }?.completed
}

private func target(_ report: WeeklyFrequencyReport, _ muscle: MuscleGroup) -> Int? {
    report.entries.first { $0.muscle == muscle }?.target
}

// MARK: - weekInterval

@Test("7.4 semana começa segunda 00:00: uma quarta-feira cai na semana de segunda a segunda")
func weekIntervalMondayStartFromWednesday() {
    let week = WeeklyFrequency.weekInterval(containing: wednesdayJan3, weekStartsOnMonday: true, calendar: utc)

    #expect(week.start == mondayJan1)
    #expect(week.end == mondayJan8)
}

@Test("7.4 fronteira: segunda 00:00 é o primeiro instante da própria semana")
func weekIntervalMondayMidnightStartsItsOwnWeek() {
    let week = WeeklyFrequency.weekInterval(containing: mondayJan1, weekStartsOnMonday: true, calendar: utc)

    #expect(week.start == mondayJan1)
    #expect(week.end == mondayJan8)
}

@Test("7.4 fronteira: domingo 23:59:59 ainda pertence à semana iniciada na segunda anterior")
func weekIntervalSundayLastSecondStaysInCurrentWeek() {
    let week = WeeklyFrequency.weekInterval(containing: sundayJan7LastSecond, weekStartsOnMonday: true, calendar: utc)

    #expect(week.start == mondayJan1)
    #expect(week.end == mondayJan8)
}

@Test("7.4 semana com 7 dias exatos em UTC")
func weekIntervalLastsSevenDays() {
    let week = WeeklyFrequency.weekInterval(containing: wednesdayJan3, weekStartsOnMonday: true, calendar: utc)

    #expect(week.duration == 7 * 86_400)
}

@Test("7.4 semana configurável: começando no domingo, a quarta cai na semana de domingo a domingo")
func weekIntervalSundayStartFromWednesday() {
    let week = WeeklyFrequency.weekInterval(containing: wednesdayJan3, weekStartsOnMonday: false, calendar: utc)

    #expect(week.start == sundayDec31)
    #expect(week.end == sundayJan7)
}

@Test("7.4 semana começando no domingo: domingo 00:00 abre a própria semana")
func weekIntervalSundayStartFromSundayMidnight() {
    let week = WeeklyFrequency.weekInterval(containing: sundayJan7, weekStartsOnMonday: false, calendar: utc)

    #expect(week.start == sundayJan7)
    #expect(week.end == Date(timeIntervalSince1970: 1_705_190_400)) // 2024-01-14T00:00:00Z
}

@Test("7.4 semana começando no domingo: segunda 00:00 pertence à semana do domingo anterior")
func weekIntervalSundayStartFromMondayMidnight() {
    let week = WeeklyFrequency.weekInterval(containing: mondayJan1, weekStartsOnMonday: false, calendar: utc)

    #expect(week.start == sundayDec31)
    #expect(week.end == sundayJan7)
}

@Test("7.4 weekInterval ignora firstWeekday do calendário; só weekStartsOnMonday decide")
func weekIntervalIgnoresCalendarFirstWeekday() {
    var sundayFirstCalendar = utc
    sundayFirstCalendar.firstWeekday = 1

    let week = WeeklyFrequency.weekInterval(containing: wednesdayJan3, weekStartsOnMonday: true, calendar: sundayFirstCalendar)

    #expect(week.start == mondayJan1)
    #expect(week.end == mondayJan8)
}

// MARK: - Time zones

@Test("7.4 fuso America/Sao_Paulo vs UTC muda a semana para um instante perto da meia-noite")
func weekIntervalDependsOnCalendarTimeZone() throws {
    let saoPaulo = try saoPauloCalendar()

    // Monday 12:00Z is Monday in both zones, but "Monday 00:00" is 3 h later in São Paulo.
    let utcWeek = WeeklyFrequency.weekInterval(containing: mondayJan1Noon, weekStartsOnMonday: true, calendar: utc)
    let saoPauloWeek = WeeklyFrequency.weekInterval(containing: mondayJan1Noon, weekStartsOnMonday: true, calendar: saoPaulo)

    #expect(utcWeek.start == mondayJan1)
    #expect(utcWeek.end == mondayJan8)
    #expect(saoPauloWeek.start == saoPauloMondayJan1Midnight)
    #expect(saoPauloWeek.end == saoPauloMondayJan8Midnight)
}

@Test("7.4 domingo 23:59 em São Paulo ainda é a semana corrente; em UTC já é a semana seguinte")
func weekIntervalSundayLateEveningSaoPauloVersusUTC() throws {
    let saoPaulo = try saoPauloCalendar()

    let saoPauloWeek = WeeklyFrequency.weekInterval(containing: saoPauloSundayJan7LateEvening, weekStartsOnMonday: true, calendar: saoPaulo)
    let utcWeek = WeeklyFrequency.weekInterval(containing: saoPauloSundayJan7LateEvening, weekStartsOnMonday: true, calendar: utc)

    #expect(saoPauloWeek.start == saoPauloMondayJan1Midnight)
    #expect(saoPauloWeek.end == saoPauloMondayJan8Midnight)
    #expect(utcWeek.start == mondayJan8)
    #expect(utcWeek.end == mondayJan15)
}

@Test("7.4 sessão de domingo 22:00 em São Paulo conta na semana anterior lá, mas na semana corrente em UTC")
func reportSessionNearMidnightCountsDifferentlyPerTimeZone() throws {
    let saoPaulo = try saoPauloCalendar()
    // 2024-01-01T01:00:00Z: already Monday in UTC, still Sunday 22:00 in São Paulo.
    let sessions = [session(startedAt: mondayJan1OneAMUTC, muscles: [.chest])]

    let utcReport = WeeklyFrequency.report(sessions: sessions, targets: [:], now: mondayJan1Noon, calendar: utc)
    let saoPauloReport = WeeklyFrequency.report(sessions: sessions, targets: [:], now: mondayJan1Noon, calendar: saoPaulo)

    #expect(completed(utcReport, .chest) == 1)
    #expect(completed(saoPauloReport, .chest) == 0)
}

// MARK: - report: which sessions count

@Test("7.4 report expõe o mesmo intervalo de weekInterval")
func reportUsesWeekInterval() {
    let report = WeeklyFrequency.report(sessions: [], targets: [:], now: wednesdayJan3, calendar: utc)

    #expect(report.weekStart == mondayJan1)
    #expect(report.weekEnd == mondayJan8)
}

@Test("7.4 sessões da semana anterior não contam")
func reportIgnoresPreviousWeekSessions() {
    let sessions = [
        session(startedAt: thursdayDec28, muscles: [.chest, .triceps]),
        session(startedAt: sundayDec31, muscles: [.back]),
    ]

    let report = WeeklyFrequency.report(sessions: sessions, targets: [:], now: wednesdayJan3, calendar: utc)

    #expect(completed(report, .chest) == 0)
    #expect(completed(report, .triceps) == 0)
    #expect(completed(report, .back) == 0)
}

@Test("7.4 sessões da semana seguinte não contam")
func reportIgnoresNextWeekSessions() {
    let sessions = [session(startedAt: mondayJan8.addingTimeInterval(3_600), muscles: [.quads])]

    let report = WeeklyFrequency.report(sessions: sessions, targets: [:], now: wednesdayJan3, calendar: utc)

    #expect(completed(report, .quads) == 0)
}

@Test("7.4 intervalo meio-aberto: sessão iniciada exatamente na segunda 00:00 conta; exatamente no fim, não")
func reportWeekBoundariesAreHalfOpen() {
    let sessions = [
        session(startedAt: mondayJan1, muscles: [.chest]),
        session(startedAt: mondayJan8, muscles: [.back]),
        session(startedAt: sundayJan7LastSecond, muscles: [.quads]),
    ]

    let report = WeeklyFrequency.report(sessions: sessions, targets: [:], now: wednesdayJan3, calendar: utc)

    #expect(completed(report, .chest) == 1)
    #expect(completed(report, .back) == 0)
    #expect(completed(report, .quads) == 1)
}

@Test("7.4 sessão abandoned não conta")
func reportIgnoresAbandonedSessions() {
    let sessions = [session(startedAt: wednesdayJan3, status: .abandoned, muscles: [.chest, .shoulders])]

    let report = WeeklyFrequency.report(sessions: sessions, targets: [:], now: wednesdayJan3, calendar: utc)

    #expect(completed(report, .chest) == 0)
    #expect(completed(report, .shoulders) == 0)
}

@Test("7.4 sessão inProgress não conta")
func reportIgnoresInProgressSessions() {
    let sessions = [session(startedAt: wednesdayJan3, status: .inProgress, muscles: [.back])]

    let report = WeeklyFrequency.report(sessions: sessions, targets: [:], now: wednesdayJan3, calendar: utc)

    #expect(completed(report, .back) == 0)
}

@Test("7.4 sessão concluída sem série de trabalho não conta")
func reportIgnoresSessionsWithoutWorkingSets() {
    let sessions = [session(startedAt: wednesdayJan3, muscles: [.glutes], workingSets: 0)]

    let report = WeeklyFrequency.report(sessions: sessions, targets: [:], now: wednesdayJan3, calendar: utc)

    #expect(completed(report, .glutes) == 0)
}

@Test("7.4 uma única série de trabalho basta para a sessão contar")
func reportCountsSessionWithOneWorkingSet() {
    let sessions = [session(startedAt: wednesdayJan3, muscles: [.glutes], workingSets: 1)]

    let report = WeeklyFrequency.report(sessions: sessions, targets: [:], now: wednesdayJan3, calendar: utc)

    #expect(completed(report, .glutes) == 1)
}

@Test("7.4 grupo treinado em 2 sessões na semana → 2/2")
func reportCountsTwoSessionsAsTwoOfTwo() {
    let sessions = [
        session(startedAt: mondayJan1.addingTimeInterval(8 * 3_600), muscles: [.chest, .triceps]),
        session(startedAt: wednesdayJan3, muscles: [.back, .biceps]),
        session(startedAt: sundayJan7.addingTimeInterval(10 * 3_600), muscles: [.chest, .shoulders]),
    ]

    let report = WeeklyFrequency.report(sessions: sessions, targets: [:], now: sundayJan7LastSecond, calendar: utc)

    #expect(completed(report, .chest) == 2)
    #expect(target(report, .chest) == 2)
    #expect(completed(report, .triceps) == 1)
    #expect(completed(report, .back) == 1)
    #expect(completed(report, .biceps) == 1)
    #expect(completed(report, .shoulders) == 1)
    #expect(completed(report, .quads) == 0)
}

@Test("7.4 realizado pode ultrapassar a meta (3/2)")
func reportCompletedMayExceedTarget() {
    let sessions = (0..<3).map { day in
        session(startedAt: mondayJan1.addingTimeInterval(TimeInterval(day) * 86_400), muscles: [.calves])
    }

    let report = WeeklyFrequency.report(sessions: sessions, targets: [:], now: wednesdayJan3, calendar: utc)

    #expect(completed(report, .calves) == 3)
    #expect(target(report, .calves) == 2)
}

@Test("7.4 mesma sessão repetida na entrada conta uma vez por grupo")
func reportCountsDuplicateSessionOnce() {
    let id = UUID()
    let repeated = session(startedAt: wednesdayJan3, muscles: [.hamstrings], id: id)

    let report = WeeklyFrequency.report(sessions: [repeated, repeated], targets: [:], now: wednesdayJan3, calendar: utc)

    #expect(completed(report, .hamstrings) == 1)
}

// MARK: - report: targets

@Test("7.4 meta padrão é 2×/semana por grupo")
func reportDefaultTargetIsTwo() {
    let report = WeeklyFrequency.report(sessions: [], targets: [:], now: wednesdayJan3, calendar: utc)

    #expect(WeeklyFrequency.defaultTarget == 2)
    #expect(report.entries.allSatisfy { $0.target == 2 })
}

@Test("7.4 meta específica por grupo sobrescreve defaultTarget")
func reportPerGroupTargetOverridesDefault() {
    let report = WeeklyFrequency.report(
        sessions: [],
        targets: [.calves: 3, .core: 1],
        defaultTarget: 2,
        now: wednesdayJan3,
        calendar: utc
    )

    #expect(target(report, .calves) == 3)
    #expect(target(report, .core) == 1)
    #expect(target(report, .chest) == 2)
    #expect(target(report, .quads) == 2)
}

@Test("7.4 defaultTarget configurável vale para grupos sem meta própria")
func reportCustomDefaultTargetAppliesToUnlistedGroups() {
    let report = WeeklyFrequency.report(
        sessions: [],
        targets: [.back: 4],
        defaultTarget: 1,
        now: wednesdayJan3,
        calendar: utc
    )

    #expect(target(report, .back) == 4)
    #expect(report.entries.filter { $0.muscle != .back }.allSatisfy { $0.target == 1 })
}

// MARK: - report: entries shape

@Test("7.4 entries cobrem todos os MuscleGroup.allCases na ordem, mesmo sem sessões")
func reportEntriesCoverAllMuscleGroupsInOrder() {
    let report = WeeklyFrequency.report(sessions: [], targets: [:], now: wednesdayJan3, calendar: utc)

    #expect(report.entries.map(\.muscle) == MuscleGroup.allCases)
    #expect(report.entries.allSatisfy { $0.completed == 0 })
}

@Test("7.4 ordem das entries não depende da ordem das sessões nem dos grupos treinados")
func reportEntriesOrderIsStable() {
    let sessions = [
        session(startedAt: wednesdayJan3, muscles: [.core, .calves]),
        session(startedAt: mondayJan1, muscles: [.chest]),
    ]

    let report = WeeklyFrequency.report(sessions: sessions, targets: [:], now: wednesdayJan3, calendar: utc)

    #expect(report.entries.map(\.muscle) == MuscleGroup.allCases)
    #expect(completed(report, .core) == 1)
    #expect(completed(report, .calves) == 1)
    #expect(completed(report, .chest) == 1)
}

@Test("P11 report é determinístico: mesma entrada duas vezes dá o mesmo relatório")
func reportIsDeterministic() {
    let sessions = [
        session(startedAt: mondayJan1, muscles: [.chest, .triceps]),
        session(startedAt: wednesdayJan3, muscles: [.back, .biceps]),
        session(startedAt: thursdayDec28, muscles: [.quads]),
    ]

    let first = WeeklyFrequency.report(sessions: sessions, targets: [.chest: 3], now: wednesdayJan3, calendar: utc)
    let second = WeeklyFrequency.report(sessions: sessions, targets: [.chest: 3], now: wednesdayJan3, calendar: utc)

    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
}
