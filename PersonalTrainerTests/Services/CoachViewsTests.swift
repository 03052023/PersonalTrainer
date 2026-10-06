import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Regras de design das views do diálogo que dá para checar sem renderizar: símbolos proibidos
/// (DESIGN §8), voz sem cultura de academia (DESIGN §6) e nada de sideload nas previews (SPEC §7.18 L4).
@MainActor
final class CoachViewsTests: XCTestCase {
    private static let forbiddenSymbolFragments = [
        "dumbbell", "figure.strengthtraining", "figure.boxing", "figure.kickboxing",
        "figure.martial.arts", "flame", "bolt", "trophy",
    ]

    func testRuleSymbols_avoidGymCultureSymbols() {
        for rule in CoachRule.allCases {
            let symbol = rule.symbolName
            XCTAssertFalse(symbol.isEmpty, "\(rule) sem símbolo")
            for fragment in Self.forbiddenSymbolFragments {
                XCTAssertFalse(symbol.contains(fragment), "\(rule) usa \(symbol), proibido pelo DESIGN §8")
            }
        }
    }

    /// SPEC §7.18 L4: as previews do diálogo também não mostram a C4 nem falam de sideload.
    func testL4_previewMessagesNeverShowTheInstallExpiry() {
        XCTAssertFalse(CoachPreviewData.all.isEmpty)
        for message in CoachPreviewData.all {
            XCTAssertNotEqual(message.rule, .installExpiry, message.id)
            XCTAssertFalse(message.actions.contains(.howToRenew), message.id)
            let text = (message.title + " " + message.reason).lowercased()
            for word in ["impactor", "expira", "renove", "validade"] {
                XCTAssertFalse(text.contains(word), "\(message.id) usa \"\(word)\" (L4)")
            }
        }
    }

    func testPreviewMessages_useTheCoachVoice() {
        let forbidden = ["deload", "treino pesado", "sem desculpas", "recorde", "falhou"]
        for message in CoachPreviewData.all {
            let text = (message.title + " " + message.reason).lowercased()
            for word in forbidden {
                XCTAssertFalse(text.contains(word), "\(message.id) usa \"\(word)\" (DESIGN §6)")
            }
        }
    }

    func testApplyDetail_describesTheChangeInPlainWords() throws {
        let suite = "CoachViewsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = CoachService(
            planner: CoachTestPlanner(),
            programs: CoachTestPrograms(),
            log: FakeCoachLogStore(),
            notifications: FakeNotificationScheduler(),
            now: { Date(timeIntervalSince1970: 1_790_262_000) },
            calendar: Calendar(identifier: .gregorian),
            defaults: defaults
        )
        let deload = ProgramSuggestion(
            id: "deload:2026-W39",
            kind: .deload,
            rule: "R2",
            title: "Semana mais leve",
            reason: "Sinais de fadiga.",
            referenceTopic: "rule.D"
        )
        let reduceDays = ProgramSuggestion(
            id: "reduceDays:2026-W39",
            kind: .reduceDays,
            rule: "R4",
            title: "Menos dias por semana",
            reason: "Aderência de 40%.",
            referenceTopic: "topic.frequency"
        )

        XCTAssertEqual(
            service.applyDetail(for: deload),
            "As próximas sessões, uma de cada dia do programa, ficam mais leves: cerca de 60% das séries, com cargas 15% menores."
        )
        XCTAssertTrue(service.applyDetail(for: reduceDays)?.hasPrefix("Nada muda sozinho") ?? false)
    }
}
