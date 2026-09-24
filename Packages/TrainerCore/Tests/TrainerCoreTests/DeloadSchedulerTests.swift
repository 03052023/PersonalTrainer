import Foundation
import Testing
@testable import TrainerCore

/// Table cases for `DeloadScheduler`: SPEC §7.5 (triggers, re-arm, duration) and
/// §7.11 C1. Every instant is fixed (SPEC P11): `Fixture.now` plays "today" and
/// scenarios place sessions, history entries and decisions in days before it.
/// Unless a case says otherwise the program has 3 days and N = 6 weeks.
@Suite("DeloadScheduler")
struct DeloadSchedulerTests {
    // MARK: - C1 — triggers through the scheduler

    @Test("C1 gatilhos (a) e (b) calculados pelo agendador", arguments: DeloadSchedulerTests.Scenario.triggers)
    func C1_triggers(_ scenario: Scenario) {
        #expect(Fixture.status(scenario) == Fixture.expected(scenario.expected))
    }

    @Test("C1 prioridade: em andamento > manual > (a) > (b); programa sem dias → inativo",
          arguments: DeloadSchedulerTests.Scenario.priority)
    func C1_priority(_ scenario: Scenario) {
        #expect(Fixture.status(scenario) == Fixture.expected(scenario.expected))
    }

    @Test("C1 Seguir normal (dismissedAt) adia (a) e (b)", arguments: DeloadSchedulerTests.Scenario.keepNormal)
    func C1_keepNormal_postponesAutomaticTriggers(_ scenario: Scenario) {
        #expect(Fixture.status(scenario) == Fixture.expected(scenario.expected))
    }

    @Test("C1 N padrão do agendador é o da política (6 semanas)")
    func C1_defaultWeeksMatchesPolicy() {
        let sessions = [Fixture.session(.normal(1, 42))]
        let justBefore = [Fixture.session(.normal(1, 42.0 - 1.0 / 86_400.0))]

        let atSix = DeloadScheduler.status(
            normalPrescriptions: [],
            histories: [:],
            sessions: sessions,
            programDayCount: 3,
            decisions: DeloadDecisions(),
            now: Fixture.now
        )
        let beforeSix = DeloadScheduler.status(
            normalPrescriptions: [],
            histories: [:],
            sessions: justBefore,
            programDayCount: 3,
            decisions: DeloadDecisions(),
            now: Fixture.now
        )

        #expect(atSix == .pending(trigger: .scheduled))
        #expect(beforeSix == .inactive)
    }

    // MARK: - §7.5 re-arm of (a)

    @Test("D_rearm (a) só conta decrease vindo de sessão posterior ao fim do último deload",
          arguments: DeloadSchedulerTests.Scenario.rearm)
    func D_rearm_decreasesAfterLastDeloadEnd(_ scenario: Scenario) {
        #expect(Fixture.status(scenario) == Fixture.expected(scenario.expected))
    }

    @Test("D_rearm (b) conta do início do último deload; nova passagem não soma à anterior",
          arguments: DeloadSchedulerTests.Scenario.scheduledAnchor)
    func D_rearm_scheduledAnchor(_ scenario: Scenario) {
        #expect(Fixture.status(scenario) == Fixture.expected(scenario.expected))
    }

    @Test("D_rearm depois do deload, as mesmas reduções não disparam outro (CA4-3)")
    func D_rearm_sameDecreasesDoNotRetrigger() {
        // Before: two of three exercises failed twice at the same load → (a).
        let before = Scenario(
            "antes",
            sessions: [.normal(1, 30), .normal(2, 12)],
            exercises: [.decrease(12), .decrease(12), .hold(12)],
            expected: .pending(.manyDecreases)
        )
        // After one light pass the normal prescriptions are unchanged (SPEC P3):
        // the same notes, from the same sessions, must not schedule another deload.
        let after = Scenario(
            "depois",
            sessions: [.normal(1, 30), .normal(2, 12), .deload(3, 10), .deload(4, 8), .deload(5, 6)],
            exercises: [.decrease(12), .decrease(12), .hold(12)],
            expected: .inactive
        )

        #expect(Fixture.status(before) == Fixture.expected(before.expected))
        #expect(Fixture.status(after) == Fixture.expected(after.expected))
    }

    // MARK: - §7.5 duration — runs of deload sessions

    @Test("D_sequence início, passagem e separação das sequências de deload",
          arguments: DeloadSchedulerTests.Scenario.sequences)
    func D_sequence_runsOfDeloadSessions(_ scenario: Scenario) {
        #expect(Fixture.status(scenario) == Fixture.expected(scenario.expected))
    }

    // MARK: - §7.5 (c) manual

    @Test("D_manual pedido posterior ao último deload e sem sessão de deload desde então",
          arguments: DeloadSchedulerTests.Scenario.manual)
    func D_manual_pendingUntilADeloadSessionStarts(_ scenario: Scenario) {
        #expect(Fixture.status(scenario) == Fixture.expected(scenario.expected))
    }

    // MARK: - SPEC P11 — determinism

    @Test("D_determinism a ordem das sessões, das entradas e das prescrições não importa",
          arguments: DeloadSchedulerTests.Scenario.determinism)
    func D_determinism_inputOrderIsIrrelevant(_ scenario: Scenario) {
        let expected = Fixture.expected(scenario.expected)

        for permutation in Permutation.allCases {
            #expect(Fixture.status(scenario, permutation: permutation) == expected, "\(permutation)")
        }
    }

    @Test("D_determinism sessão repetida (mesmo id) conta uma vez, em qualquer ordem")
    func D_determinism_duplicatedSessionCountsOnce() {
        // The session that completed the pass delivered twice: the copy must not
        // open a second light week.
        let completed: [SessionSummary] = [
            Fixture.session(.normal(1, 20)),
            Fixture.session(.deload(2, 6)),
            Fixture.session(.deload(3, 4)),
            Fixture.session(.deload(4, 2)),
            Fixture.session(.deload(4, 2)),
        ]
        // Two of three done, one of them delivered twice: still running.
        let running: [SessionSummary] = [
            Fixture.session(.normal(1, 20)),
            Fixture.session(.deload(2, 4)),
            Fixture.session(.deload(3, 2)),
            Fixture.session(.deload(3, 2)),
        ]

        for reverse in [false, true] {
            let completedResult = DeloadScheduler.status(
                normalPrescriptions: [],
                histories: [:],
                sessions: reverse ? Array(completed.reversed()) : completed,
                programDayCount: 3,
                decisions: DeloadDecisions(),
                now: Fixture.now
            )
            let runningResult = DeloadScheduler.status(
                normalPrescriptions: [],
                histories: [:],
                sessions: reverse ? Array(running.reversed()) : running,
                programDayCount: 3,
                decisions: DeloadDecisions(),
                now: Fixture.now
            )
            #expect(completedResult == .inactive)
            #expect(runningResult == .active(start: Fixture.ago(4)))
        }
    }

    // MARK: - DeloadDecisions (JSON kept by the app)

    @Test("C1 DeloadDecisions começa vazio")
    func C1_decisions_defaultsAreEmpty() {
        let decisions = DeloadDecisions()

        #expect(decisions.manualRequestedAt == nil)
        #expect(decisions.dismissedAt == nil)
    }

    @Test("C1 DeloadDecisions faz round-trip em JSON")
    func C1_decisions_roundTrip() throws {
        let value = DeloadDecisions(manualRequestedAt: Fixture.ago(2), dismissedAt: Fixture.ago(9))

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(DeloadDecisions.self, from: data)

        #expect(decoded == value)
    }

    @Test("C1 DeloadDecisions: arquivo sem os campos decodifica como vazio")
    func C1_decisions_missingKeysDecodeAsNil() throws {
        let empty = try JSONDecoder().decode(DeloadDecisions.self, from: Data("{}".utf8))
        let onlyManual = try JSONDecoder().decode(
            DeloadDecisions.self,
            from: Data("{\"manualRequestedAt\": 100}".utf8)
        )

        #expect(empty == DeloadDecisions())
        #expect(onlyManual == DeloadDecisions(manualRequestedAt: Date(timeIntervalSinceReferenceDate: 100)))
    }
}

// MARK: - Scenario tables

extension DeloadSchedulerTests {
    /// A session `daysAgo` days before `Fixture.now`.
    struct SessionSpec: Sendable {
        let n: Int
        let daysAgo: Double
        let status: SessionStatus
        let isDeload: Bool
        let workingSets: Int

        static func normal(
            _ n: Int,
            _ daysAgo: Double,
            status: SessionStatus = .completed,
            sets: Int = 12
        ) -> SessionSpec {
            SessionSpec(n: n, daysAgo: daysAgo, status: status, isDeload: false, workingSets: sets)
        }

        static func deload(
            _ n: Int,
            _ daysAgo: Double,
            status: SessionStatus = .completed,
            sets: Int = 6
        ) -> SessionSpec {
            SessionSpec(n: n, daysAgo: daysAgo, status: status, isDeload: true, workingSets: sets)
        }
    }

    /// One history entry of an exercise. `session` forces a shared session id, to
    /// model one session delivered as two entries.
    struct EntrySpec: Sendable {
        let daysAgo: Double
        let wasDeload: Bool
        let hasWorkingSets: Bool
        let session: Int?

        static func normal(_ daysAgo: Double, session: Int? = nil) -> EntrySpec {
            EntrySpec(daysAgo: daysAgo, wasDeload: false, hasWorkingSets: true, session: session)
        }

        static func deload(_ daysAgo: Double, session: Int? = nil) -> EntrySpec {
            EntrySpec(daysAgo: daysAgo, wasDeload: true, hasWorkingSets: true, session: session)
        }

        static func warmupOnly(_ daysAgo: Double) -> EntrySpec {
            EntrySpec(daysAgo: daysAgo, wasDeload: false, hasWorkingSets: false, session: nil)
        }
    }

    /// One program exercise: its normal prescription note and its history.
    struct ExerciseSpec: Sendable {
        let note: PrescriptionNote
        let entries: [EntrySpec]

        /// Two failures at the same load, the latest `daysAgo` days ago (SPEC P6).
        static func decrease(_ daysAgo: Double) -> ExerciseSpec {
            ExerciseSpec(note: .decrease, entries: [.normal(daysAgo + 3), .normal(daysAgo)])
        }

        static func hold(_ daysAgo: Double) -> ExerciseSpec {
            ExerciseSpec(note: .hold, entries: [.normal(daysAgo)])
        }
    }

    enum Expected: Sendable {
        case inactive
        case pending(DeloadTrigger)
        case active(startDaysAgo: Double)
    }

    enum Permutation: CaseIterable, Sendable {
        case original
        case reversed
        case rotated
    }

    struct Scenario: Sendable, CustomTestStringConvertible {
        let label: String
        let sessions: [SessionSpec]
        let exercises: [ExerciseSpec]
        let manualDaysAgo: Double?
        let dismissedDaysAgo: Double?
        let weeks: Int
        let days: Int
        let expected: Expected

        var testDescription: String { label }

        init(
            _ label: String,
            sessions: [SessionSpec] = [],
            exercises: [ExerciseSpec] = [],
            manual: Double? = nil,
            dismissed: Double? = nil,
            weeks: Int = 6,
            days: Int = 3,
            expected: Expected
        ) {
            self.label = label
            self.sessions = sessions
            self.exercises = exercises
            self.manualDaysAgo = manual
            self.dismissedDaysAgo = dismissed
            self.weeks = weeks
            self.days = days
            self.expected = expected
        }

        /// A finished light week: started 10 days ago, pass completed 6 days ago.
        static let finishedDeload: [SessionSpec] = [
            .normal(1, 30), .deload(2, 10), .deload(3, 8), .deload(4, 6),
        ]

        static let triggers: [Scenario] = [
            Scenario("sem sessões nem decisões → inativo", expected: .inactive),
            Scenario("(b) sem deload: 1ª sessão há exatamente 42 dias → programado",
                     sessions: [.normal(1, 42), .normal(2, 40)], expected: .pending(.scheduled)),
            Scenario("(b) sem deload: 1ª sessão há 41,9 dias → inativo",
                     sessions: [.normal(1, 41.9)], expected: .inactive),
            Scenario("(b) a 1ª sessão vale mesmo sem séries e em qualquer status",
                     sessions: [.normal(1, 43, status: .abandoned, sets: 0), .normal(2, 20)],
                     expected: .pending(.scheduled)),
            Scenario("(b) N = 4: 28 dias → programado",
                     sessions: [.normal(1, 28)], weeks: 4, expected: .pending(.scheduled)),
            Scenario("(b) N = 4: 27,9 dias → inativo",
                     sessions: [.normal(1, 27.9)], weeks: 4, expected: .inactive),
            Scenario("(b) N = 0 desliga",
                     sessions: [.normal(1, 300)], weeks: 0, expected: .inactive),
            Scenario("(b) N negativo desliga",
                     sessions: [.normal(1, 300)], weeks: -2, expected: .inactive),
            Scenario("(a) 1 de 2 com decrease, sem deload anterior → muitas reduções",
                     sessions: [.normal(1, 10)], exercises: [.decrease(2), .hold(2)],
                     expected: .pending(.manyDecreases)),
            Scenario("(a) 1 de 3 → inativo",
                     sessions: [.normal(1, 10)], exercises: [.decrease(2), .hold(2), .hold(2)],
                     expected: .inactive),
            Scenario("(a) calibrate fica fora da conta: 1 de 2 → muitas reduções",
                     sessions: [.normal(1, 10)],
                     exercises: [.decrease(2), .hold(2), ExerciseSpec(note: .calibrate, entries: [])],
                     expected: .pending(.manyDecreases)),
            Scenario("(a) e (b) juntos → muitas reduções",
                     sessions: [.normal(1, 60)], exercises: [.decrease(2), .hold(2)],
                     expected: .pending(.manyDecreases)),
        ]

        static let priority: [Scenario] = [
            Scenario("em andamento > manual",
                     sessions: [.normal(1, 20), .deload(2, 2)], manual: 1,
                     expected: .active(startDaysAgo: 2)),
            Scenario("em andamento > (a) e (b)",
                     sessions: [.normal(1, 100), .deload(2, 1)], exercises: [.decrease(5), .decrease(5)],
                     expected: .active(startDaysAgo: 1)),
            Scenario("em andamento ignora Seguir normal",
                     sessions: [.normal(1, 20), .deload(2, 2)], dismissed: 1,
                     expected: .active(startDaysAgo: 2)),
            Scenario("manual > (a)",
                     sessions: [.normal(1, 10)], exercises: [.decrease(2), .hold(2)], manual: 0.5,
                     expected: .pending(.manual)),
            Scenario("manual > (b)",
                     sessions: [.normal(1, 60)], manual: 1, expected: .pending(.manual)),
            Scenario("programa sem dias → inativo, mesmo com deload em andamento e pedido manual",
                     sessions: [.deload(1, 1)], manual: 0.5, days: 0, expected: .inactive),
            Scenario("programa sem dias → inativo, mesmo com (a) e (b)",
                     sessions: [.normal(1, 100)], exercises: [.decrease(2)], days: 0, expected: .inactive),
            Scenario("programa com dias negativos → inativo",
                     sessions: [.normal(1, 100)], days: -1, expected: .inactive),
        ]

        static let keepNormal: [Scenario] = [
            Scenario("decrease vindo de antes da dispensa não conta",
                     sessions: [.normal(1, 20)], exercises: [.decrease(5), .decrease(5)], dismissed: 3,
                     expected: .inactive),
            Scenario("decrease vindo de depois da dispensa conta",
                     sessions: [.normal(1, 20)], exercises: [.decrease(1), .hold(1)], dismissed: 3,
                     expected: .pending(.manyDecreases)),
            Scenario("decrease no instante da dispensa não conta (tem de ser posterior)",
                     sessions: [.normal(1, 20)], exercises: [.decrease(3), .decrease(3)], dismissed: 3,
                     expected: .inactive),
            Scenario("(b) sem deload: conta da dispensa, não da 1ª sessão",
                     sessions: [.normal(1, 100)], dismissed: 10, expected: .inactive),
            Scenario("(b) sem deload: 42 dias depois da dispensa → programado",
                     sessions: [.normal(1, 100)], dismissed: 42, expected: .pending(.scheduled)),
            Scenario("(b) dispensa mais recente que o último deload: 41 dias → inativo",
                     sessions: [.normal(1, 200), .deload(2, 100), .deload(3, 99), .deload(4, 98)],
                     dismissed: 41, expected: .inactive),
            Scenario("(b) dispensa mais recente que o último deload: 42 dias → programado",
                     sessions: [.normal(1, 200), .deload(2, 100), .deload(3, 99), .deload(4, 98)],
                     dismissed: 42, expected: .pending(.scheduled)),
            Scenario("(b) dispensa mais antiga que o último deload: vale o início do deload",
                     sessions: [.normal(1, 200), .deload(2, 42), .deload(3, 41), .deload(4, 40)],
                     dismissed: 100, expected: .pending(.scheduled)),
            Scenario("rearme usa a mais recente entre fim do deload e dispensa",
                     sessions: finishedDeload, exercises: [.decrease(4), .decrease(4)], dismissed: 3,
                     expected: .inactive),
            Scenario("rearme: decrease depois do fim do deload e da dispensa conta",
                     sessions: finishedDeload, exercises: [.decrease(1), .hold(1)], dismissed: 3,
                     expected: .pending(.manyDecreases)),
        ]

        static let rearm: [Scenario] = [
            Scenario("decrease vindo de antes do deload não conta → inativo",
                     sessions: finishedDeload,
                     exercises: [
                         ExerciseSpec(note: .decrease, entries: [.normal(15), .normal(12), .deload(10), .deload(8)]),
                         .decrease(12),
                     ],
                     expected: .inactive),
            Scenario("decrease vindo de depois do fim do deload conta → muitas reduções",
                     sessions: finishedDeload, exercises: [.decrease(2), .hold(2)],
                     expected: .pending(.manyDecreases)),
            Scenario("entrada no instante do fim do deload não conta (tem de ser posterior)",
                     sessions: finishedDeload, exercises: [.decrease(6), .decrease(6)],
                     expected: .inactive),
            Scenario("reduções filtradas ficam no total: 1 nova + 1 antiga + 2 hold → inativo (1 de 4)",
                     sessions: finishedDeload,
                     exercises: [.decrease(2), .decrease(12), .hold(2), .hold(2)],
                     expected: .inactive),
            Scenario("reduções filtradas ficam no total: 1 nova + 1 antiga → muitas reduções (1 de 2)",
                     sessions: finishedDeload, exercises: [.decrease(2), .decrease(12)],
                     expected: .pending(.manyDecreases)),
            Scenario("entrada normal posterior só com aquecimento não rearma",
                     sessions: finishedDeload,
                     exercises: [
                         ExerciseSpec(note: .decrease, entries: [.normal(15), .normal(12), .warmupOnly(2)]),
                         ExerciseSpec(note: .decrease, entries: [.normal(15), .normal(12), .warmupOnly(2)]),
                     ],
                     expected: .inactive),
            Scenario("entrada de deload posterior não rearma (só sessão normal conta)",
                     sessions: finishedDeload,
                     exercises: [
                         ExerciseSpec(note: .decrease, entries: [.normal(12), .deload(2)]),
                         ExerciseSpec(note: .decrease, entries: [.normal(12), .deload(2)]),
                     ],
                     expected: .inactive),
            Scenario("sessão em duas entradas, uma de deload, é deload inteira",
                     sessions: finishedDeload,
                     exercises: [
                         ExerciseSpec(note: .decrease,
                                      entries: [.normal(12), .normal(2, session: 0x77), .deload(2, session: 0x77)]),
                         ExerciseSpec(note: .decrease,
                                      entries: [.normal(12), .normal(2, session: 0x78), .deload(2, session: 0x78)]),
                     ],
                     expected: .inactive),
            Scenario("decrease sem histórico, depois de um deload, não conta",
                     sessions: finishedDeload,
                     exercises: [ExerciseSpec(note: .decrease, entries: []), ExerciseSpec(note: .decrease, entries: [])],
                     expected: .inactive),
            Scenario("sem deload nem dispensa, decrease sem histórico conta (nada a filtrar)",
                     sessions: [.normal(1, 10)],
                     exercises: [ExerciseSpec(note: .decrease, entries: []), .hold(2)],
                     expected: .pending(.manyDecreases)),
            Scenario("sem deload anterior, decrease antigo conta",
                     sessions: [.normal(1, 30)], exercises: [.decrease(20), .hold(2)],
                     expected: .pending(.manyDecreases)),
            Scenario("retry e returning continuam fora da conta depois do deload",
                     sessions: finishedDeload,
                     exercises: [
                         ExerciseSpec(note: .retry, entries: [.normal(2)]),
                         ExerciseSpec(note: .returning, entries: [.normal(2)]),
                     ],
                     expected: .inactive),
        ]

        static let scheduledAnchor: [Scenario] = [
            Scenario("(b) conta do início do último deload, não do fim: 42 dias → programado",
                     sessions: [.normal(1, 200), .deload(2, 42), .deload(3, 40), .deload(4, 38)],
                     expected: .pending(.scheduled)),
            Scenario("(b) início do último deload há 41 dias → inativo",
                     sessions: [.normal(1, 200), .deload(2, 41), .deload(3, 40), .deload(4, 38)],
                     expected: .inactive),
            Scenario("(b) deload recente prevalece sobre a 1ª sessão antiga → inativo",
                     sessions: [.normal(1, 100), .deload(2, 10), .deload(3, 8), .deload(4, 6), .normal(5, 1)],
                     expected: .inactive),
            Scenario("(b) vale o último de vários deloads",
                     sessions: [.deload(1, 150), .deload(2, 149), .deload(3, 148), .normal(4, 140),
                                .deload(5, 50), .deload(6, 49), .deload(7, 48), .normal(8, 1)],
                     expected: .pending(.scheduled)),
            Scenario("pausa longa logo após o deload: a sessão leve da volta inicia outra passagem",
                     sessions: [.normal(1, 120), .deload(2, 60), .deload(3, 58), .deload(4, 56), .deload(5, 1)],
                     expected: .active(startDaysAgo: 1)),
            Scenario("pausa longa logo após o deload: a nova passagem completa rearma (b) a partir dela",
                     sessions: [.normal(1, 120), .deload(2, 60), .deload(3, 58), .deload(4, 56),
                                .deload(5, 5), .deload(6, 3), .deload(7, 1)],
                     expected: .inactive),
        ]

        static let sequences: [Scenario] = [
            Scenario("sessão de deload em andamento, ainda sem séries, inicia a passagem",
                     sessions: [.normal(1, 10), .deload(2, 0.1, status: .inProgress, sets: 0)],
                     expected: .active(startDaysAgo: 0.1)),
            Scenario("1 de 3 concluídas → em andamento desde a 1ª sessão de deload",
                     sessions: [.normal(1, 10), .deload(2, 3)], expected: .active(startDaysAgo: 3)),
            Scenario("3 de 3 concluídas → passagem terminou",
                     sessions: finishedDeload, expected: .inactive),
            Scenario("abandonada não conclui a passagem",
                     sessions: [.deload(2, 6), .deload(3, 4), .deload(4, 2, status: .abandoned)],
                     expected: .active(startDaysAgo: 6)),
            Scenario("deload sem série de trabalho não conclui a passagem",
                     sessions: [.deload(2, 6), .deload(3, 4), .deload(4, 2, sets: 0)],
                     expected: .active(startDaysAgo: 6)),
            Scenario("normal abandonada com séries não separa as sequências",
                     sessions: [.deload(2, 6), .normal(3, 5, status: .abandoned), .deload(4, 4)],
                     expected: .active(startDaysAgo: 6)),
            Scenario("normal em andamento não separa as sequências",
                     sessions: [.deload(2, 6), .normal(3, 5, status: .inProgress), .deload(4, 4)],
                     expected: .active(startDaysAgo: 6)),
            Scenario("normal concluída sem série de trabalho não separa as sequências",
                     sessions: [.deload(2, 6), .normal(3, 5, sets: 0), .deload(4, 4)],
                     expected: .active(startDaysAgo: 6)),
            Scenario("normal concluída com séries separa: nova sequência começa depois dela",
                     sessions: [.deload(2, 6), .normal(3, 5), .deload(4, 4)],
                     expected: .active(startDaysAgo: 4)),
            Scenario("deload interrompido por sessão normal continua em andamento (só a passagem encerra)",
                     sessions: [.normal(1, 30), .deload(2, 6), .normal(3, 4)],
                     expected: .active(startDaysAgo: 6)),
            Scenario("deload antigo concluído, sessões normais, deload novo em andamento",
                     sessions: [.deload(1, 70), .deload(2, 69), .deload(3, 68), .normal(4, 60), .normal(5, 30),
                                .deload(6, 2)],
                     expected: .active(startDaysAgo: 2)),
            Scenario("programa de 1 dia: 1 concluída encerra",
                     sessions: [.normal(1, 20), .deload(2, 2)], days: 1, expected: .inactive),
            Scenario("programa de 5 dias: 3 concluídas → em andamento",
                     sessions: [.deload(2, 6), .deload(3, 4), .deload(4, 2)], days: 5,
                     expected: .active(startDaysAgo: 6)),
            Scenario("duas sessões de deload no mesmo instante contam as duas",
                     sessions: [.deload(2, 3), .deload(3, 3), .deload(4, 1)], expected: .inactive),
            Scenario("passagem completa e nova sessão de deload no mesmo instante da última: nova passagem",
                     sessions: [.deload(2, 5), .deload(3, 3), .deload(4, 1), .deload(5, 1)], manual: 2,
                     expected: .active(startDaysAgo: 1)),
        ]

        static let manual: [Scenario] = [
            Scenario("sem deload anterior → manual",
                     sessions: [.normal(1, 10)], manual: 1, expected: .pending(.manual)),
            Scenario("sem sessão alguma → manual",
                     manual: 0, expected: .pending(.manual)),
            Scenario("pedido anterior ao início do último deload já foi atendido",
                     sessions: finishedDeload, manual: 11, expected: .inactive),
            Scenario("pedido no instante do início do último deload (não é posterior)",
                     sessions: finishedDeload, manual: 10, expected: .inactive),
            Scenario("pedido durante a passagem, que depois terminou, já foi atendido",
                     sessions: finishedDeload, manual: 9, expected: .inactive),
            Scenario("pedido depois do fim do último deload, sem sessão de deload desde então → manual",
                     sessions: finishedDeload, manual: 1, expected: .pending(.manual)),
            Scenario("pedido seguido de sessão de deload → em andamento",
                     sessions: [.normal(1, 10), .deload(2, 0.5, status: .inProgress, sets: 0)], manual: 1,
                     expected: .active(startDaysAgo: 0.5)),
            Scenario("pedido seguido de sessão de deload abandonada → em andamento",
                     sessions: [.normal(1, 10), .deload(2, 0.5, status: .abandoned, sets: 0)], manual: 1,
                     expected: .active(startDaysAgo: 0.5)),
            Scenario("sessão normal depois do pedido não o atende",
                     sessions: [.normal(1, 10), .normal(2, 0.5)], manual: 1, expected: .pending(.manual)),
            Scenario("Seguir normal não cancela o pedido manual (só adia (a) e (b))",
                     sessions: [.normal(1, 10)], manual: 2, dismissed: 1, expected: .pending(.manual)),
            Scenario("pedido logo após uma passagem completa, sem sessão normal no meio: nova passagem",
                     sessions: [.normal(1, 30), .deload(2, 10), .deload(3, 8), .deload(4, 6), .deload(5, 0.5)],
                     manual: 1, expected: .active(startDaysAgo: 0.5)),
        ]

        static let determinism: [Scenario] = [
            Scenario("deload antigo, reduções novas e antigas, dispensa",
                     sessions: [.normal(1, 90), .deload(2, 50), .normal(3, 49, status: .abandoned),
                                .deload(4, 48), .deload(5, 46), .normal(6, 30), .normal(7, 20, sets: 0),
                                .normal(8, 4)],
                     exercises: [.decrease(4), .decrease(40), .decrease(25), .hold(4)],
                     dismissed: 30,
                     expected: .pending(.manyDecreases)),
            Scenario("sequências no mesmo instante e sessão normal intercalada",
                     sessions: [.deload(1, 9), .deload(2, 9), .normal(3, 8), .deload(4, 7), .deload(5, 7),
                                .deload(6, 7, status: .abandoned)],
                     expected: .active(startDaysAgo: 7)),
            Scenario("passagem completa e pedido manual posterior",
                     sessions: [.normal(1, 40), .deload(2, 12), .deload(3, 12), .deload(4, 11), .normal(5, 5)],
                     exercises: [.decrease(5), .hold(5)],
                     manual: 3,
                     expected: .pending(.manual)),
        ]
    }
}

// MARK: - Fixture

private enum Fixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let day: TimeInterval = 86_400
    static let programDayID = id(0xD000)

    static func ago(_ days: Double) -> Date {
        now.addingTimeInterval(-days * day)
    }

    static func id(_ n: Int) -> UUID {
        let hex = String(n, radix: 16, uppercase: true)
        let suffix = String(repeating: "0", count: max(0, 12 - hex.count)) + hex
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }

    static func exerciseID(_ index: Int) -> UUID {
        id(0x100 + index)
    }

    static func session(_ spec: DeloadSchedulerTests.SessionSpec) -> SessionSummary {
        let startedAt = ago(spec.daysAgo)
        return SessionSummary(
            id: id(spec.n),
            programDayID: programDayID,
            startedAt: startedAt,
            endedAt: spec.status == .inProgress ? nil : startedAt.addingTimeInterval(3_600),
            status: spec.status,
            primaryMusclesTrained: [.chest],
            workingSetCount: spec.workingSets,
            isDeload: spec.isDeload
        )
    }

    static func prescriptions(_ exercises: [DeloadSchedulerTests.ExerciseSpec]) -> [ExercisePrescription] {
        exercises.enumerated().map { index, exercise in
            ExercisePrescription(
                exerciseID: exerciseID(index),
                load: exercise.note == .calibrate ? nil : 50,
                note: exercise.note
            )
        }
    }

    static func histories(_ exercises: [DeloadSchedulerTests.ExerciseSpec]) -> [UUID: [ExerciseHistoryEntry]] {
        var result: [UUID: [ExerciseHistoryEntry]] = [:]
        for (index, exercise) in exercises.enumerated() where !exercise.entries.isEmpty {
            var entries: [ExerciseHistoryEntry] = []
            for (position, entry) in exercise.entries.enumerated() {
                let date = ago(entry.daysAgo)
                let set = entry.hasWorkingSets
                    ? SetResult(load: 50, reps: 6, rir: 0, completedAt: date)
                    : SetResult(load: 20, reps: 10, isWarmup: true, completedAt: date)
                entries.append(ExerciseHistoryEntry(
                    sessionID: id(entry.session ?? (0x10000 + index * 0x100 + position)),
                    date: date,
                    sets: [set],
                    wasDeload: entry.wasDeload
                ))
            }
            result[exerciseID(index)] = entries
        }
        return result
    }

    static func decisions(_ scenario: DeloadSchedulerTests.Scenario) -> DeloadDecisions {
        DeloadDecisions(
            manualRequestedAt: scenario.manualDaysAgo.map { ago($0) },
            dismissedAt: scenario.dismissedDaysAgo.map { ago($0) }
        )
    }

    static func status(
        _ scenario: DeloadSchedulerTests.Scenario,
        permutation: DeloadSchedulerTests.Permutation = .original
    ) -> DeloadStatus {
        let permutedHistories = Self.histories(scenario.exercises).mapValues { permuted($0, permutation) }
        return DeloadScheduler.status(
            normalPrescriptions: permuted(prescriptions(scenario.exercises), permutation),
            histories: permutedHistories,
            sessions: permuted(scenario.sessions.map { session($0) }, permutation),
            programDayCount: scenario.days,
            decisions: decisions(scenario),
            weeksBetweenDeloads: scenario.weeks,
            now: now
        )
    }

    static func expected(_ expected: DeloadSchedulerTests.Expected) -> DeloadStatus {
        switch expected {
        case .inactive:
            return .inactive
        case .pending(let trigger):
            return .pending(trigger: trigger)
        case .active(let startDaysAgo):
            return .active(start: ago(startDaysAgo))
        }
    }

    static func permuted<Element>(_ values: [Element], _ permutation: DeloadSchedulerTests.Permutation) -> [Element] {
        switch permutation {
        case .original:
            return values
        case .reversed:
            return Array(values.reversed())
        case .rotated:
            // [a, b, c, d] → [b, c, d, a]
            guard values.count > 1 else { return values }
            return Array(values.dropFirst()) + [values[0]]
        }
    }
}
