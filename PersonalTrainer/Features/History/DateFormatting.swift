import Foundation

/// Formatação pt-BR de datas e durações do histórico (SPEC F5, RF-09).
///
/// Só a View formata (AGENTS §4, "Unidades"); os modelos guardam `Date` e segundos. Os
/// textos são fixos em pt-BR, sem `Localizable.strings`, como o resto da UI.
enum DateFormatting {
    private static let locale = Locale(identifier: "pt_BR")

    /// "ter., 23 de set. · 19:40".
    ///
    /// `timeZone` existe para testes determinísticos; o app usa o fuso do aparelho
    /// (`.autoupdatingCurrent`), que é o que o usuário espera ver no histórico.
    static func shortDate(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let base = Date.FormatStyle(locale: locale, timeZone: timeZone)
        let dayText = date.formatted(base.weekday(.abbreviated).day().month(.abbreviated))
        let timeText = date.formatted(base.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return "\(dayText) · \(timeText)"
    }

    /// "1 h 05 min", "45 min". `nil` (sessão sem `endedAt`) vira "Em andamento".
    ///
    /// Minutos são truncados, não arredondados: uma sessão de 59 min 50 s mostra "59 min",
    /// coerente com o que um cronômetro mostraria.
    static func duration(_ interval: TimeInterval?) -> String {
        guard let interval else {
            return "Em andamento"
        }
        guard interval.isFinite else {
            return "—"
        }
        let totalMinutes = max(0, Int(interval / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
            return "\(hours) h \(paddedMinutes) min"
        }
        return "\(minutes) min"
    }
}
