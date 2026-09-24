import Foundation

/// Recuperação: HRV (SDNN), FC de repouso e sono, média dos últimos 7 vs. 28 dias (SPEC §7.10 A4,
/// RF-29). Só tendências agregadas: nada disso entra no motor de musculação (P12, AGENTS R2).
///
/// - "Últimos 7 dias" = hoje e os 6 dias anteriores no calendário recebido (a amostra de hoje traz a
///   noite que acabou de terminar); "últimos 28" = hoje e os 27 anteriores. Dias futuros são ignorados.
/// - Médias ignoram valores ausentes (`nil`, zero, negativos ou não finitos). Se o mesmo dia aparece
///   mais de uma vez, os valores do dia são promediados antes, para que um dia não pese dobrado.
/// - Alertas (A4): `hrvDrop` se hrv7 ≤ 0,9 × hrv28; `restingHeartRateRise` se FCr7 ≥ FCr28 + 5 bpm;
///   `lowSleep` se sono7 < meta. Cada alerta exige as duas médias (ou a média e a meta).
enum RecoveryTrend {
    /// Queda de HRV que dispara o alerta (A4: "quedas de HRV ≥ 10 %").
    static let hrvDropFraction = 0.10
    /// Alta de FC de repouso que dispara o alerta (A4: "alta de FC de repouso ≥ 5 bpm").
    static let restingHeartRateRiseBpm = 5.0

    static func summary(
        samples: [DailyRecoverySample],
        sleepTarget: Double,
        now: Date,
        calendar: Calendar
    ) -> RecoverySummary {
        let days = dailyValues(samples: samples, now: now, calendar: calendar)
        let last7 = days.filter { $0.daysAgo < 7 }

        let hrv7 = HealthMath.mean(last7.compactMap(\.hrv))
        let hrv28 = HealthMath.mean(days.compactMap(\.hrv))
        let resting7 = HealthMath.mean(last7.compactMap(\.resting))
        let resting28 = HealthMath.mean(days.compactMap(\.resting))
        let sleep7 = HealthMath.mean(last7.compactMap(\.sleep))
        let sleep28 = HealthMath.mean(days.compactMap(\.sleep))
        // A4 conta "dado noturno": HRV ou sono. FC de repouso sozinha não serve, porque o Watch
        // também a estima durante o dia.
        let nights = last7.filter { $0.hrv != nil || $0.sleep != nil }.count

        var alerts: [RecoveryAlert] = []
        if let hrv7, let hrv28, hrv7 <= (1 - hrvDropFraction) * hrv28 + HealthMath.epsilon {
            alerts.append(.hrvDrop)
        }
        if let resting7, let resting28, resting7 >= resting28 + restingHeartRateRiseBpm - HealthMath.epsilon {
            alerts.append(.restingHeartRateRise)
        }
        if let sleep7, sleep7 < sleepTarget - HealthMath.epsilon {
            alerts.append(.lowSleep)
        }

        return RecoverySummary(
            hrv7: hrv7,
            hrv28: hrv28,
            restingHR7: resting7,
            restingHR28: resting28,
            sleep7: sleep7,
            sleep28: sleep28,
            nightsWithData7: nights,
            alerts: alerts
        )
    }

    /// Valores válidos de um dia da janela de 28 dias.
    struct DayValues {
        /// 0 = hoje, 27 = o dia mais antigo da janela.
        let daysAgo: Int
        let hrv: Double?
        let resting: Double?
        let sleep: Double?
    }

    /// Um registro por dia dos últimos 28 (hoje incluído), com os valores inválidos descartados.
    static func dailyValues(samples: [DailyRecoverySample], now: Date, calendar: Calendar) -> [DayValues] {
        var hrvByDay: [Int: [Double]] = [:]
        var restingByDay: [Int: [Double]] = [:]
        var sleepByDay: [Int: [Double]] = [:]
        for sample in samples {
            let daysAgo = HealthDays.daysBetween(sample.day, now, calendar: calendar)
            guard (0..<28).contains(daysAgo) else { continue }
            if let hrv = HealthMath.positive(sample.hrvSDNN) { hrvByDay[daysAgo, default: []].append(hrv) }
            if let resting = HealthMath.positive(sample.restingHeartRate) {
                restingByDay[daysAgo, default: []].append(resting)
            }
            if let sleep = HealthMath.positive(sample.sleepHours) { sleepByDay[daysAgo, default: []].append(sleep) }
        }
        return (0..<28).map { daysAgo in
            DayValues(
                daysAgo: daysAgo,
                hrv: hrvByDay[daysAgo].flatMap(HealthMath.mean),
                resting: restingByDay[daysAgo].flatMap(HealthMath.mean),
                sleep: sleepByDay[daysAgo].flatMap(HealthMath.mean)
            )
        }
    }
}
