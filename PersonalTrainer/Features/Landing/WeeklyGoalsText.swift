import Foundation
import TrainerCore

/// Textos pt-BR da tela "Metas da semana" (SPEC RF-52, §7.16; DESIGN §9.2): o nome de cada meta e o
/// número em palavras. Nunca porcentagem, nunca "faltam", nunca frase de efeito (decisão 20, W6).
enum WeeklyGoalsText {
    private static let locale = Locale(identifier: "pt_BR")

    /// "Hipertrofia" (sessões, pelo objetivo do plano), "Músculos", "Aeróbico", "Passos", "Sono",
    /// "Equilíbrio", "Mobilidade".
    static func title(_ goal: WeeklyGoal) -> String {
        switch goal.kind {
        case .planSessions:
            return goal.planGoal?.displayName ?? "Sessões"
        case .muscles:
            return "Músculos"
        case .aerobic:
            return "Aeróbico"
        case .steps:
            return "Passos"
        case .sleep:
            return "Sono"
        case .balance:
            return "Equilíbrio"
        case .mobility:
            return "Mobilidade"
        }
    }

    /// "3 de 4 sessões", "6 de 10 grupos 2 vezes", "95 de 150 min", "média de 6.200 por dia",
    /// "média de 7 h 20 min", "Feito nesta semana" / "Ainda não marcado nesta semana", ou
    /// "sem dados" quando `!goal.hasData` (W4).
    static func valueText(_ goal: WeeklyGoal) -> String {
        guard goal.hasData, let done = goal.done else {
            return "sem dados"
        }
        switch goal.kind {
        case .planSessions:
            return "\(wholeNumber(done)) de \(wholeNumber(goal.target)) sessões"
        case .muscles:
            return "\(wholeNumber(done)) de \(wholeNumber(goal.target)) grupos 2 vezes"
        case .aerobic:
            return "\(wholeNumber(done)) de \(wholeNumber(goal.target)) min"
        case .steps:
            return "média de \(integer(wholeNumber(done))) por dia"
        case .sleep:
            return "média de \(hoursAndMinutes(done))"
        case .balance, .mobility:
            return done >= 1 ? "Feito nesta semana" : "Ainda não marcado nesta semana"
        }
    }

    /// "Peito 1 de 2", para a grade de grupos musculares embaixo da meta agregada (DESIGN §9.2).
    /// Mesmos nomes de `WeeklyFrequencyCard.muscleName` (docs/V23-UI-CONTRACT.md §4.3): repetidos
    /// aqui (não chamados por lá) porque `WeeklyFrequencyCard` é `@MainActor` (é uma `View`) e este
    /// tipo precisa continuar puro e testável sem o ator principal, como o `Format` do Saúde.
    static func muscleDetailText(_ entry: WeeklyFrequencyEntry) -> String {
        "\(muscleName(entry.muscle)) \(entry.completed) de \(entry.target)"
    }

    /// Nomes dos grupos em pt-BR (SPEC §7.4), os mesmos do antigo painel do Histórico.
    static func muscleName(_ muscle: MuscleGroup) -> String {
        switch muscle {
        case .chest: return "Peito"
        case .back: return "Costas"
        case .shoulders: return "Ombros"
        case .biceps: return "Bíceps"
        case .triceps: return "Tríceps"
        case .quads: return "Quadríceps"
        case .hamstrings: return "Posteriores"
        case .glutes: return "Glúteos"
        case .calves: return "Panturrilhas"
        case .core: return "Core"
        }
    }

    /// "Hipertrofia: 3 de 4 sessões nesta semana", para o VoiceOver de uma linha (RF-52 ponto 6). Com a
    /// meta cumprida, acrescenta ", meta cumprida" (o "✓" da tela); só o fato, nenhum elogio (W6).
    static func accessibilityText(_ goal: WeeklyGoal) -> String {
        var text = "\(title(goal)): \(valueText(goal))"
        guard goal.hasData else {
            return text
        }
        switch goal.kind {
        case .planSessions, .muscles, .aerobic:
            text += " nesta semana"
        case .steps, .sleep, .balance, .mobility:
            // Passos e sono já dizem "média"; equilíbrio e mobilidade já dizem "nesta semana".
            break
        }
        if goal.isMet && goal.kind != .balance && goal.kind != .mobility {
            text += ", meta cumprida"
        }
        return text
    }

    // MARK: - Privado

    private static func wholeNumber(_ value: Double) -> Int {
        Int(value.rounded())
    }

    /// "6.200": separador de milhar pt-BR, sem casas decimais.
    private static func integer(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// "7 h 20 min": horas cheias e minutos com dois dígitos (mesmo padrão de `DateFormatting.duration`).
    private static func hoursAndMinutes(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let wholeHours = max(0, totalMinutes) / 60
        let minutes = max(0, totalMinutes) % 60
        let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        return "\(wholeHours) h \(paddedMinutes) min"
    }
}
