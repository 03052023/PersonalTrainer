import Foundation

/// Ponto de entrada do painel de saúde (SPEC §7.10 A1–A6, RF-27..RF-31): uma função pura que
/// transforma o que o serviço de HealthKit já agregou em `HealthReport`.
///
/// Vive em `TrainerCore/Health`, fora de `Engine/`: FC classifica só o aeróbico e alimenta tendências
/// de recuperação, e nada daqui volta para a prescrição de musculação (SPEC §7.6, P12, AGENTS R2).
/// `now` e o `Calendar` (com o fuso do usuário) são parâmetros; nada lê o relógio (SPEC P11, R3), e a
/// mesma entrada em qualquer ordem dá o mesmo relatório (A6).
public enum HealthCalculator: Sendable {
    /// Relatório da semana que contém `now`.
    ///
    /// - Semana: `[segunda 00:00, próxima segunda)` no calendário recebido, igual a §7.4.
    /// - Zonas de FC (A1): FCmáx informada ou Tanaka pela idade em `now`; % da FC de reserva quando há
    ///   FC de repouso nos últimos 7 dias, senão % da FCmáx; sem FCmáx, intensidade padrão do tipo de treino.
    /// - Recuperação (A4): médias de 7 e 28 dias terminando hoje; passos: 7 dias completos até ontem.
    /// - Sugestões (A3–A5): ordem fixa de `HealthSuggestionKind.allCases`.
    public static func report(
        input: HealthInput,
        targets: HealthTargets,
        now: Date,
        calendar: Calendar
    ) -> HealthReport {
        let week = WeeklyFrequency.weekInterval(containing: now, weekStartsOnMonday: true, calendar: calendar)

        let recovery = RecoveryTrend.summary(
            samples: input.recovery,
            sleepTarget: targets.sleepHours,
            now: now,
            calendar: calendar
        )
        let zones = HeartRateZones.make(
            physiology: input.physiology,
            restingHeartRate: recovery.restingHR7,
            now: now,
            calendar: calendar
        )
        let aerobic = AerobicWeek.summary(
            workouts: input.aerobicWorkouts,
            zones: zones,
            week: week,
            target: targets.weeklyModerateEquivalentMinutes,
            calendar: calendar
        )
        let vo2Max = Vo2MaxTrend.summary(
            samples: input.vo2Max,
            physiology: input.physiology,
            now: now,
            calendar: calendar
        )
        let steps = StepsTrend.summary(steps: input.steps, target: targets.dailySteps, now: now, calendar: calendar)
        let suggestions = HealthSuggestions.make(
            aerobic: aerobic,
            vo2MaxSamples: input.vo2Max,
            recovery: recovery,
            steps: steps,
            targets: targets,
            recentSessions: input.recentSessions,
            week: week,
            now: now,
            calendar: calendar
        )

        return HealthReport(
            weekStart: week.start,
            aerobic: aerobic,
            vo2Max: vo2Max,
            recovery: recovery,
            steps: steps,
            suggestions: suggestions
        )
    }
}
