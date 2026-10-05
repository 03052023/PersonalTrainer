import Foundation
import TrainerCore

/// Textos pt-BR das atividades fora do app (SPEC §7.17 X1, X2, X7, RF-53; DESIGN §7, §9 item 8, §9.1, §9.3):
/// as linhas de registro ("Pilates · terça · 50 min · leve"), das fixas ("Pilates · terça · 19h · 50 min"),
/// do "Também hoje" e as mensagens da folha. Só o fato e o que fazer: nada de elogio, "!" nem frase de efeito
/// (decisão 20, itens 15 e 16 do dono). Funções puras, sem `Date()` nem `Locale` do sistema (SPEC P11): o
/// calendário chega por parâmetro.
enum ActivityText {
    // MARK: - Rótulos (DESIGN §7, palavras da 2.4)

    static let sectionTitle = "Fora do app"
    static let register = "Registrar atividade"
    static let registerButton = "Registrar"
    static let saveButton = "Salvar"
    static let editTitle = "Editar atividade"
    static let fixedTitle = "Atividades fixas"
    static let newFixedTitle = "Atividade fixa"
    static let editFixedTitle = "Editar atividade fixa"
    static let addFixed = "Acrescentar atividade fixa"
    static let everyWeek = "Toda semana"
    static let alsoToday = "Também hoje"
    static let done = "Feito"
    static let doneMark = "✓ Feito"
    static let delete = "Apagar atividade"
    static let deleteShort = "Apagar"
    static let kind = "Tipo"
    static let duration = "Duração"
    static let intensity = "Intensidade"
    static let when = "Quando"
    static let day = "Dia"
    static let time = "Hora"

    // MARK: - Estados e explicações curtas

    static let nothingThisWeek = "Nada registrado nesta semana."
    static let noFixed = "Nenhuma atividade fixa."
    static let fixedFootnote = "Repetem toda semana e contam depois do “Feito” do dia."
    static let fixedLimitReached = "Você já tem 10 atividades fixas."
    /// SPEC §7.16 W4 (2.4): sem o app Saúde, o aeróbico das Metas vem só dos registros.
    static let aerobicFromActivitiesOnly = "Aeróbico só das atividades registradas no app."

    // MARK: - Confirmações

    static let deleteQuestion = "Apagar esta atividade?"
    static let deleteEntryMessage = "Ela sai das metas da semana."
    /// SPEC X2: apagar uma fixa não apaga os registros já feitos.
    static let deleteFixedMessage = "Os registros já feitos continuam."

    // MARK: - Falhas (sempre com o que fazer)

    static let errorTitle = "Não foi possível continuar"
    static let saveFailed = "Não foi possível guardar a atividade. Tente de novo."
    static let invalidMinutes = "A duração deve ficar entre 5 e 300 min."
    static let fixedLimit = "Você já tem 10 atividades fixas. Apague uma para acrescentar outra."
    static let futureEntry = "Escolha um dia e uma hora que já passaram."
    static let missingEntry = "Este registro não existe mais."
    static let missingFixed = "Esta atividade fixa não existe mais."

    // MARK: - Intensidade pelo teste da fala (SPEC §7.14 F2, X1)

    /// "Leve", "Moderada", "Forte" (a intensidade, no feminino).
    static func intensityName(_ intensity: CardioIntensity) -> String {
        switch intensity {
        case .light: return "Leve"
        case .moderate: return "Moderada"
        case .vigorous: return "Forte"
        }
    }

    /// "leve", "moderada", "forte", para o meio das linhas.
    static func intensityWord(_ intensity: CardioIntensity) -> String {
        switch intensity {
        case .light: return "leve"
        case .moderate: return "moderada"
        case .vigorous: return "forte"
        }
    }

    /// "Leve: a conversa é fácil", "Moderada: dá para conversar, mas não para cantar", "Forte: só dá para
    /// dizer poucas palavras" (DESIGN §9.3 ponto 2).
    static func talkTestLine(_ intensity: CardioIntensity) -> String {
        switch intensity {
        case .light: return "Leve: a conversa é fácil"
        case .moderate: return "Moderada: dá para conversar, mas não para cantar"
        case .vigorous: return "Forte: só dá para dizer poucas palavras"
        }
    }

    // MARK: - Números

    /// "50 min".
    static func minutesText(_ minutes: Int) -> String {
        "\(minutes) min"
    }

    /// "1 minuto", "50 minutos", para o VoiceOver.
    static func minutesSpoken(_ minutes: Int) -> String {
        minutes == 1 ? "1 minuto" : "\(minutes) minutos"
    }

    /// "19h", "19h30", "7h05", "0h" (minutos desde 00:00, limitados a 0…1439).
    static func timeText(minuteOfDay: Int) -> String {
        let minute = min(max(minuteOfDay, 0), 24 * 60 - 1)
        let hours = minute / 60
        let minutes = minute % 60
        guard minutes > 0 else {
            return "\(hours)h"
        }
        return minutes < 10 ? "\(hours)h0\(minutes)" : "\(hours)h\(minutes)"
    }

    /// Minutos desde 00:00 de `date` no calendário da pessoa.
    static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    /// "Segunda", "Terça" … "Domingo", para o seletor do dia da fixa.
    static func weekdayTitle(_ weekday: PlanWeekday) -> String {
        switch weekday {
        case .monday: return "Segunda"
        case .tuesday: return "Terça"
        case .wednesday: return "Quarta"
        case .thursday: return "Quinta"
        case .friday: return "Sexta"
        case .saturday: return "Sábado"
        case .sunday: return "Domingo"
        }
    }

    /// "toda terça", "todo sábado" (sábado e domingo são masculinos).
    static func everyWeekday(_ weekday: PlanWeekday) -> String {
        switch weekday {
        case .saturday, .sunday:
            return "todo \(weekday.name)"
        default:
            return "toda \(weekday.name)"
        }
    }

    /// "às 19h", "à 1h", "à 0h" (a uma hora, à zero hora).
    static func atTime(minuteOfDay: Int) -> String {
        let hours = min(max(minuteOfDay, 0), 24 * 60 - 1) / 60
        let preposition = hours <= 1 ? "à" : "às"
        return "\(preposition) \(timeText(minuteOfDay: minuteOfDay))"
    }

    /// Embaixo da chave "Toda semana": "Repete toda terça às 19h."
    static func repeatHint(weekday: PlanWeekday, minuteOfDay: Int) -> String {
        "Repete \(everyWeekday(weekday)) \(atTime(minuteOfDay: minuteOfDay))."
    }

    // MARK: - Linhas (DESIGN §9.3)

    /// "terça · 50 min · leve": o resto da linha de um registro, depois do nome do tipo.
    static func entryDetails(_ entry: OutsideActivityEntry, calendar: Calendar) -> String {
        let weekday = PlanWeekday.of(entry.start, calendar: calendar)
        return [weekday.name, minutesText(entry.minutes), intensityWord(entry.intensity)].joined(separator: " · ")
    }

    /// "Pilates · terça · 50 min · leve" (Metas da semana, seção "Fora do app").
    static func entryLine(_ entry: OutsideActivityEntry, calendar: Calendar) -> String {
        "\(entry.kind.displayName) · \(entryDetails(entry, calendar: calendar))"
    }

    /// "Pilates, terça, 50 minutos, leve".
    static func entrySpoken(_ entry: OutsideActivityEntry, calendar: Calendar) -> String {
        let weekday = PlanWeekday.of(entry.start, calendar: calendar)
        return [
            entry.kind.displayName,
            weekday.name,
            minutesSpoken(entry.minutes),
            intensityWord(entry.intensity),
        ].joined(separator: ", ")
    }

    /// "Pilates · terça · 19h · 50 min" (aba Plano, "Atividades fixas").
    static func fixedLine(_ fixed: FixedOutsideActivity) -> String {
        [
            fixed.kind.displayName,
            fixed.weekday.name,
            timeText(minuteOfDay: fixed.startMinuteOfDay),
            minutesText(fixed.minutes),
        ].joined(separator: " · ")
    }

    /// "Pilates, toda terça às 19h, 50 minutos, leve".
    static func fixedSpoken(_ fixed: FixedOutsideActivity) -> String {
        [
            fixed.kind.displayName,
            "\(everyWeekday(fixed.weekday)) \(atTime(minuteOfDay: fixed.startMinuteOfDay))",
            minutesSpoken(fixed.minutes),
            intensityWord(fixed.intensity),
        ].joined(separator: ", ")
    }

    /// "Pilates · 19h · 50 min" (tela Hoje, cartão "Também hoje").
    static func todayFixedLine(_ fixed: FixedOutsideActivity) -> String {
        [
            fixed.kind.displayName,
            timeText(minuteOfDay: fixed.startMinuteOfDay),
            minutesText(fixed.minutes),
        ].joined(separator: " · ")
    }

    /// "Pilates às 19h, 50 minutos".
    static func todayFixedSpoken(_ fixed: FixedOutsideActivity) -> String {
        "\(fixed.kind.displayName) \(atTime(minuteOfDay: fixed.startMinuteOfDay)), \(minutesSpoken(fixed.minutes))"
    }

    /// Início (SPEC RF-49, X2): "Também hoje: Pilates às 19h"; várias, "Também hoje: Pilates às 19h e
    /// Futebol ou esporte com bola às 21h". `nil` sem fixa pendente. A ordem é a de quem chama (a das fixas
    /// do dia, pela hora).
    static func alsoTodayLine(_ fixed: [FixedOutsideActivity]) -> String? {
        guard !fixed.isEmpty else {
            return nil
        }
        let parts = fixed.map { "\($0.kind.displayName) \(atTime(minuteOfDay: $0.startMinuteOfDay))" }
        return "\(alsoToday): \(joinedList(parts))"
    }

    /// "a", "a e b", "a, b e c".
    static func joinedList(_ parts: [String]) -> String {
        guard let last = parts.last else {
            return ""
        }
        guard parts.count > 1 else {
            return last
        }
        return parts.dropLast().joined(separator: ", ") + " e " + last
    }
}
