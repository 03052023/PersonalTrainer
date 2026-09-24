import Foundation
import SwiftUI
import TrainerCore

// Fixtures e doubles só para os #Preview da feature Saúde (AGENTS R9: previews usam fakes).
// Tudo privado ao arquivo e prefixado por "Health" para não colidir com doubles de outras
// features; por isso os previews da Saúde vivem aqui, e não em cada arquivo de view.
// Cada estado usa uma suite própria de `UserDefaults` para a flag de autorização e o perfil.

// MARK: - Previews

#Preview("Saúde — card conectado") {
    NavigationStack {
        ScrollView {
            HealthCardView(model: HealthPreviewFixture.connectedModel(), references: HealthPreviewFixture.references)
                .padding(16)
        }
        .navigationTitle("Treino")
    }
}

#Preview("Saúde — card sem conexão") {
    NavigationStack {
        ScrollView {
            HealthCardView(model: HealthPreviewFixture.disconnectedModel(), references: HealthPreviewFixture.references)
                .padding(16)
        }
        .navigationTitle("Treino")
    }
}

#Preview("Saúde — card sem app Saúde") {
    NavigationStack {
        ScrollView {
            HealthCardView(model: HealthPreviewFixture.unavailableModel(), references: HealthPreviewFixture.references)
                .padding(16)
        }
        .navigationTitle("Treino")
    }
}

#Preview("Saúde — card com falha de leitura") {
    NavigationStack {
        ScrollView {
            HealthCardView(model: HealthPreviewFixture.failingModel(), references: HealthPreviewFixture.references)
                .padding(16)
        }
        .navigationTitle("Treino")
    }
}

#Preview("Saúde — detalhe") {
    NavigationStack {
        HealthDetailView(model: HealthPreviewFixture.connectedModel(), references: HealthPreviewFixture.references)
    }
}

#Preview("Saúde — detalhe sem dados") {
    NavigationStack {
        HealthDetailView(model: HealthPreviewFixture.emptyDataModel(), references: HealthPreviewFixture.references)
    }
}

#Preview("Saúde — perfil") {
    NavigationStack {
        HealthProfileView(model: HealthPreviewFixture.connectedModel())
    }
}

#Preview("AerobicWeekChart") {
    List {
        AerobicWeekChart(summary: HealthPreviewFixture.sampleReport.aerobic, calendar: HealthPreviewFixture.calendar)
    }
}

#Preview("Vo2MaxTrendChart") {
    List {
        Vo2MaxTrendChart(samples: HealthPreviewFixture.sampleInput.vo2Max, calendar: HealthPreviewFixture.calendar)
    }
}

#Preview("HealthSuggestionRow") {
    List {
        ForEach(HealthPreviewFixture.suggestions) { suggestion in
            HealthSuggestionRow(suggestion: suggestion, references: HealthPreviewFixture.references, onDismiss: {})
        }
    }
}

// MARK: - Fixtures

@MainActor
private enum HealthPreviewFixture {
    /// Data fixa (SPEC P11): previews determinísticos.
    static let referenceDate = Date(timeIntervalSince1970: 1_758_600_000)

    /// Calendário fixo (gregoriano, São Paulo, semana começando na segunda) para os rótulos
    /// não mudarem com o aparelho que roda o preview.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .gmt
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Catálogo real do bundle (contrato do M2): os botões "Por quê?" aparecem nos tópicos que
    /// já têm referências e somem nos demais.
    static let references = ReferenceLibrary.load(bundle: .main)

    static let sampleInput = FakeHealthDataReader.sampleInput(now: referenceDate, calendar: calendar)

    static let sampleReport = HealthCalculator.report(
        input: sampleInput,
        targets: HealthTargets(),
        now: referenceDate,
        calendar: calendar
    )

    /// Três sugestões de tipos diferentes, com textos no tom do app, para ver ícones e botões.
    static let suggestions: [HealthSuggestion] = [
        HealthSuggestion(
            id: "wear-watch-at-night",
            kind: .wearWatchAtNight,
            title: "Use o Apple Watch para dormir",
            detail: "Faltaram dados noturnos em 5 dos últimos 7 dias. O relógio mede HRV, FC de repouso e sono, que o app usa na revisão periódica.",
            referenceTopic: "topic.hrv"
        ),
        HealthSuggestion(
            id: "update-vo2max",
            kind: .updateVo2Max,
            title: "Atualize o seu VO2máx",
            detail: "A última estimativa tem 72 dias. Faça 20 min de caminhada rápida ou corrida ao ar livre com o Watch.",
            referenceTopic: "topic.vo2max"
        ),
        HealthSuggestion(
            id: "aerobic-deficit",
            kind: .aerobicDeficit,
            title: "Faltam 55 min de aeróbico nesta semana",
            detail: "Uma caminhada de 30 min no sábado e outra no domingo completam a meta, longe do treino de pernas de segunda.",
            referenceTopic: "topic.aerobic"
        ),
    ]

    // MARK: ViewModels por estado

    static func connectedModel() -> HealthViewModel {
        makeModel(reader: FakeHealthDataReader(), suite: "HealthPreview.connected", authorized: true)
    }

    static func disconnectedModel() -> HealthViewModel {
        makeModel(reader: FakeHealthDataReader(), suite: "HealthPreview.disconnected", authorized: false)
    }

    static func unavailableModel() -> HealthViewModel {
        makeModel(reader: FakeHealthDataReader(isAvailable: false), suite: "HealthPreview.unavailable", authorized: false)
    }

    static func failingModel() -> HealthViewModel {
        makeModel(reader: HealthPreviewFailingReader(), suite: "HealthPreview.failing", authorized: true)
    }

    /// Saúde conectado, mas sem nenhum dado (relógio nunca usado, ou leitura negada).
    static func emptyDataModel() -> HealthViewModel {
        let empty = HealthInput(
            physiology: UserPhysiology(birthDate: nil, sex: nil, maxHeartRateOverride: nil),
            aerobicWorkouts: [],
            recovery: [],
            steps: [],
            vo2Max: [],
            recentSessions: []
        )
        return makeModel(reader: FakeHealthDataReader(input: empty), suite: "HealthPreview.empty", authorized: true)
    }

    /// O relógio vira uma constante local antes de entrar no fechamento `now`, que não é isolado
    /// ao MainActor (ao contrário das propriedades estáticas deste enum).
    private static func makeModel(reader: any HealthDataReading, suite: String, authorized: Bool) -> HealthViewModel {
        let fixedNow = referenceDate
        return HealthViewModel(
            reader: reader,
            sessionsProvider: { [] },
            now: { fixedNow },
            calendar: calendar,
            defaults: defaults(suite: suite, authorized: authorized)
        )
    }

    /// Suite isolada por estado; sem suite (não deveria acontecer) cai no `.standard`, o que só
    /// afeta o preview.
    private static func defaults(suite: String, authorized: Bool) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.set(authorized, forKey: HealthViewModel.Keys.readAuthorized)
        defaults.removeObject(forKey: HealthViewModel.Keys.dismissedSuggestions)
        return defaults
    }
}

// MARK: - Doubles

private enum HealthPreviewError: Error {
    case readFailed
}

/// Leitor que sempre falha na leitura, para o estado de erro do card (o `FakeHealthDataReader`
/// do contrato só simula disponibilidade).
private struct HealthPreviewFailingReader: HealthDataReading {
    let isAvailable = true

    func requestReadAuthorization() async throws {}

    func healthInput(now: Date, calendar: Calendar, recentSessions: [SessionSummary]) async throws -> HealthInput {
        throw HealthPreviewError.readFailed
    }
}
