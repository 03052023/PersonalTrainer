import Foundation

/// Aritmética de dias do painel de saúde. Tudo passa pelo `Calendar` recebido (fuso do usuário),
/// nunca por múltiplos de 86 400 s, para que dias com mudança de horário de verão continuem
/// começando à 00:00 local (mesma abordagem de `WeeklyFrequency`).
enum HealthDays {
    /// `date` deslocada `days` dias de calendário. `Calendar.date(byAdding:)` só falha com entradas
    /// absurdas; nesse caso cai para segundos em vez de travar.
    static func adding(_ days: Int, to date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)
            ?? date.addingTimeInterval(TimeInterval(days) * 86_400)
    }

    /// Quantos dias de calendário vão do dia de `from` até o dia de `to` (positivo se `to` é depois).
    /// Ex.: de domingo 23:59 até segunda 00:01 é 1 dia; de segunda 00:01 até segunda 23:59 é 0.
    static func daysBetween(_ from: Date, _ to: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        if let days = calendar.dateComponents([.day], from: start, to: end).day {
            return days
        }
        return HealthMath.roundedInt(end.timeIntervalSince(start) / 86_400)
    }
}
