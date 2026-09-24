import Foundation

/// Passos: média dos últimos 7 dias **completos** (ontem e os 6 anteriores; hoje ainda está em
/// andamento e puxaria a média para baixo) contra a meta diária (SPEC §7.9 Longevidade: ≥ 7.000/dia,
/// Paluch 2022).
///
/// - Dias sem registro não entram na média. Um total ≤ 0 também é tratado como sem registro: o iPhone
///   conta passos sempre que está no bolso, então zero significa "sem aparelho", não "parado o dia todo".
/// - Se o mesmo dia aparece mais de uma vez (releitura), vale o maior total, em vez de somar em dobro.
enum StepsTrend {
    static func summary(steps: [DailyStepCount], target: Int, now: Date, calendar: Calendar) -> StepsSummary {
        var totalByDay: [Int: Int] = [:]
        for entry in steps where entry.steps > 0 {
            let daysAgo = HealthDays.daysBetween(entry.day, now, calendar: calendar)
            guard (1...7).contains(daysAgo) else { continue }
            totalByDay[daysAgo] = max(totalByDay[daysAgo] ?? 0, entry.steps)
        }
        let average = HealthMath.mean(totalByDay.values.map(Double.init)).map(HealthMath.roundedInt)
        return StepsSummary(average7: average, target: target)
    }
}
