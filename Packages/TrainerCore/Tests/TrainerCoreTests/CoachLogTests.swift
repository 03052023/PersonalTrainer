import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.11: "Decisões ficam registradas localmente (log JSON) para auditoria e para
// não repetir."

private typealias CF = CoachFixtures

@Suite("Coach — log de decisões")
struct CoachLogTests {
    static let message = CoachMessage(
        id: "backup:2026-W39",
        rule: .backup,
        itemKey: "backup",
        title: "Faça um backup do seu histórico",
        reason: "Motivo.",
        referenceTopic: nil,
        actions: [.backupNow, .later],
        priority: 600,
        highlightsOnLaunch: false
    )

    @Test("C7 record guarda id, regra, chave, ação e data, em ordem, sem mexer em lastReviewAt")
    func recordAppendsTheAnswer() {
        var log = CoachLog(lastReviewAt: CF.at(-28))
        log.record(Self.message, action: .later, at: CF.at(0))
        log.record(Self.message, action: .backupNow, at: CF.at(1))

        #expect(log.entries == [
            CoachLogEntry(messageID: "backup:2026-W39", rule: .backup, itemKey: "backup", action: .later, date: CF.at(0)),
            CoachLogEntry(messageID: "backup:2026-W39", rule: .backup, itemKey: "backup", action: .backupNow, date: CF.at(1)),
        ])
        #expect(log.lastReviewAt == CF.at(-28))
    }

    @Test("C2 o log vai e volta em JSON; sem lastReviewAt decodifica como nil")
    func logRoundTripsThroughJSON() throws {
        var log = CoachLog(lastReviewAt: CF.now)
        log.record(Self.message, action: .neverAgain, at: CF.now)

        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(CoachLog.self, from: data)
        let legacy = try JSONDecoder().decode(CoachLog.self, from: Data(#"{"entries":[]}"#.utf8))

        #expect(decoded == log)
        #expect(legacy == CoachLog())
    }

    @Test("C1–C8 a mensagem vai e volta em JSON")
    func messageRoundTripsThroughJSON() throws {
        let feed = CF.feed(CF.fullInput())

        let data = try JSONEncoder().encode(feed)

        #expect(try JSONDecoder().decode([CoachMessage].self, from: data) == feed)
    }

    @Test("C1–C8 raw values persistidos são estáveis")
    func rawValuesAreStable() {
        #expect(CoachRule.allCases.map(\.rawValue) == [
            "deload", "review", "health", "installExpiry", "comeback", "personalRecord", "backup", "longevity",
        ])
        #expect(CoachAction.allCases.map(\.rawValue) == [
            "ok", "keepNormal", "apply", "notNow", "neverAgain", "understood", "remindTomorrow", "howToRenew",
            "start", "seeProgress", "backupNow", "later", "done", "skip",
        ])
    }

    @Test("C1–C8 rótulos das ações em pt-BR, como na SPEC §7.11")
    func actionLabels() {
        #expect(CoachAction.allCases.map(\.label) == [
            "Ok", "Seguir normal", "Aplicar", "Agora não", "Não sugerir mais isto", "Entendi", "Lembrar amanhã",
            "Como renovar", "Começar", "Ver evolução", "Fazer backup", "Depois", "Feito", "Pular",
        ])
    }

    @Test("C2 consultas do log: respondida, silenciada e resposta mais recente")
    func logQueries() {
        let log = CF.log([
            CF.entry("a:1", .review, "a", .notNow, at: CF.at(0)),
            CF.entry("a:2", .review, "a", .neverAgain, at: CF.at(-3)),
            CF.entry("a:3", .health, "a", .understood, at: CF.at(1)),
        ])

        #expect(log.hasAnswered(messageID: "a:1"))
        #expect(!log.hasAnswered(messageID: "a:9"))
        #expect(log.isSilenced(rule: .review, itemKey: "a"))
        #expect(!log.isSilenced(rule: .health, itemKey: "a"))
        #expect(log.latestEntry(rule: .review, itemKey: "a")?.messageID == "a:1")
        #expect(log.latestEntry(rule: .backup, itemKey: "a") == nil)
    }
}
