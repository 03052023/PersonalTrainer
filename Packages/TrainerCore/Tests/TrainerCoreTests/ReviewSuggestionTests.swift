import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.8 R5 (suggestions), R6 (recovery modulation), R7 (determinism and fixed order)
// and §7.11 C2 (switching programs after the mesocycle).

private typealias RF = ReviewFixtures

@Suite("Review — R5 sugestões, R6 recuperação e R7 determinismo")
struct ReviewSuggestionTests {
    // MARK: - Scenarios

    /// Two stagnant exercises (chest, back) with little volume: deload by stagnation (R1),
    /// addSets for both slots (R3) and changeRepRange for both (R5).
    static func stagnationScenario(
        recovery: RecoveryContext = .unknown,
        prescriptions: [ExercisePrescription] = []
    ) -> ReviewReport {
        let bench = RF.exercise(1, [.chest])
        let row = RF.exercise(2, [.back])
        return RF.review(
            RF.input(
                exercises: [
                    RF.slot(bench, target: 1, history: RF.history(e1rms: [100, 100, 100, 100], exercise: 1)),
                    RF.slot(row, target: 2, history: RF.history(e1rms: [100, 100, 100, 100], exercise: 2)),
                ],
                prescriptions: prescriptions,
                recovery: recovery
            )
        )
    }

    /// Every kind except reduceDays: fatigue (R2) → deload; chest above the ceiling →
    /// removeSets; back, quads and glutes below the range → addSets; quads stagnant for 3
    /// sessions → changeRepRange; glutes stagnant for 6 → swapExercise; 8+ weeks on the
    /// program → switchProgram.
    static func fullScenarioInput(sessions: [SessionSummary] = ReviewFixtures.sessionsInWindow(12)) -> ReviewInput {
        RF.input(
            exercises: [
                RF.slot(RF.exercise(1, [.chest]), target: 1, sets: 3, history: RF.weeklyHistory([11, 11, 11, 11], exercise: 1)),
                RF.slot(RF.exercise(2, [.chest]), target: 2, sets: 4, history: RF.weeklyHistory([11, 11, 11, 11], exercise: 2)),
                RF.slot(RF.exercise(3, [.back]), target: 3, history: RF.weeklyHistory([2, 2, 2, 2], exercise: 3)),
                RF.slot(RF.exercise(4, [.quads]), target: 4, history: RF.history(e1rms: [100, 100, 100, 100], exercise: 4)),
                RF.slot(RF.exercise(5, [.glutes]), target: 5, history: RF.history(e1rms: Array(repeating: 100, count: 7), exercise: 5)),
            ],
            sessions: sessions,
            programStartDate: RF.at(-60),
            prescriptions: [RF.prescription(.decrease, exercise: 1), RF.prescription(.hold, exercise: 2)]
        )
    }

    // MARK: - R5: deload

    @Test("R5 deload quando ≥ 50 % dos exercícios estagnaram (R1), com o motivo e os números")
    func deloadWhenHalfTheExercisesStagnate() throws {
        let flat = [100.0, 100, 100, 100]
        let rising = [100.0, 102.5, 105, 107.5]
        let muscles: [MuscleGroup] = [.chest, .back, .quads, .glutes]
        let slots = [flat, flat, rising, rising].enumerated().map { index, e1rms in
            RF.slot(RF.exercise(index + 1, [muscles[index]]), target: index + 1, history: RF.history(e1rms: e1rms, exercise: index + 1))
        }

        let report = RF.review(RF.input(exercises: slots))

        #expect(report.stagnantExerciseIDs == [RF.id(101), RF.id(102)])
        #expect(!report.fatigueHigh)
        let deload = try #require(RF.suggestions(report, .deload).first)
        #expect(deload.rule == "R1")
        #expect(deload.strength == .recommended)
        #expect(
            deload.reason
                == "2 de 4 exercícios (50%) não melhoram há pelo menos 3 sessões. Uma semana com menos séries "
                + "e cargas um pouco menores ajuda o corpo a se recuperar e a voltar a progredir."
        )
    }

    @Test("R5 fronteira: 1 de 4 exercícios estagnado não pede deload, só muda aquele exercício")
    func oneStagnantExerciseOfFourIsNotADeload() {
        let flat = [100.0, 100, 100, 100]
        let rising = [100.0, 102.5, 105, 107.5]
        let muscles: [MuscleGroup] = [.chest, .back, .quads, .glutes]
        let slots = [flat, rising, rising, rising].enumerated().map { index, e1rms in
            RF.slot(RF.exercise(index + 1, [muscles[index]]), target: index + 1, history: RF.history(e1rms: e1rms, exercise: index + 1))
        }

        let report = RF.review(RF.input(exercises: slots))

        #expect(RF.suggestions(report, .deload).isEmpty)
        #expect(RF.suggestions(report, .changeRepRange).map(\.targetIDs) == [[RF.id(201)]])
    }

    @Test("R5 deload já em andamento (prescrições com nota deload) não é sugerido de novo")
    func noDeloadSuggestionWhileADeloadRuns() {
        let bench = RF.exercise(1, [.chest])
        let date = RF.at(-1)
        let sets = Array(repeating: RF.workingSet(50, 10, rir: 0, at: date), count: 4)
            + Array(repeating: RF.workingSet(50, 10, rir: 2, at: date), count: 6)

        let report = RF.review(
            RF.input(
                exercises: [RF.slot(bench, target: 1, history: [RF.entry(RF.id(10_100), date, sets)])],
                prescriptions: [RF.prescription(.deload, exercise: 1), RF.prescription(.deload, exercise: 2)]
            )
        )

        #expect(report.fatigueHigh)
        #expect(RF.suggestions(report, .deload).isEmpty)
    }

    // MARK: - R5: exercise changes

    @Test("R5 exercício estagnado há menos de 6 sessões → faixa de repetições vizinha")
    func stagnantExerciseMovesToTheNeighbouringRange() throws {
        let bench = RF.exercise(1, [.chest])

        let report = RF.review(
            RF.input(exercises: [RF.slot(bench, target: 1, history: RF.history(e1rms: [100, 100, 100, 100], exercise: 1))])
        )

        #expect(RF.suggestions(report, .swapExercise).isEmpty)
        let change = try #require(RF.suggestions(report, .changeRepRange).first)
        #expect(change.id == "changeRepRange:\(RF.id(201).uuidString):\(RF.week)")
        #expect(change.rule == "R1")
        #expect(change.targetIDs == [RF.id(201)])
        #expect(change.proposedRepRange == 6...10)
        #expect(change.proposedSets == nil)
        #expect(change.muscle == nil)
        #expect(change.referenceTopic == "topic.substitution")
        #expect(change.title == "Outra faixa de repetições em Exercício 1")
        #expect(
            change.reason
                == "Exercício 1 está há 3 sessões sem superar sua melhor marca estimada (100 kg); "
                + "trocar a faixa de 8–12 para 6–10 repetições muda o estímulo."
        )
    }

    struct RangeCase: Sendable, CustomTestStringConvertible {
        let repMin: Int
        let repMax: Int
        let expected: ClosedRange<Int>?

        var testDescription: String {
            guard let expected else { return "\(repMin)–\(repMax) → nil" }
            return "\(repMin)–\(repMax) → \(expected.lowerBound)–\(expected.upperBound)"
        }
    }

    static let rangeCases: [RangeCase] = [
        RangeCase(repMin: 8, repMax: 12, expected: 6...10),
        RangeCase(repMin: 6, repMax: 10, expected: 4...8),
        RangeCase(repMin: 5, repMax: 8, expected: 3...6),
        RangeCase(repMin: 12, repMax: 20, expected: 10...18),
        RangeCase(repMin: 4, repMax: 6, expected: 6...8),
        RangeCase(repMin: 3, repMax: 6, expected: 5...8),
        RangeCase(repMin: 1, repMax: 1, expected: 3...3),
        RangeCase(repMin: 0, repMax: 5, expected: nil),
        RangeCase(repMin: 10, repMax: 8, expected: nil),
    ]

    @Test("R5 faixa vizinha: 2 repetições abaixo; abaixo de 3 no mínimo, 2 acima", arguments: ReviewSuggestionTests.rangeCases)
    func neighbouringRangeTable(_ testCase: RangeCase) {
        #expect(ProgramReviewer.neighbouringRepRange(repMin: testCase.repMin, repMax: testCase.repMax) == testCase.expected)
    }

    struct SwapCase: Sendable, CustomTestStringConvertible {
        let sessionsWithoutProgress: Int
        let swap: Bool

        var testDescription: String { "\(sessionsWithoutProgress) sessões sem melhora → \(swap ? "trocar" : "faixa")" }
    }

    static let swapCases: [SwapCase] = [
        SwapCase(sessionsWithoutProgress: 3, swap: false),
        SwapCase(sessionsWithoutProgress: 5, swap: false),
        SwapCase(sessionsWithoutProgress: 6, swap: true),
        SwapCase(sessionsWithoutProgress: 9, swap: true),
    ]

    @Test("R5 fronteira: estagnado há ≥ 6 sessões → trocar o exercício em vez da faixa", arguments: ReviewSuggestionTests.swapCases)
    func swapAfterSixSessions(_ testCase: SwapCase) {
        let bench = RF.exercise(1, [.chest])
        let e1rms = [Double](repeating: 100, count: testCase.sessionsWithoutProgress + 1)

        let report = RF.review(RF.input(exercises: [RF.slot(bench, target: 1, history: RF.history(e1rms: e1rms, exercise: 1))]))

        #expect(RF.suggestions(report, .swapExercise).count == (testCase.swap ? 1 : 0))
        #expect(RF.suggestions(report, .changeRepRange).count == (testCase.swap ? 0 : 1))
    }

    @Test("R5 troca de exercício: uma sugestão por exercício, com todos os seus slots")
    func swapCoversEverySlotOfTheExercise() throws {
        let bench = RF.exercise(1, [.chest])
        let history = RF.history(e1rms: [Double](repeating: 100, count: 7), exercise: 1)

        let report = RF.review(
            RF.input(exercises: [
                RF.slot(bench, target: 2, day: 2, history: history),
                RF.slot(bench, target: 1, day: 1, history: history),
            ])
        )

        let swaps = RF.suggestions(report, .swapExercise)
        let swap = try #require(swaps.first)
        #expect(swaps.count == 1)
        #expect(swap.id == "swapExercise:\(RF.id(101).uuidString):\(RF.week)")
        #expect(swap.rule == "R1")
        #expect(swap.targetIDs == [RF.id(201), RF.id(202)])
        #expect(swap.referenceTopic == "topic.substitution")
        #expect(swap.title == "Trocar Exercício 1 por um exercício parecido")
        #expect(
            swap.reason
                == "Exercício 1 está há 6 sessões sem superar sua melhor marca estimada (100 kg); um exercício "
                + "diferente para os mesmos músculos renova o estímulo, e as cargas dos outros exercícios continuam."
        )
    }

    @Test("R5 marca estimada sem unidade quando a carga é em placas ou nível")
    func estimateWithoutUnitForPlates() throws {
        let machine = RF.exercise(1, [.chest], unit: .plates, equipment: .machine)

        let report = RF.review(
            RF.input(exercises: [RF.slot(machine, target: 1, history: RF.history(e1rms: [12.5, 12.5, 12.5, 12.5], exercise: 1))])
        )

        let change = try #require(RF.suggestions(report, .changeRepRange).first)
        #expect(change.reason.contains("melhor marca estimada (12,5);"))
    }

    // MARK: - C2: switching programs

    struct MesocycleCase: Sendable, CustomTestStringConvertible {
        let start: Date?
        let weeks: Int
        let suggested: Bool
        let label: String

        var testDescription: String { label }
    }

    static let mesocycleCases: [MesocycleCase] = [
        MesocycleCase(start: RF.now.addingTimeInterval(-56 * RF.oneDay), weeks: 8, suggested: true, label: "fronteira: exatamente 8 semanas"),
        MesocycleCase(start: RF.now.addingTimeInterval(-56 * RF.oneDay + 1), weeks: 8, suggested: false, label: "1 s antes de 8 semanas"),
        MesocycleCase(start: RF.defaultStart, weeks: 8, suggested: false, label: "6 semanas de 8"),
        MesocycleCase(start: RF.defaultStart, weeks: 4, suggested: true, label: "mesociclo configurado em 4 semanas"),
        MesocycleCase(start: RF.defaultStart, weeks: 0, suggested: false, label: "mesociclo 0 desliga"),
        MesocycleCase(start: nil, weeks: 8, suggested: false, label: "programa nunca treinado"),
    ]

    @Test("C2/R5 trocar de programa depois de mesocycleWeeks semanas (sempre opcional)", arguments: ReviewSuggestionTests.mesocycleCases)
    func switchProgramAfterTheMesocycle(_ testCase: MesocycleCase) {
        let bench = RF.exercise(1, [.chest])

        let report = RF.review(
            RF.input(
                exercises: [RF.slot(bench, target: 1, history: RF.weeklyHistory([12, 12, 12, 12], exercise: 1))],
                programStartDate: testCase.start,
                mesocycleWeeks: testCase.weeks
            )
        )

        #expect(RF.suggestions(report, .switchProgram).count == (testCase.suggested ? 1 : 0))
        #expect(RF.suggestions(report, .switchProgram).allSatisfy { $0.strength == .optional })
    }

    @Test("C2/R5 texto da troca de programa traz o nome e as semanas")
    func switchProgramText() throws {
        let bench = RF.exercise(1, [.chest])

        let report = RF.review(
            RF.input(
                exercises: [RF.slot(bench, target: 1, history: RF.weeklyHistory([12, 12, 12, 12], exercise: 1))],
                programStartDate: RF.now.addingTimeInterval(-56 * RF.oneDay)
            )
        )

        #expect(RF.kinds(report) == [.switchProgram])
        let suggestion = try #require(report.suggestions.first)
        #expect(suggestion.id == "switchProgram:\(RF.programID.uuidString):\(RF.week)")
        #expect(suggestion.rule == "R5")
        #expect(suggestion.targetIDs.isEmpty)
        #expect(suggestion.referenceTopic == "topic.substitution")
        #expect(suggestion.title == "Experimentar um novo programa")
        #expect(
            suggestion.reason
                == "Você treina com o programa Programa A há 8 semanas; depois de 8 semanas, mudar de programa "
                + "renova o estímulo, e as cargas de cada exercício são mantidas."
        )
    }

    // MARK: - R6

    struct RecoveryCase: Sendable, CustomTestStringConvertible {
        let recovery: RecoveryContext
        let fatigue: Bool
        let deload: SuggestionStrength
        let addSets: SuggestionStrength
        let label: String

        var testDescription: String { label }
    }

    static let recoveryCases: [RecoveryCase] = [
        RecoveryCase(recovery: .unknown, fatigue: false, deload: .recommended, addSets: .recommended, label: "sem dados de recuperação"),
        RecoveryCase(recovery: RecoveryContext(hrvDropped: true, hasData: true), fatigue: false, deload: .recommended, addSets: .optional, label: "HRV em queda"),
        RecoveryCase(recovery: RecoveryContext(restingHeartRateRose: true, hasData: true), fatigue: false, deload: .recommended, addSets: .optional, label: "FC de repouso em alta"),
        RecoveryCase(recovery: RecoveryContext(hrvDropped: true, restingHeartRateRose: true, sleepLow: true, hasData: true), fatigue: false, deload: .recommended, addSets: .optional, label: "tudo em queda"),
        RecoveryCase(recovery: RecoveryContext(hasData: true), fatigue: false, deload: .optional, addSets: .recommended, label: "estável e sem fadiga"),
        RecoveryCase(recovery: RecoveryContext(hasData: true), fatigue: true, deload: .recommended, addSets: .recommended, label: "estável com fadiga (R2)"),
        RecoveryCase(recovery: RecoveryContext(sleepLow: true, hasData: true), fatigue: false, deload: .recommended, addSets: .recommended, label: "só sono baixo: não enfraquece nem reforça"),
        RecoveryCase(recovery: RecoveryContext(hrvDropped: true, restingHeartRateRose: true, hasData: false), fatigue: false, deload: .recommended, addSets: .recommended, label: "sem dados suficientes: sinais ignorados"),
        RecoveryCase(recovery: RecoveryContext(hrvDropped: true, hasData: true), fatigue: true, deload: .recommended, addSets: .optional, label: "HRV em queda com fadiga"),
    ]

    @Test("R6 recuperação só modula: queda reforça deload e enfraquece addSets; estável sem fadiga enfraquece deload", arguments: ReviewSuggestionTests.recoveryCases)
    func recoveryModulationTable(_ testCase: RecoveryCase) throws {
        let prescriptions: [ExercisePrescription] = testCase.fatigue
            ? [RF.prescription(.decrease, exercise: 1), RF.prescription(.hold, exercise: 2)]
            : []

        let report = Self.stagnationScenario(recovery: testCase.recovery, prescriptions: prescriptions)
        let baseline = Self.stagnationScenario(prescriptions: prescriptions)

        let deload = try #require(RF.suggestions(report, .deload).first)
        #expect(deload.strength == testCase.deload)
        #expect(RF.suggestions(report, .addSets).count == 2)
        #expect(RF.suggestions(report, .addSets).allSatisfy { $0.strength == testCase.addSets })
        #expect(RF.suggestions(report, .changeRepRange).allSatisfy { $0.strength == .recommended })
        // R6 never adds nor removes a suggestion.
        #expect(report.suggestions.map(\.id) == baseline.suggestions.map(\.id))
        #expect(report.fatigueHigh == testCase.fatigue)
    }

    @Test("R6 o motivo explica a modulação pela recuperação")
    func recoveryModulationIsExplained() throws {
        let strained = Self.stagnationScenario(
            recovery: RecoveryContext(hrvDropped: true, restingHeartRateRose: true, hasData: true)
        )
        let stable = Self.stagnationScenario(recovery: RecoveryContext(hasData: true))
        let trend = "a variabilidade da frequência cardíaca caiu e a frequência cardíaca de repouso subiu"

        let reinforced = try #require(RF.suggestions(strained, .deload).first)
        let weakenedAddition = try #require(RF.suggestions(strained, .addSets).first)
        let weakenedDeload = try #require(RF.suggestions(stable, .deload).first)

        #expect(reinforced.reason.hasSuffix(" Na última semana \(trend) em relação ao último mês, o que reforça a pausa."))
        #expect(weakenedAddition.reason.hasSuffix(" Fica opcional porque, na última semana, \(trend) em relação ao último mês."))
        #expect(weakenedDeload.reason.hasSuffix(" Fica opcional porque seus sinais de recuperação estão estáveis e não há sinais de cansaço."))
    }

    @Test("R6 recuperação sozinha nunca gera sugestão")
    func recoveryAloneCreatesNothing() {
        let bench = RF.exercise(1, [.chest])
        let exercises = [RF.slot(bench, target: 1, history: RF.weeklyHistory([12, 12, 12, 12], exercise: 1))]

        let strained = RF.review(
            RF.input(
                exercises: exercises,
                recovery: RecoveryContext(hrvDropped: true, restingHeartRateRose: true, sleepLow: true, hasData: true)
            )
        )
        let stable = RF.review(RF.input(exercises: exercises, recovery: RecoveryContext(hasData: true)))

        #expect(strained.suggestions.isEmpty)
        #expect(stable.suggestions.isEmpty)
        #expect(!strained.fatigueHigh)
    }

    @Test("R6 não toca em removeSets, reduceDays, troca de faixa/exercício nem troca de programa")
    func recoveryLeavesOtherKindsAlone() {
        let strainedRecovery = RecoveryContext(hrvDropped: true, restingHeartRateRose: true, hasData: true)
        let lowAdherence = RF.sessionsInWindow(6)

        for sessions in [RF.sessionsInWindow(12), lowAdherence] {
            let baseline = RF.review(Self.fullScenarioInput(sessions: sessions))
            let input = Self.fullScenarioInput(sessions: sessions)
            let strained = RF.review(
                ReviewInput(
                    programID: input.programID,
                    programName: input.programName,
                    programDayCount: input.programDayCount,
                    programStartDate: input.programStartDate,
                    exercises: input.exercises,
                    sessions: input.sessions,
                    weeklySetTarget: input.weeklySetTarget,
                    muscleTargets: input.muscleTargets,
                    currentPrescriptions: input.currentPrescriptions,
                    recovery: strainedRecovery,
                    mesocycleWeeks: input.mesocycleWeeks,
                    weekStartsOnMonday: input.weekStartsOnMonday
                )
            )

            #expect(strained.suggestions.map(\.id) == baseline.suggestions.map(\.id))
            for (modulated, original) in zip(strained.suggestions, baseline.suggestions)
            where modulated.kind != .deload && modulated.kind != .addSets {
                #expect(modulated == original)
            }
        }
    }

    // MARK: - R7

    @Test("R7 ordem fixa: deload, removeSets, addSets, changeRepRange, swapExercise, switchProgram; depois por id")
    func fixedOrderWithoutReduceDays() {
        let report = RF.review(Self.fullScenarioInput())

        #expect(report.suggestions.map(\.id) == [
            "deload:\(RF.week)",
            "removeSets:chest:\(RF.id(201).uuidString):\(RF.week)",
            "removeSets:chest:\(RF.id(202).uuidString):\(RF.week)",
            "addSets:back:\(RF.id(203).uuidString):\(RF.week)",
            "addSets:glutes:\(RF.id(205).uuidString):\(RF.week)",
            "addSets:quads:\(RF.id(204).uuidString):\(RF.week)",
            "changeRepRange:\(RF.id(204).uuidString):\(RF.week)",
            "swapExercise:\(RF.id(105).uuidString):\(RF.week)",
            "switchProgram:\(RF.programID.uuidString):\(RF.week)",
        ])
        #expect(report.suggestions.map(\.rule) == ["R2", "R3", "R3", "R3", "R3", "R3", "R1", "R1", "R5"])
        #expect(report.stagnantExerciseIDs == [RF.id(104), RF.id(105)])
        #expect(report.fatigueHigh)
        #expect(report.adherence == 1)
        #expect(report.generatedAt == RF.now)
    }

    @Test("R7 ordem fixa com aderência baixa: reduceDays logo após o deload e nenhum addSets (R4)")
    func fixedOrderWithReduceDays() {
        let report = RF.review(Self.fullScenarioInput(sessions: RF.sessionsInWindow(6)))

        #expect(RF.kinds(report) == [
            .deload, .reduceDays, .removeSets, .removeSets, .changeRepRange, .swapExercise, .switchProgram,
        ])
    }

    @Test("R7 mesma entrada em qualquer ordem → mesmo relatório")
    func sameInputInAnyOrderGivesTheSameReport() {
        let input = Self.fullScenarioInput()
        let shuffled = ReviewInput(
            programID: input.programID,
            programName: input.programName,
            programDayCount: input.programDayCount,
            programStartDate: input.programStartDate,
            exercises: input.exercises.reversed().map { slot in
                ExerciseReviewInput(
                    exercise: slot.exercise,
                    targetID: slot.targetID,
                    dayID: slot.dayID,
                    sets: slot.sets,
                    repMin: slot.repMin,
                    repMax: slot.repMax,
                    history: slot.history.reversed()
                )
            },
            sessions: input.sessions.reversed(),
            weeklySetTarget: input.weeklySetTarget,
            muscleTargets: input.muscleTargets,
            currentPrescriptions: input.currentPrescriptions.reversed(),
            recovery: input.recovery,
            mesocycleWeeks: input.mesocycleWeeks,
            weekStartsOnMonday: input.weekStartsOnMonday
        )

        let first = RF.review(input)
        let again = RF.review(input)
        let reordered = RF.review(shuffled)

        #expect(first == again)
        #expect(first == reordered)
    }

    @Test("R7 ids estáveis dentro da mesma semana ISO")
    func idsAreStableWithinTheWeek() {
        let wednesday = RF.review(Self.fullScenarioInput())
        let saturday = RF.review(Self.fullScenarioInput(), now: RF.at(5, hour: 12))

        #expect(wednesday.suggestions.map(\.id) == saturday.suggestions.map(\.id))
    }

    struct WeekLabelCase: Sendable, CustomTestStringConvertible {
        let date: Date
        let saoPaulo: Bool
        let label: String

        var testDescription: String { "\(date.timeIntervalSince1970) \(saoPaulo ? "São Paulo" : "UTC") → \(label)" }
    }

    static let weekLabelCases: [WeekLabelCase] = [
        WeekLabelCase(date: RF.now, saoPaulo: false, label: "2026-W39"),
        WeekLabelCase(date: RF.monday.addingTimeInterval(RF.oneHour), saoPaulo: false, label: "2026-W39"),
        // Monday 01:00 UTC is still Sunday 22:00 in São Paulo.
        WeekLabelCase(date: RF.monday.addingTimeInterval(RF.oneHour), saoPaulo: true, label: "2026-W38"),
        // 2026-01-01 (Thursday) is in ISO week 1 of 2026, which starts on 2025-12-29.
        WeekLabelCase(date: Date(timeIntervalSince1970: 1_767_268_800), saoPaulo: false, label: "2026-W01"),
        WeekLabelCase(date: Date(timeIntervalSince1970: 1_767_009_600), saoPaulo: false, label: "2026-W01"),
        // 2027-01-01 (Friday) still belongs to ISO week 53 of 2026.
        WeekLabelCase(date: Date(timeIntervalSince1970: 1_798_804_800), saoPaulo: false, label: "2026-W53"),
    ]

    @Test("R7 semana ISO nos ids, no fuso do calendário", arguments: ReviewSuggestionTests.weekLabelCases)
    func isoWeekLabelTable(_ testCase: WeekLabelCase) throws {
        let calendar = try testCase.saoPaulo ? RF.saoPaulo() : RF.utc

        #expect(ProgramReviewer.isoWeekLabel(for: testCase.date, calendar: calendar) == testCase.label)
    }

    @Test("R7 números do motivo em pt-BR, sem formatador dependente de locale")
    func reasonNumberFormatting() {
        #expect(ReviewText.number(8) == "8")
        #expect(ReviewText.number(8.25) == "8,3")
        #expect(ReviewText.number(1.75) == "1,8")
        #expect(ReviewText.number(133.33333) == "133,3")
        #expect(ReviewText.number(0.04) == "0")
        #expect(ReviewText.number(.nan) == "0")
        #expect(ReviewText.percent(1, of: 3) == "33%")
        #expect(ReviewText.percent(2, of: 3) == "67%")
        #expect(ReviewText.percent(1, of: 0) == "0%")
        #expect(ReviewText.count(1, "semana", "semanas") == "1 semana")
        #expect(ReviewText.count(2, "dia", "dias") == "2 dias")
    }
}
