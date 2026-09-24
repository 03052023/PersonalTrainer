import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.10 A3 (RF-28): último VO2max, tendência de 90 dias, faixa por idade e sexo (FRIEND 2015).

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

// 2024-06-30 12:00 UTC. 60 dias antes = 2024-05-01 12:00; 80 dias = 2024-04-11 12:00; 100 dias = 2024-03-22 12:00.
private let now = at(2024, 6, 30, 12)
private let man40 = UserPhysiology(birthDate: at(1984, 1, 1), sex: .male)

private func summary(_ samples: [Vo2MaxSample], physiology: UserPhysiology = man40) -> Vo2MaxSummary? {
    HealthCalculator.report(
        input: HealthInput(physiology: physiology, vo2Max: samples),
        targets: HealthTargets(),
        now: now,
        calendar: utc
    ).vo2Max
}

// MARK: - Tabela normativa (transcrição de Kaminsky 2015, Table 3)

@Test("A3 tabela FRIEND 2015 transcrita: homens, percentis 5/10/25/50/75/90/95 por década")
func friendMenTranscription() {
    let expected: [(Int, [Double])] = [
        (25, [29.0, 32.1, 40.1, 48.0, 55.2, 61.8, 66.3]),
        (35, [27.2, 30.2, 35.9, 42.4, 49.2, 56.5, 59.8]),
        (45, [24.2, 26.8, 31.9, 37.8, 45.0, 52.1, 55.6]),
        (55, [20.9, 22.8, 27.1, 32.6, 39.7, 45.6, 50.7]),
        (65, [17.4, 19.8, 23.7, 28.2, 34.5, 40.3, 43.0]),
        (75, [16.3, 17.1, 20.4, 24.4, 30.4, 36.6, 39.7]),
    ]
    for (age, row) in expected {
        #expect(Vo2MaxNorms.percentiles(ageYears: age, sex: .male) == row)
    }
}

@Test("A3 tabela FRIEND 2015 transcrita: mulheres, percentis 5/10/25/50/75/90/95 por década")
func friendWomenTranscription() {
    let expected: [(Int, [Double])] = [
        (25, [21.7, 23.9, 30.5, 37.6, 44.7, 51.3, 56.0]),
        (35, [19.0, 20.9, 25.3, 30.2, 36.1, 41.4, 45.8]),
        (45, [17.0, 18.8, 22.1, 26.7, 32.4, 38.4, 41.7]),
        (55, [16.0, 17.3, 19.9, 23.4, 27.6, 32.0, 35.9]),
        (65, [13.4, 14.6, 17.2, 20.0, 23.8, 27.0, 29.4]),
        (75, [13.1, 13.6, 15.6, 18.3, 20.8, 23.1, 24.1]),
    ]
    for (age, row) in expected {
        #expect(Vo2MaxNorms.percentiles(ageYears: age, sex: .female) == row)
    }
}

@Test("A3 décadas: 20 e 29 na mesma linha, 30 na seguinte, 79 na última")
func decadeBoundaries() {
    #expect(Vo2MaxNorms.percentiles(ageYears: 20, sex: .male) == Vo2MaxNorms.percentiles(ageYears: 29, sex: .male))
    #expect(Vo2MaxNorms.percentiles(ageYears: 30, sex: .male)?.first == 27.2)
    #expect(Vo2MaxNorms.percentiles(ageYears: 79, sex: .female)?.first == 13.1)
}

@Test("A3 fora de 20–79 anos ou com sexo 'outro' não há faixa (não extrapola)")
func noBandOutsideTable() {
    #expect(Vo2MaxNorms.percentiles(ageYears: 19, sex: .male) == nil)
    #expect(Vo2MaxNorms.percentiles(ageYears: 80, sex: .female) == nil)
    #expect(Vo2MaxNorms.band(vo2Max: 40, ageYears: 30, sex: .other) == nil)
    #expect(Vo2MaxNorms.band(vo2Max: 40, ageYears: 18, sex: .male) == nil)
    #expect(Vo2MaxNorms.band(vo2Max: 0, ageYears: 30, sex: .male) == nil)
    #expect(Vo2MaxNorms.band(vo2Max: .nan, ageYears: 30, sex: .male) == nil)
}

// Casos com tipo explícito: tuplas com membros implícitos dentro do macro @Test estouram o tempo de
// inferência do compilador.
private let bandBoundaryCasesMan25: [(Double, FitnessBand)] = [
    (32.0, FitnessBand.veryPoor),
    (32.1, FitnessBand.poor),
    (40.0, FitnessBand.poor),
    (40.1, FitnessBand.fair),
    (47.9, FitnessBand.fair),
    (48.0, FitnessBand.good),
    (55.1, FitnessBand.good),
    (55.2, FitnessBand.excellent),
    (66.2, FitnessBand.excellent),
    (66.3, FitnessBand.superior),
    (80.0, FitnessBand.superior),
]

@Test(
    "A3 faixas: < P10 muito baixo, P10 baixo, P25 regular, P50 bom, P75 excelente, P95 superior (homem de 25 anos)",
    arguments: bandBoundaryCasesMan25
)
func bandBoundariesMan25(vo2Max: Double, expected: FitnessBand) {
    #expect(Vo2MaxNorms.band(vo2Max: vo2Max, ageYears: 25, sex: .male) == expected)
}

@Test("A3 faixas usam a tabela do sexo: 30 mL/kg/min aos 72 anos é superior para mulher e bom para homem")
func bandDependsOnSex() {
    #expect(Vo2MaxNorms.band(vo2Max: 30, ageYears: 72, sex: .female) == .superior)
    #expect(Vo2MaxNorms.band(vo2Max: 30, ageYears: 72, sex: .male) == .good)
    #expect(Vo2MaxNorms.band(vo2Max: 13.5, ageYears: 72, sex: .female) == .veryPoor)
}

// MARK: - Resumo

@Test("A3 sem estimativas não há resumo de VO2max")
func noSamplesNoSummary() {
    #expect(summary([]) == nil)
}

@Test("A3 último valor = amostra mais recente, faixa pela idade em now e pelo sexo")
func latestAndBand() {
    let result = summary([
        Vo2MaxSample(date: at(2024, 5, 1, 12), value: 41.0),
        Vo2MaxSample(date: at(2024, 6, 20, 8), value: 45.0),
        Vo2MaxSample(date: at(2024, 6, 1, 8), value: 43.0),
    ])
    #expect(result?.latest == 45.0)
    #expect(result?.latestDate == at(2024, 6, 20, 8))
    #expect(result?.ageYears == 40)
    #expect(result?.band == .excellent) // homem 40–49: P75 = 45,0
}

@Test("A3 empate de data: vale o maior valor, independentemente da ordem")
func latestTieBreak() {
    let a = Vo2MaxSample(date: at(2024, 6, 20, 8), value: 44.0)
    let b = Vo2MaxSample(date: at(2024, 6, 20, 8), value: 46.0)
    #expect(summary([a, b])?.latest == 46.0)
    #expect(summary([b, a])?.latest == 46.0)
}

@Test("A3 amostras inválidas ou com data futura são ignoradas")
func invalidSamplesIgnored() {
    let result = summary([
        Vo2MaxSample(date: at(2024, 6, 20), value: 42.0),
        Vo2MaxSample(date: at(2024, 6, 25), value: 0),
        Vo2MaxSample(date: at(2024, 6, 26), value: -3),
        Vo2MaxSample(date: at(2024, 6, 27), value: .nan),
        Vo2MaxSample(date: at(2024, 7, 1), value: 60.0),
    ])
    #expect(result?.latest == 42.0)
}

@Test("A3 tendência de 90 dias = último − média das amostras entre 80 e 100 dias atrás (fronteiras inclusivas)")
func ninetyDayChange() throws {
    let result = try #require(summary([
        Vo2MaxSample(date: at(2024, 3, 22, 11, 59), value: 10.0), // 100 dias e 1 min: fora
        Vo2MaxSample(date: at(2024, 3, 22, 12), value: 40.0),     // 100 dias exatos: entra
        Vo2MaxSample(date: at(2024, 4, 1), value: 41.0),          // ~90 dias: entra
        Vo2MaxSample(date: at(2024, 4, 11, 12), value: 42.0),     // 80 dias exatos: entra
        Vo2MaxSample(date: at(2024, 4, 11, 12, 1), value: 99.0),  // 1 min depois dos 80 dias: fora
        Vo2MaxSample(date: at(2024, 6, 20), value: 45.0),
    ]))
    #expect(result.latest == 45.0)
    #expect(result.change90Days == 4.0)
}

@Test("A3 sem amostras entre 80 e 100 dias atrás a tendência é nil")
func noTrendWithoutWindow() {
    let result = summary([
        Vo2MaxSample(date: at(2024, 5, 1), value: 41.0),
        Vo2MaxSample(date: at(2024, 6, 20), value: 45.0),
    ])
    #expect(result != nil)
    #expect(result?.change90Days == nil)
}

@Test("A3 sem sexo, sem data de nascimento ou sexo 'outro': mostra o valor, sem faixa")
func noBandWithoutPhysiology() {
    let samples = [Vo2MaxSample(date: at(2024, 6, 20), value: 45.0)]
    #expect(summary(samples, physiology: UserPhysiology(birthDate: at(1984, 1, 1)))?.band == nil)
    #expect(summary(samples, physiology: UserPhysiology(sex: .female))?.band == nil)
    #expect(summary(samples, physiology: UserPhysiology(sex: .female))?.ageYears == nil)
    #expect(summary(samples, physiology: UserPhysiology(birthDate: at(1984, 1, 1), sex: .other))?.band == nil)
    #expect(summary(samples, physiology: UserPhysiology(sex: .female))?.latest == 45.0)
}

// MARK: - Estimativa desatualizada (60 dias)

@Test("A3 estimativa com exatamente 60 dias ainda é recente; 1 min a mais já está desatualizada")
func staleBoundary() {
    #expect(!Vo2MaxTrend.isStale(samples: [Vo2MaxSample(date: at(2024, 5, 1, 12), value: 40)], now: now, calendar: utc))
    #expect(Vo2MaxTrend.isStale(samples: [Vo2MaxSample(date: at(2024, 5, 1, 11, 59), value: 40)], now: now, calendar: utc))
    #expect(Vo2MaxTrend.isStale(samples: [], now: now, calendar: utc))
    // Amostra com data futura não conta como recente.
    #expect(Vo2MaxTrend.isStale(samples: [Vo2MaxSample(date: at(2024, 7, 2), value: 40)], now: now, calendar: utc))
}
