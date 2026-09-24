import Foundation

/// Sugestões do painel de saúde (SPEC §7.10 A3–A6, RF-28..RF-30). Regras fixas, texto fixo em pt-BR
/// com o motivo e os números; ordem fixa de `HealthSuggestionKind.allCases`, no máximo uma por tipo.
/// Nenhuma sugestão mexe na musculação (P12).
enum HealthSuggestions {
    /// A4: "sem dado noturno em ≥ 5 dos últimos 7 dias" = menos de 3 noites com HRV ou sono.
    static let minimumNightsWithData = 3
    /// Só sugere completar o aeróbico quando faltam pelo menos estes minutos moderados-equivalentes.
    static let minimumAerobicDeficit = 20

    /// Identificadores estáveis (usados pela UI para "ok, entendi").
    static func id(for kind: HealthSuggestionKind) -> String {
        switch kind {
        case .wearWatchAtNight: return "wear-watch-at-night"
        case .updateVo2Max: return "update-vo2max"
        case .aerobicDeficit: return "aerobic-deficit"
        case .lowSleep: return "low-sleep"
        case .recoveryAlert: return "recovery-alert"
        case .lowSteps: return "low-steps"
        }
    }

    /// Tópico do catálogo de referências para o botão "Por quê?" de cada tipo.
    static func referenceTopic(for kind: HealthSuggestionKind) -> String {
        switch kind {
        case .wearWatchAtNight: return "topic.hrv"
        case .updateVo2Max: return "topic.vo2max"
        case .aerobicDeficit: return "topic.aerobic"
        case .lowSleep: return "topic.sleep"
        case .recoveryAlert: return "topic.hrv"
        case .lowSteps: return "topic.steps"
        }
    }

    static func make(
        aerobic: AerobicWeekSummary,
        vo2MaxSamples: [Vo2MaxSample],
        recovery: RecoverySummary,
        steps: StepsSummary,
        targets: HealthTargets,
        recentSessions: [SessionSummary],
        week: DateInterval,
        now: Date,
        calendar: Calendar
    ) -> [HealthSuggestion] {
        var result: [HealthSuggestion] = []
        for kind in HealthSuggestionKind.allCases {
            let text: (title: String, detail: String)?
            switch kind {
            case .wearWatchAtNight:
                text = wearWatchAtNight(recovery: recovery)
            case .updateVo2Max:
                text = updateVo2Max(samples: vo2MaxSamples, now: now, calendar: calendar)
            case .aerobicDeficit:
                text = aerobicDeficit(
                    aerobic: aerobic,
                    placement: AerobicPlacement.today(sessions: recentSessions, now: now),
                    week: week,
                    now: now,
                    calendar: calendar
                )
            case .lowSleep:
                text = lowSleep(recovery: recovery, target: targets.sleepHours)
            case .recoveryAlert:
                text = recoveryAlert(recovery: recovery)
            case .lowSteps:
                text = lowSteps(steps: steps)
            }
            if let text {
                result.append(
                    HealthSuggestion(
                        id: id(for: kind),
                        kind: kind,
                        title: text.title,
                        detail: text.detail,
                        referenceTopic: referenceTopic(for: kind)
                    )
                )
            }
        }
        return result
    }

    // MARK: - A4: dados noturnos

    static func wearWatchAtNight(recovery: RecoverySummary) -> (title: String, detail: String)? {
        let nights = recovery.nightsWithData7
        guard nights < minimumNightsWithData else { return nil }
        let reason: String
        switch nights {
        case ...0: reason = "Nenhum dos últimos 7 dias tem HRV ou sono registrados."
        case 1: reason = "Só 1 dos últimos 7 dias tem HRV ou sono registrados."
        default: reason = "Só \(nights) dos últimos 7 dias têm HRV ou sono registrados."
        }
        return (
            "Use o relógio à noite",
            reason + " Use o relógio para dormir: ele mede HRV, FC de repouso e sono, que o app usa "
                + "para acompanhar sua recuperação e na revisão periódica."
        )
    }

    // MARK: - A3: VO2max desatualizado

    /// Janela de leitura do HealthKit para VO2max (igual a `HealthInput.vo2Max`, SPEC A3). Sem
    /// nenhuma estimativa aqui, o relógio do usuário provavelmente não envia VO2max ao Saúde, então
    /// a sugestão de atualizar nunca aparece — só quem já teve alguma estimativa a recebe.
    static let vo2MaxReadingWindowDays = 180

    /// Só sugere quando há estimativa desatualizada (> 60 dias, `Vo2MaxTrend.isStale`) **e** ao menos
    /// uma estimativa na janela de leitura de 180 dias: quem usa um relógio que nunca enviou VO2max
    /// ao Saúde não tem o que "atualizar", então nunca recebe esta sugestão.
    static func updateVo2Max(
        samples: [Vo2MaxSample],
        now: Date,
        calendar: Calendar
    ) -> (title: String, detail: String)? {
        // `latest` é a amostra válida mais recente: se ela já está fora da janela de leitura,
        // nenhuma outra amostra (todas mais antigas) estaria dentro, então basta checar `latest`.
        guard Vo2MaxTrend.isStale(samples: samples, now: now, calendar: calendar),
              let latest = Vo2MaxTrend.validSamples(samples, now: now).last
        else { return nil }
        let readingWindowStart = HealthDays.adding(-vo2MaxReadingWindowDays, to: now, calendar: calendar)
        guard latest.date >= readingWindowStart else { return nil }

        let days = HealthDays.daysBetween(latest.date, now, calendar: calendar)
        let reason = "Sua última estimativa de VO2max (\(HealthText.decimal(latest.value)) mL/kg/min) "
            + "tem \(HealthText.count(days, singular: "dia", plural: "dias"))."
        return (
            "Atualize seu VO2max",
            reason + " Faça 20 min de caminhada rápida ou corrida ao ar livre com o seu relógio para "
                + "ele atualizar a estimativa."
        )
    }

    // MARK: - A2 + A5: completar a meta sem atrapalhar o treino de pernas

    static func aerobicDeficit(
        aerobic: AerobicWeekSummary,
        placement: AerobicPlacement,
        week: DateInterval,
        now: Date,
        calendar: Calendar
    ) -> (title: String, detail: String)? {
        let remaining = aerobic.target - aerobic.moderateEquivalentMinutes
        guard remaining >= minimumAerobicDeficit else { return nil }
        // Dias que ainda restam na semana, contando hoje (segunda → 7, domingo → 1).
        let daysLeft = max(1, HealthDays.daysBetween(now, week.end, calendar: calendar))
        let perDay = (remaining + daysLeft - 1) / daysLeft

        var sentences = [
            "Faltam \(HealthText.integer(remaining)) min moderados-equivalentes para a meta de "
                + "\(HealthText.integer(aerobic.target)) min desta semana "
                + "(feitos: \(HealthText.integer(aerobic.moderateEquivalentMinutes)))."
        ]
        if daysLeft == 1 {
            sentences.append("Hoje é o último dia da semana.")
        } else {
            sentences.append(
                "Restam \(daysLeft) dias, contando hoje: cerca de \(HealthText.integer(perDay)) min por dia."
            )
        }

        switch placement {
        case .vigorousAllowed:
            sentences.append(
                "Hoje pode ser vigoroso, como corrida ou HIIT (1 min vigoroso vale 2 moderados), se amanhã "
                    + "não for dia de treino de pernas."
            )
        case .lowImpactOnly(let hours):
            // `hours` está em [0, 24): a conversão para Int é segura.
            let elapsed = Int(hours.rounded(.down))
            let when = elapsed < 1
                ? "há menos de 1 hora"
                : "há \(HealthText.count(elapsed, singular: "hora", plural: "horas"))"
            sentences.append(
                "Seu último treino de pernas foi \(when): "
                    + "hoje prefira caminhada ou bicicleta leve, de baixo impacto, em vez de corrida ou HIIT."
            )
            if hours < AerobicPlacement.sameDayGapHours {
                let wait = max(1, Int((AerobicPlacement.sameDayGapHours - hours).rounded(.up)))
                sentences.append(
                    "Deixe pelo menos 6 h depois do treino de pernas "
                        + "(faltam cerca de \(HealthText.count(wait, singular: "hora", plural: "horas")))."
                )
            }
        }
        sentences.append(
            "Regra geral: nada de aeróbico vigoroso na véspera ou no dia do treino de pernas; no dia das "
                + "pernas, só caminhada ou bicicleta leve, com pelo menos 6 h de intervalo."
        )
        return ("Complete o aeróbico da semana", sentences.joined(separator: " "))
    }

    // MARK: - A4: sono

    static func lowSleep(recovery: RecoverySummary, target: Double) -> (title: String, detail: String)? {
        guard recovery.alerts.contains(.lowSleep), let sleep7 = recovery.sleep7 else { return nil }
        return (
            "Durma mais",
            "Sua média de sono nos últimos 7 dias foi de \(HealthText.decimal(sleep7)) h, abaixo da meta de "
                + "\(HealthText.decimal(target)) h. O recomendado para adultos é de 7 a 9 h por noite."
        )
    }

    // MARK: - A4: alerta de recuperação

    static func recoveryAlert(recovery: RecoverySummary) -> (title: String, detail: String)? {
        var sentences: [String] = []
        if recovery.alerts.contains(.hrvDrop), let hrv7 = recovery.hrv7, let hrv28 = recovery.hrv28, hrv28 > 0 {
            let drop = HealthMath.roundedInt((1 - hrv7 / hrv28) * 100)
            sentences.append(
                "Sua HRV média dos últimos 7 dias (\(HealthText.decimal(hrv7)) ms) está \(drop) % abaixo da "
                    + "média de 28 dias (\(HealthText.decimal(hrv28)) ms)."
            )
        }
        if recovery.alerts.contains(.restingHeartRateRise),
           let resting7 = recovery.restingHR7,
           let resting28 = recovery.restingHR28 {
            sentences.append(
                "Sua FC de repouso média dos últimos 7 dias (\(HealthText.decimal(resting7)) bpm) está "
                    + "\(HealthText.decimal(resting7 - resting28)) bpm acima da média de 28 dias "
                    + "(\(HealthText.decimal(resting28)) bpm)."
            )
        }
        guard !sentences.isEmpty else { return nil }
        sentences.append(
            "Se puder, faça um dia mais leve no aeróbico e cuide do sono. A musculação segue a prescrição "
                + "normal: o app não muda carga por HRV nem por FC."
        )
        return ("Recuperação abaixo do normal", sentences.joined(separator: " "))
    }

    // MARK: - Passos

    static func lowSteps(steps: StepsSummary) -> (title: String, detail: String)? {
        guard let average = steps.average7, average < steps.target else { return nil }
        return (
            "Caminhe mais",
            "Sua média nos últimos 7 dias foi de \(HealthText.integer(average)) passos por dia, abaixo da meta de "
                + "\(HealthText.integer(steps.target)). Faltam cerca de \(HealthText.integer(steps.target - average)) "
                + "passos por dia; caminhadas curtas ao longo do dia ajudam."
        )
    }
}
