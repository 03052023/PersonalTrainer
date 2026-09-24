import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.10 A3–A6 (RF-28..RF-30): sugestões determinísticas, com motivo e números, em ordem fixa.
// "Agora" = quarta-feira 2024-01-03 12:00 UTC; a semana vai de 01/01 00:00 a 08/01 00:00.

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private let wednesdayNoon = at(2024, 1, 3, 12)

/// Início do dia `daysAgo` dias antes de `wednesdayNoon`.
private func day(_ daysAgo: Int) -> Date {
    utc.date(byAdding: .day, value: -daysAgo, to: at(2024, 1, 3))!
}

/// HRV e sono em todos os últimos 7 dias: sem sugestão de usar o Watch à noite nem de sono.
private let goodNights = (0..<7).map { DailyRecoverySample(day: day($0), hrvSDNN: 60, restingHeartRate: 55, sleepHours: 7.5) }
private let recentVo2Max = [Vo2MaxSample(date: day(10), value: 45)]
private let goodSteps = (1...7).map { DailyStepCount(day: day($0), steps: 9_000) }

private func walk(minutes: Double, on date: Date = at(2024, 1, 1, 8)) -> AerobicWorkoutSample {
    AerobicWorkoutSample(activity: .walking, start: date, end: date.addingTimeInterval(minutes * 60))
}

private func session(
    _ muscles: Set<MuscleGroup>,
    start: Date,
    end: Date?,
    status: SessionStatus = .completed
) -> SessionSummary {
    SessionSummary(
        programDayID: UUID(),
        startedAt: start,
        endedAt: end,
        status: status,
        primaryMusclesTrained: muscles,
        workingSetCount: 12
    )
}

private func suggestions(
    recovery: [DailyRecoverySample] = goodNights,
    vo2Max: [Vo2MaxSample] = recentVo2Max,
    steps: [DailyStepCount] = goodSteps,
    workouts: [AerobicWorkoutSample] = [],
    sessions: [SessionSummary] = [],
    targets: HealthTargets = HealthTargets(),
    now: Date = wednesdayNoon
) -> [HealthSuggestion] {
    HealthCalculator.report(
        input: HealthInput(
            aerobicWorkouts: workouts,
            recovery: recovery,
            steps: steps,
            vo2Max: vo2Max,
            recentSessions: sessions
        ),
        targets: targets,
        now: now,
        calendar: utc
    ).suggestions
}

private func suggestion(_ kind: HealthSuggestionKind, in list: [HealthSuggestion]) -> HealthSuggestion? {
    list.first { $0.kind == kind }
}

/// Meta da semana já cumprida: 150 min de caminhada (moderado pelo tipo).
private let weekDone = [walk(minutes: 150)]

// MARK: - A6: ordem, ids e tópicos

@Test("A6 todas as sugestões juntas: ordem fixa, ids estáveis e tópicos do 'Por quê?'")
func allSuggestionsOrderIdsTopics() {
    let recovery = [
        DailyRecoverySample(day: day(0), hrvSDNN: 40, sleepHours: 5.5),
        DailyRecoverySample(day: day(1), hrvSDNN: 40, sleepHours: 5.5),
    ] + (7..<14).map { DailyRecoverySample(day: day($0), hrvSDNN: 70) }
    let steps = (1...7).map { DailyStepCount(day: day($0), steps: 4_000) }
    // Estimativa desatualizada mas dentro da janela de leitura, para a sugestão de VO2max aparecer
    // junto com as outras (CA5-4 cobre a ausência total de estimativa em separado).
    let list = suggestions(recovery: recovery, vo2Max: [Vo2MaxSample(date: day(65), value: 42)], steps: steps)

    #expect(list.map(\.kind) == HealthSuggestionKind.allCases)
    #expect(list.map(\.id) == [
        "wear-watch-at-night", "update-vo2max", "aerobic-deficit", "low-sleep", "recovery-alert", "low-steps",
    ])
    #expect(list.map(\.referenceTopic) == [
        "topic.hrv", "topic.vo2max", "topic.aerobic", "topic.sleep", "topic.hrv", "topic.steps",
    ])
    #expect(list.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
}

@Test("A6 tudo em dia: nenhuma sugestão")
func noSuggestionsWhenEverythingIsFine() {
    #expect(suggestions(workouts: weekDone).isEmpty)
}

// MARK: - CA5-3 (A4): usar o relógio à noite

// Casos com tipo explícito (evita o limite de inferência do compilador dentro do macro @Test).
private let nightDataCases: [(Int, Bool)] = [(0, true), (1, true), (2, true), (3, false), (7, false)]
private let aerobicDeficitCases: [(Double, Bool)] = [(0.0, true), (130.0, true), (131.0, false), (150.0, false), (200.0, false)]
private let recentLowerBodyHours: [Double] = [0.0, 0.5, 2.0, 5.9, 6.0, 12.0, 17.0, 23.9]
private let noRecentLowerBodyHours: [Double] = [24.0, 25.0, 49.0]

@Test(
    "CA5-3 A4 sem HRV/sono em 5 ou mais dos últimos 7 dias → sugestão 'Use o relógio à noite'",
    arguments: nightDataCases
)
func ca53WearWatchAtNight(nightsWithData: Int, expectsSuggestion: Bool) {
    // Noites com dado nos primeiros `nightsWithData` dias; o resto só tem FC de repouso (não conta).
    let recovery = (0..<7).map { daysAgo in
        daysAgo < nightsWithData
            ? DailyRecoverySample(day: day(daysAgo), hrvSDNN: 60, sleepHours: 7.5)
            : DailyRecoverySample(day: day(daysAgo), restingHeartRate: 55)
    }
    let found = suggestion(.wearWatchAtNight, in: suggestions(recovery: recovery, workouts: weekDone))
    #expect((found != nil) == expectsSuggestion)
    if let found {
        #expect(found.title == "Use o relógio à noite")
        #expect(found.detail.contains("Use o relógio para dormir: ele mede HRV, FC de repouso e sono"))
        #expect(found.referenceTopic == "topic.hrv")
    }
}

@Test("CA5-3 A4 texto traz o número de noites com dado")
func wearWatchTextHasNumbers() {
    let none = suggestion(.wearWatchAtNight, in: suggestions(recovery: []))
    #expect(none?.detail.hasPrefix("Nenhum dos últimos 7 dias tem HRV ou sono registrados.") == true)

    let one = suggestion(.wearWatchAtNight, in: suggestions(recovery: [DailyRecoverySample(day: day(0), sleepHours: 7)]))
    #expect(one?.detail.hasPrefix("Só 1 dos últimos 7 dias tem HRV ou sono registrados.") == true)

    let two = suggestion(
        .wearWatchAtNight,
        in: suggestions(recovery: [
            DailyRecoverySample(day: day(0), sleepHours: 7),
            DailyRecoverySample(day: day(4), hrvSDNN: 50),
        ])
    )
    #expect(two?.detail.hasPrefix("Só 2 dos últimos 7 dias têm HRV ou sono registrados.") == true)
}

// MARK: - CA5-4 (A3): atualizar o VO2max

@Test("CA5-4 A3 sem nenhuma estimativa de VO2max (relógio que nunca enviou ao Saúde) → sem sugestão")
func ca54NoVo2Max() {
    // Onda A2: relógio sem nenhuma estimativa na janela de leitura nunca recebe a sugestão, porque
    // não há como saber se ele algum dia enviaria VO2max ao Saúde.
    #expect(suggestion(.updateVo2Max, in: suggestions(vo2Max: [], workouts: weekDone)) == nil)
}

@Test("CA5-4 A3 última estimativa com mais de 60 dias → sugestão com a idade da estimativa")
func ca54StaleVo2Max() throws {
    let stale = [Vo2MaxSample(date: day(61), value: 42.5)]
    let found = try #require(suggestion(.updateVo2Max, in: suggestions(vo2Max: stale, workouts: weekDone)))
    #expect(found.title == "Atualize seu VO2max")
    #expect(found.detail.hasPrefix("Sua última estimativa de VO2max (42,5 mL/kg/min) tem 61 dias."))
    #expect(found.detail.contains("20 min de caminhada rápida ou corrida ao ar livre"))
    #expect(found.detail.contains("com o seu relógio"))
    #expect(found.referenceTopic == "topic.vo2max")
}

@Test("CA5-4 A3 estimativa nos últimos 60 dias → sem sugestão")
func ca54RecentVo2Max() {
    #expect(suggestion(.updateVo2Max, in: suggestions(vo2Max: [Vo2MaxSample(date: day(59), value: 40)])) == nil)
    #expect(suggestion(.updateVo2Max, in: suggestions(vo2Max: [Vo2MaxSample(date: day(0), value: 40)])) == nil)
}

@Test("CA5-4 A3 (onda A2) só sugere com estimativa na janela de leitura de 180 dias")
func ca54ReadingWindowGatesSuggestion() {
    // Estimativa desatualizada mas ainda dentro dos 180 dias de leitura: sugere. (170, não 180, para
    // não depender da hora exata do corte; a fronteira exata é `ca54ReadingWindowBoundary`, abaixo.)
    #expect(suggestion(.updateVo2Max, in: suggestions(vo2Max: [Vo2MaxSample(date: day(170), value: 40)])) != nil)
    // Fora da janela de leitura (relógio provavelmente não envia VO2max ao Saúde): nunca sugere.
    #expect(suggestion(.updateVo2Max, in: suggestions(vo2Max: [Vo2MaxSample(date: day(190), value: 40)])) == nil)
    #expect(suggestion(.updateVo2Max, in: suggestions(vo2Max: [Vo2MaxSample(date: day(365), value: 40)])) == nil)
}

@Test("CA5-4 A3 (onda A2) fronteira exata: 180 dias atrás ainda entra na janela; 1 min a mais, não")
func ca54ReadingWindowBoundary() throws {
    // "Agora" = 2024-01-03 12:00 UTC (`wednesdayNoon`); 180 dias antes = 2023-07-07 12:00.
    let atBoundary = try #require(
        suggestion(.updateVo2Max, in: suggestions(vo2Max: [Vo2MaxSample(date: at(2023, 7, 7, 12), value: 40)]))
    )
    #expect(atBoundary.detail.hasPrefix("Sua última estimativa de VO2max (40 mL/kg/min)"))
    #expect(suggestion(
        .updateVo2Max,
        in: suggestions(vo2Max: [Vo2MaxSample(date: at(2023, 7, 7, 11, 59), value: 40)])
    ) == nil)
}

// MARK: - A2: déficit aeróbico

@Test(
    "A2 sugestão de completar o aeróbico só quando faltam ≥ 20 min moderados-equivalentes",
    arguments: aerobicDeficitCases
)
func aerobicDeficitThreshold(done: Double, expectsSuggestion: Bool) {
    let workouts = done > 0 ? [walk(minutes: done)] : []
    let found = suggestion(.aerobicDeficit, in: suggestions(workouts: workouts))
    #expect((found != nil) == expectsSuggestion)
}

@Test("A2 texto: minutos que faltam, feitos, dias restantes (contando hoje) e minutos por dia")
func aerobicDeficitNumbers() throws {
    let found = try #require(suggestion(.aerobicDeficit, in: suggestions(workouts: [walk(minutes: 70)])))
    #expect(found.title == "Complete o aeróbico da semana")
    #expect(found.detail.hasPrefix(
        "Faltam 80 min moderados-equivalentes para a meta de 150 min desta semana (feitos: 70). "
            + "Restam 5 dias, contando hoje: cerca de 16 min por dia."
    ))
    #expect(found.referenceTopic == "topic.aerobic")
}

@Test("A2 no domingo é o último dia da semana")
func aerobicDeficitOnSunday() throws {
    let found = try #require(suggestion(.aerobicDeficit, in: suggestions(now: at(2024, 1, 7, 10))))
    #expect(found.detail.contains("(feitos: 0). Hoje é o último dia da semana."))
}

@Test("A2 na segunda-feira restam 7 dias")
func aerobicDeficitOnMonday() throws {
    let found = try #require(suggestion(.aerobicDeficit, in: suggestions(now: at(2024, 1, 1, 6))))
    #expect(found.detail.contains("Restam 7 dias, contando hoje: cerca de 22 min por dia."))
}

// MARK: - CA5-5 (A5): encaixe longe do treino de pernas

@Test(
    "CA5-5 A5 treino de inferior terminado há menos de 24 h → hoje só baixo impacto leve, nunca vigoroso",
    arguments: recentLowerBodyHours
)
func ca55NoVigorousWithin24hAfterLegs(hoursAgo: Double) throws {
    let end = wednesdayNoon.addingTimeInterval(-hoursAgo * 3_600)
    let legs = session([.quads, .glutes], start: end.addingTimeInterval(-3_600), end: end)

    #expect(AerobicPlacement.today(sessions: [legs], now: wednesdayNoon) == .lowImpactOnly(hoursSinceLowerBody: hoursAgo))
    let found = try #require(suggestion(.aerobicDeficit, in: suggestions(sessions: [legs])))
    #expect(found.detail.contains("hoje prefira caminhada ou bicicleta leve, de baixo impacto, em vez de corrida ou HIIT"))
    #expect(!found.detail.contains("Hoje pode ser vigoroso"))
}

@Test("CA5-5 A5 no mesmo dia do treino de pernas: pelo menos 6 h de intervalo")
func ca55SameDaySixHourGap() throws {
    let legs = session([.hamstrings], start: at(2024, 1, 3, 9), end: at(2024, 1, 3, 10))
    let found = try #require(suggestion(.aerobicDeficit, in: suggestions(sessions: [legs])))
    #expect(found.detail.contains("Seu último treino de pernas foi há 2 horas"))
    #expect(found.detail.contains("Deixe pelo menos 6 h depois do treino de pernas (faltam cerca de 4 horas)."))
}

@Test("CA5-5 A5 treino de pernas de ontem à noite: sem aviso de 6 h, mas ainda sem vigoroso")
func ca55YesterdayEvening() throws {
    let legs = session([.quads], start: at(2024, 1, 2, 18), end: at(2024, 1, 2, 19))
    let found = try #require(suggestion(.aerobicDeficit, in: suggestions(sessions: [legs])))
    #expect(found.detail.contains("Seu último treino de pernas foi há 17 horas"))
    #expect(!found.detail.contains("Deixe pelo menos 6 h"))
    #expect(!found.detail.contains("Hoje pode ser vigoroso"))
}

@Test("CA5-5 A5 treino de pernas em andamento conta desde o início, com menos de 1 hora")
func ca55InProgressLegSession() throws {
    let legs = session([.glutes], start: at(2024, 1, 3, 11, 30), end: nil, status: .inProgress)
    let found = try #require(suggestion(.aerobicDeficit, in: suggestions(sessions: [legs])))
    #expect(found.detail.contains("Seu último treino de pernas foi há menos de 1 hora"))
    #expect(found.detail.contains("faltam cerca de 6 horas"))
}

@Test(
    "CA5-5 A5 sem treino de inferior nas últimas 24 h → hoje pode ser vigoroso",
    arguments: noRecentLowerBodyHours
)
func ca55VigorousAllowedAfter24h(hoursAgo: Double) throws {
    let end = wednesdayNoon.addingTimeInterval(-hoursAgo * 3_600)
    let legs = session([.quads], start: end.addingTimeInterval(-3_600), end: end)
    #expect(AerobicPlacement.today(sessions: [legs], now: wednesdayNoon) == .vigorousAllowed)
    let found = try #require(suggestion(.aerobicDeficit, in: suggestions(sessions: [legs])))
    #expect(found.detail.contains("Hoje pode ser vigoroso"))
    #expect(found.detail.contains("se amanhã não for dia de treino de pernas"))
}

@Test("CA5-5 A5 o texto sempre lembra: nada vigoroso na véspera nem no dia do treino de pernas")
func ca55GeneralRuleAlwaysPresent() throws {
    let cases: [[SessionSummary]] = [
        [],
        [session([.quads], start: at(2024, 1, 3, 9), end: at(2024, 1, 3, 10))],
        [session([.chest], start: at(2024, 1, 3, 9), end: at(2024, 1, 3, 10))],
    ]
    for sessions in cases {
        let found = try #require(suggestion(.aerobicDeficit, in: suggestions(sessions: sessions)))
        #expect(found.detail.hasSuffix(
            "Regra geral: nada de aeróbico vigoroso na véspera ou no dia do treino de pernas; no dia das pernas, "
                + "só caminhada ou bicicleta leve, com pelo menos 6 h de intervalo."
        ))
    }
}

@Test("A5 vale o treino de inferior mais recente, mesmo que depois dele tenha havido um de superior")
func mostRecentLowerBodyCounts() {
    let legs = session([.quads], start: at(2024, 1, 2, 20), end: at(2024, 1, 2, 21))
    let upper = session([.chest, .back], start: at(2024, 1, 3, 10), end: at(2024, 1, 3, 11))
    #expect(AerobicPlacement.today(sessions: [upper, legs], now: wednesdayNoon) == .lowImpactOnly(hoursSinceLowerBody: 15))
}

private let lowerBodyCases: [(Set<MuscleGroup>, Bool)] = [
    ([.quads], true),
    ([.hamstrings], true),
    ([.glutes], true),
    ([.calves], true),
    ([.core], false),
    ([.chest, .back, .shoulders, .biceps, .triceps, .core], false),
    ([.chest, .calves], true),
]

@Test(
    "A5 treino de inferior = quadríceps, posteriores, glúteos ou panturrilhas como primário",
    arguments: lowerBodyCases
)
func lowerBodyDefinition(muscles: Set<MuscleGroup>, isLower: Bool) {
    let recent = session(muscles, start: at(2024, 1, 3, 8), end: at(2024, 1, 3, 9))
    #expect(AerobicPlacement.isLowerBody(recent) == isLower)
    let placement = AerobicPlacement.today(sessions: [recent], now: wednesdayNoon)
    #expect((placement != .vigorousAllowed) == isLower)
}

@Test("A5 sessão com início depois de now é ignorada")
func futureSessionIgnored() {
    let tomorrow = session([.quads], start: at(2024, 1, 4, 9), end: at(2024, 1, 4, 10))
    #expect(AerobicPlacement.today(sessions: [tomorrow], now: wednesdayNoon) == .vigorousAllowed)
}

// MARK: - A4: sono e alerta de recuperação

@Test("A4 sono médio abaixo da meta → sugestão com a média e a meta")
func lowSleepSuggestion() throws {
    let recovery = (0..<7).map {
        DailyRecoverySample(day: day($0), hrvSDNN: 60, sleepHours: $0.isMultiple(of: 2) ? 6 : 6.5)
    }
    let found = try #require(suggestion(.lowSleep, in: suggestions(recovery: recovery, workouts: weekDone)))
    // (4 × 6 + 3 × 6,5) / 7 = 6,21 → "6,2"
    #expect(found.title == "Durma mais")
    #expect(found.detail.hasPrefix("Sua média de sono nos últimos 7 dias foi de 6,2 h, abaixo da meta de 7 h."))
    #expect(found.referenceTopic == "topic.sleep")
}

@Test("A4 queda de HRV → alerta de recuperação com os números e sem mexer na musculação (P12)")
func recoveryAlertHrv() throws {
    let recovery = (0..<7).map { DailyRecoverySample(day: day($0), hrvSDNN: 54, sleepHours: 7.5) }
        + (7..<14).map { DailyRecoverySample(day: day($0), hrvSDNN: 66) }
    let found = try #require(suggestion(.recoveryAlert, in: suggestions(recovery: recovery, workouts: weekDone)))
    #expect(found.title == "Recuperação abaixo do normal")
    #expect(found.detail.hasPrefix("Sua HRV média dos últimos 7 dias (54 ms) está 10 % abaixo da média de 28 dias (60 ms)."))
    #expect(found.detail.contains("faça um dia mais leve no aeróbico"))
    #expect(found.detail.contains("A musculação segue a prescrição normal: o app não muda carga por HRV nem por FC."))
    #expect(found.referenceTopic == "topic.hrv")
}

@Test("A4 alta da FC de repouso → alerta de recuperação com os números")
func recoveryAlertRestingHeartRate() throws {
    let recovery = (0..<7).map { DailyRecoverySample(day: day($0), restingHeartRate: 65, sleepHours: 7.5) }
        + (7..<14).map { DailyRecoverySample(day: day($0), restingHeartRate: 55) }
    let found = try #require(suggestion(.recoveryAlert, in: suggestions(recovery: recovery, workouts: weekDone)))
    #expect(found.detail.hasPrefix(
        "Sua FC de repouso média dos últimos 7 dias (65 bpm) está 5 bpm acima da média de 28 dias (60 bpm)."
    ))
}

@Test("A4 só sono baixo não vira alerta de recuperação (tem sugestão própria)")
func lowSleepAloneIsNotRecoveryAlert() {
    let recovery = (0..<7).map { DailyRecoverySample(day: day($0), hrvSDNN: 60, sleepHours: 5) }
    let list = suggestions(recovery: recovery, workouts: weekDone)
    #expect(list.map(\.kind) == [.lowSleep])
}

// MARK: - Passos

@Test("Passos abaixo da meta → sugestão com a média, a meta e quanto falta")
func lowStepsSuggestion() throws {
    let steps = (1...7).map { DailyStepCount(day: day($0), steps: 5_000) }
    let found = try #require(suggestion(.lowSteps, in: suggestions(steps: steps, workouts: weekDone)))
    #expect(found.title == "Caminhe mais")
    #expect(found.detail.hasPrefix(
        "Sua média nos últimos 7 dias foi de 5.000 passos por dia, abaixo da meta de 7.000. "
            + "Faltam cerca de 2.000 passos por dia"
    ))
    #expect(found.referenceTopic == "topic.steps")
}

@Test("Passos na meta ou sem registro → sem sugestão")
func noLowStepsSuggestion() {
    let atTarget = (1...7).map { DailyStepCount(day: day($0), steps: 7_000) }
    #expect(suggestion(.lowSteps, in: suggestions(steps: atTarget)) == nil)
    #expect(suggestion(.lowSteps, in: suggestions(steps: [])) == nil)
}

// MARK: - Texto pt-BR

@Test("HealthText: milhar com ponto, decimal com vírgula e sem ',0'")
func healthTextFormatting() {
    #expect(HealthText.integer(0) == "0")
    #expect(HealthText.integer(999) == "999")
    #expect(HealthText.integer(1_000) == "1.000")
    #expect(HealthText.integer(1_234_567) == "1.234.567")
    #expect(HealthText.integer(-1_500) == "-1.500")
    #expect(HealthText.decimal(7) == "7")
    #expect(HealthText.decimal(6.25) == "6,3")
    #expect(HealthText.decimal(42.04) == "42")
    #expect(HealthText.decimal(0.05) == "0,1")
    #expect(HealthText.decimal(-2.5) == "-2,5")
    #expect(HealthText.decimal(1_234.5) == "1.234,5")
    #expect(HealthText.decimal(.nan) == "0")
    #expect(HealthText.count(1, singular: "dia", plural: "dias") == "1 dia")
    #expect(HealthText.count(3, singular: "dia", plural: "dias") == "3 dias")
}
