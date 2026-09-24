import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.11: the feed as a whole — order, answered and silenced messages, determinism.

private typealias CF = CoachFixtures

@Suite("Coach — feed")
struct CoachFeedTests {
    @Test("C1–C8 sem nada a dizer, o feed fica vazio")
    func emptyInputGivesEmptyFeed() {
        #expect(CF.feed(CoachInput()).isEmpty)
    }

    @Test("C1–C8 ordem: prioridade, depois id; C4 e C1 no topo")
    func orderIsPriorityThenID() {
        let feed = CF.feed(CF.fullInput())

        #expect(feed.map(\.rule) == [
            .installExpiry,
            .deload,
            .comeback,
            .review,
            .review,
            .personalRecord,
            .health,
            .health,
            .backup,
            .longevity,
            .longevity,
        ])
        #expect(feed.map(\.id) == feed.sorted { ($0.priority, $0.id) < ($1.priority, $1.id) }.map(\.id))
        // C3 follows the kind order of SPEC §7.10, not the input order.
        #expect(feed.filter { $0.rule == .health }.map(\.itemKey) == ["updateVo2Max", "lowSteps"])
    }

    @Test("C1–C8 a ordem da entrada não muda o feed")
    func inputOrderDoesNotMatter() {
        var input = CF.fullInput()
        input.personalRecords = [
            CF.record(exercise: 103, load: 40, reps: 10, previousBest: 50),
            CF.record(exercise: 101, load: 105, reps: 5, previousBest: 116),
        ]
        var reversed = input
        reversed.healthSuggestions.reverse()
        reversed.personalRecords.reverse()

        #expect(CF.feed(input) == CF.feed(reversed))
    }

    @Test("C1–C8 destaque na abertura só para C4, C1, C5 e C2")
    func onlyImportantRulesHighlightOnLaunch() {
        let feed = CF.feed(CF.fullInput())
        let highlighted = Set(feed.filter(\.highlightsOnLaunch).map(\.rule))

        #expect(highlighted == [.installExpiry, .deload, .comeback, .review])
    }

    struct RuleCase: Sendable, CustomTestStringConvertible {
        let rule: CoachRule
        let topic: String?
        let actions: [CoachAction]

        var testDescription: String { rule.rawValue }
    }

    static let ruleCases: [RuleCase] = [
        RuleCase(rule: .deload, topic: "rule.D", actions: [.ok, .keepNormal]),
        RuleCase(rule: .review, topic: "topic.volume", actions: [.apply, .notNow, .neverAgain]),
        RuleCase(rule: .health, topic: "topic.updateVo2Max", actions: [.understood, .remindTomorrow]),
        RuleCase(rule: .installExpiry, topic: nil, actions: [.howToRenew]),
        RuleCase(rule: .comeback, topic: "rule.P9", actions: [.start]),
        RuleCase(rule: .personalRecord, topic: "topic.e1rm", actions: [.seeProgress]),
        RuleCase(rule: .backup, topic: nil, actions: [.backupNow, .later]),
        RuleCase(rule: .longevity, topic: "goal.longevity", actions: [.done, .skip]),
    ]

    @Test("C1–C8 tópico do Por quê? e ações de cada regra", arguments: CoachFeedTests.ruleCases)
    func topicAndActionsPerRule(_ testCase: RuleCase) throws {
        let message = try #require(CF.feed(CF.fullInput()).first { $0.rule == testCase.rule })

        #expect(message.referenceTopic == testCase.topic)
        #expect(message.actions == testCase.actions)
    }

    @Test("C1–C8 cada regra do contrato aparece no feed completo")
    func everyRuleSpeaks() {
        #expect(Set(CF.feed(CF.fullInput()).map(\.rule)) == Set(CoachRule.allCases))
        #expect(Set(CoachFeedTests.ruleCases.map(\.rule)) == Set(CoachRule.allCases))
    }

    @Test("C1–C8 mensagem respondida com qualquer ação some", arguments: CoachAction.allCases)
    func anyAnswerHidesTheMessage(_ action: CoachAction) throws {
        let input = CF.fullInput()
        let before = CF.feed(input)
        let backup = try #require(before.first { $0.rule == .backup })
        var log = CoachLog()
        log.record(backup, action: action, at: CF.now)

        let after = CF.feed(input, log: log)

        #expect(!after.contains { $0.id == backup.id })
        #expect(after.count == before.count - 1)
    }

    @Test("C2 Não sugerir mais isto silencia só a mesma regra e o mesmo item")
    func neverAgainSilencesRuleAndItemOnly() {
        let input = CoachInput(goal: .longevity)
        let lastYear = CF.at(-365)
        let silenced = CF.log([
            CF.entry("longevity:balance:2025-W39", .longevity, CoachInput.balanceKey, .neverAgain, at: lastYear),
        ])
        let otherRule = CF.log([
            CF.entry("backup:2025-W39", .backup, CoachInput.balanceKey, .neverAgain, at: lastYear),
        ])

        #expect(CF.feed(input, log: silenced).map(\.itemKey) == [CoachInput.mobilityKey])
        #expect(CF.feed(input, log: otherRule).map(\.itemKey) == [CoachInput.balanceKey, CoachInput.mobilityKey])
    }

    @Test("C1–C8 entrada repetida gera uma mensagem só")
    func duplicatedInputYieldsOneMessage() {
        let record = CF.record(exercise: 101, load: 105, reps: 5, previousBest: 110)
        let suggestion = CF.suggestion(.addSets, id: CF.addSetsID(target: 201))
        let input = CoachInput(
            review: CF.report([suggestion, suggestion]),
            healthSuggestions: [CF.health(.lowSleep), CF.health(.lowSleep)],
            personalRecords: [record, record]
        )

        let feed = CF.feed(input)

        #expect(feed.map(\.rule) == [.review, .personalRecord, .health])
        #expect(Set(feed.map(\.id)).count == feed.count)
    }

    @Test("C1–C8 textos sem jargão de academia (DESIGN §6)")
    func textsAvoidGymJargon() {
        var inputs = [CF.fullInput()]
        for trigger in DeloadTrigger.allCases {
            inputs.append(CoachInput(deload: .scheduled(trigger: trigger, since: CF.at(0))))
        }
        inputs.append(CoachInput(lastSessionStart: CF.at(-30), nextDayName: "Dia A"))
        inputs.append(CoachInput(lastBackupAt: CF.at(-20)))
        let forbidden = ["deload", "recorde", "treino", "falha", "falhou", "monstro", "shape"]

        for input in inputs {
            for message in CF.feed(input) where message.rule != .review && message.rule != .health {
                let text = (message.title + " " + message.reason).lowercased()
                for word in forbidden {
                    #expect(!text.contains(word.lowercased()), "\(message.id): \(word)")
                }
            }
        }
    }
}
