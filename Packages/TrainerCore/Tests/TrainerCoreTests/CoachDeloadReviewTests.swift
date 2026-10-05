import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.11 C1 (lighter week) and C2 (periodic review suggestions).

private typealias CF = CoachFixtures

@Suite("Coach — C1 semana leve e C2 revisão")
struct CoachDeloadReviewTests {
    // MARK: C1

    @Test("C1 sem semana leve programada, ou com ela em andamento, não há mensagem")
    func noMessageWithoutScheduledDeload() {
        #expect(CF.feed(CoachInput(deload: .none)).isEmpty)
        #expect(CF.feed(CoachInput(deload: .running(start: CF.at(0, hour: 9)))).isEmpty)
    }

    @Test("C1 semana leve programada: id com o dia do agendamento, Ok / Seguir normal, destaque")
    func scheduledDeloadMessage() throws {
        let input = CoachInput(deload: .scheduled(trigger: .manyDecreases, since: CF.at(0, hour: 10)))

        let message = try #require(CF.feed(input).first)

        #expect(message.id == "deload:2026-09-21")
        #expect(message.rule == .deload)
        #expect(message.itemKey == DeloadTrigger.manyDecreases.rawValue)
        #expect(message.title == "Semana mais leve programada")
        #expect(message.actions == [.ok, .keepNormal])
        #expect(message.referenceTopic == "rule.D")
        #expect(message.highlightsOnLaunch)
        #expect(message.suggestionID == nil)
    }

    struct TriggerCase: Sendable, CustomTestStringConvertible {
        let trigger: DeloadTrigger
        let opening: String

        var testDescription: String { trigger.rawValue }
    }

    static let triggerCases: [TriggerCase] = [
        TriggerCase(trigger: .manyDecreases, opening: "Em metade ou mais dos exercícios a carga precisou baixar;"),
        TriggerCase(trigger: .scheduled, opening: "Chegou a semana leve programada no seu plano;"),
        TriggerCase(trigger: .manual, opening: "Você pediu uma semana mais leve;"),
    ]

    @Test("C1 o motivo diz o gatilho e os números da semana leve (60% das séries, cargas 15% menores)", arguments: CoachDeloadReviewTests.triggerCases)
    func reasonNamesTheTrigger(_ testCase: TriggerCase) throws {
        let input = CoachInput(deload: .scheduled(trigger: testCase.trigger, since: CF.at(0)))

        let message = try #require(CF.feed(input).first)

        #expect(message.reason.hasPrefix(testCase.opening))
        #expect(message.reason.contains("60% das séries"))
        #expect(message.reason.contains("15% menores"))
    }

    @Test("C1 respondida some; um novo agendamento volta a falar")
    func answeredDeloadWaitsForTheNextScheduling() {
        let log = CF.log([CF.entry("deload:2026-09-21", .deload, "scheduled", .ok, at: CF.at(0, hour: 11))])
        let sameScheduling = CoachInput(deload: .scheduled(trigger: .scheduled, since: CF.at(0, hour: 10)))
        let newScheduling = CoachInput(deload: .scheduled(trigger: .scheduled, since: CF.at(2, hour: 8)))

        #expect(CF.feed(sameScheduling, log: log).isEmpty)
        #expect(CF.feed(newScheduling, log: log).map(\.id) == ["deload:2026-09-23"])
    }

    @Test("C1 o dia do id segue o fuso do calendário")
    func deloadDayFollowsTheCalendar() throws {
        // 2026-09-21 01:00 UTC is still 2026-09-20 in São Paulo (UTC−3).
        let input = CoachInput(deload: .scheduled(trigger: .manual, since: CF.at(0, hour: 1)))
        let saoPaulo = try ReviewFixtures.saoPaulo()

        #expect(CF.feed(input).map(\.id) == ["deload:2026-09-21"])
        #expect(CF.feed(input, calendar: saoPaulo).map(\.id) == ["deload:2026-09-20"])
    }

    // MARK: C1 with numbers (2.4, TASKS B11)

    struct NumbersCase: Sendable, CustomTestStringConvertible {
        let label: String
        let trigger: DeloadTrigger
        let detail: DeloadTriggerDetail?
        let opening: String

        var testDescription: String { label }
    }

    static let numbersCases: [NumbersCase] = [
        NumbersCase(
            label: "(a) 4 de 7",
            trigger: .manyDecreases,
            detail: DeloadTriggerDetail(trigger: .manyDecreases, decreasedExercises: 4, countedExercises: 7),
            opening: "Em 4 de 7 exercícios a carga precisou baixar; "
        ),
        NumbersCase(
            label: "(a) 1 de 2",
            trigger: .manyDecreases,
            detail: DeloadTriggerDetail(trigger: .manyDecreases, decreasedExercises: 1, countedExercises: 2),
            opening: "Em 1 de 2 exercícios a carga precisou baixar; "
        ),
        NumbersCase(
            label: "(a) singular: 1 de 1 exercício",
            trigger: .manyDecreases,
            detail: DeloadTriggerDetail(trigger: .manyDecreases, decreasedExercises: 1, countedExercises: 1),
            opening: "Em 1 de 1 exercício a carga precisou baixar; "
        ),
        NumbersCase(
            label: "(b) 6 semanas desde a última semana leve",
            trigger: .scheduled,
            detail: DeloadTriggerDetail(trigger: .scheduled, weeksSinceAnchor: 6, anchorIsLastDeload: true),
            opening: "Já são 6 semanas desde a última semana leve; "
        ),
        NumbersCase(
            label: "(b) 6 semanas desde a primeira sessão, sem semana leve antes",
            trigger: .scheduled,
            detail: DeloadTriggerDetail(trigger: .scheduled, weeksSinceAnchor: 6, anchorIsLastDeload: false),
            opening: "Já são 6 semanas desde a primeira sessão; "
        ),
        NumbersCase(
            label: "(b) singular: 1 semana",
            trigger: .scheduled,
            detail: DeloadTriggerDetail(trigger: .scheduled, weeksSinceAnchor: 1, anchorIsLastDeload: true,
                                        weeksBetweenDeloads: 1),
            opening: "Já faz 1 semana desde a última semana leve; "
        ),
        NumbersCase(
            label: "sem detalhe, (a): o texto sem números",
            trigger: .manyDecreases,
            detail: nil,
            opening: "Em metade ou mais dos exercícios a carga precisou baixar; "
        ),
        NumbersCase(
            label: "sem detalhe, (b): o texto sem números",
            trigger: .scheduled,
            detail: nil,
            opening: "Chegou a semana leve programada no seu plano; "
        ),
        NumbersCase(
            label: "detalhe de outro gatilho é ignorado",
            trigger: .scheduled,
            detail: DeloadTriggerDetail(trigger: .manyDecreases, decreasedExercises: 4, countedExercises: 7),
            opening: "Chegou a semana leve programada no seu plano; "
        ),
        NumbersCase(
            label: "pedido manual: sem números, mesmo com detalhe",
            trigger: .manual,
            detail: DeloadTriggerDetail(trigger: .manual),
            opening: "Você pediu uma semana mais leve; "
        ),
        NumbersCase(
            label: "(a) sem reduções contadas: o texto sem números",
            trigger: .manyDecreases,
            detail: DeloadTriggerDetail(trigger: .manyDecreases, decreasedExercises: 0, countedExercises: 0),
            opening: "Em metade ou mais dos exercícios a carga precisou baixar; "
        ),
        NumbersCase(
            label: "(b) 0 semanas: o texto sem números",
            trigger: .scheduled,
            detail: DeloadTriggerDetail(trigger: .scheduled, weeksSinceAnchor: 0),
            opening: "Chegou a semana leve programada no seu plano; "
        ),
    ]

    @Test("C1 motivo com os números do gatilho", arguments: CoachDeloadReviewTests.numbersCases)
    func reasonHasTheTriggerNumbers(_ testCase: NumbersCase) throws {
        let input = CoachInput(
            deload: .scheduled(trigger: testCase.trigger, since: CF.at(0, hour: 10)),
            deloadDetail: testCase.detail
        )

        let message = try #require(CF.feed(input).first)

        #expect(message.reason.hasPrefix(testCase.opening))
        // The content after the opening is the 2.3 one, the same with or without numbers.
        #expect(message.reason.hasSuffix(
            "nas próximas sessões, uma de cada dia do programa, você fará cerca de 60% das séries "
                + "com cargas 15% menores, para o corpo se recuperar."
        ))
        // The numbers change only the reason: id, title and actions stay.
        #expect(message.id == "deload:2026-09-21")
        #expect(message.title == "Semana mais leve programada")
        #expect(message.actions == [.ok, .keepNormal])
    }

    @Test("C1 o detalhe não cria mensagem sem semana leve programada")
    func detailAloneSaysNothing() {
        let detail = DeloadTriggerDetail(trigger: .scheduled, weeksSinceAnchor: 6, anchorIsLastDeload: true)

        #expect(CF.feed(CoachInput(deload: .none, deloadDetail: detail)).isEmpty)
        #expect(CF.feed(CoachInput(deload: .running(start: CF.at(0)), deloadDetail: detail)).isEmpty)
    }

    // MARK: C2

    @Test("C2 sem revisão, nenhuma mensagem de revisão")
    func noReviewNoMessage() {
        #expect(CF.feed(CoachInput(review: nil)).isEmpty)
        #expect(CF.feed(CoachInput(review: CF.report([]))).isEmpty)
    }

    @Test("C2 uma mensagem por sugestão, na ordem do relatório, com id, chave, sugestão e tópico")
    func oneMessagePerSuggestionInReportOrder() {
        let target = CF.id(201).uuidString
        let program = CF.id(1).uuidString
        let report = CF.report([
            CF.suggestion(.deload, id: "deload:2026-W39", topic: "rule.D"),
            CF.suggestion(.addSets, id: CF.addSetsID(target: 201)),
            CF.suggestion(.switchProgram, id: "switchProgram:\(program):2026-W39", topic: "topic.mesocycle"),
        ])

        let feed = CF.feed(CoachInput(review: report))

        #expect(feed.map(\.id) == [
            "review:deload:2026-W39",
            "review:addSets:chest:\(target):2026-W39",
            "review:switchProgram:\(program):2026-W39",
        ])
        #expect(feed.map(\.itemKey) == ["deload", "addSets:chest:\(target)", "switchProgram:\(program)"])
        #expect(feed.map(\.suggestionID) == report.suggestions.map { Optional($0.id) })
        #expect(feed.map(\.referenceTopic) == ["rule.D", "topic.volume", "topic.mesocycle"])
        #expect(feed.map(\.title) == report.suggestions.map(\.title))
        #expect(feed.map(\.reason) == report.suggestions.map(\.reason))
        #expect(feed.map(\.priority) == [300, 301, 302])
        #expect(feed.allSatisfy { $0.rule == .review && $0.highlightsOnLaunch })
        #expect(feed.allSatisfy { $0.actions == [.apply, .notNow, .neverAgain] })
    }

    @Test("C2 Agora não esconde a sugestão só até a próxima revisão")
    func notNowWaitsForTheNextReview() {
        let week39 = CoachInput(review: CF.report([CF.suggestion(.addSets, id: CF.addSetsID(target: 201))]))
        let week43 = CoachInput(
            review: CF.report([CF.suggestion(.addSets, id: CF.addSetsID(target: 201, week: "2026-W43"))])
        )
        var log = CoachLog()
        for message in CF.feed(week39) {
            log.record(message, action: .notNow, at: CF.now)
        }

        #expect(CF.feed(week39, log: log).isEmpty)
        #expect(CF.feed(week43, log: log, now: CF.at(29)).count == 1)
    }

    @Test("C2 Não sugerir mais isto silencia o mesmo item nas revisões seguintes")
    func neverAgainOutlivesTheReview() {
        let week39 = CoachInput(review: CF.report([CF.suggestion(.addSets, id: CF.addSetsID(target: 201))]))
        let week43 = CoachInput(
            review: CF.report([
                CF.suggestion(.addSets, id: CF.addSetsID(target: 201, week: "2026-W43")),
                CF.suggestion(.addSets, id: CF.addSetsID(target: 202, week: "2026-W43")),
            ])
        )
        var log = CoachLog()
        for message in CF.feed(week39) {
            log.record(message, action: .neverAgain, at: CF.now)
        }

        #expect(CF.feed(week43, log: log, now: CF.at(29)).map(\.itemKey) == ["addSets:chest:\(CF.id(202).uuidString)"])
    }

    struct DeloadStateCase: Sendable, CustomTestStringConvertible {
        let state: CoachDeloadState
        let showsDeloadSuggestion: Bool
        let label: String

        var testDescription: String { label }
    }

    static let deloadStateCases: [DeloadStateCase] = [
        DeloadStateCase(state: .none, showsDeloadSuggestion: true, label: "sem semana leve"),
        DeloadStateCase(
            state: .scheduled(trigger: .scheduled, since: CoachFixtures.at(0)),
            showsDeloadSuggestion: false,
            label: "semana leve programada"
        ),
        DeloadStateCase(
            state: .running(start: CoachFixtures.at(0)),
            showsDeloadSuggestion: false,
            label: "semana leve em andamento"
        ),
    ]

    @Test("C2 R5 não sugere semana leve com uma programada ou em andamento", arguments: CoachDeloadReviewTests.deloadStateCases)
    func noDeloadSuggestionWhileOneIsPlanned(_ testCase: DeloadStateCase) {
        let report = CF.report([
            CF.suggestion(.deload, id: "deload:2026-W39", topic: "rule.D"),
            CF.suggestion(.addSets, id: CF.addSetsID(target: 201)),
        ])

        let reviewIDs = CF.feed(CoachInput(deload: testCase.state, review: report))
            .filter { $0.rule == .review }
            .map(\.id)

        #expect(reviewIDs.contains("review:deload:2026-W39") == testCase.showsDeloadSuggestion)
        #expect(reviewIDs.contains("review:\(CF.addSetsID(target: 201))"))
    }

    struct ItemKeyCase: Sendable, CustomTestStringConvertible {
        let suggestionID: String
        let itemKey: String

        var testDescription: String { suggestionID }
    }

    static let itemKeyCases: [ItemKeyCase] = [
        ItemKeyCase(suggestionID: "addSets:chest:ABC:2026-W39", itemKey: "addSets:chest:ABC"),
        ItemKeyCase(suggestionID: "deload:2026-W39", itemKey: "deload"),
        ItemKeyCase(suggestionID: "reduceDays:2027-W01", itemKey: "reduceDays"),
        ItemKeyCase(suggestionID: "custom", itemKey: "custom"),
        ItemKeyCase(suggestionID: "swap:2026-39", itemKey: "swap:2026-39"),
        ItemKeyCase(suggestionID: "swap:2026-W3", itemKey: "swap:2026-W3"),
        ItemKeyCase(suggestionID: "swap:26-W39", itemKey: "swap:26-W39"),
    ]

    @Test("C2 a chave do item é o id da sugestão sem a semana ISO do fim", arguments: CoachDeloadReviewTests.itemKeyCases)
    func itemKeyDropsTheTrailingWeek(_ testCase: ItemKeyCase) {
        #expect(CoachFeedBuilder.reviewItemKey(suggestionID: testCase.suggestionID) == testCase.itemKey)
    }
}
