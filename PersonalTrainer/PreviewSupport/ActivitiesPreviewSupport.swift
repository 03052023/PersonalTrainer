import Foundation
import SwiftUI
import TrainerCore

// Fixtures só para os #Preview das atividades fora do app (SPEC §7.17, RF-53; AGENTS R9: previews usam o
// `FakeOutsideActivityStore`, nunca o arquivo real). Tudo privado ao arquivo e prefixado por "Activities".

// MARK: - Previews

#Preview("Também hoje — uma pendente, uma feita") {
    ScrollView {
        TodayActivitiesCard(model: ActivitiesPreviewFixture.model(with: ActivitiesPreviewFixture.sampleLog()))
            .padding(16)
    }
    .paperBackground()
}

#Preview("Atividades fixas") {
    ScrollView {
        FixedActivitiesSection(model: ActivitiesPreviewFixture.model(with: ActivitiesPreviewFixture.sampleLog()))
            .padding(16)
    }
    .paperBackground()
}

#Preview("Atividades fixas — vazio") {
    ScrollView {
        FixedActivitiesSection(model: ActivitiesPreviewFixture.model(with: .empty))
            .padding(16)
    }
    .paperBackground()
}

#Preview("Fora do app (Metas da semana)") {
    let model = ActivitiesPreviewFixture.model(with: ActivitiesPreviewFixture.sampleLog())
    return List {
        OutsideActivitiesGoalsSection(
            model: model,
            references: ActivitiesPreviewFixture.references,
            onRegister: {},
            onEdit: { _ in },
            onDelete: { _ in }
        )
    }
    .scrollContentBackground(.hidden)
    .paperBackground()
}

#Preview("Folha — registrar atividade") {
    ActivityEditorSheet(activities: ActivitiesPreviewFixture.model(with: .empty), mode: .newEntry)
}

#Preview("Folha — atividade fixa") {
    ActivityEditorSheet(activities: ActivitiesPreviewFixture.model(with: .empty), mode: .newFixed)
}

#Preview("Folha — editar registro") {
    ActivitiesPreviewFixture.editEntrySheet()
}

// MARK: - Fixtures

@MainActor
private enum ActivitiesPreviewFixture {
    /// Quarta-feira, 30/09/2026, 07:00 em São Paulo (SPEC P11: previews determinísticos).
    static let referenceDate = Date(timeIntervalSince1970: 1_790_762_400)

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
        return calendar
    }()

    static let references = ReferenceLibrary.load(bundle: .main)

    /// O relógio vira uma constante local antes de entrar no fechamento `now`.
    static func model(with log: OutsideActivityLog) -> ActivitiesModel {
        let fixedNow = referenceDate
        let model = ActivitiesModel(
            store: FakeOutsideActivityStore(log: log),
            now: { fixedNow },
            calendar: calendar
        )
        model.refresh()
        return model
    }

    /// A folha de edição do primeiro registro de `sampleLog()`.
    static func editEntrySheet() -> ActivityEditorSheet {
        let log = sampleLog()
        let entry = log.entries.first
            ?? OutsideActivityEntry(kind: .walkRun, start: referenceDate, minutes: 30, intensity: .moderate)
        return ActivityEditorSheet(activities: model(with: log), mode: .editEntry(entry))
    }

    /// Pilates na quarta 19h (pendente hoje), ioga na quarta 7h (já com o "Feito" de hoje), futebol no
    /// sábado; e dois registros desta semana: o "Feito" da ioga e um spinning avulso na segunda.
    static func sampleLog() -> OutsideActivityLog {
        let pilates = FixedOutsideActivity(
            kind: .pilates,
            weekday: .wednesday,
            startMinuteOfDay: 19 * 60,
            minutes: 50,
            intensity: .light
        )
        let yoga = FixedOutsideActivity(
            kind: .yoga,
            weekday: .wednesday,
            startMinuteOfDay: 6 * 60,
            minutes: 45,
            intensity: .light
        )
        let football = FixedOutsideActivity(
            kind: .teamSport,
            weekday: .saturday,
            startMinuteOfDay: 9 * 60 + 30,
            minutes: 60,
            intensity: .vigorous
        )
        let spinning = OutsideActivityEntry(
            kind: .spinning,
            start: referenceDate.addingTimeInterval(-2 * 86_400 + 11 * 3_600),
            minutes: 45,
            intensity: .vigorous
        )
        let yogaDone = OutsideActivities.entry(loggingFixed: yoga, on: referenceDate, calendar: calendar)
        return OutsideActivityLog(entries: [spinning, yogaDone], fixed: [pilates, yoga, football])
    }
}
