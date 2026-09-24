import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.10 A6 / §7.7: mesmo histórico → mesmo relatório, em qualquer ordem de entrada; nada lê o relógio.

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private let now = at(2024, 1, 3, 12)

private func day(_ daysAgo: Int) -> Date {
    utc.date(byAdding: .day, value: -daysAgo, to: at(2024, 1, 3))!
}

/// Entrada realista com um pouco de tudo, inclusive duplicatas e valores inválidos.
private func sampleInput() -> HealthInput {
    let walkID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let runID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let walk = AerobicWorkoutSample(
        id: walkID,
        activity: .walking,
        start: at(2024, 1, 1, 7),
        end: at(2024, 1, 1, 7, 30),
        minuteHeartRates: Array(repeating: 126, count: 30)
    )
    let run = AerobicWorkoutSample(
        id: runID,
        activity: .running,
        start: at(2024, 1, 2, 18),
        end: at(2024, 1, 2, 18, 20),
        minuteHeartRates: Array(repeating: 153, count: 12) + [0, .nan]
    )
    let lastWeek = AerobicWorkoutSample(activity: .cycling, start: at(2023, 12, 30, 9), end: at(2023, 12, 30, 10))

    var recovery: [DailyRecoverySample] = []
    for daysAgo in 0..<28 {
        recovery.append(
            DailyRecoverySample(
                day: day(daysAgo),
                hrvSDNN: daysAgo < 7 ? (daysAgo.isMultiple(of: 2) ? 48 : nil) : 62,
                restingHeartRate: daysAgo < 7 ? 58 : 55,
                sleepHours: daysAgo == 1 ? 0 : 6.8
            )
        )
    }
    recovery.append(DailyRecoverySample(day: day(0), hrvSDNN: 52))

    let steps = (0...9).map { DailyStepCount(day: day($0), steps: 6_000 + 250 * $0) }
    let vo2Max = [
        Vo2MaxSample(date: day(95), value: 40.2),
        Vo2MaxSample(date: day(85), value: 40.8),
        Vo2MaxSample(date: day(20), value: 42.9),
        Vo2MaxSample(date: day(3), value: 43.4),
    ]
    let sessions = [
        SessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
            programDayID: UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!,
            startedAt: at(2024, 1, 2, 19),
            endedAt: at(2024, 1, 2, 20),
            status: .completed,
            primaryMusclesTrained: [.quads, .glutes],
            workingSetCount: 15
        ),
        SessionSummary(
            id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!,
            programDayID: UUID(uuidString: "00000000-0000-0000-0000-0000000000D2")!,
            startedAt: at(2023, 12, 31, 10),
            endedAt: at(2023, 12, 31, 11),
            status: .completed,
            primaryMusclesTrained: [.chest, .back],
            workingSetCount: 15
        ),
    ]
    return HealthInput(
        physiology: UserPhysiology(birthDate: at(1984, 1, 1), sex: .male),
        aerobicWorkouts: [walk, run, lastWeek, walk],
        recovery: recovery,
        steps: steps,
        vo2Max: vo2Max,
        recentSessions: sessions
    )
}

private func reversed(_ input: HealthInput) -> HealthInput {
    HealthInput(
        physiology: input.physiology,
        aerobicWorkouts: input.aerobicWorkouts.reversed(),
        recovery: input.recovery.reversed(),
        steps: input.steps.reversed(),
        vo2Max: input.vo2Max.reversed(),
        recentSessions: input.recentSessions.reversed()
    )
}

@Test("A6 relatório de exemplo: todos os blocos calculados com os números esperados")
func fullReport() throws {
    let report = HealthCalculator.report(input: sampleInput(), targets: HealthTargets(), now: now, calendar: utc)

    #expect(report.weekStart == at(2024, 1, 1))

    // Aeróbico: FC de repouso 58 nos últimos 7 dias → Karvonen com FCmáx 180 (reserva 122).
    // Caminhada a 126 bpm = 56 % da reserva → 30 moderados. Corrida: 12 min a 153 bpm = 78 % → vigorosos,
    // 2 leituras inválidas + 6 min sem FC → 8 vigorosos pelo tipo. Duplicata e semana passada não contam.
    #expect(report.aerobic.moderateMinutes == 30)
    #expect(report.aerobic.vigorousMinutes == 20)
    #expect(report.aerobic.moderateEquivalentMinutes == 70)
    #expect(report.aerobic.perDay.map(\.moderate) == [30, 0, 0, 0, 0, 0, 0])
    #expect(report.aerobic.perDay.map(\.vigorous) == [0, 20, 0, 0, 0, 0, 0])

    // VO2max: último 43,4; referência = média de 40,2 e 40,8 = 40,5 → +2,9; homem de 40 anos: P50 37,8 ≤ 43,4 < P75 45,0.
    let vo2Max = try #require(report.vo2Max)
    #expect(vo2Max.latest == 43.4)
    #expect(vo2Max.latestDate == day(3))
    #expect(abs((vo2Max.change90Days ?? 0) - 2.9) < 1e-9)
    #expect(vo2Max.band == .good)
    #expect(vo2Max.ageYears == 40)

    // Recuperação: HRV dos últimos 7 dias = dias 0 (média de 48 e 52 = 50), 2, 4 e 6 (48) → 48,5;
    // 28 dias = (194 + 21 × 62) / 25 = 59,84 → queda de 19 %. FC de repouso 58 vs. 55,75: sem alerta.
    // O dia 1 não tem HRV e o sono 0 é ausência de leitura → 6 noites com dado.
    #expect(report.recovery.hrv7 == 48.5)
    #expect(abs((report.recovery.hrv28 ?? 0) - 59.84) < 1e-9)
    #expect(report.recovery.restingHR7 == 58)
    #expect(report.recovery.restingHR28 == 55.75)
    #expect(abs((report.recovery.sleep7 ?? 0) - 6.8) < 1e-9)
    #expect(report.recovery.nightsWithData7 == 6)
    #expect(report.recovery.alerts == [.hrvDrop, .lowSleep])

    // Passos: dias 1 a 7 → 6.250 … 7.750 → média 7.000.
    #expect(report.steps.average7 == 7_000)
    #expect(report.steps.target == 7_000)

    // Treino de pernas terminou há 16 h → encaixe só de baixo impacto.
    #expect(report.suggestions.map(\.kind) == [.aerobicDeficit, .lowSleep, .recoveryAlert])
    let aerobic = try #require(report.suggestions.first)
    #expect(aerobic.detail.contains("Seu último treino de pernas foi há 16 horas"))
    #expect(!aerobic.detail.contains("Hoje pode ser vigoroso"))
}

@Test("A6 determinismo: a mesma entrada em outra ordem dá exatamente o mesmo relatório")
func orderIndependent() {
    let input = sampleInput()
    let a = HealthCalculator.report(input: input, targets: HealthTargets(), now: now, calendar: utc)
    let b = HealthCalculator.report(input: reversed(input), targets: HealthTargets(), now: now, calendar: utc)
    let c = HealthCalculator.report(input: input, targets: HealthTargets(), now: now, calendar: utc)
    #expect(a == b)
    #expect(a == c)
}

@Test("A6 entrada vazia: zeros, sem VO2max e só as sugestões que dependem de falta de dado")
func emptyInput() {
    let report = HealthCalculator.report(input: HealthInput(), targets: HealthTargets(), now: now, calendar: utc)
    #expect(report.aerobic.moderateEquivalentMinutes == 0)
    #expect(report.aerobic.perDay.count == 7)
    #expect(report.vo2Max == nil)
    #expect(report.recovery.nightsWithData7 == 0)
    #expect(report.recovery.alerts.isEmpty)
    #expect(report.steps.average7 == nil)
    // Onda A2: sem nenhuma estimativa de VO2max na janela de leitura (relógio que nunca enviou ao
    // Saúde), a sugestão de atualizar nunca aparece — mesmo com entrada totalmente vazia.
    #expect(report.suggestions.map(\.kind) == [.wearWatchAtNight, .aerobicDeficit])
}

@Test("Relatório é Codable sem perda (o app pode guardar o último relatório)")
func reportCodableRoundTrip() throws {
    let report = HealthCalculator.report(input: sampleInput(), targets: HealthTargets(), now: now, calendar: utc)
    let data = try JSONEncoder().encode(report)
    let decoded = try JSONDecoder().decode(HealthReport.self, from: data)
    #expect(decoded == report)
}

@Test("Entrada é Codable sem perda")
func inputCodableRoundTrip() throws {
    let input = HealthInput(
        physiology: UserPhysiology(birthDate: at(1984, 1, 1), sex: .female, maxHeartRateOverride: 185),
        aerobicWorkouts: [AerobicWorkoutSample(activity: .rowing, start: at(2024, 1, 2), end: at(2024, 1, 2, 0, 40), minuteHeartRates: [120, 130])],
        recovery: [DailyRecoverySample(day: day(0), hrvSDNN: 50, restingHeartRate: 58, sleepHours: 7.2)],
        steps: [DailyStepCount(day: day(1), steps: 8_000)],
        vo2Max: [Vo2MaxSample(date: day(2), value: 38.5)]
    )
    let decoded = try JSONDecoder().decode(HealthInput.self, from: JSONEncoder().encode(input))
    #expect(decoded == input)
}
