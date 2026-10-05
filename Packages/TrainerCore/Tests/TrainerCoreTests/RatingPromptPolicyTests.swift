import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.18 L3: o pedido de avaliação, o mínimo invasivo (contrato docs/V25-CONTRACT.md §5.4).

@Suite("L3 pedido de avaliação")
struct RatingPromptPolicyTests {
    static let day: TimeInterval = 86_400
    static let now: Date = Date(timeIntervalSince1970: 1_790_000_000)

    /// Uma entrada que cumpre tudo, com o campo de cada caso trocado.
    static func input(
        firstDaysAgo: TimeInterval? = 10,
        completedCount: Int = 3,
        ending: RatingSessionEnding = .completed,
        version: String = "1.0.0",
        lastVersion: String? = nil,
        lastRequestDaysAgo: TimeInterval? = nil,
        isStoreInstall: Bool = true
    ) -> RatingPromptInput {
        let first: Date? = firstDaysAgo.map { RatingPromptPolicyTests.now.addingTimeInterval(-$0 * RatingPromptPolicyTests.day) }
        let lastAt: Date? = lastRequestDaysAgo.map { RatingPromptPolicyTests.now.addingTimeInterval(-$0 * RatingPromptPolicyTests.day) }
        return RatingPromptInput(
            firstCompletedSessionStart: first,
            completedSessionCount: completedCount,
            sessionEnding: ending,
            currentVersion: version,
            lastRequestVersion: lastVersion,
            lastRequestAt: lastAt,
            isStoreInstall: isStoreInstall
        )
    }

    struct DecisionCase: Sendable, CustomTestStringConvertible {
        let name: String
        let input: RatingPromptInput
        let asks: Bool

        var testDescription: String { name }
    }

    static let sevenDaysMinusOneSecond: TimeInterval = 7 - 1 / 86_400
    static let sevenDays: TimeInterval = 7

    static let decisionCases: [DecisionCase] = [
        DecisionCase(name: "pede com tudo cumprido", input: input(), asks: true),
        DecisionCase(name: "7 dias menos 1 s não pede", input: input(firstDaysAgo: sevenDaysMinusOneSecond), asks: false),
        DecisionCase(name: "7 dias exatos pede", input: input(firstDaysAgo: sevenDays), asks: true),
        DecisionCase(name: "2 sessões não pede", input: input(completedCount: 2), asks: false),
        DecisionCase(name: "3 sessões pedem", input: input(completedCount: 3), asks: true),
        DecisionCase(name: "sessão abandonada não pede", input: input(ending: .abandoned), asks: false),
        DecisionCase(name: "erro de gravação ou do Saúde não pede", input: input(ending: .failed), asks: false),
        DecisionCase(name: "sem primeira sessão não pede", input: input(firstDaysAgo: nil), asks: false),
        DecisionCase(
            name: "mesma versão não pede",
            input: input(lastVersion: "1.0.0", lastRequestDaysAgo: 200),
            asks: false
        ),
        DecisionCase(
            name: "outra versão com 119 dias não pede",
            input: input(lastVersion: "0.9.0", lastRequestDaysAgo: 119),
            asks: false
        ),
        DecisionCase(
            name: "outra versão com 120 dias pede",
            input: input(lastVersion: "0.9.0", lastRequestDaysAgo: 120),
            asks: true
        ),
        DecisionCase(name: "nunca pediu pede", input: input(lastVersion: nil, lastRequestDaysAgo: nil), asks: true),
        DecisionCase(name: "fora da loja não pede", input: input(isStoreInstall: false), asks: false),
        DecisionCase(name: "versão vazia não pede", input: input(version: ""), asks: false),
        DecisionCase(name: "versão só com espaços não pede", input: input(version: "  "), asks: false),
        DecisionCase(
            name: "último pedido no futuro não pede",
            input: input(lastVersion: "0.9.0", lastRequestDaysAgo: -1),
            asks: false
        ),
    ]

    @Test("L3 pede só quando todas as condições valem", arguments: RatingPromptPolicyTests.decisionCases)
    func decision(_ testCase: DecisionCase) {
        #expect(RatingPromptPolicy.shouldRequest(testCase.input, now: RatingPromptPolicyTests.now) == testCase.asks)
    }

    @Test("L3 constantes: 7 dias, 3 sessões, 120 dias, dias de 24 h")
    func constants() {
        #expect(RatingPromptPolicy.minimumDaysSinceFirstSession == 7)
        #expect(RatingPromptPolicy.minimumCompletedSessions == 3)
        #expect(RatingPromptPolicy.minimumDaysBetweenRequests == 120)
        #expect(RatingPromptPolicy.secondsPerDay == 86_400)
    }

    @Test("L3 conta só sessões concluídas com série")
    func countsOnlyCompletedSessionsWithWorkingSets() {
        let base = RatingPromptPolicyTests.now
        let abandoned = SessionSummary(
            programDayID: UUID(),
            startedAt: base.addingTimeInterval(-30 * RatingPromptPolicyTests.day),
            endedAt: base.addingTimeInterval(-30 * RatingPromptPolicyTests.day + 3_600),
            status: .abandoned,
            workingSetCount: 12
        )
        let completedWithoutSets = SessionSummary(
            programDayID: UUID(),
            startedAt: base.addingTimeInterval(-20 * RatingPromptPolicyTests.day),
            endedAt: base.addingTimeInterval(-20 * RatingPromptPolicyTests.day + 600),
            status: .completed,
            workingSetCount: 0
        )
        let inProgress = SessionSummary(
            programDayID: UUID(),
            startedAt: base.addingTimeInterval(-15 * RatingPromptPolicyTests.day),
            status: .inProgress,
            workingSetCount: 4
        )
        let laterCompleted = SessionSummary(
            programDayID: UUID(),
            startedAt: base.addingTimeInterval(-2 * RatingPromptPolicyTests.day),
            endedAt: base.addingTimeInterval(-2 * RatingPromptPolicyTests.day + 3_600),
            status: .completed,
            workingSetCount: 15
        )
        let firstCompleted = SessionSummary(
            programDayID: UUID(),
            startedAt: base.addingTimeInterval(-9 * RatingPromptPolicyTests.day),
            endedAt: base.addingTimeInterval(-9 * RatingPromptPolicyTests.day + 3_600),
            status: .completed,
            workingSetCount: 1
        )
        // Fora de ordem de propósito: a primeira concluída é a de início mais antigo, não a primeira da lista.
        let sessions: [SessionSummary] = [abandoned, completedWithoutSets, inProgress, laterCompleted, firstCompleted]

        #expect(!RatingPromptPolicy.countsAsCompleted(abandoned))
        #expect(!RatingPromptPolicy.countsAsCompleted(completedWithoutSets))
        #expect(!RatingPromptPolicy.countsAsCompleted(inProgress))
        #expect(RatingPromptPolicy.countsAsCompleted(laterCompleted))
        #expect(RatingPromptPolicy.countsAsCompleted(firstCompleted))
        #expect(RatingPromptPolicy.completedSessionCount(in: sessions) == 2)
        #expect(RatingPromptPolicy.firstCompletedSessionStart(in: sessions) == firstCompleted.startedAt)
    }

    @Test("L3 sem histórico: nenhuma sessão concluída e nenhuma primeira sessão")
    func emptyHistory() {
        let sessions: [SessionSummary] = []

        #expect(RatingPromptPolicy.completedSessionCount(in: sessions) == 0)
        #expect(RatingPromptPolicy.firstCompletedSessionStart(in: sessions) == nil)
    }
}
