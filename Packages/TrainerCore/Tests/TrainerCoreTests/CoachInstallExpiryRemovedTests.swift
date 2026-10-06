import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.18 L4: since 2.5 the app is distributed by the App Store and does not talk about
// sideload. The C4 rule (installation expiry) is gone; the persisted cases
// `CoachRule.installExpiry` and `CoachAction.howToRenew` stay, because their raw values may be
// in the dialogue log, but they are never emitted nor offered again.

private typealias CF = CoachFixtures

@Suite("L4 sem sideload no app")
struct CoachInstallExpiryRemovedTests {
    /// One input of the dialogue at one instant.
    struct FeedCase: Sendable, CustomTestStringConvertible {
        let label: String
        let input: CoachInput
        let now: Date

        var testDescription: String { label }
    }

    /// `CF.now` is Wednesday 2026-09-23 12:00 UTC. The other instants are a month before, early
    /// on Thursday (inside the window where the old C4 used to speak) and more than a year later.
    static let instants: [Date] = [
        CoachFixtures.now,
        CoachFixtures.at(-30),
        CoachFixtures.at(3, hour: 1),
        CoachFixtures.at(400, hour: 9),
    ]

    static let feedCases: [FeedCase] = [
        FeedCase(label: "completo, agora", input: CoachFixtures.fullInput(), now: CoachFixtures.now),
        FeedCase(label: "completo, um mês antes", input: CoachFixtures.fullInput(), now: CoachFixtures.at(-30)),
        FeedCase(label: "completo, quinta de madrugada", input: CoachFixtures.fullInput(), now: CoachFixtures.at(3, hour: 1)),
        FeedCase(label: "completo, um ano depois", input: CoachFixtures.fullInput(), now: CoachFixtures.at(400, hour: 9)),
        FeedCase(label: "vazio, agora", input: CoachInput(), now: CoachFixtures.now),
        FeedCase(label: "vazio, um mês antes", input: CoachInput(), now: CoachFixtures.at(-30)),
        FeedCase(label: "vazio, quinta de madrugada", input: CoachInput(), now: CoachFixtures.at(3, hour: 1)),
        FeedCase(label: "vazio, um ano depois", input: CoachInput(), now: CoachFixtures.at(400, hour: 9)),
    ]

    @Test("L4 o diálogo nunca gera a C4", arguments: CoachInstallExpiryRemovedTests.feedCases)
    func feedNeverEmitsInstallExpiry(_ testCase: FeedCase) {
        let feed = CF.feed(testCase.input, now: testCase.now)

        #expect(!feed.contains { $0.rule == .installExpiry }, "\(testCase.label)")
        #expect(!feed.contains { $0.actions.contains(.howToRenew) }, "\(testCase.label)")
        #expect(!feed.contains { $0.id.hasPrefix("expiry:") }, "\(testCase.label)")
    }

    @Test("L4 nenhuma mensagem cita o Impactor nem a validade da instalação")
    func noMessageTalksAboutSideload() {
        let forbidden: [String] = [
            "impactor", "expira", "validade", "instalação", "renove", "renovar", "sideload", "perfil de assinatura",
        ]
        for now in Self.instants {
            let feed = CF.feed(CF.fullInput(), now: now)
            #expect(!feed.isEmpty, "o feed completo tem o que dizer")
            for message in feed {
                let text = (message.title + " " + message.reason).lowercased()
                for word in forbidden {
                    #expect(!text.contains(word), "\(message.id): \(word)")
                }
                #expect(!message.actions.map(\.label).contains("Como renovar"), "\(message.id)")
            }
        }
    }

    @Test("L4 installExpiry e howToRenew continuam decodificáveis no log")
    func legacyEntriesStillDecode() throws {
        // A log written by 2.4: one answer to the old C4 message, next to an answer to C7.
        let json = #"""
        {"entries":[
          {"messageID":"expiry:2026-09-25:2026-09-23","rule":"installExpiry","itemKey":"expiry","action":"howToRenew","date":780000000},
          {"messageID":"backup:2026-W39","rule":"backup","itemKey":"backup","action":"later","date":780000100}
        ]}
        """#

        let log = try JSONDecoder().decode(CoachLog.self, from: Data(json.utf8))

        #expect(log.entries.count == 2)
        #expect(log.entries.first?.rule == .installExpiry)
        #expect(log.entries.first?.action == .howToRenew)
        #expect(log.entries.first?.itemKey == "expiry")
        #expect(CoachRule(rawValue: "installExpiry") == .installExpiry)
        #expect(CoachAction(rawValue: "howToRenew") == .howToRenew)
        #expect(CoachAction.howToRenew.label == "Ok")

        // The old entries round-trip and do not disturb the feed of the active rules.
        let reencoded = try JSONDecoder().decode(CoachLog.self, from: JSONEncoder().encode(log))
        #expect(reencoded == log)
        let withLegacy = CF.feed(CF.fullInput(), log: log)
        #expect(!withLegacy.contains { $0.rule == .installExpiry })
        #expect(withLegacy.map(\.rule) == CF.feed(CF.fullInput()).filter { $0.id != "backup:2026-W39" }.map(\.rule))
    }
}
