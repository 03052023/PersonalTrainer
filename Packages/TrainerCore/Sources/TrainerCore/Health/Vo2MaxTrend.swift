import Foundation

/// VO2max estimado pelo Watch: último valor, tendência de 90 dias e faixa por idade e sexo
/// (SPEC §7.10 A3, RF-28).
///
/// - Amostras válidas: valor finito > 0 e data ≤ `now` (dado com data futura é erro de relógio).
/// - `latest` = amostra mais recente (empate de data → maior valor, para não depender da ordem).
/// - `change90Days` = `latest` − média das amostras com data em `[now − 100 dias, now − 80 dias]`;
///   `nil` sem amostras nessa janela. Os dias são de calendário (`Calendar` recebido), não 86 400 s.
/// - Faixa: `Vo2MaxNorms` (FRIEND 2015) pela idade em `now` e pelo sexo; `nil` sem um dos dois.
enum Vo2MaxTrend {
    /// Janela da comparação "90 dias atrás" (A3), em dias antes de `now`.
    static let trendWindowDays = 80...100
    /// Sem estimativa nesse prazo → sugestão de atualizar o VO2max (A3).
    static let staleAfterDays = 60

    static func validSamples(_ samples: [Vo2MaxSample], now: Date) -> [Vo2MaxSample] {
        samples
            .filter { $0.value.isFinite && $0.value > 0 && $0.date <= now }
            .sorted { lhs, rhs in
                lhs.date != rhs.date ? lhs.date < rhs.date : lhs.value < rhs.value
            }
    }

    static func summary(
        samples: [Vo2MaxSample],
        physiology: UserPhysiology,
        now: Date,
        calendar: Calendar
    ) -> Vo2MaxSummary? {
        let valid = validSamples(samples, now: now)
        guard let latest = valid.last else { return nil }

        let windowStart = HealthDays.adding(-trendWindowDays.upperBound, to: now, calendar: calendar)
        let windowEnd = HealthDays.adding(-trendWindowDays.lowerBound, to: now, calendar: calendar)
        let reference = HealthMath.mean(
            valid.filter { $0.date >= windowStart && $0.date <= windowEnd }.map(\.value)
        )

        let age = physiology.ageYears(at: now, calendar: calendar)
        var band: FitnessBand?
        if let age, let sex = physiology.sex {
            band = Vo2MaxNorms.band(vo2Max: latest.value, ageYears: age, sex: sex)
        }

        return Vo2MaxSummary(
            latest: latest.value,
            latestDate: latest.date,
            change90Days: reference.map { latest.value - $0 },
            band: band,
            ageYears: age
        )
    }

    /// `true` quando não há estimativa válida em `[now − 60 dias, now]` (A3).
    static func isStale(samples: [Vo2MaxSample], now: Date, calendar: Calendar) -> Bool {
        let cutoff = HealthDays.adding(-staleAfterDays, to: now, calendar: calendar)
        guard let latest = validSamples(samples, now: now).last else { return true }
        return latest.date < cutoff
    }
}
