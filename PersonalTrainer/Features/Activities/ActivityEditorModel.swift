import Foundation
import Observation
import TrainerCore

/// Estado da folha "Registrar atividade" (SPEC §7.17 X1, X2, RF-53; DESIGN §9.3 ponto 2), a mesma para editar
/// um registro e para acrescentar ou editar uma fixa. Guarda o rascunho da pessoa; quem grava é o
/// `ActivitiesModel`. Numa falha, o rascunho fica como estava e `errorMessage` traz o texto pt-BR: a pessoa
/// corrige ou tenta de novo sem escolher tudo outra vez.
@Observable
@MainActor
final class ActivityEditorModel {
    /// O que a folha faz. `Identifiable` para `.sheet(item:)`.
    enum Mode: Identifiable, Hashable {
        /// "Registrar atividade" (Metas da semana): registro avulso, com a chave "Toda semana".
        case newEntry
        /// Tocar num registro da semana.
        case editEntry(OutsideActivityEntry)
        /// "Acrescentar atividade fixa" (aba Plano).
        case newFixed
        /// Tocar numa fixa.
        case editFixed(FixedOutsideActivity)

        var id: String {
            switch self {
            case .newEntry:
                return "newEntry"
            case .editEntry(let entry):
                return "entry-\(entry.id.uuidString)"
            case .newFixed:
                return "newFixed"
            case .editFixed(let fixed):
                return "fixed-\(fixed.id.uuidString)"
            }
        }
    }

    let mode: Mode
    var draft: OutsideActivityDraft
    /// Texto pt-BR da última tentativa que falhou; `nil` antes de tentar ou depois de dar certo.
    private(set) var errorMessage: String? = nil

    private let activities: ActivitiesModel
    /// O último "Quando" sugerido pela folha (registro novo). Enquanto a pessoa não muda o "Quando", trocar o
    /// tipo recalcula o início pela duração nova; depois que ela muda, o dela fica.
    @ObservationIgnored private var suggestedStart: Date?

    init(mode: Mode, activities: ActivitiesModel) {
        self.mode = mode
        self.activities = activities
        let now = activities.currentDate()
        let calendar = activities.calendar
        switch mode {
        case .newEntry:
            let draft = OutsideActivityDraft.suggested(now: now, calendar: calendar)
            self.draft = draft
            self.suggestedStart = draft.start
        case .editEntry(let entry):
            self.draft = OutsideActivityDraft.editing(entry, calendar: calendar)
            self.suggestedStart = nil
        case .newFixed:
            var draft = OutsideActivityDraft.suggested(now: now, calendar: calendar)
            // A hora cheia seguinte é um começo mais natural para uma aula fixa que "agora menos a duração".
            draft.start = ActivityEditorModel.nextFullHour(after: now, calendar: calendar)
            self.draft = draft
            self.suggestedStart = nil
        case .editFixed(let fixed):
            self.draft = OutsideActivityDraft.editing(fixed, reference: now, calendar: calendar)
            self.suggestedStart = nil
        }
    }

    // MARK: - O que a folha mostra

    /// Título em New York no topo da folha.
    var title: String {
        switch mode {
        case .newEntry: return ActivityText.register
        case .editEntry: return ActivityText.editTitle
        case .newFixed: return ActivityText.newFixedTitle
        case .editFixed: return ActivityText.editFixedTitle
        }
    }

    /// "Registrar" num registro novo; "Salvar" no resto.
    var saveTitle: String {
        mode == .newEntry ? ActivityText.registerButton : ActivityText.saveButton
    }

    /// Fixa: dia da semana e hora no lugar do "Quando".
    var isFixedMode: Bool {
        switch mode {
        case .newFixed, .editFixed: return true
        case .newEntry, .editEntry: return false
        }
    }

    /// A chave "Toda semana" só existe no registro novo.
    var showsRepeatToggle: Bool {
        mode == .newEntry
    }

    /// "Apagar atividade" só na edição.
    var canDelete: Bool {
        switch mode {
        case .editEntry, .editFixed: return true
        case .newEntry, .newFixed: return false
        }
    }

    /// Limite de cima do "Quando": o que já passou; com "Toda semana", até 7 dias à frente (a fixa pode
    /// começar mais tarde); na edição, também o início que já estava gravado (um "Feito" dado antes da hora).
    var latestStart: Date {
        let now = activities.currentDate()
        switch mode {
        case .newEntry:
            return draft.repeatsWeekly ? now.addingTimeInterval(7 * 86_400) : now
        case .editEntry(let entry):
            return max(now, entry.start)
        case .newFixed, .editFixed:
            return now
        }
    }

    /// "Repete toda terça às 19h.", embaixo da chave "Toda semana".
    var repeatHint: String {
        let calendar = activities.calendar
        return ActivityText.repeatHint(
            weekday: PlanWeekday.of(draft.start, calendar: calendar),
            minuteOfDay: ActivityText.minuteOfDay(draft.start, calendar: calendar)
        )
    }

    // MARK: - Ações

    /// Toca num tipo: a duração e a intensidade passam às sugeridas dele (X1). No registro novo, se a pessoa
    /// ainda não mexeu no "Quando", ele acompanha a duração nova.
    func selectKind(_ kind: OutsideActivityKind) {
        guard kind != draft.kind else {
            return
        }
        var next = draft.choosing(kind)
        if mode == .newEntry, let suggestedStart, next.start == suggestedStart {
            let start = OutsideActivityDraft.suggestedStart(
                minutes: next.minutes,
                now: activities.currentDate(),
                calendar: activities.calendar
            )
            next.start = start
            self.suggestedStart = start
        }
        draft = next
    }

    /// Sem "Toda semana", o "Quando" não fica no futuro: volta ao sugerido.
    func keepStartInThePast() {
        let now = activities.currentDate()
        guard !draft.repeatsWeekly, draft.start > now else {
            return
        }
        let start = OutsideActivityDraft.suggestedStart(minutes: draft.minutes, now: now, calendar: activities.calendar)
        draft.start = start
        suggestedStart = start
    }

    /// Grava. `true` = deu certo e a folha pode fechar; `false` = a folha fica, com o rascunho e a mensagem.
    func save() -> Bool {
        let didSave: Bool
        switch mode {
        case .newEntry:
            didSave = activities.registerEntry(draft)
        case .editEntry(let entry):
            didSave = activities.updateEntry(id: entry.id, with: draft)
        case .newFixed:
            didSave = activities.addFixed(draft)
        case .editFixed(let fixed):
            didSave = activities.updateFixed(id: fixed.id, with: draft)
        }
        errorMessage = didSave ? nil : (activities.errorMessage ?? ActivityText.saveFailed)
        return didSave
    }

    /// "Apagar atividade" (depois da confirmação). `true` = a folha pode fechar.
    func delete() -> Bool {
        let didDelete: Bool
        switch mode {
        case .editEntry(let entry):
            didDelete = activities.deleteEntry(id: entry.id)
        case .editFixed(let fixed):
            didDelete = activities.deleteFixed(id: fixed.id)
        case .newEntry, .newFixed:
            return false
        }
        errorMessage = didDelete ? nil : (activities.errorMessage ?? ActivityText.saveFailed)
        return didDelete
    }

    // MARK: - Apoio

    /// A hora cheia depois de `date` no calendário da pessoa (19:20 → 20:00).
    static func nextFullHour(after date: Date, calendar: Calendar) -> Date {
        let startOfHour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        return calendar.date(byAdding: .hour, value: 1, to: startOfHour) ?? date.addingTimeInterval(3_600)
    }
}
