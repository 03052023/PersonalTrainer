import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.11 C4 (installation expiry), C5 (comeback), C6 (best mark), C7 (backup) and
// C8 (longevity blocks).

private typealias CF = CoachFixtures

@Suite("Coach — C4 a C8 lembretes")
struct CoachRemindersTests {
    // MARK: C4

    struct ExpiryCase: Sendable, CustomTestStringConvertible {
        let expiry: Date
        let title: String?
        let label: String

        var testDescription: String { label }
    }

    // `now` is Wednesday 2026-09-23 12:00 UTC.
    static let expiryCases: [ExpiryCase] = [
        ExpiryCase(expiry: CoachFixtures.at(5, hour: 8), title: nil, label: "sábado: 3 dias antes, ainda nada"),
        ExpiryCase(expiry: CoachFixtures.at(4, hour: 23), title: "O app expira em 2 dias", label: "sexta: 2 dias antes"),
        ExpiryCase(expiry: CoachFixtures.at(3, hour: 1), title: "O app expira amanhã", label: "quinta: véspera"),
        ExpiryCase(expiry: CoachFixtures.at(2, hour: 18), title: "O app expira hoje", label: "hoje mais tarde"),
        ExpiryCase(expiry: CoachFixtures.at(2, hour: 12), title: nil, label: "expira agora: o app já não abre"),
        ExpiryCase(expiry: CoachFixtures.at(1, hour: 12), title: nil, label: "já expirou"),
    ]

    @Test("C4 a partir de 2 dias antes da expiração", arguments: CoachRemindersTests.expiryCases)
    func expiryWindow(_ testCase: ExpiryCase) {
        let feed = CF.feed(CoachInput(provisioningExpiry: testCase.expiry))

        #expect(feed.map(\.title) == (testCase.title.map { [$0] } ?? []))
    }

    @Test("C4 mensagem: data e hora da expiração, Como renovar, sem tópico, no topo e em destaque")
    func expiryMessage() throws {
        let message = try #require(CF.feed(CoachInput(provisioningExpiry: CF.at(4, hour: 23))).first)

        #expect(message.id == "expiry:2026-09-25:\(CF.today)")
        #expect(message.rule == .installExpiry)
        #expect(message.reason.contains("25/09 às 23:00"))
        #expect(message.reason.contains("Impactor"))
        #expect(message.actions == [.howToRenew])
        #expect(message.referenceTopic == nil)
        #expect(message.priority == 0)
        #expect(message.highlightsOnLaunch)
    }

    @Test("C4 uma por dia: respondida hoje some e volta amanhã")
    func expiryOncePerDay() {
        let input = CoachInput(provisioningExpiry: CF.at(4, hour: 23))
        var log = CoachLog()
        for message in CF.feed(input) {
            log.record(message, action: .howToRenew, at: CF.now)
        }

        #expect(CF.feed(input, log: log).isEmpty)
        #expect(CF.feed(input, log: log, now: CF.at(3, hour: 9)).map(\.id) == ["expiry:2026-09-25:2026-09-24"])
    }

    // MARK: C5

    struct ComebackCase: Sendable, CustomTestStringConvertible {
        let lastSessionStart: Date?
        let id: String?
        let label: String

        var testDescription: String { label }
    }

    static let comebackCases: [ComebackCase] = [
        ComebackCase(lastSessionStart: nil, id: nil, label: "nunca treinou"),
        ComebackCase(lastSessionStart: CoachFixtures.at(-3), id: nil, label: "5 dias de calendário"),
        ComebackCase(lastSessionStart: CoachFixtures.at(-4, hour: 23), id: "comeback:2026-09-17", label: "6 dias de calendário"),
        ComebackCase(
            lastSessionStart: CoachFixtures.now.addingTimeInterval(-21 * 86_400),
            id: "comeback:2026-09-02",
            label: "21 dias exatos: P9 ainda não reduz"
        ),
        ComebackCase(
            lastSessionStart: CoachFixtures.now.addingTimeInterval(-21 * 86_400 - 1),
            id: "comeback:2026-09-02:reduced",
            label: "21 dias e 1 segundo: P9 reduz as cargas"
        ),
    ]

    @Test("C5 a partir de 6 dias sem sessão; depois de 21 dias avisa das cargas reduzidas (P9)", arguments: CoachRemindersTests.comebackCases)
    func comebackThresholds(_ testCase: ComebackCase) {
        let feed = CF.feed(CoachInput(lastSessionStart: testCase.lastSessionStart, nextDayName: "Dia B"))

        #expect(feed.map(\.id) == (testCase.id.map { [$0] } ?? []))
        if let message = feed.first {
            let reduced = testCase.id?.hasSuffix(":reduced") == true
            #expect(message.reason.contains("mais de 21 dias") == reduced)
            #expect(message.reason.contains("10% menores") == reduced)
        }
    }

    @Test("C5 mensagem: dias sem sessão, próximo dia, Começar, rule.P9, em destaque")
    func comebackMessage() throws {
        let message = try #require(
            CF.feed(CoachInput(lastSessionStart: CF.at(-5), nextDayName: " Dia B ")).first
        )

        #expect(message.title == "Bom te ver de volta")
        #expect(message.reason == "Sua última sessão foi há 7 dias; voltar também é progresso. Hoje o plano é Dia B.")
        #expect(message.actions == [.start])
        #expect(message.referenceTopic == "rule.P9")
        #expect(message.highlightsOnLaunch)
    }

    @Test("C5 sem nome do próximo dia, o motivo não fala do plano")
    func comebackWithoutNextDay() throws {
        let unnamed = try #require(CF.feed(CoachInput(lastSessionStart: CF.at(-5))).first)
        let blank = try #require(CF.feed(CoachInput(lastSessionStart: CF.at(-5), nextDayName: "  ")).first)

        #expect(unnamed.reason == "Sua última sessão foi há 7 dias; voltar também é progresso.")
        #expect(blank.reason == unnamed.reason)
    }

    @Test("C5 quem respondeu à volta simples ainda vê o aviso de cargas reduzidas")
    func reducedWarningIsANewMessage() {
        let last = CF.at(-5)
        let input = CoachInput(lastSessionStart: last)
        var log = CoachLog()
        for message in CF.feed(input) {
            log.record(message, action: .start, at: CF.now)
        }

        #expect(CF.feed(input, log: log).isEmpty)
        #expect(CF.feed(input, log: log, now: CF.at(20)).map(\.id) == ["comeback:2026-09-16:reduced"])
    }

    // MARK: C6

    @Test("C6 melhor marca: série, estimativa anterior e nova, Ver evolução, topic.e1rm")
    func personalRecordMessage() throws {
        let record = CF.record(exercise: 101, load: 105, reps: 5, previousBest: 100 * (1 + 5.0 / 30))
        let input = CoachInput(personalRecords: [record], exerciseNames: [CF.id(101): "Supino reto"])

        let message = try #require(CF.feed(input).first)
        let exercise = CF.id(101).uuidString

        #expect(message.id == "record:\(exercise):105x5")
        #expect(message.rule == .personalRecord)
        #expect(message.itemKey == exercise)
        #expect(message.suggestionID == exercise)
        #expect(message.title == "Nova melhor marca")
        #expect(message.reason == "Supino reto: 105 kg × 5 repetições; sua força estimada para 1 repetição subiu de 116,7 kg para 122,5 kg.")
        #expect(message.actions == [.seeProgress])
        #expect(message.referenceTopic == "topic.e1rm")
        #expect(!message.highlightsOnLaunch)
    }

    @Test("C6 placas ou nível sem kg; nome ausente; 1 repetição; sem marca anterior")
    func personalRecordTextVariants() throws {
        let plates = CF.record(exercise: 101, load: 7, reps: 10, previousBest: 8.5)
        let single = CF.record(exercise: 102, load: 102.5, reps: 1, previousBest: nil)
        let input = CoachInput(
            personalRecords: [single, plates],
            exerciseNames: [CF.id(101): "Cadeira extensora"],
            loadUnits: [CF.id(101): .plates]
        )

        let feed = CF.feed(input)

        #expect(feed.map(\.reason) == [
            "Cadeira extensora: 7 × 10 repetições; sua força estimada para 1 repetição subiu de 8,5 para 9,3.",
            "Exercício: 102,5 kg × 1 repetição; sua força estimada para 1 repetição chegou a 102,5 kg.",
        ])
        #expect(feed.map(\.id) == [
            "record:\(CF.id(101).uuidString):7x10",
            "record:\(CF.id(102).uuidString):102.5x1",
        ])
    }

    @Test("C6 uma mensagem por exercício, ordenadas pelo id; respondida some")
    func personalRecordsSortedAndAnswered() throws {
        let first = CF.record(exercise: 101, load: 105, reps: 5, previousBest: 110)
        let second = CF.record(exercise: 103, load: 42.5, reps: 10, previousBest: 55)
        let input = CoachInput(personalRecords: [second, first])
        let feed = CF.feed(input)
        let answered = try #require(feed.first)
        var log = CoachLog()
        log.record(answered, action: .seeProgress, at: CF.now)

        #expect(feed.map(\.itemKey) == [CF.id(101).uuidString, CF.id(103).uuidString])
        #expect(feed.map(\.priority) == [400, 401])
        #expect(CF.feed(input, log: log).map(\.itemKey) == [CF.id(103).uuidString])
    }

    // MARK: C7

    struct BackupCase: Sendable, CustomTestStringConvertible {
        let lastBackupAt: Date?
        let sessions: Int
        let shown: Bool
        let label: String

        var testDescription: String { label }
    }

    static let backupCases: [BackupCase] = [
        BackupCase(lastBackupAt: CoachFixtures.at(-11, hour: 9), sessions: 30, shown: false, label: "backup há 13 dias"),
        BackupCase(lastBackupAt: CoachFixtures.at(-12, hour: 9), sessions: 30, shown: true, label: "backup há 14 dias"),
        BackupCase(lastBackupAt: CoachFixtures.at(-12, hour: 9), sessions: 0, shown: true, label: "backup antigo, sem sessões novas contadas"),
        BackupCase(lastBackupAt: nil, sessions: 4, shown: false, label: "nunca, com 4 sessões"),
        BackupCase(lastBackupAt: nil, sessions: 5, shown: true, label: "nunca, com 5 sessões"),
    ]

    @Test("C7 backup há 14 dias ou mais, ou nunca feito com 5 sessões ou mais", arguments: CoachRemindersTests.backupCases)
    func backupThresholds(_ testCase: BackupCase) {
        let input = CoachInput(lastBackupAt: testCase.lastBackupAt, completedSessionCount: testCase.sessions)

        #expect(CF.feed(input).map(\.id) == (testCase.shown ? ["backup:\(CF.week)"] : []))
    }

    @Test("C7 mensagem: dias ou sessões no motivo, Fazer backup / Depois, sem tópico")
    func backupMessage() throws {
        let stale = try #require(CF.feed(CoachInput(lastBackupAt: CF.at(-20))).first)
        let never = try #require(CF.feed(CoachInput(completedSessionCount: 1_200)).first)

        #expect(stale.reason.hasPrefix("Seu último backup foi há 22 dias;"))
        #expect(never.reason.hasPrefix("Você já tem 1.200 sessões registradas e ainda nenhum backup;"))
        #expect(stale.actions == [.backupNow, .later])
        #expect(stale.referenceTopic == nil)
        #expect(!stale.highlightsOnLaunch)
    }

    @Test("C7 uma por semana: respondida nesta semana ISO some, na semana passada volta")
    func backupOncePerWeek() {
        let input = CoachInput(completedSessionCount: 8)
        let thisWeek = CF.log([CF.entry("backup:2026-W39", .backup, "backup", .later, at: CF.at(0, hour: 8))])
        let lastWeek = CF.log([CF.entry("backup:2026-W38", .backup, "backup", .later, at: CF.at(-1, hour: 20))])

        #expect(CF.feed(input, log: thisWeek).isEmpty)
        #expect(CF.feed(input, log: lastWeek).map(\.id) == ["backup:2026-W39"])
    }

    // MARK: C8

    struct LongevityCase: Sendable, CustomTestStringConvertible {
        let goal: ProgramGoal?
        let done: Set<String>
        let itemKeys: [String]
        let label: String

        var testDescription: String { label }
    }

    static let longevityCases: [LongevityCase] = [
        LongevityCase(goal: nil, done: [], itemKeys: [], label: "sem objetivo"),
        LongevityCase(goal: .hypertrophy, done: [], itemKeys: [], label: "hipertrofia"),
        LongevityCase(goal: .longevity, done: [], itemKeys: ["balance", "mobility"], label: "longevidade, nada marcado"),
        LongevityCase(goal: .longevity, done: ["balance"], itemKeys: ["mobility"], label: "equilíbrio marcado"),
        LongevityCase(goal: .longevity, done: ["mobility"], itemKeys: ["balance"], label: "mobilidade marcada"),
        LongevityCase(goal: .longevity, done: ["balance", "mobility"], itemKeys: [], label: "tudo marcado"),
    ]

    @Test("C8 só com objetivo Longevidade, se equilíbrio ou mobilidade não foram marcados", arguments: CoachRemindersTests.longevityCases)
    func longevityBlocks(_ testCase: LongevityCase) {
        let feed = CF.feed(CoachInput(goal: testCase.goal, longevityDoneThisWeek: testCase.done))

        #expect(feed.map(\.itemKey) == testCase.itemKeys)
        #expect(feed.map(\.id) == testCase.itemKeys.map { "longevity:\($0):\(CF.week)" })
    }

    @Test("C8 mensagem: 5 a 10 minutos, Feito / Pular, goal.longevity; uma por semana")
    func longevityMessageAndCadence() throws {
        let input = CoachInput(goal: .longevity, longevityDoneThisWeek: [CoachInput.mobilityKey])
        let message = try #require(CF.feed(input).first)
        let thisWeek = CF.log([CF.entry(message.id, .longevity, "balance", .skip, at: CF.at(0, hour: 9))])
        let lastWeek = CF.log([CF.entry("longevity:balance:2026-W38", .longevity, "balance", .done, at: CF.at(-2))])

        #expect(message.title == "Equilíbrio: 5 a 10 minutos")
        #expect(message.reason.contains("2 a 3 vezes por semana"))
        #expect(message.actions == [.done, .skip])
        #expect(message.referenceTopic == "goal.longevity")
        #expect(CF.feed(input, log: thisWeek).isEmpty)
        #expect(CF.feed(input, log: lastWeek).map(\.id) == ["longevity:balance:\(CF.week)"])
    }
}
