import Foundation
import Observation
import os
import TrainerCore

/// Estado das atividades fora do app (SPEC §7.17, RF-53; DESIGN §9.3): os registros da semana, as fixas e o
/// "Feito" das fixas de hoje. Um só modelo para o Início (Metas da semana), a tela Hoje e a aba Plano; o
/// integrador cria uma instância na raiz.
///
/// Escreve só pelo `OutsideActivityStoring` (AGENTS R4: nada de `ModelContext`). O relógio e o calendário
/// chegam por injeção (SPEC P11). `onChange` roda depois de cada gravação bem-sucedida: o integrador o usa
/// para reler o Início, a tela Hoje e o relatório de saúde.
///
/// Cada ação parte do que está gravado agora (`store.load()`), não da cópia em memória: o "Feito" do C8
/// (`CoachService`) e a importação do backup também escrevem no mesmo arquivo, e nada deles se perde. Numa
/// falha (validação de X1 ou gravação), nada muda, `onChange` não roda e `errorMessage` traz o texto pt-BR;
/// a folha que chamou continua com o rascunho da pessoa (`ActivityEditorModel`).
///
/// Andaime da 2.4 (docs/V24-CONTRACT.md §3.2): a assinatura do `init`, `log` e `refresh()` estão congelados.
@Observable
@MainActor
final class ActivitiesModel {
    /// Uma fixa de hoje e se já tem o "Feito" do dia (X2).
    struct TodayItem: Identifiable, Hashable {
        let activity: FixedOutsideActivity
        let isDone: Bool

        var id: UUID {
            activity.id
        }
    }

    /// O que está gravado, relido em `refresh()` e depois de cada gravação.
    private(set) var log: OutsideActivityLog = .empty
    /// O relógio da última leitura ou gravação: a semana (§7.4) e o dia de hoje saem dele. Fica guardado
    /// (e observado) para a tela mudar de dia quando o integrador chama `refresh()`.
    private(set) var referenceDate: Date
    /// Texto pt-BR da última falha; `nil` depois de uma ação que deu certo.
    private(set) var errorMessage: String? = nil

    /// O calendário da pessoa (fuso de §7.4), o mesmo que a folha usa para o dia e a hora.
    let calendar: Calendar

    private let store: any OutsideActivityStoring
    private let now: () -> Date
    private let onChange: @MainActor () -> Void

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "Activities"
    )

    init(
        store: any OutsideActivityStoring,
        now: @escaping () -> Date,
        calendar: Calendar = .autoupdatingCurrent,
        onChange: @escaping @MainActor () -> Void = {}
    ) {
        self.store = store
        self.now = now
        self.calendar = calendar
        self.onChange = onChange
        self.referenceDate = now()
    }

    /// Relê o que está gravado. Nunca lança (o store devolve vazio quando não consegue ler).
    func refresh() {
        referenceDate = now()
        log = store.load()
    }

    /// O relógio injetado, para a folha sugerir o "Quando" (SPEC P11: nada aqui lê a data do sistema).
    func currentDate() -> Date {
        now()
    }

    // MARK: - Listas (derivadas de `log` e `referenceDate`)

    /// A semana de §7.4 que contém `referenceDate`: de segunda 00:00 à segunda seguinte.
    var week: DateInterval {
        WeeklyFrequency.weekInterval(containing: referenceDate, weekStartsOnMonday: true, calendar: calendar)
    }

    /// Os registros da semana, do mais antigo ao mais novo (DESIGN §9.3 ponto 1).
    var weekEntries: [OutsideActivityEntry] {
        OutsideActivities.entries(log.entries, in: week)
    }

    /// Todas as fixas, por dia da semana, hora e id.
    var fixedActivities: [FixedOutsideActivity] {
        log.fixed.sorted { lhs, rhs in
            if lhs.weekday != rhs.weekday {
                return lhs.weekday < rhs.weekday
            }
            if lhs.startMinuteOfDay != rhs.startMinuteOfDay {
                return lhs.startMinuteOfDay < rhs.startMinuteOfDay
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// As fixas de hoje, pela hora, com o "Feito" do dia (X2).
    var todayItems: [TodayItem] {
        let today = referenceDate
        let weekday = PlanWeekday.of(today, calendar: calendar)
        let entries = log.entries
        return OutsideActivities.fixed(log.fixed, on: weekday).map { activity in
            TodayItem(
                activity: activity,
                isDone: OutsideActivities.isLogged(activity, on: today, entries: entries, calendar: calendar)
            )
        }
    }

    /// Ainda cabe mais uma fixa (X2: até 10).
    var canAddFixed: Bool {
        log.fixed.count < OutsideActivities.maxFixed
    }

    // MARK: - Registros (X1, X2)

    /// Grava um registro avulso. Com "Toda semana", grava a fixa daquele dia da semana e hora e, se o
    /// "Quando" já passou, também o registro do dia com o id dela (é o "Feito" dela, X2).
    @discardableResult
    func registerEntry(_ draft: OutsideActivityDraft) -> Bool {
        let current = now()
        let calendar = self.calendar
        return commit { next in
            guard OutsideActivities.isValidMinutes(draft.minutes) else {
                return ActivityText.invalidMinutes
            }
            guard draft.repeatsWeekly else {
                guard draft.start <= current else {
                    return ActivityText.futureEntry
                }
                next.entries.append(OutsideActivityEntry(
                    kind: draft.kind,
                    start: draft.start,
                    minutes: draft.minutes,
                    intensity: draft.intensity
                ))
                return nil
            }
            guard next.fixed.count < OutsideActivities.maxFixed else {
                return ActivityText.fixedLimit
            }
            let fixed = FixedOutsideActivity(
                kind: draft.kind,
                weekday: PlanWeekday.of(draft.start, calendar: calendar),
                startMinuteOfDay: ActivityText.minuteOfDay(draft.start, calendar: calendar),
                minutes: draft.minutes,
                intensity: draft.intensity
            )
            next.fixed.append(fixed)
            if draft.start <= current {
                next.entries.append(OutsideActivities.entry(loggingFixed: fixed, on: draft.start, calendar: calendar))
            }
            return nil
        }
    }

    /// Troca o tipo, o início, a duração e a intensidade de um registro; o id e a fixa de origem ficam.
    @discardableResult
    func updateEntry(id: UUID, with draft: OutsideActivityDraft) -> Bool {
        commit { next in
            guard OutsideActivities.isValidMinutes(draft.minutes) else {
                return ActivityText.invalidMinutes
            }
            guard let index = next.entries.firstIndex(where: { $0.id == id }) else {
                return ActivityText.missingEntry
            }
            let old = next.entries[index]
            next.entries[index] = OutsideActivityEntry(
                id: old.id,
                kind: draft.kind,
                start: draft.start,
                minutes: draft.minutes,
                intensity: draft.intensity,
                fixedActivityID: old.fixedActivityID
            )
            return nil
        }
    }

    /// Apaga um registro. Apagar o registro do dia de uma fixa desfaz o "Feito" (X2).
    @discardableResult
    func deleteEntry(id: UUID) -> Bool {
        guard store.load().entries.contains(where: { $0.id == id }) else {
            // Já não está gravado: nada a gravar, a tela só relê.
            refresh()
            errorMessage = nil
            return true
        }
        return commit { next in
            next.entries.removeAll { $0.id == id }
            return nil
        }
    }

    // MARK: - Fixas (X2)

    /// "Feito" numa fixa: grava o registro do dia com os dados dela, na hora dela. Uma vez por dia: o segundo
    /// toque não grava nada.
    @discardableResult
    func markDone(fixedID: UUID) -> Bool {
        let today = now()
        let calendar = self.calendar
        let stored = store.load()
        guard let fixed = stored.fixed.first(where: { $0.id == fixedID }) else {
            refresh()
            errorMessage = ActivityText.missingFixed
            return false
        }
        guard !OutsideActivities.isLogged(fixed, on: today, entries: stored.entries, calendar: calendar) else {
            refresh()
            errorMessage = nil
            return true
        }
        return commit { next in
            next.entries.append(OutsideActivities.entry(loggingFixed: fixed, on: today, calendar: calendar))
            return nil
        }
    }

    /// Acrescenta uma fixa (até 10), com o dia da semana de `draft.weekday` e a hora de `draft.start`.
    @discardableResult
    func addFixed(_ draft: OutsideActivityDraft) -> Bool {
        let calendar = self.calendar
        return commit { next in
            guard OutsideActivities.isValidMinutes(draft.minutes) else {
                return ActivityText.invalidMinutes
            }
            guard next.fixed.count < OutsideActivities.maxFixed else {
                return ActivityText.fixedLimit
            }
            next.fixed.append(FixedOutsideActivity(
                kind: draft.kind,
                weekday: draft.weekday,
                startMinuteOfDay: ActivityText.minuteOfDay(draft.start, calendar: calendar),
                minutes: draft.minutes,
                intensity: draft.intensity
            ))
            return nil
        }
    }

    /// Muda uma fixa, com o mesmo id. Os registros já feitos ficam como foram feitos.
    @discardableResult
    func updateFixed(id: UUID, with draft: OutsideActivityDraft) -> Bool {
        let calendar = self.calendar
        return commit { next in
            guard OutsideActivities.isValidMinutes(draft.minutes) else {
                return ActivityText.invalidMinutes
            }
            guard let index = next.fixed.firstIndex(where: { $0.id == id }) else {
                return ActivityText.missingFixed
            }
            next.fixed[index] = FixedOutsideActivity(
                id: id,
                kind: draft.kind,
                weekday: draft.weekday,
                startMinuteOfDay: ActivityText.minuteOfDay(draft.start, calendar: calendar),
                minutes: draft.minutes,
                intensity: draft.intensity
            )
            return nil
        }
    }

    /// Apaga uma fixa. Os registros já feitos dela continuam (X2).
    @discardableResult
    func deleteFixed(id: UUID) -> Bool {
        guard store.load().fixed.contains(where: { $0.id == id }) else {
            refresh()
            errorMessage = nil
            return true
        }
        return commit { next in
            next.fixed.removeAll { $0.id == id }
            return nil
        }
    }

    /// Esquece a última falha.
    func clearError() {
        errorMessage = nil
    }

    // MARK: - Gravação

    /// Aplica `change` sobre o que está gravado agora e grava. `change` devolve o texto da falha de
    /// validação, ou `nil` para gravar. Só depois da gravação o estado em memória muda e `onChange` roda.
    private func commit(_ change: (inout OutsideActivityLog) -> String?) -> Bool {
        var next = store.load()
        if let problem = change(&next) {
            errorMessage = problem
            return false
        }
        do {
            try store.save(next)
        } catch {
            Self.logger.error("Falha ao gravar as atividades: \(String(describing: error), privacy: .public)")
            errorMessage = ActivityText.saveFailed
            return false
        }
        log = next
        referenceDate = now()
        errorMessage = nil
        onChange()
        return true
    }
}
