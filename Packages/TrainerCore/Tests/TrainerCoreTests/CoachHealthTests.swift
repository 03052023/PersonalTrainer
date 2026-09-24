import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.11 C3: health suggestions, "no máximo 1 por tipo a cada 3 dias";
// "Lembrar amanhã" comes back the next day.

private typealias CF = CoachFixtures

@Suite("Coach — C3 saúde")
struct CoachHealthTests {
    static let kind = HealthSuggestionKind.updateVo2Max

    struct CadenceCase: Sendable, CustomTestStringConvertible {
        let action: CoachAction?
        let answeredAt: Date?
        let saoPaulo: Bool
        let shown: Bool
        let label: String

        var testDescription: String { label }
    }

    // `now` is Wednesday 2026-09-23 12:00 UTC (09:00 in São Paulo).
    static let cadenceCases: [CadenceCase] = [
        CadenceCase(action: nil, answeredAt: nil, saoPaulo: false, shown: true, label: "nunca respondida"),
        CadenceCase(
            action: .understood,
            answeredAt: CoachFixtures.at(0, hour: 20),
            saoPaulo: false,
            shown: false,
            label: "Entendi há 2 dias: espera"
        ),
        CadenceCase(
            action: .understood,
            answeredAt: CoachFixtures.at(-1, hour: 23),
            saoPaulo: false,
            shown: true,
            label: "Entendi há 3 dias de calendário: volta"
        ),
        CadenceCase(
            action: .understood,
            answeredAt: CoachFixtures.at(2, hour: 8),
            saoPaulo: false,
            shown: false,
            label: "Entendi hoje: espera"
        ),
        CadenceCase(
            action: .remindTomorrow,
            answeredAt: CoachFixtures.at(2, hour: 8),
            saoPaulo: false,
            shown: false,
            label: "Lembrar amanhã hoje: espera"
        ),
        CadenceCase(
            action: .remindTomorrow,
            answeredAt: CoachFixtures.at(1, hour: 23, minute: 30),
            saoPaulo: false,
            shown: true,
            label: "Lembrar amanhã ontem à noite: volta"
        ),
        CadenceCase(
            action: .remindTomorrow,
            answeredAt: CoachFixtures.at(0, hour: 10),
            saoPaulo: false,
            shown: true,
            label: "Lembrar amanhã há 2 dias: volta"
        ),
        CadenceCase(
            action: .understood,
            answeredAt: CoachFixtures.at(0, hour: 1),
            saoPaulo: false,
            shown: false,
            label: "Entendi segunda 01:00 UTC: 2 dias em UTC"
        ),
        CadenceCase(
            action: .understood,
            answeredAt: CoachFixtures.at(0, hour: 1),
            saoPaulo: true,
            shown: true,
            label: "Entendi domingo 22:00 em São Paulo: 3 dias no fuso do usuário"
        ),
        CadenceCase(
            action: .neverAgain,
            answeredAt: CoachFixtures.at(-60),
            saoPaulo: false,
            shown: false,
            label: "Não sugerir mais isto há 60 dias: silenciada"
        ),
        CadenceCase(
            action: .understood,
            answeredAt: CoachFixtures.at(3),
            saoPaulo: false,
            shown: false,
            label: "resposta com data depois de agora: espera"
        ),
    ]

    @Test("C3 cadência por tipo: 3 dias depois de Entendi, 1 dia depois de Lembrar amanhã", arguments: CoachHealthTests.cadenceCases)
    func cadence(_ testCase: CadenceCase) throws {
        let calendar = try testCase.saoPaulo ? ReviewFixtures.saoPaulo() : CF.utc
        let key = Self.kind.rawValue
        var entries: [CoachLogEntry] = []
        if let action = testCase.action, let date = testCase.answeredAt {
            let answeredID = "health:\(key):\(CoachText.day(date, calendar: calendar))"
            entries.append(CF.entry(answeredID, .health, key, action, at: date))
        }
        let input = CoachInput(healthSuggestions: [CF.health(Self.kind)])

        let feed = CF.feed(input, log: CF.log(entries), calendar: calendar)

        #expect(feed.map(\.id) == (testCase.shown ? ["health:updateVo2Max:\(CF.today)"] : []))
    }

    @Test("C3 vale a resposta mais recente do tipo")
    func latestAnswerWins() {
        let key = Self.kind.rawValue
        let input = CoachInput(healthSuggestions: [CF.health(Self.kind)])
        let oldUnderstood = CF.entry("health:\(key):2026-09-10", .health, key, .understood, at: CF.at(-11))
        let recentUnderstood = CF.entry("health:\(key):2026-09-22", .health, key, .understood, at: CF.at(1))
        let recentReminder = CF.entry("health:\(key):2026-09-22", .health, key, .remindTomorrow, at: CF.at(1))

        #expect(CF.feed(input, log: CF.log([recentUnderstood, oldUnderstood])).isEmpty)
        #expect(CF.feed(input, log: CF.log([oldUnderstood, recentReminder])).count == 1)
        // Two answers at the same instant: the one recorded last counts.
        #expect(CF.feed(input, log: CF.log([recentReminder, recentUnderstood])).isEmpty)
        #expect(CF.feed(input, log: CF.log([recentUnderstood, recentReminder])).count == 1)
    }

    @Test("C3 a espera é por tipo: responder um tipo não cala os outros")
    func cadenceIsPerKind() {
        let input = CoachInput(healthSuggestions: [CF.health(.lowSleep), CF.health(.lowSteps)])
        let log = CF.log([CF.entry("health:lowSleep:\(CF.today)", .health, "lowSleep", .understood, at: CF.at(2, hour: 8))])

        #expect(CF.feed(input, log: log).map(\.itemKey) == ["lowSteps"])
    }

    @Test("C3 mensagem com o texto e o tópico da sugestão, Entendi / Lembrar amanhã, sem destaque")
    func messageCarriesTheSuggestion() throws {
        let suggestion = CF.health(.recoveryAlert)

        let message = try #require(CF.feed(CoachInput(healthSuggestions: [suggestion])).first)

        #expect(message.id == "health:recoveryAlert:\(CF.today)")
        #expect(message.rule == .health)
        #expect(message.itemKey == "recoveryAlert")
        #expect(message.title == suggestion.title)
        #expect(message.reason == suggestion.detail)
        #expect(message.referenceTopic == suggestion.referenceTopic)
        #expect(message.actions == [.understood, .remindTomorrow])
        #expect(!message.highlightsOnLaunch)
        #expect(message.suggestionID == nil)
    }

    @Test("C3 prioridade segue a ordem dos tipos de SPEC §7.10")
    func priorityFollowsKindOrder() {
        let suggestions = HealthSuggestionKind.allCases.reversed().map { CF.health($0) }

        let feed = CF.feed(CoachInput(healthSuggestions: suggestions))

        #expect(feed.map(\.itemKey) == HealthSuggestionKind.allCases.map(\.rawValue))
        #expect(feed.map(\.priority) == Array(500..<(500 + HealthSuggestionKind.allCases.count)))
    }
}
