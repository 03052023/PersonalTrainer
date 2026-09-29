import Foundation
import TrainerCore

/// Textos pt-BR da aba "Início" (SPEC RF-49; DESIGN §6, §9.1): fixos no código, sem jargão de
/// academia e sem nenhuma mensagem de efeito (decisão 20, itens 15 e 16). Formatação pura, sem
/// `Date()` nem `Locale` do sistema, para o mesmo texto sair igual no iPhone e no CI Linux (SPEC P11).
enum LandingText {
    private static let weekdayFullNames = [
        "segunda-feira", "terça-feira", "quarta-feira", "quinta-feira", "sexta-feira", "sábado", "domingo",
    ]
    private static let monthNames = [
        "janeiro", "fevereiro", "março", "abril", "maio", "junho",
        "julho", "agosto", "setembro", "outubro", "novembro", "dezembro",
    ]
    private static let monthAbbreviations = [
        "jan.", "fev.", "mar.", "abr.", "mai.", "jun.",
        "jul.", "ago.", "set.", "out.", "nov.", "dez.",
    ]

    /// "segunda-feira, 28 de setembro", no calendário e no fuso da pessoa.
    static func dateText(_ date: Date, calendar: Calendar) -> String {
        let weekday = PlanWeekday.of(date, calendar: calendar)
        let day = calendar.component(.day, from: date)
        let monthIndex = calendar.component(.month, from: date) - 1
        let month = monthNames.indices.contains(monthIndex) ? monthNames[monthIndex] : monthNames[0]
        return "\(weekdayFullNames[weekday.rawValue]), \(day) de \(month)"
    }

    /// "28 set. – 4 out.": o intervalo da semana, do primeiro ao último dia (o `weekEnd` é exclusivo,
    /// como em `WeeklyFrequencyReport`), no calendário e no fuso da pessoa (DESIGN §9.2). Feito à mão,
    /// como `dateText`, para a saída não depender do ICU do aparelho.
    static func weekRangeText(weekStart: Date, weekEnd: Date, calendar: Calendar) -> String {
        let lastDay = calendar.date(byAdding: .day, value: -1, to: weekEnd) ?? weekEnd.addingTimeInterval(-86_400)
        return "\(shortDay(weekStart, calendar: calendar)) – \(shortDay(lastDay, calendar: calendar))"
    }

    /// "28 set."
    private static func shortDay(_ date: Date, calendar: Calendar) -> String {
        let day = calendar.component(.day, from: date)
        let monthIndex = calendar.component(.month, from: date) - 1
        let month = monthAbbreviations.indices.contains(monthIndex) ? monthAbbreviations[monthIndex] : monthAbbreviations[0]
        return "\(day) \(month)"
    }

    /// "Bom dia" (5h–11h59), "Boa tarde" (12h–17h59), "Boa noite" (18h–4h59), pelo `hour` (0...23)
    /// do calendário da pessoa.
    static func greeting(hour: Int) -> String {
        switch hour {
        case 5...11:
            return "Bom dia"
        case 12...17:
            return "Boa tarde"
        default:
            return "Boa noite"
        }
    }

    /// "Hipertrofia · Cardio"; sem objetivo, o convite a escolher um (RF-49).
    static func activeGoalsText(_ goals: [ProgramGoal]) -> String {
        guard !goals.isEmpty else {
            return "Escolha um objetivo para começar"
        }
        return goals.map(\.displayName).joined(separator: " · ")
    }

    /// "2 sessões nesta semana." / "1 sessão nesta semana." / "Nenhuma sessão nesta semana ainda."
    /// Nunca meta, "faltam" ou porcentagem (RF-49).
    static func weekSentence(sessionCount: Int) -> String {
        switch sessionCount {
        case 0:
            return "Nenhuma sessão nesta semana ainda."
        case 1:
            return "1 sessão nesta semana."
        default:
            return "\(sessionCount) sessões nesta semana."
        }
    }

    /// "5 exercícios · ≈ 55 min" / "1 exercício · ≈ 10 min", para uma única sessão pendente hoje.
    static func exerciseCountSubtitle(exerciseCount: Int, estimatedMinutes: Int) -> String {
        let noun = exerciseCount == 1 ? "exercício" : "exercícios"
        return "\(exerciseCount) \(noun) · ≈ \(estimatedMinutes) min"
    }

    /// "2 sessões · ≈ 85 min", para duas sessões pendentes hoje (SPEC §7.15 M6).
    static func multipleSessionsSubtitle(count: Int, estimatedMinutes: Int) -> String {
        "\(count) sessões · ≈ \(estimatedMinutes) min"
    }

    /// Leitura do VoiceOver de "Esta semana" num elemento só (RF-49 ponto 4): "Esta semana: sessão
    /// na segunda-feira e na quarta-feira." Sem sessão nenhuma, diz que ainda não há.
    static func weekMarksAccessibilityLabel(marks: [Bool]) -> String {
        let phrases = PlanWeekday.allCases.enumerated().compactMap { index, weekday -> String? in
            guard index < marks.count, marks[index] else { return nil }
            return "\(preposition(for: weekday)) \(weekdayFullNames[index])"
        }
        guard !phrases.isEmpty else {
            return "Esta semana: nenhuma sessão ainda."
        }
        guard phrases.count > 1 else {
            return "Esta semana: sessão \(phrases[0])."
        }
        let joined = phrases.dropLast().joined(separator: ", ") + " e " + (phrases.last ?? "")
        return "Esta semana: sessão \(joined)."
    }

    /// "sábado" e "domingo" são masculinos ("no sábado"); os demais dias, femininos ("na segunda-feira").
    private static func preposition(for weekday: PlanWeekday) -> String {
        switch weekday {
        case .saturday, .sunday:
            return "no"
        default:
            return "na"
        }
    }
}
