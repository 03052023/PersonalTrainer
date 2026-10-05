import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T10.5: `ActivitiesModel` e a folha `ActivityEditorModel` (SPEC §7.17 X1, X2, RF-53; DESIGN §9.3) sobre o
/// `FakeOutsideActivityStore` (AGENTS R9). Cobre registrar, editar e apagar; a validação de X1; o "Feito" uma
/// vez por dia; "Toda semana"; o limite de 10 fixas; `onChange` só depois de gravar; e a folha que guarda o
/// rascunho numa falha. Relógio e calendário fixos (SPEC P11): segunda-feira, 2026-09-28, 10:00 UTC.
@MainActor
final class ActivitiesModelTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    /// Segunda-feira, 2026-09-28, 10:00 UTC.
    private let monday = Date(timeIntervalSince1970: 1_790_589_600)

    private var mondayStart: Date {
        calendar.startOfDay(for: monday)
    }

    // MARK: - Registrar, editar e apagar (RF-53, X1)

    func testRF53_registerAndDelete() throws {
        let (model, store) = makeModel()
        var draft = OutsideActivityDraft.suggested(kind: .walkRun, now: monday, calendar: calendar)
        XCTAssertEqual(draft.minutes, 30, "X1: duração sugerida do tipo")
        XCTAssertEqual(draft.intensity, .moderate, "X1: intensidade sugerida do tipo")
        XCTAssertEqual(draft.start, monday.addingTimeInterval(-30 * 60), "agora menos a duração")

        XCTAssertTrue(model.registerEntry(draft))

        XCTAssertEqual(store.saveCount, 1)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.log, store.log)
        let entry = try XCTUnwrap(model.weekEntries.first)
        XCTAssertEqual(model.weekEntries.count, 1)
        XCTAssertEqual(entry.kind, .walkRun)
        XCTAssertEqual(entry.start, monday.addingTimeInterval(-30 * 60))
        XCTAssertEqual(entry.minutes, 30)
        XCTAssertEqual(entry.intensity, .moderate)
        XCTAssertNil(entry.fixedActivityID, "registro avulso")

        draft.minutes = 45
        draft.intensity = .vigorous
        XCTAssertTrue(model.updateEntry(id: entry.id, with: draft))
        let edited = try XCTUnwrap(store.log.entries.first)
        XCTAssertEqual(edited.id, entry.id, "editar mantém o id")
        XCTAssertEqual(edited.minutes, 45)
        XCTAssertEqual(edited.intensity, .vigorous)

        XCTAssertTrue(model.deleteEntry(id: entry.id))
        XCTAssertTrue(store.log.entries.isEmpty)
        XCTAssertTrue(model.weekEntries.isEmpty)
        XCTAssertEqual(store.saveCount, 3)
    }

    func testRF53_weekEntriesAreTheCurrentWeekOldestFirst() {
        let lastSunday = OutsideActivityEntry(kind: .dance, start: mondayStart.addingTimeInterval(-3_600), minutes: 60, intensity: .moderate)
        let tuesday = OutsideActivityEntry(kind: .pilates, start: mondayStart.addingTimeInterval(86_400 + 19 * 3_600), minutes: 50, intensity: .light)
        let mondayMorning = OutsideActivityEntry(kind: .walkRun, start: mondayStart.addingTimeInterval(7 * 3_600), minutes: 30, intensity: .moderate)
        let nextMonday = OutsideActivityEntry(kind: .walkRun, start: mondayStart.addingTimeInterval(7 * 86_400), minutes: 30, intensity: .moderate)
        let (model, _) = makeModel(log: OutsideActivityLog(entries: [tuesday, nextMonday, lastSunday, mondayMorning]))

        XCTAssertEqual(model.weekEntries.map(\.id), [mondayMorning.id, tuesday.id], "§7.4: de segunda 00:00 à segunda seguinte")
    }

    func testRF53_validationRejectsOutOfRange() {
        let (model, store) = makeModel()
        var draft = OutsideActivityDraft.suggested(kind: .pilates, now: monday, calendar: calendar)

        for minutes in [0, 4, 301, -5] {
            draft.minutes = minutes
            XCTAssertFalse(model.registerEntry(draft), "\(minutes) min")
            XCTAssertEqual(model.errorMessage, "A duração deve ficar entre 5 e 300 min.")
            XCTAssertFalse(model.addFixed(draft), "\(minutes) min na fixa")
        }
        XCTAssertEqual(store.saveCount, 0, "nada é gravado numa falha de validação")

        draft.minutes = 5
        XCTAssertTrue(model.registerEntry(draft))
        draft.minutes = 300
        XCTAssertTrue(model.registerEntry(draft))
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(store.log.entries.map(\.minutes), [5, 300])
    }

    func testRF53_singleEntryCannotBeInTheFuture() {
        let (model, store) = makeModel()
        var draft = OutsideActivityDraft.suggested(kind: .walkRun, now: monday, calendar: calendar)
        draft.start = monday.addingTimeInterval(3_600)

        XCTAssertFalse(model.registerEntry(draft))
        XCTAssertEqual(model.errorMessage, "Escolha um dia e uma hora que já passaram.")
        XCTAssertEqual(store.saveCount, 0)
    }

    // MARK: - X2: fixas e "Feito"

    func testX2_markDoneOncePerDay() throws {
        let pilates = FixedOutsideActivity(kind: .pilates, weekday: .monday, startMinuteOfDay: 19 * 60, minutes: 50, intensity: .light)
        let football = FixedOutsideActivity(kind: .teamSport, weekday: .tuesday, startMinuteOfDay: 21 * 60, minutes: 60, intensity: .vigorous)
        let (model, store) = makeModel(log: OutsideActivityLog(fixed: [football, pilates]))
        XCTAssertEqual(model.todayItems.map(\.activity.id), [pilates.id], "só as fixas de hoje")
        XCTAssertEqual(model.todayItems.map(\.isDone), [false])

        XCTAssertTrue(model.markDone(fixedID: pilates.id))
        XCTAssertTrue(model.markDone(fixedID: pilates.id), "o segundo toque não falha")

        XCTAssertEqual(store.saveCount, 1, "uma vez por dia")
        XCTAssertEqual(store.log.entries.count, 1)
        let entry = try XCTUnwrap(store.log.entries.first)
        XCTAssertEqual(entry.fixedActivityID, pilates.id)
        XCTAssertEqual(entry.kind, .pilates)
        XCTAssertEqual(entry.start, mondayStart.addingTimeInterval(19 * 3_600), "na hora da fixa")
        XCTAssertEqual(entry.minutes, 50)
        XCTAssertEqual(entry.intensity, .light)
        XCTAssertEqual(model.todayItems.map(\.isDone), [true])

        // Apagar o registro do dia desfaz o "Feito" (X2).
        XCTAssertTrue(model.deleteEntry(id: entry.id))
        XCTAssertEqual(model.todayItems.map(\.isDone), [false])

        // Uma fixa que não existe mais: mensagem, nada gravado.
        let saves = store.saveCount
        XCTAssertFalse(model.markDone(fixedID: UUID()))
        XCTAssertEqual(model.errorMessage, "Esta atividade fixa não existe mais.")
        XCTAssertEqual(store.saveCount, saves)
    }

    func testX2_markDoneAgainNextWeek() {
        let pilates = FixedOutsideActivity(kind: .pilates, weekday: .monday, startMinuteOfDay: 19 * 60, minutes: 50, intensity: .light)
        let lastWeekDone = OutsideActivities.entry(loggingFixed: pilates, on: monday, calendar: calendar)
        let nextMonday = monday.addingTimeInterval(7 * 86_400)
        let (model, store) = makeModel(log: OutsideActivityLog(entries: [lastWeekDone], fixed: [pilates]), now: nextMonday)
        XCTAssertEqual(model.todayItems.map(\.isDone), [false], "o Feito da semana passada não vale hoje")

        XCTAssertTrue(model.markDone(fixedID: pilates.id))

        XCTAssertEqual(store.log.entries.count, 2)
        XCTAssertEqual(model.todayItems.map(\.isDone), [true])
    }

    /// O "Feito" vale para o dia que a tela mostra: com a tela aberta na virada da meia-noite (sem `refresh()`),
    /// o pilates de segunda fica na segunda, nunca como um pilates de terça.
    func testX2_markDoneUsesTheDayShown() throws {
        let pilates = FixedOutsideActivity(kind: .pilates, weekday: .monday, startMinuteOfDay: 19 * 60, minutes: 50, intensity: .light)
        let store = FakeOutsideActivityStore(log: OutsideActivityLog(fixed: [pilates]))
        let clock = ActivitiesTestClock(mondayStart.addingTimeInterval(23 * 3_600 + 50 * 60))
        let model = ActivitiesModel(store: store, now: { clock.now }, calendar: calendar)
        model.refresh()
        XCTAssertEqual(model.todayItems.map(\.activity.id), [pilates.id])

        clock.now = mondayStart.addingTimeInterval(86_400 + 10 * 60)
        XCTAssertTrue(model.markDone(fixedID: pilates.id))

        let entry = try XCTUnwrap(store.log.entries.first)
        XCTAssertEqual(entry.start, mondayStart.addingTimeInterval(19 * 3_600), "segunda, na hora da fixa")
        XCTAssertEqual(entry.fixedActivityID, pilates.id)
        XCTAssertTrue(model.todayItems.isEmpty, "depois de gravar, a tela passa para terça, sem fixa")

        // Na terça, a fixa de segunda não é de hoje: nada é gravado.
        let saves = store.saveCount
        XCTAssertTrue(model.markDone(fixedID: pilates.id))
        XCTAssertEqual(store.saveCount, saves)
        XCTAssertEqual(store.log.entries.count, 1)
        XCTAssertNil(model.errorMessage)
    }

    func testX2_everyWeekCreatesFixedAndTodayEntry() throws {
        let (model, store) = makeModel()
        var draft = OutsideActivityDraft.suggested(kind: .pilates, now: monday, calendar: calendar)
        draft.repeatsWeekly = true

        XCTAssertTrue(model.registerEntry(draft))

        let fixed = try XCTUnwrap(store.log.fixed.first)
        XCTAssertEqual(fixed.kind, .pilates)
        XCTAssertEqual(fixed.weekday, .monday)
        XCTAssertEqual(fixed.startMinuteOfDay, 9 * 60 + 10, "10:00 menos 50 min")
        XCTAssertEqual(fixed.minutes, 50)
        XCTAssertEqual(fixed.intensity, .light)
        let entry = try XCTUnwrap(store.log.entries.first)
        XCTAssertEqual(entry.fixedActivityID, fixed.id, "o Quando já passou: é o Feito da fixa")
        XCTAssertEqual(entry.start, monday.addingTimeInterval(-50 * 60))
        XCTAssertEqual(model.todayItems.map(\.isDone), [true])
        XCTAssertEqual(store.saveCount, 1, "a fixa e o registro numa gravação só")

        // Um "Quando" no futuro com "Toda semana": só a fixa.
        var later = OutsideActivityDraft.suggested(kind: .teamSport, now: monday, calendar: calendar)
        later.start = mondayStart.addingTimeInterval(2 * 86_400 + 19 * 3_600)
        later.repeatsWeekly = true
        XCTAssertTrue(model.registerEntry(later))
        XCTAssertEqual(store.log.fixed.count, 2)
        XCTAssertEqual(store.log.entries.count, 1)
        XCTAssertEqual(store.log.fixed.last?.weekday, .wednesday)
        XCTAssertEqual(store.log.fixed.last?.startMinuteOfDay, 19 * 60)
        XCTAssertEqual(model.fixedActivities.map(\.weekday), [.monday, .wednesday])
    }

    func testX2_fixedLimitIsTen() throws {
        let ten: [FixedOutsideActivity] = (0..<10).map { index in
            FixedOutsideActivity(
                kind: .yoga,
                weekday: PlanWeekday(rawValue: index % 7) ?? .monday,
                startMinuteOfDay: 6 * 60 + index,
                minutes: 30,
                intensity: .light
            )
        }
        let (model, store) = makeModel(log: OutsideActivityLog(fixed: ten))
        XCTAssertFalse(model.canAddFixed)
        var draft = OutsideActivityDraft.suggested(kind: .pilates, now: monday, calendar: calendar)

        XCTAssertFalse(model.addFixed(draft))
        XCTAssertEqual(model.errorMessage, "Você já tem 10 atividades fixas. Apague uma para acrescentar outra.")
        draft.repeatsWeekly = true
        XCTAssertFalse(model.registerEntry(draft), "Toda semana também respeita o limite")
        XCTAssertEqual(store.saveCount, 0)

        let first = try XCTUnwrap(ten.first)
        XCTAssertTrue(model.deleteFixed(id: first.id))
        XCTAssertTrue(model.canAddFixed)
        XCTAssertTrue(model.addFixed(draft))
        XCTAssertEqual(store.log.fixed.count, 10)
        XCTAssertFalse(model.canAddFixed)
    }

    func testX2_editAndDeleteFixedKeepEntries() throws {
        let pilates = FixedOutsideActivity(kind: .pilates, weekday: .monday, startMinuteOfDay: 7 * 60, minutes: 50, intensity: .light)
        let done = OutsideActivities.entry(loggingFixed: pilates, on: monday, calendar: calendar)
        let (model, store) = makeModel(log: OutsideActivityLog(entries: [done], fixed: [pilates]))

        var draft = OutsideActivityDraft.editing(pilates, reference: monday, calendar: calendar)
        XCTAssertEqual(draft.start, mondayStart.addingTimeInterval(7 * 3_600))
        draft.weekday = .thursday
        draft.start = mondayStart.addingTimeInterval(18 * 3_600 + 30 * 60)
        draft.minutes = 60
        XCTAssertTrue(model.updateFixed(id: pilates.id, with: draft))
        let edited = try XCTUnwrap(store.log.fixed.first)
        XCTAssertEqual(edited.id, pilates.id)
        XCTAssertEqual(edited.weekday, .thursday)
        XCTAssertEqual(edited.startMinuteOfDay, 18 * 60 + 30)
        XCTAssertEqual(edited.minutes, 60)
        XCTAssertEqual(store.log.entries, [done], "o registro já feito fica como foi feito")

        XCTAssertTrue(model.deleteFixed(id: pilates.id))
        XCTAssertTrue(store.log.fixed.isEmpty)
        XCTAssertEqual(store.log.entries, [done], "X2: apagar a fixa não apaga os registros")
    }

    // MARK: - onChange e falhas

    func testRF53_onChangeAfterSave() {
        var changes = 0
        let (model, store) = makeModel(onChange: { changes += 1 })
        var draft = OutsideActivityDraft.suggested(kind: .walkRun, now: monday, calendar: calendar)

        XCTAssertTrue(model.registerEntry(draft))
        XCTAssertEqual(changes, 1)

        draft.minutes = 2
        XCTAssertFalse(model.registerEntry(draft))
        XCTAssertEqual(changes, 1, "validação recusada: nada muda")

        draft.minutes = 30
        store.saveError = ActivitiesTestError.diskFull
        XCTAssertFalse(model.registerEntry(draft))
        XCTAssertEqual(changes, 1, "gravação que falhou: nada muda")
        XCTAssertEqual(model.errorMessage, "Não foi possível guardar a atividade. Tente de novo.")
        XCTAssertEqual(model.log.entries.count, 1, "a memória continua igual ao que está gravado")
    }

    func testRF53_saveFailureKeepsDraft() {
        var changes = 0
        let (model, store) = makeModel(onChange: { changes += 1 })
        store.saveError = ActivitiesTestError.diskFull
        let editor = ActivityEditorModel(mode: .newEntry, activities: model)
        editor.selectKind(.spinning)
        editor.draft.minutes = 40
        editor.draft.intensity = .moderate
        let chosen = editor.draft

        XCTAssertFalse(editor.submit())

        XCTAssertEqual(editor.draft, chosen, "o que a pessoa escolheu continua na folha")
        XCTAssertEqual(editor.errorMessage, "Não foi possível guardar a atividade. Tente de novo.")
        XCTAssertEqual(model.log, .empty)
        XCTAssertEqual(store.saveCount, 0)
        XCTAssertEqual(changes, 0)

        store.saveError = nil
        XCTAssertTrue(editor.submit(), "tentar de novo grava o mesmo rascunho")
        XCTAssertNil(editor.errorMessage)
        XCTAssertEqual(store.log.entries.map(\.kind), [.spinning])
        XCTAssertEqual(store.log.entries.map(\.minutes), [40])
        XCTAssertEqual(changes, 1)
    }

    // MARK: - A folha (DESIGN §9.3 ponto 2)

    func testRF53_editorSuggestionsFollowTheKind() {
        // 10:07:30: o "Quando" sugerido é agora menos a duração, arredondado para baixo a 5 min.
        let now = monday.addingTimeInterval(7 * 60 + 30)
        let (model, _) = makeModel(now: now)
        let editor = ActivityEditorModel(mode: .newEntry, activities: model)
        XCTAssertEqual(editor.draft.kind, .pilates)
        XCTAssertEqual(editor.draft.minutes, 50)
        XCTAssertEqual(editor.draft.intensity, .light)
        XCTAssertEqual(editor.draft.start, mondayStart.addingTimeInterval(9 * 3_600 + 15 * 60), "9:17:30 → 9:15")

        editor.selectKind(.walkRun)
        XCTAssertEqual(editor.draft.minutes, 30)
        XCTAssertEqual(editor.draft.intensity, .moderate)
        XCTAssertEqual(editor.draft.start, mondayStart.addingTimeInterval(9 * 3_600 + 35 * 60), "o Quando acompanha a duração")

        // Depois que a pessoa escolhe o "Quando", trocar o tipo não mexe nele.
        let chosenStart = mondayStart.addingTimeInterval(8 * 3_600)
        editor.draft.start = chosenStart
        editor.selectKind(.cross)
        XCTAssertEqual(editor.draft.minutes, 60)
        XCTAssertEqual(editor.draft.intensity, .vigorous)
        XCTAssertEqual(editor.draft.start, chosenStart)
    }

    func testRF53_editorModes() {
        let entry = OutsideActivityEntry(kind: .dance, start: monday.addingTimeInterval(-3_600), minutes: 60, intensity: .moderate)
        let fixed = FixedOutsideActivity(kind: .pilates, weekday: .tuesday, startMinuteOfDay: 19 * 60, minutes: 50, intensity: .light)
        let (model, _) = makeModel(log: OutsideActivityLog(entries: [entry], fixed: [fixed]))

        let newEntry = ActivityEditorModel(mode: .newEntry, activities: model)
        XCTAssertEqual(newEntry.title, "Registrar atividade")
        XCTAssertEqual(newEntry.saveTitle, "Registrar")
        XCTAssertTrue(newEntry.showsRepeatToggle)
        XCTAssertFalse(newEntry.isFixedMode)
        XCTAssertFalse(newEntry.canDelete)
        XCTAssertEqual(newEntry.latestStart, monday, "registro avulso: só o que já passou")
        newEntry.draft.repeatsWeekly = true
        XCTAssertEqual(newEntry.latestStart, monday.addingTimeInterval(7 * 86_400))

        let editEntry = ActivityEditorModel(mode: .editEntry(entry), activities: model)
        XCTAssertEqual(editEntry.title, "Editar atividade")
        XCTAssertEqual(editEntry.saveTitle, "Salvar")
        XCTAssertFalse(editEntry.showsRepeatToggle)
        XCTAssertTrue(editEntry.canDelete)
        XCTAssertEqual(editEntry.draft.kind, .dance)
        XCTAssertEqual(editEntry.draft.start, entry.start)

        let newFixed = ActivityEditorModel(mode: .newFixed, activities: model)
        XCTAssertTrue(newFixed.isFixedMode)
        XCTAssertFalse(newFixed.showsRepeatToggle)
        XCTAssertEqual(newFixed.draft.weekday, .monday)
        XCTAssertEqual(newFixed.draft.start, mondayStart.addingTimeInterval(11 * 3_600), "a hora cheia seguinte")

        let editFixed = ActivityEditorModel(mode: .editFixed(fixed), activities: model)
        XCTAssertEqual(editFixed.title, "Editar atividade fixa")
        XCTAssertTrue(editFixed.canDelete)
        XCTAssertEqual(editFixed.draft.weekday, .tuesday)
        XCTAssertEqual(ActivityText.minuteOfDay(editFixed.draft.start, calendar: calendar), 19 * 60)

        // A dica embaixo de "Toda semana" diz o dia e a hora do "Quando" (10:00 − 50 min).
        XCTAssertEqual(newEntry.repeatHint, "Repete toda segunda às 9h10.")
    }

    func testRF53_editorDeleteRemovesTheEntry() {
        let entry = OutsideActivityEntry(kind: .dance, start: monday.addingTimeInterval(-3_600), minutes: 60, intensity: .moderate)
        let (model, store) = makeModel(log: OutsideActivityLog(entries: [entry]))
        let editor = ActivityEditorModel(mode: .editEntry(entry), activities: model)

        XCTAssertTrue(editor.delete())

        XCTAssertTrue(store.log.entries.isEmpty)
        XCTAssertTrue(model.weekEntries.isEmpty)
    }

    func testRF53_editorKeepsStartInThePastWithoutEveryWeek() {
        let (model, _) = makeModel()
        let editor = ActivityEditorModel(mode: .newEntry, activities: model)
        editor.draft.repeatsWeekly = true
        editor.draft.start = monday.addingTimeInterval(2 * 86_400)
        editor.draft.repeatsWeekly = false

        editor.keepStartInThePast()

        XCTAssertLessThanOrEqual(editor.draft.start, monday)
        XCTAssertTrue(editor.submit(), "sem Toda semana, o registro fica no passado e grava")
    }

    // MARK: - Suporte

    private func makeModel(
        log: OutsideActivityLog = .empty,
        now: Date? = nil,
        onChange: @escaping @MainActor () -> Void = {}
    ) -> (ActivitiesModel, FakeOutsideActivityStore) {
        let store = FakeOutsideActivityStore(log: log)
        let fixedNow = now ?? monday
        let model = ActivitiesModel(store: store, now: { fixedNow }, calendar: calendar, onChange: onChange)
        model.refresh()
        return (model, store)
    }
}

private enum ActivitiesTestError: Error {
    case diskFull
}

/// Relógio ajustável pelo teste (só no MainActor, como o modelo que o lê).
private final class ActivitiesTestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}
