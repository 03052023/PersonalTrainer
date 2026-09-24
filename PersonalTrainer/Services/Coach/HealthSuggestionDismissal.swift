import Foundation
import TrainerCore

/// Se uma sugestão de saúde está dispensada agora, e a entrada que dispensa uma (SPEC §7.11 C3).
///
/// A fonte única é o `CoachLog` (V21-CONTRACT B3, A4/B8: "dispensar uma sugestão de saúde no feed
/// também a esconde no detalhe de Saúde"). O feed do diálogo (`CoachFeedBuilder`, TrainerCore) e a
/// tela de Saúde (`HealthViewModel`) chamam a mesma regra sobre o mesmo log — gravado por
/// `CoachService` ou por `HealthViewModel.dismiss(_:)` —, então dispensar em qualquer um dos dois
/// esconde no outro, nos dois sentidos.
///
/// A lógica de prazo espelha a de `CoachFeedBuilder+Rules.healthMessages` (TrainerCore), que não é
/// `public`; os números vêm de SPEC §7.11 C3 ("no máximo 1 por tipo a cada 3 dias" e "Lembrar
/// amanhã", que volta no dia seguinte).
enum HealthSuggestionDismissal {
    /// SPEC §7.11 C3: cadência padrão depois de "Entendi".
    static let cooldownDays = 3
    /// SPEC §7.11 C3: cadência depois de "Lembrar amanhã".
    static let remindTomorrowDays = 1

    /// `true` enquanto a última resposta de `kind` (regra `.health`) ainda está no prazo de
    /// espera. Uma resposta datada depois de `now` (relógio dessincronizado) também conta como
    /// dispensada, como em `CoachFeedBuilder`.
    static func isDismissed(_ kind: HealthSuggestionKind, log: CoachLog, now: Date, calendar: Calendar) -> Bool {
        guard let last = latestEntry(itemKey: kind.rawValue, in: log) else {
            return false
        }
        let wait = last.action == .remindTomorrow ? remindTomorrowDays : cooldownDays
        return daysBetween(last.date, now, calendar: calendar) < wait
    }

    /// A resposta mais recente à regra `.health` para este item: maior `date` e, em empate, a
    /// última gravada — mesmo critério de `CoachLog.latestEntry` (TrainerCore, não pública).
    /// `CoachLog.entries` é pública; só a busca não é, então repetimos aqui.
    private static func latestEntry(itemKey: String, in log: CoachLog) -> CoachLogEntry? {
        var latest: CoachLogEntry?
        for entry in log.entries where entry.rule == .health && entry.itemKey == itemKey {
            if let current = latest, entry.date < current.date {
                continue
            }
            latest = entry
        }
        return latest
    }

    /// A entrada que "Ok, entendi" grava no log compartilhado: mesma `rule` e `itemKey` que o
    /// feed usa para `kind`, para as duas telas lerem a mesma dispensa.
    static func entry(dismissing kind: HealthSuggestionKind, at date: Date, calendar: Calendar) -> CoachLogEntry {
        CoachLogEntry(
            messageID: "health:\(kind.rawValue):\(dayLabel(date, calendar: calendar))",
            rule: .health,
            itemKey: kind.rawValue,
            action: .understood,
            date: date
        )
    }

    /// Dias de calendário entre as datas (cópia de `HealthDays.daysBetween` do TrainerCore, que
    /// não é pública); negativo se `to` vem antes de `from`.
    private static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        if let days = calendar.dateComponents([.day], from: start, to: end).day {
            return days
        }
        return Int((end.timeIntervalSince(start) / 86_400).rounded())
    }

    /// "2026-09-23": dígitos gregorianos no fuso do calendário recebido, sem depender do locale
    /// (cópia do formato de `CoachText.day`, TrainerCore, que não é público).
    private static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = gregorian.dateComponents([.year, .month, .day], from: date)
        return "\(padded(components.year ?? 0, digits: 4))-\(padded(components.month ?? 0, digits: 2))-\(padded(components.day ?? 0, digits: 2))"
    }

    private static func padded(_ value: Int, digits: Int) -> String {
        let text = String(value.magnitude)
        let zeros = String(repeating: "0", count: max(0, digits - text.count))
        return (value < 0 ? "-" : "") + zeros + text
    }
}
