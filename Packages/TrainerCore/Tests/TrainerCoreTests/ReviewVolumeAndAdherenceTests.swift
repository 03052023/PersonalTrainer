import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.8 R3 (weekly working sets per primary group vs the goal range) and R4
// (adherence over the last 4 complete weeks).

private typealias RF = ReviewFixtures

@Suite("Review — R3 volume e R4 aderência")
struct ReviewVolumeAndAdherenceTests {
    // MARK: - R3: measurement

    @Test("R3 séries por semana = média das 4 semanas completas; a semana corrente fica fora")
    func weeklyAverageUsesTheFourCompleteWeeks() {
        let bench = RF.exercise(1, [.chest])
        let lastSecond = RF.monday.addingTimeInterval(-1)
        let beforeWindow = RF.windowStart.addingTimeInterval(-1)
        let history = [
            RF.entry(RF.id(10_100), RF.windowStart, Array(repeating: RF.workingSet(50, 10, at: RF.windowStart), count: 8)),
            RF.entry(RF.id(10_101), lastSecond, Array(repeating: RF.workingSet(52.5, 10, at: lastSecond), count: 8)),
            RF.entry(RF.id(10_102), beforeWindow, Array(repeating: RF.workingSet(50, 10, at: beforeWindow), count: 100)),
            RF.entry(RF.id(10_103), RF.monday, Array(repeating: RF.workingSet(55, 10, at: RF.monday), count: 100)),
        ]

        let report = RF.review(RF.input(exercises: [RF.slot(bench, target: 1, history: history)]))

        // 8 (window's first instant) + 8 (its last second) over 4 weeks.
        #expect(report.weeklySetsByMuscle == [.chest: 4])
    }

    @Test("R3 exercício com vários grupos primários conta 1 série para cada; aquecimentos não contam")
    func multiplePrimariesCountForEachGroup() {
        let bench = RF.exercise(1, [.chest, .triceps])
        let row = RF.exercise(2, [.back])
        var benchHistory = RF.weeklyHistory([5, 5, 5, 5], exercise: 1)
        let warmupDay = RF.at(-20)
        benchHistory.append(RF.entry(RF.id(10_150), warmupDay, Array(repeating: RF.warmup(20, 10, at: warmupDay), count: 12)))

        let report = RF.review(
            RF.input(exercises: [
                RF.slot(bench, target: 1, history: benchHistory),
                RF.slot(row, target: 2),
            ])
        )

        #expect(report.weeklySetsByMuscle == [.chest: 5, .triceps: 5, .back: 0])
    }

    @Test("R3 o mesmo histórico em dois slots não conta em dobro")
    func sharedHistoryIsNotDoubled() {
        let bench = RF.exercise(1, [.chest])
        let history = RF.weeklyHistory([12, 12, 12, 12], exercise: 1)

        let report = RF.review(
            RF.input(exercises: [
                RF.slot(bench, target: 1, day: 1, history: history),
                RF.slot(bench, target: 2, day: 2, history: history),
            ])
        )

        #expect(report.weeklySetsByMuscle == [.chest: 12])
        #expect(RF.suggestions(report, .addSets).isEmpty)
    }

    @Test("R3 fuso fixo: semanas começam à meia-noite de segunda no fuso do calendário")
    func windowFollowsTheCalendarTimeZone() throws {
        let saoPaulo = try RF.saoPaulo()
        let bench = RF.exercise(1, [.chest])
        // Sunday 22:00 in São Paulo = Monday 01:00 UTC.
        let sundayNightLastWeek = RF.monday.addingTimeInterval(RF.oneHour)
        let sundayNightBeforeWindow = RF.windowStart.addingTimeInterval(RF.oneHour)
        let history = [
            RF.entry(RF.id(10_100), sundayNightLastWeek, Array(repeating: RF.workingSet(50, 10, at: sundayNightLastWeek), count: 8)),
            RF.entry(RF.id(10_101), sundayNightBeforeWindow, Array(repeating: RF.workingSet(50, 10, at: sundayNightBeforeWindow), count: 4)),
        ]
        let input = RF.input(exercises: [RF.slot(bench, target: 1, history: history)])

        let inUTC = RF.review(input, calendar: RF.utc)
        let inSaoPaulo = RF.review(input, calendar: saoPaulo)

        // UTC: Monday 01:00 is the current week; 2026-08-24 01:00 is inside the window.
        #expect(inUTC.weeklySetsByMuscle == [.chest: 1])
        // São Paulo: both are Sunday 22:00; only the one before `monday` is in the window.
        #expect(inSaoPaulo.weeklySetsByMuscle == [.chest: 2])
    }

    @Test("R3 semana começando no domingo desloca a janela (SPEC §7.4 configurável)")
    func sundayStartShiftsTheWindow() {
        let bench = RF.exercise(1, [.chest])
        let sunday = RF.at(-1, hour: 10)
        let history = [RF.entry(RF.id(10_100), sunday, Array(repeating: RF.workingSet(50, 10, at: sunday), count: 8))]

        let mondayWeeks = RF.review(RF.input(exercises: [RF.slot(bench, target: 1, history: history)]))
        let sundayWeeks = RF.review(
            RF.input(exercises: [RF.slot(bench, target: 1, history: history)], weekStartsOnMonday: false)
        )

        #expect(mondayWeeks.weeklySetsByMuscle == [.chest: 2])
        #expect(sundayWeeks.weeklySetsByMuscle == [.chest: 0])
    }

    // MARK: - R3: below the range

    @Test("R3 abaixo da faixa → +1 série por exercício do grupo, com regra, números e referência")
    func belowRangeAddsOneSetPerExercise() throws {
        let bench = RF.exercise(1, [.chest], name: "Supino reto")
        let fly = RF.exercise(2, [.chest], name: "Crucifixo")
        let row = RF.exercise(3, [.back], name: "Remada")

        let report = RF.review(
            RF.input(exercises: [
                RF.slot(bench, target: 1, history: RF.weeklyHistory([4, 4, 4, 4], exercise: 1)),
                RF.slot(fly, target: 2, history: RF.weeklyHistory([4, 4, 4, 4], exercise: 2)),
                RF.slot(row, target: 3, history: RF.weeklyHistory([12, 12, 12, 12], exercise: 3)),
            ])
        )

        let additions = RF.suggestions(report, .addSets)
        #expect(additions.map(\.id) == [
            "addSets:chest:\(RF.id(201).uuidString):\(RF.week)",
            "addSets:chest:\(RF.id(202).uuidString):\(RF.week)",
        ])
        #expect(additions.map(\.proposedSets) == [4, 4])
        #expect(additions.map(\.targetIDs) == [[RF.id(201)], [RF.id(202)]])

        let first = try #require(additions.first)
        #expect(first.rule == "R3")
        #expect(first.muscle == .chest)
        #expect(first.strength == .recommended)
        #expect(first.referenceTopic == "topic.volume")
        #expect(first.title == "Mais uma série de Supino reto")
        #expect(
            first.reason
                == "Peito teve em média 8 séries por semana nas últimas 4 semanas, abaixo da meta de 10 "
                + "(faixa do objetivo: 10 a 20); passar Supino reto de 3 para 4 séries aproxima da meta."
        )
        #expect(report.weeklySetsByMuscle == [.chest: 8, .back: 12])
    }

    struct BoundaryCase: Sendable, CustomTestStringConvertible {
        let setsPerWeek: [Int]
        let suggested: Bool
        let label: String

        var testDescription: String { label }
    }

    static let lowerBoundaryCases: [BoundaryCase] = [
        BoundaryCase(setsPerWeek: [10, 10, 10, 10], suggested: false, label: "fronteira: média 10 = mínimo da faixa"),
        BoundaryCase(setsPerWeek: [10, 10, 10, 9], suggested: true, label: "média 9,75"),
        BoundaryCase(setsPerWeek: [0, 0, 20, 20], suggested: false, label: "média 10 com semanas desiguais"),
        BoundaryCase(setsPerWeek: [0, 0, 0, 0], suggested: true, label: "nenhuma série"),
    ]

    @Test("R3 fronteira inferior: só abaixo do mínimo (estritamente) sugere mais séries", arguments: ReviewVolumeAndAdherenceTests.lowerBoundaryCases)
    func lowerBoundary(_ testCase: BoundaryCase) {
        let bench = RF.exercise(1, [.chest])

        let report = RF.review(
            RF.input(exercises: [RF.slot(bench, target: 1, history: RF.weeklyHistory(testCase.setsPerWeek, exercise: 1))])
        )

        #expect(RF.suggestions(report, .addSets).count == (testCase.suggested ? 1 : 0))
    }

    @Test("R3 no máximo +2 séries por grupo por revisão, começando pelos exercícios com menos séries")
    func additionsAreCappedAtTwoPerGroup() {
        let exercises = (1...3).map { RF.exercise($0, [.chest]) }

        let report = RF.review(
            RF.input(exercises: [
                RF.slot(exercises[0], target: 1, sets: 3, history: RF.weeklyHistory([2, 2, 2, 2], exercise: 1)),
                RF.slot(exercises[1], target: 2, sets: 4, history: RF.weeklyHistory([2, 2, 2, 2], exercise: 2)),
                RF.slot(exercises[2], target: 3, sets: 2, history: RF.weeklyHistory([2, 2, 2, 2], exercise: 3)),
            ])
        )

        let additions = RF.suggestions(report, .addSets)
        #expect(additions.map(\.targetIDs) == [[RF.id(201)], [RF.id(203)]])
        #expect(additions.map(\.proposedSets) == [4, 3])
    }

    @Test("R3 nunca sugere passar de 10 séries num exercício")
    func additionsNeverExceedTenSets() {
        let atCap = RF.exercise(1, [.chest])
        let belowCap = RF.exercise(2, [.chest])

        let report = RF.review(
            RF.input(exercises: [
                RF.slot(atCap, target: 1, sets: 10, history: RF.weeklyHistory([2, 2, 2, 2], exercise: 1)),
                RF.slot(belowCap, target: 2, sets: 9, history: RF.weeklyHistory([2, 2, 2, 2], exercise: 2)),
            ])
        )

        let additions = RF.suggestions(report, .addSets)
        #expect(additions.map(\.targetIDs) == [[RF.id(202)]])
        #expect(additions.map(\.proposedSets) == [10])
    }

    @Test("R3 um exercício de dois grupos abaixo da meta recebe só +1 série na revisão")
    func sharedExerciseChangesOncePerReview() {
        let bench = RF.exercise(1, [.chest, .triceps])

        let report = RF.review(
            RF.input(exercises: [RF.slot(bench, target: 1, history: RF.weeklyHistory([5, 5, 5, 5], exercise: 1))])
        )

        let additions = RF.suggestions(report, .addSets)
        #expect(additions.count == 1)
        #expect(additions.first?.muscle == .chest)
        #expect(additions.first?.proposedSets == 4)
    }

    // MARK: - R3: above the range

    @Test("R3 acima do teto sem fadiga → nenhuma sugestão de volume")
    func aboveCeilingWithoutFatigueKeepsVolume() {
        let bench = RF.exercise(1, [.chest])
        let fly = RF.exercise(2, [.chest])

        let report = RF.review(
            RF.input(exercises: [
                RF.slot(bench, target: 1, history: RF.weeklyHistory([11, 11, 11, 11], exercise: 1)),
                RF.slot(fly, target: 2, history: RF.weeklyHistory([11, 11, 11, 11], exercise: 2)),
            ])
        )

        #expect(!report.fatigueHigh)
        #expect(RF.suggestions(report, .removeSets).isEmpty)
        #expect(RF.suggestions(report, .addSets).isEmpty)
    }

    @Test("R3 acima do teto com fadiga (R2) → −1 série, começando pelos exercícios com mais séries")
    func aboveCeilingWithFatigueRemovesOneSet() throws {
        let exercises = (1...3).map { RF.exercise($0, [.chest], name: "Peito \($0)") }

        let report = RF.review(
            RF.input(
                exercises: [
                    RF.slot(exercises[0], target: 1, sets: 3, history: RF.weeklyHistory([8, 8, 8, 8], exercise: 1)),
                    RF.slot(exercises[1], target: 2, sets: 5, history: RF.weeklyHistory([8, 8, 8, 8], exercise: 2)),
                    RF.slot(exercises[2], target: 3, sets: 4, history: RF.weeklyHistory([8, 8, 8, 8], exercise: 3)),
                ],
                prescriptions: [RF.prescription(.decrease, exercise: 1), RF.prescription(.hold, exercise: 2)]
            )
        )

        let removals = RF.suggestions(report, .removeSets)
        #expect(report.fatigueHigh)
        #expect(removals.map(\.targetIDs) == [[RF.id(202)], [RF.id(203)]])
        #expect(removals.map(\.proposedSets) == [4, 3])

        let first = try #require(removals.first)
        #expect(first.id == "removeSets:chest:\(RF.id(202).uuidString):\(RF.week)")
        #expect(first.rule == "R3")
        #expect(first.muscle == .chest)
        #expect(first.referenceTopic == "topic.volume")
        #expect(first.title == "Uma série a menos de Peito 2")
        #expect(
            first.reason
                == "Peito teve em média 24 séries por semana nas últimas 4 semanas, acima do teto de 20, "
                + "e há sinais de cansaço; passar Peito 2 de 5 para 4 séries ajuda a recuperar."
        )
    }

    @Test("R3 fronteira superior: média igual ao teto não reduz, mesmo com fadiga")
    func ceilingItselfIsInRange() {
        let bench = RF.exercise(1, [.chest])
        let fly = RF.exercise(2, [.chest])

        let report = RF.review(
            RF.input(
                exercises: [
                    RF.slot(bench, target: 1, history: RF.weeklyHistory([10, 10, 10, 10], exercise: 1)),
                    RF.slot(fly, target: 2, history: RF.weeklyHistory([10, 10, 10, 10], exercise: 2)),
                ],
                prescriptions: [RF.prescription(.decrease, exercise: 1)]
            )
        )

        #expect(report.fatigueHigh)
        #expect(report.weeklySetsByMuscle == [.chest: 20])
        #expect(RF.suggestions(report, .removeSets).isEmpty)
    }

    @Test("R3 nunca sugere menos de 1 série num exercício")
    func removalsKeepAtLeastOneSet() {
        let bench = RF.exercise(1, [.chest])

        let report = RF.review(
            RF.input(
                exercises: [RF.slot(bench, target: 1, sets: 1, history: RF.weeklyHistory([30, 30, 30, 30], exercise: 1))],
                prescriptions: [RF.prescription(.decrease, exercise: 1)]
            )
        )

        #expect(RF.suggestions(report, .removeSets).isEmpty)
    }

    // MARK: - R3: per-group targets and program coverage

    @Test("R3 muscleTargets substitui o mínimo do grupo; 0 desliga a sugestão de mais séries")
    func muscleTargetsOverrideTheMinimum() {
        let bench = RF.exercise(1, [.chest])
        let row = RF.exercise(2, [.back])
        let exercises = [
            RF.slot(bench, target: 1, history: RF.weeklyHistory([11, 11, 11, 11], exercise: 1)),
            RF.slot(row, target: 2, history: RF.weeklyHistory([2, 2, 2, 2], exercise: 2)),
        ]

        let goalOnly = RF.review(RF.input(exercises: exercises))
        let overridden = RF.review(RF.input(exercises: exercises, muscleTargets: [.chest: 12, .back: 0]))

        #expect(RF.suggestions(goalOnly, .addSets).compactMap(\.muscle) == [.back])
        #expect(RF.suggestions(overridden, .addSets).compactMap(\.muscle) == [.chest])
    }

    @Test("R3 mínimo por grupo acima do teto do objetivo eleva o teto")
    func overrideAboveTheCeilingRaisesIt() {
        let bench = RF.exercise(1, [.chest])
        let fly = RF.exercise(2, [.chest])

        let report = RF.review(
            RF.input(
                exercises: [
                    RF.slot(bench, target: 1, history: RF.weeklyHistory([11, 11, 11, 11], exercise: 1)),
                    RF.slot(fly, target: 2, history: RF.weeklyHistory([11, 11, 11, 11], exercise: 2)),
                ],
                muscleTargets: [.chest: 25],
                prescriptions: [RF.prescription(.decrease, exercise: 1)]
            )
        )

        // 22 per week: above the goal's 20 but below the group's own minimum of 25.
        #expect(RF.suggestions(report, .removeSets).isEmpty)
        #expect(RF.suggestions(report, .addSets).count == 2)
    }

    struct CoverageCase: Sendable, CustomTestStringConvertible {
        let start: Date?
        let covered: Bool
        let label: String

        var testDescription: String { label }
    }

    static let coverageCases: [CoverageCase] = [
        CoverageCase(start: RF.windowStart, covered: true, label: "fronteira: primeira sessão à 00:00 do 1º dia da janela"),
        CoverageCase(start: RF.windowStart.addingTimeInterval(RF.oneDay - 1), covered: true, label: "primeira sessão às 23:59:59 do 1º dia"),
        CoverageCase(start: RF.windowStart.addingTimeInterval(RF.oneDay), covered: false, label: "primeira sessão no 2º dia da janela"),
        CoverageCase(start: RF.defaultStart, covered: true, label: "programa com 6 semanas"),
        CoverageCase(start: nil, covered: false, label: "programa nunca treinado"),
    ]

    @Test("R3/R4 só julgam quando o programa cobre as 4 semanas completas", arguments: ReviewVolumeAndAdherenceTests.coverageCases)
    func programMustCoverTheWindow(_ testCase: CoverageCase) {
        let bench = RF.exercise(1, [.chest])
        let exercises = [RF.slot(bench, target: 1, history: RF.weeklyHistory([2, 2, 2, 2], exercise: 1))]

        let lowVolume = RF.review(RF.input(exercises: exercises, programStartDate: testCase.start))
        let lowAdherence = RF.review(
            RF.input(exercises: exercises, sessions: RF.sessionsInWindow(4), programStartDate: testCase.start)
        )

        #expect(RF.suggestions(lowVolume, .addSets).isEmpty != testCase.covered)
        #expect((lowVolume.adherence != nil) == testCase.covered)
        #expect(RF.suggestions(lowAdherence, .reduceDays).isEmpty != testCase.covered)
        // The signal itself is always measured.
        #expect(lowVolume.weeklySetsByMuscle == [.chest: 2])
    }

    // MARK: - R4

    struct AdherenceCase: Sendable, CustomTestStringConvertible {
        let days: Int
        let completed: Int
        let adherence: Double
        let low: Bool
        let label: String

        var testDescription: String { label }
    }

    static let adherenceCases: [AdherenceCase] = [
        AdherenceCase(days: 3, completed: 9, adherence: 0.75, low: false, label: "9 de 12 (75 %)"),
        AdherenceCase(days: 3, completed: 8, adherence: 8.0 / 12, low: true, label: "8 de 12 (66,7 %)"),
        AdherenceCase(days: 5, completed: 14, adherence: 0.7, low: false, label: "fronteira: 14 de 20 = 70 % exatos"),
        AdherenceCase(days: 5, completed: 13, adherence: 0.65, low: true, label: "13 de 20 (65 %)"),
        AdherenceCase(days: 3, completed: 14, adherence: 1, low: false, label: "mais treinos que o previsto: limitado a 100 %"),
        AdherenceCase(days: 3, completed: 0, adherence: 0, low: true, label: "nenhum treino"),
        AdherenceCase(days: 2, completed: 6, adherence: 0.75, low: false, label: "programa de 2 dias, 6 de 8"),
    ]

    @Test("R4 aderência = sessões concluídas por semana ÷ dias do programa; < 70 % sugere menos dias", arguments: ReviewVolumeAndAdherenceTests.adherenceCases)
    func adherenceTable(_ testCase: AdherenceCase) throws {
        let bench = RF.exercise(1, [.chest])

        let report = RF.review(
            RF.input(
                exercises: [RF.slot(bench, target: 1, history: RF.weeklyHistory([12, 12, 12, 12], exercise: 1))],
                sessions: RF.sessionsInWindow(testCase.completed),
                programDayCount: testCase.days
            )
        )

        let adherence = try #require(report.adherence)
        #expect(RF.isClose(adherence, testCase.adherence))
        #expect(RF.suggestions(report, .reduceDays).count == (testCase.low ? 1 : 0))
    }

    @Test("R4 só contam sessões concluídas, com série de trabalho, dentro da janela e uma vez por id")
    func onlyCompletedSessionsInsideTheWindowCount() {
        let bench = RF.exercise(1, [.chest])
        let counted = RF.sessionsInWindow(8)
        let ignored = [
            RF.session(100, at: RF.at(-20), status: .abandoned),
            RF.session(101, at: RF.at(-19), status: .inProgress),
            RF.session(102, at: RF.at(-18), workingSets: 0),
            RF.session(103, at: RF.monday),
            RF.session(104, at: RF.windowStart.addingTimeInterval(-1)),
            counted[0],
        ]

        func report(_ sessions: [SessionSummary]) -> ReviewReport {
            RF.review(
                RF.input(
                    exercises: [RF.slot(bench, target: 1, history: RF.weeklyHistory([12, 12, 12, 12], exercise: 1))],
                    sessions: sessions
                )
            )
        }

        let low = report(counted + ignored)
        let enough = report(counted + ignored + [RF.session(105, at: RF.windowStart)])

        #expect(low.adherence.map { RF.isClose($0, 8.0 / 12) } == true)
        #expect(RF.suggestions(low, .reduceDays).count == 1)
        #expect(enough.adherence == 0.75)
        #expect(RF.suggestions(enough, .reduceDays).isEmpty)
    }

    @Test("R4 aderência baixa vem antes de mais volume: suprime addSets")
    func lowAdherenceSuppressesAdditions() throws {
        let bench = RF.exercise(1, [.chest])

        let report = RF.review(
            RF.input(
                exercises: [RF.slot(bench, target: 1, history: RF.weeklyHistory([2, 2, 2, 2], exercise: 1))],
                sessions: RF.sessionsInWindow(6)
            )
        )

        #expect(RF.kinds(report) == [.reduceDays])
        let reduceDays = try #require(report.suggestions.first)
        #expect(reduceDays.id == "reduceDays:\(RF.week)")
        #expect(reduceDays.rule == "R4")
        #expect(reduceDays.title == "Treinar menos dias por semana")
        #expect(reduceDays.referenceTopic == "topic.frequency")
        #expect(reduceDays.strength == .recommended)
        #expect(reduceDays.targetIDs.isEmpty)
        #expect(
            reduceDays.reason
                == "Nas últimas 4 semanas você concluiu 6 de 12 treinos previstos (50%), cerca de 1,5 por semana; "
                + "um programa de 2 dias pode caber melhor na sua rotina antes de pensar em mais séries."
        )
    }

    @Test("R4 programa de 1 dia com aderência baixa: não há dia a tirar, mas addSets continua suprimido")
    func singleDayProgramCannotLoseDays() {
        let bench = RF.exercise(1, [.chest])

        let report = RF.review(
            RF.input(
                exercises: [RF.slot(bench, target: 1, history: RF.weeklyHistory([2, 2, 2, 2], exercise: 1))],
                sessions: RF.sessionsInWindow(2),
                programDayCount: 1
            )
        )

        #expect(report.adherence == 0.5)
        #expect(report.suggestions.isEmpty)
    }

    @Test("R4 programa sem dias não tem aderência")
    func programWithoutDaysHasNoAdherence() {
        let bench = RF.exercise(1, [.chest])

        let report = RF.review(
            RF.input(
                exercises: [RF.slot(bench, target: 1, history: RF.weeklyHistory([12, 12, 12, 12], exercise: 1))],
                programDayCount: 0
            )
        )

        #expect(report.adherence == nil)
        #expect(RF.suggestions(report, .reduceDays).isEmpty)
    }
}
