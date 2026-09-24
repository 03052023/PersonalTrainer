import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.10 A4 (RF-29): HRV, FC de repouso e sono, médias de 7 vs. 28 dias, e passos (7 dias completos).
// "Hoje" = domingo 2024-01-28 (UTC); últimos 7 dias = 22 a 28/01; últimos 28 = 01 a 28/01.

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private let now = at(2024, 1, 28, 9)

/// Início do dia `daysAgo` dias antes de hoje (0 = hoje).
private func day(_ daysAgo: Int) -> Date {
    utc.date(byAdding: .day, value: -daysAgo, to: at(2024, 1, 28))!
}

private func recovery(_ samples: [DailyRecoverySample], targets: HealthTargets = HealthTargets()) -> RecoverySummary {
    HealthCalculator.report(
        input: HealthInput(recovery: samples),
        targets: targets,
        now: now,
        calendar: utc
    ).recovery
}

private func hrvSamples(last7: Double, days7to13: Double) -> [DailyRecoverySample] {
    (0..<7).map { DailyRecoverySample(day: day($0), hrvSDNN: last7) }
        + (7..<14).map { DailyRecoverySample(day: day($0), hrvSDNN: days7to13) }
}

private func restingSamples(last7: Double, days7to13: Double) -> [DailyRecoverySample] {
    (0..<7).map { DailyRecoverySample(day: day($0), restingHeartRate: last7) }
        + (7..<14).map { DailyRecoverySample(day: day($0), restingHeartRate: days7to13) }
}

// MARK: - Médias

@Test("A4 médias de 7 e 28 dias ignoram dias sem dado")
func sevenAndTwentyEightDayAverages() {
    var samples: [DailyRecoverySample] = []
    for daysAgo in 0..<28 {
        samples.append(
            DailyRecoverySample(
                day: day(daysAgo),
                hrvSDNN: daysAgo < 7 ? 54 : (daysAgo < 14 ? 66 : nil),
                restingHeartRate: daysAgo == 3 ? nil : 60,
                sleepHours: daysAgo < 7 ? 7.5 : 6.5
            )
        )
    }
    let summary = recovery(samples)

    #expect(summary.hrv7 == 54)
    #expect(summary.hrv28 == 60)
    #expect(summary.restingHR7 == 60)
    #expect(summary.restingHR28 == 60)
    #expect(summary.sleep7 == 7.5)
    #expect(summary.sleep28 == 6.75)
    #expect(summary.nightsWithData7 == 7)
    #expect(summary.alerts == [.hrvDrop])
}

@Test("A4 sem dados: médias nil, nenhuma noite, nenhum alerta")
func emptyRecovery() {
    let summary = recovery([])
    #expect(summary.hrv7 == nil)
    #expect(summary.hrv28 == nil)
    #expect(summary.restingHR7 == nil)
    #expect(summary.restingHR28 == nil)
    #expect(summary.sleep7 == nil)
    #expect(summary.sleep28 == nil)
    #expect(summary.nightsWithData7 == 0)
    #expect(summary.alerts.isEmpty)
}

@Test("A4 janelas: hoje conta (mesmo com hora depois de now), 28 dias atrás e dias futuros não")
func windowEdges() {
    let summary = recovery([
        DailyRecoverySample(day: at(2024, 1, 28, 15), hrvSDNN: 40), // hoje, 15:00: dia 0
        DailyRecoverySample(day: day(27), hrvSDNN: 60),              // 01/01: último dia da janela de 28
        DailyRecoverySample(day: day(28), hrvSDNN: 999),             // 31/12: fora
        DailyRecoverySample(day: at(2024, 1, 29), hrvSDNN: 999),     // amanhã: fora
    ])
    #expect(summary.hrv7 == 40)
    #expect(summary.hrv28 == 50)
    #expect(summary.nightsWithData7 == 1)
}

@Test("A4 dia repetido é promediado antes, para não pesar dobrado")
func duplicateDayAveragedFirst() {
    let summary = recovery([
        DailyRecoverySample(day: day(0), hrvSDNN: 30),
        DailyRecoverySample(day: day(0), hrvSDNN: 70),
        DailyRecoverySample(day: day(1), hrvSDNN: 80),
    ])
    #expect(summary.hrv7 == 65)
    #expect(summary.nightsWithData7 == 2)
}

@Test("A4 zero, negativo e NaN são ausência de leitura")
func invalidValuesIgnored() {
    let summary = recovery([
        DailyRecoverySample(day: day(1), hrvSDNN: 0, restingHeartRate: -1, sleepHours: 0),
        DailyRecoverySample(day: day(2), hrvSDNN: .nan, restingHeartRate: .infinity, sleepHours: -2),
        DailyRecoverySample(day: day(3), hrvSDNN: 50, restingHeartRate: 58, sleepHours: 7),
    ])
    #expect(summary.hrv7 == 50)
    #expect(summary.restingHR7 == 58)
    #expect(summary.sleep7 == 7)
    #expect(summary.nightsWithData7 == 1)
}

@Test("A4 noite com dado = HRV ou sono; só FC de repouso não conta")
func nightsCountHrvOrSleepOnly() {
    var samples = [
        DailyRecoverySample(day: day(0), hrvSDNN: 50),
        DailyRecoverySample(day: day(1), sleepHours: 7),
        DailyRecoverySample(day: day(7), hrvSDNN: 50, sleepHours: 7), // 8 dias atrás: fora dos 7
    ]
    samples += (2..<7).map { DailyRecoverySample(day: day($0), restingHeartRate: 60) }
    #expect(recovery(samples).nightsWithData7 == 2)
}

// MARK: - Alertas

// Casos com tipo explícito (evita o limite de inferência do compilador dentro do macro @Test).
private let hrvDropCases: [(Double, Bool)] = [(54.0, true), (55.0, false), (40.0, true), (66.0, false)]
private let restingRiseCases: [(Double, Bool)] = [(65.0, true), (64.0, false), (70.0, true), (55.0, false)]
private let lowSleepCases: [(Double, Double, Bool)] = [(6.0, 7.0, true), (7.0, 7.0, false), (8.5, 7.0, false), (7.5, 8.0, true)]

@Test(
    "A4 alerta de HRV quando a média de 7 dias está ≥ 10 % abaixo da de 28 (fronteira inclusiva)",
    arguments: hrvDropCases
)
func hrvDropThreshold(last7: Double, expectsAlert: Bool) {
    // 7 dias em `last7` e os 7 anteriores em 66: com 54, a média de 28 dias é 60 e 54 = 0,9 × 60.
    let summary = recovery(hrvSamples(last7: last7, days7to13: 66))
    #expect(summary.alerts.contains(.hrvDrop) == expectsAlert)
}

@Test(
    "A4 alerta de FC de repouso quando a média de 7 dias está ≥ 5 bpm acima da de 28 (fronteira inclusiva)",
    arguments: restingRiseCases
)
func restingRiseThreshold(last7: Double, expectsAlert: Bool) {
    // Com 65, a média de 28 dias é 60: 65 = 60 + 5.
    let summary = recovery(restingSamples(last7: last7, days7to13: 55))
    #expect(summary.alerts.contains(.restingHeartRateRise) == expectsAlert)
}

@Test(
    "A4 sono médio de 7 dias abaixo da meta gera alerta",
    arguments: lowSleepCases
)
func lowSleepThreshold(sleep: Double, target: Double, expectsAlert: Bool) {
    let samples = (0..<7).map { DailyRecoverySample(day: day($0), sleepHours: sleep) }
    let summary = recovery(samples, targets: HealthTargets(sleepHours: target))
    #expect(summary.alerts.contains(.lowSleep) == expectsAlert)
}

@Test("A4 alertas saem na ordem fixa hrvDrop, restingHeartRateRise, lowSleep")
func alertOrder() {
    let samples = (0..<7).map {
        DailyRecoverySample(day: day($0), hrvSDNN: 40, restingHeartRate: 70, sleepHours: 5)
    } + (7..<14).map {
        DailyRecoverySample(day: day($0), hrvSDNN: 70, restingHeartRate: 55, sleepHours: 8)
    }
    #expect(recovery(samples).alerts == [.hrvDrop, .restingHeartRateRise, .lowSleep])
}

@Test("A4 sem a média de 28 dias de um sinal não há alerta desse sinal")
func alertNeedsBothAverages() {
    // Só dados de FC de repouso: HRV não pode alertar.
    let summary = recovery(restingSamples(last7: 60, days7to13: 60))
    #expect(summary.hrv7 == nil)
    #expect(!summary.alerts.contains(.hrvDrop))
    #expect(summary.alerts.isEmpty)
}

// MARK: - Passos

@Test("Passos: média dos últimos 7 dias completos, sem hoje, sem zeros e sem contar dia repetido em dobro")
func stepsAverage() {
    let steps = [
        DailyStepCount(day: at(2024, 1, 28), steps: 100),    // hoje: fora
        DailyStepCount(day: at(2024, 1, 27), steps: 5_000),
        DailyStepCount(day: at(2024, 1, 27), steps: 9_000),  // releitura: vale o maior
        DailyStepCount(day: at(2024, 1, 26), steps: 10_000),
        DailyStepCount(day: at(2024, 1, 25), steps: 9_000),
        DailyStepCount(day: at(2024, 1, 24), steps: 8_000),
        DailyStepCount(day: at(2024, 1, 23), steps: 0),      // sem aparelho: fora
        DailyStepCount(day: at(2024, 1, 22), steps: 7_000),
        DailyStepCount(day: at(2024, 1, 21), steps: 6_000),  // 7 dias atrás: entra
        DailyStepCount(day: at(2024, 1, 20), steps: 50_000), // 8 dias atrás: fora
    ]
    let summary = HealthCalculator.report(
        input: HealthInput(steps: steps),
        targets: HealthTargets(),
        now: now,
        calendar: utc
    ).steps
    // (9.000 + 10.000 + 9.000 + 8.000 + 7.000 + 6.000) / 6 = 8.166,7 → 8.167
    #expect(summary.average7 == 8_167)
    #expect(summary.target == 7_000)
}

@Test("Passos: sem registro nos 7 dias completos a média é nil")
func stepsWithoutData() {
    let onlyToday = [DailyStepCount(day: at(2024, 1, 28), steps: 12_000)]
    let summary = HealthCalculator.report(
        input: HealthInput(steps: onlyToday),
        targets: HealthTargets(dailySteps: 9_000),
        now: now,
        calendar: utc
    ).steps
    #expect(summary.average7 == nil)
    #expect(summary.target == 9_000)
}
