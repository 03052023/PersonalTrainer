import Foundation
import TrainerCore

/// O que a pessoa está escolhendo na folha "Registrar atividade" (SPEC §7.17 X1, X2; DESIGN §9.3 ponto 2): o
/// tipo, a duração, a intensidade pelo teste da fala, o "Quando" e a chave "Toda semana". A mesma folha serve
/// para a fixa: aí valem o dia da semana (`weekday`) e só a hora de `start`.
///
/// Valor puro: quem grava é o `ActivitiesModel`, que valida X1 antes. Numa falha, a folha continua com este
/// rascunho, sem perder nada do que foi escolhido.
struct OutsideActivityDraft: Hashable, Sendable {
    var kind: OutsideActivityKind
    /// Minutos inteiros; o stepper anda de 5 em 5 (X1: 5 a 300).
    var minutes: Int
    var intensity: CardioIntensity
    /// Registro: o início ("Quando"). Fixa: só a hora e os minutos contam.
    var start: Date
    /// Só na fixa: o dia da semana dela.
    var weekday: PlanWeekday
    /// "Toda semana" num registro novo: grava também a fixa daquele dia e hora (X2).
    var repeatsWeekly: Bool

    init(
        kind: OutsideActivityKind,
        minutes: Int,
        intensity: CardioIntensity,
        start: Date,
        weekday: PlanWeekday,
        repeatsWeekly: Bool = false
    ) {
        self.kind = kind
        self.minutes = minutes
        self.intensity = intensity
        self.start = start
        self.weekday = weekday
        self.repeatsWeekly = repeatsWeekly
    }

    /// Folha nova: a duração e a intensidade sugeridas do tipo (X1) e o "Quando" = agora menos a duração,
    /// arredondado para baixo a 5 min (DESIGN §9.3 ponto 2). Sem tipo, o primeiro da tabela X1.
    static func suggested(
        kind: OutsideActivityKind = .pilates,
        now: Date,
        calendar: Calendar
    ) -> OutsideActivityDraft {
        let start = suggestedStart(minutes: kind.defaultMinutes, now: now, calendar: calendar)
        return OutsideActivityDraft(
            kind: kind,
            minutes: kind.defaultMinutes,
            intensity: kind.defaultIntensity,
            start: start,
            weekday: PlanWeekday.of(now, calendar: calendar)
        )
    }

    /// Agora menos `minutes`, sem segundos e com os minutos arredondados para baixo a um múltiplo de 5: fica
    /// sempre no passado.
    static func suggestedStart(minutes: Int, now: Date, calendar: Calendar) -> Date {
        let raw = now.addingTimeInterval(-TimeInterval(max(0, minutes)) * 60)
        let minute = calendar.component(.minute, from: raw)
        let second = calendar.component(.second, from: raw)
        let nanosecond = calendar.component(.nanosecond, from: raw)
        let extraSeconds = TimeInterval((minute % 5) * 60 + second) + TimeInterval(nanosecond) / 1_000_000_000
        return raw.addingTimeInterval(-extraSeconds)
    }

    /// A folha de edição de um registro, preenchida.
    static func editing(_ entry: OutsideActivityEntry, calendar: Calendar) -> OutsideActivityDraft {
        OutsideActivityDraft(
            kind: entry.kind,
            minutes: entry.minutes,
            intensity: entry.intensity,
            start: entry.start,
            weekday: PlanWeekday.of(entry.start, calendar: calendar)
        )
    }

    /// A folha de uma fixa: a hora dela num dia qualquer (o de `reference`), que o seletor de hora mostra.
    static func editing(_ fixed: FixedOutsideActivity, reference: Date, calendar: Calendar) -> OutsideActivityDraft {
        let minute = min(max(fixed.startMinuteOfDay, 0), 24 * 60 - 1)
        let start = calendar.startOfDay(for: reference).addingTimeInterval(TimeInterval(minute) * 60)
        return OutsideActivityDraft(
            kind: fixed.kind,
            minutes: fixed.minutes,
            intensity: fixed.intensity,
            start: start,
            weekday: fixed.weekday
        )
    }

    /// Outro tipo tocado: a duração e a intensidade passam às sugeridas dele (X1); a pessoa pode mudar depois.
    func choosing(_ kind: OutsideActivityKind) -> OutsideActivityDraft {
        var copy = self
        copy.kind = kind
        copy.minutes = kind.defaultMinutes
        copy.intensity = kind.defaultIntensity
        return copy
    }
}
