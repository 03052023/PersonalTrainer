import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.10 A1/A2 (RF-27): minutos aeróbicos da semana por intensidade, contra a meta da OMS.
// 2024-01-01 é uma segunda-feira. Nascido em 1984-01-01 → 40 anos em janeiro de 2024 → FCmáx 180.

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func calendar(_ identifier: String) throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: identifier))
    return calendar
}

private func at(
    _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, in calendar: Calendar = utc
) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private let wednesdayNoon = at(2024, 1, 3, 12)
private let fortyYearsOld = UserPhysiology(birthDate: at(1984, 1, 1))

private func workout(
    _ activity: AerobicActivity,
    start: Date,
    minutes: Double,
    heartRates: [Double] = [],
    id: UUID = UUID()
) -> AerobicWorkoutSample {
    AerobicWorkoutSample(
        id: id,
        activity: activity,
        start: start,
        end: start.addingTimeInterval(minutes * 60),
        minuteHeartRates: heartRates
    )
}

private func aerobic(
    _ workouts: [AerobicWorkoutSample],
    physiology: UserPhysiology = fortyYearsOld,
    recovery: [DailyRecoverySample] = [],
    now: Date = wednesdayNoon,
    calendar: Calendar = utc
) -> AerobicWeekSummary {
    HealthCalculator.report(
        input: HealthInput(physiology: physiology, aerobicWorkouts: workouts, recovery: recovery),
        targets: HealthTargets(),
        now: now,
        calendar: calendar
    ).aerobic
}

// MARK: - CA5-1

@Test("CA5-1 A1 caminhada de 30 min a 70 % da FCmáx = 30 min moderados")
func ca51WalkAtSeventyPercent() {
    let walk = workout(.walking, start: at(2024, 1, 2, 8), minutes: 30, heartRates: Array(repeating: 126, count: 30))
    let summary = aerobic([walk])

    #expect(summary.moderateMinutes == 30)
    #expect(summary.vigorousMinutes == 0)
    #expect(summary.moderateEquivalentMinutes == 30)
}

@Test("CA5-1 A1/A2 corrida de 20 min a 85 % da FCmáx = 20 vigorosos = 40 moderados-equivalentes")
func ca51RunAtEightyFivePercent() {
    let run = workout(.running, start: at(2024, 1, 3, 7), minutes: 20, heartRates: Array(repeating: 153, count: 20))
    let summary = aerobic([run])

    #expect(summary.moderateMinutes == 0)
    #expect(summary.vigorousMinutes == 20)
    #expect(summary.moderateEquivalentMinutes == 40)
}

@Test("CA5-1 A2 caminhada + corrida na semana: 30 + 2 × 20 = 70 contra a meta de 150, por dia")
func ca51WalkAndRunTogether() {
    let walk = workout(.walking, start: at(2024, 1, 2, 8), minutes: 30, heartRates: Array(repeating: 126, count: 30))
    let run = workout(.running, start: at(2024, 1, 3, 7), minutes: 20, heartRates: Array(repeating: 153, count: 20))
    let summary = aerobic([walk, run])

    #expect(summary.moderateMinutes == 30)
    #expect(summary.vigorousMinutes == 20)
    #expect(summary.moderateEquivalentMinutes == 70)
    #expect(summary.target == 150)
    #expect(summary.perDay.count == 7)
    #expect(summary.perDay.map(\.moderate) == [0, 30, 0, 0, 0, 0, 0])
    #expect(summary.perDay.map(\.vigorous) == [0, 0, 20, 0, 0, 0, 0])
    #expect(summary.perDay.map(\.day) == (1...7).map { at(2024, 1, $0) })
}

@Test("A2 meta configurável aparece no resumo")
func customTarget() {
    let report = HealthCalculator.report(
        input: HealthInput(),
        targets: HealthTargets(weeklyModerateEquivalentMinutes: 300),
        now: wednesdayNoon,
        calendar: utc
    )
    #expect(report.aerobic.target == 300)
    #expect(report.aerobic.moderateEquivalentMinutes == 0)
}

// MARK: - A1: minutos sem FC e sem zonas

@Test(
    "A1 treino sem FC usa o tipo: corrida/HIIT/escada vigorosos, caminhada/ciclismo moderados",
    arguments: [
        (AerobicActivity.running, 0, 30),
        (.hiit, 0, 30),
        (.stairs, 0, 30),
        (.walking, 30, 0),
        (.cycling, 30, 0),
        (.swimming, 30, 0),
        (.other, 30, 0),
    ]
)
func workoutWithoutHeartRateUsesActivity(activity: AerobicActivity, moderate: Int, vigorous: Int) {
    let summary = aerobic([workout(activity, start: at(2024, 1, 2, 18), minutes: 30)])
    #expect(summary.moderateMinutes == moderate)
    #expect(summary.vigorousMinutes == vigorous)
}

@Test("A1 sem idade e sem FCmáx informada, FC alta não vira vigoroso: vale o tipo do treino")
func noZonesUsesDefaultIntensity() {
    let walk = workout(.walking, start: at(2024, 1, 2, 8), minutes: 30, heartRates: Array(repeating: 170, count: 30))
    let summary = aerobic([walk], physiology: UserPhysiology())
    #expect(summary.moderateMinutes == 30)
    #expect(summary.vigorousMinutes == 0)
}

@Test("A1 FC parcial: minutos com FC classificados, o resto pelo tipo do treino")
func partialHeartRate() {
    let walk = workout(.walking, start: at(2024, 1, 2, 8), minutes: 30, heartRates: Array(repeating: 153, count: 10))
    let run = workout(.running, start: at(2024, 1, 2, 18), minutes: 20, heartRates: Array(repeating: 126, count: 10))
    let summary = aerobic([walk, run])
    // Caminhada: 10 vigorosos (85 %) + 20 moderados (padrão). Corrida: 10 moderados (70 %) + 10 vigorosos (padrão).
    #expect(summary.moderateMinutes == 30)
    #expect(summary.vigorousMinutes == 20)
    #expect(summary.moderateEquivalentMinutes == 70)
}

@Test("A1 minutos leves (< 64 % da FCmáx) não contam para a meta")
func lightMinutesDoNotCount() {
    let walk = workout(.walking, start: at(2024, 1, 2, 8), minutes: 30, heartRates: Array(repeating: 90, count: 30))
    let summary = aerobic([walk])
    #expect(summary.moderateMinutes == 0)
    #expect(summary.vigorousMinutes == 0)
    #expect(summary.moderateEquivalentMinutes == 0)
}

@Test("A1 leituras de FC inválidas contam como minutos sem FC")
func invalidReadingsUseDefault() {
    let run = workout(.running, start: at(2024, 1, 2, 8), minutes: 3, heartRates: [0, .nan, 126])
    let summary = aerobic([run])
    #expect(summary.vigorousMinutes == 2)
    #expect(summary.moderateMinutes == 1)
}

@Test("A1 FC além da duração do treino é ignorada")
func extraHeartRateIgnored() {
    let walk = workout(.walking, start: at(2024, 1, 2, 8), minutes: 30, heartRates: Array(repeating: 153, count: 35))
    #expect(aerobic([walk]).vigorousMinutes == 30)
}

@Test(
    "A1 duração arredondada ao minuto; fim antes do início conta zero",
    arguments: [(29.0 + 40.0 / 60, 30), (29.0 + 20.0 / 60, 29), (0.4, 0), (-10.0, 0)]
)
func durationRounding(minutes: Double, expected: Int) {
    #expect(aerobic([workout(.walking, start: at(2024, 1, 2, 8), minutes: minutes)]).moderateMinutes == expected)
}

@Test("A1 o mesmo HKWorkout lido duas vezes conta uma vez")
func duplicateWorkoutCountsOnce() {
    let id = UUID()
    let walk = workout(.walking, start: at(2024, 1, 2, 8), minutes: 30, id: id)
    #expect(aerobic([walk, walk]).moderateMinutes == 30)
}

@Test("A1 FCmáx informada muda a zona: 150 bpm é vigoroso com FCmáx 180 e moderado com FCmáx 200")
func overrideChangesZone() {
    let walk = workout(.walking, start: at(2024, 1, 2, 8), minutes: 30, heartRates: Array(repeating: 150, count: 30))
    #expect(aerobic([walk]).vigorousMinutes == 30)
    let withOverride = UserPhysiology(birthDate: at(1984, 1, 1), maxHeartRateOverride: 200)
    #expect(aerobic([walk], physiology: withOverride).moderateMinutes == 30)
}

@Test("A1 com FC de repouso dos últimos 7 dias usa a FC de reserva: 110 bpm passa de leve a moderado")
func restingHeartRateSwitchesToReserve() {
    let walk = workout(.walking, start: at(2024, 1, 2, 8), minutes: 30, heartRates: Array(repeating: 110, count: 30))
    #expect(aerobic([walk]).moderateEquivalentMinutes == 0)

    let recovery = (1...3).map { DailyRecoverySample(day: at(2024, 1, $0), restingHeartRate: 60) }
    #expect(aerobic([walk], recovery: recovery).moderateMinutes == 30)
}

@Test("A1 FC de repouso com mais de 7 dias não conta para a reserva")
func oldRestingHeartRateIgnoredForZones() {
    let walk = workout(.walking, start: at(2024, 1, 2, 8), minutes: 30, heartRates: Array(repeating: 110, count: 30))
    let old = [DailyRecoverySample(day: at(2023, 12, 20), restingHeartRate: 60)]
    #expect(aerobic([walk], recovery: old).moderateEquivalentMinutes == 0)
}

// MARK: - Fronteiras da semana (§7.4) e fuso

@Test("A2 semana semiaberta: segunda 00:00 entra, domingo anterior e segunda seguinte ficam de fora")
func weekBoundaries() {
    let now = at(2024, 1, 7, 23, 59)
    let workouts = [
        workout(.walking, start: at(2024, 1, 1), minutes: 10),          // segunda 00:00: entra
        workout(.walking, start: at(2023, 12, 31, 23, 59), minutes: 10), // começa no domingo anterior: fora
        workout(.walking, start: at(2024, 1, 7, 23, 30), minutes: 10),   // domingo 23:30: entra
        workout(.walking, start: at(2024, 1, 8), minutes: 10),           // próxima segunda 00:00: fora
    ]
    let summary = aerobic(workouts, physiology: UserPhysiology(), now: now)
    #expect(summary.moderateMinutes == 20)
    #expect(summary.perDay.map(\.moderate) == [10, 0, 0, 0, 0, 0, 10])

    let report = HealthCalculator.report(
        input: HealthInput(aerobicWorkouts: workouts),
        targets: HealthTargets(),
        now: now,
        calendar: utc
    )
    #expect(report.weekStart == at(2024, 1, 1))
}

@Test("A2 segunda 00:00 já é a semana nova")
func mondayMidnightStartsNewWeek() {
    let workouts = [
        workout(.walking, start: at(2024, 1, 7, 18), minutes: 10),
        workout(.walking, start: at(2024, 1, 8), minutes: 15),
    ]
    let summary = aerobic(workouts, physiology: UserPhysiology(), now: at(2024, 1, 8))
    #expect(summary.moderateMinutes == 15)
    #expect(summary.perDay.first?.day == at(2024, 1, 8))
}

@Test("A2 a semana segue o fuso do calendário recebido (São Paulo, UTC−3)")
func weekFollowsCalendarTimeZone() throws {
    let saoPaulo = try calendar("America/Sao_Paulo")
    // Segunda 01:00 UTC = domingo 22:00 em São Paulo; segunda 02:00 UTC do dia 8 = domingo 23:00 em São Paulo.
    let walk = workout(.walking, start: at(2024, 1, 1, 1), minutes: 30)
    let run = workout(.running, start: at(2024, 1, 8, 2), minutes: 20)

    let inUTC = aerobic([walk, run], physiology: UserPhysiology(), calendar: utc)
    #expect(inUTC.moderateMinutes == 30)
    #expect(inUTC.vigorousMinutes == 0)

    let inSaoPaulo = aerobic([walk, run], physiology: UserPhysiology(), calendar: saoPaulo)
    #expect(inSaoPaulo.moderateMinutes == 0)
    #expect(inSaoPaulo.vigorousMinutes == 20)
    #expect(inSaoPaulo.perDay.first?.day == at(2024, 1, 1, in: saoPaulo))
    #expect(inSaoPaulo.perDay.last?.day == at(2024, 1, 7, in: saoPaulo))
    #expect(inSaoPaulo.perDay.last?.vigorous == 20)

    let report = HealthCalculator.report(
        input: HealthInput(aerobicWorkouts: [walk, run]),
        targets: HealthTargets(),
        now: wednesdayNoon,
        calendar: saoPaulo
    )
    #expect(report.weekStart == at(2024, 1, 1, 3))
}

@Test("A2 semana com mudança para horário de verão (Nova York, 10/03/2024) continua começando à 00:00 local")
func weekAcrossDaylightSavingChange() throws {
    let newYork = try calendar("America/New_York")
    let now = at(2024, 3, 6, 12, in: newYork)
    let workouts = [
        workout(.walking, start: at(2024, 3, 10, 23, 30, in: newYork), minutes: 20), // domingo 23:30 EDT: entra
        workout(.walking, start: at(2024, 3, 11, 0, 15, in: newYork), minutes: 20),  // segunda 00:15 EDT: fora
    ]
    let summary = aerobic(workouts, physiology: UserPhysiology(), now: now, calendar: newYork)
    #expect(summary.moderateMinutes == 20)
    #expect(summary.perDay.map(\.moderate) == [0, 0, 0, 0, 0, 0, 20])
    #expect(summary.perDay.map(\.day) == (4...10).map { at(2024, 3, $0, in: newYork) })
}

// MARK: - Unidade

@Test("A2 moderados-equivalentes = moderado + 2 × vigoroso")
func moderateEquivalentFormula() {
    #expect(AerobicWeek.moderateEquivalent(moderate: 0, vigorous: 0) == 0)
    #expect(AerobicWeek.moderateEquivalent(moderate: 30, vigorous: 0) == 30)
    #expect(AerobicWeek.moderateEquivalent(moderate: 0, vigorous: 20) == 40)
    #expect(AerobicWeek.moderateEquivalent(moderate: 90, vigorous: 30) == 150)
}

@Test("A1 treino com fim absurdo não estoura: no máximo uma semana de minutos")
func absurdDurationIsCapped() {
    let broken = AerobicWorkoutSample(
        activity: .walking,
        start: at(2024, 1, 2, 8),
        end: Date.distantFuture
    )
    #expect(aerobic([broken]).moderateMinutes == AerobicWeek.maxMinutesPerWorkout)
}
