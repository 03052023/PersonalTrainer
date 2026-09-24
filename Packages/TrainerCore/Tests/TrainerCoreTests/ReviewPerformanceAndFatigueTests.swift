import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.8 R1 (stagnation over 3 consecutive sessions) and R2 (fatigue signals).

private typealias RF = ReviewFixtures

@Suite("Review — R1 estagnação e R2 fadiga")
struct ReviewPerformanceAndFatigueTests {
    // MARK: - R1

    struct StagnationCase: Sendable, CustomTestStringConvertible {
        let e1rms: [Double]
        let deloadAt: Set<Int>
        let stagnant: Bool
        let label: String

        init(_ e1rms: [Double], deloadAt: Set<Int> = [], stagnant: Bool, _ label: String) {
            self.e1rms = e1rms
            self.deloadAt = deloadAt
            self.stagnant = stagnant
            self.label = label
        }

        var testDescription: String { label }
    }

    static let stagnationCases: [StagnationCase] = [
        StagnationCase([], stagnant: false, "sem histórico"),
        StagnationCase([100], stagnant: false, "uma sessão"),
        StagnationCase([100, 100, 100], stagnant: false, "fronteira: 3 sessões sem melhor anterior para comparar"),
        StagnationCase([100, 100, 100, 100], stagnant: true, "fronteira: 3 sessões seguidas sem superar a melhor anterior"),
        StagnationCase([100, 101, 100, 100], stagnant: false, "só 2 sessões desde a última melhora"),
        StagnationCase([100, 90, 95, 99], stagnant: true, "queda e recuperação parcial não é aumento"),
        StagnationCase([100, 99, 98, 101], stagnant: false, "a última sessão supera a melhor"),
        StagnationCase([100, 102.5, 105, 107.5], stagnant: false, "progresso contínuo"),
        StagnationCase([120, 100, 110, 115, 119], stagnant: true, "4 sessões abaixo de um pico antigo"),
        StagnationCase([100, 100, 100, 100], deloadAt: [2], stagnant: false, "sessão de deload não conta: só 3 medidas"),
        StagnationCase([100, 100, 100, 100, 100], deloadAt: [2], stagnant: true, "deload ignorado: 3 medidas depois da melhor"),
        StagnationCase([100, 100, 110, 100, 100], deloadAt: [2], stagnant: true, "pico numa semana de deload não é referência"),
    ]

    @Test("R1 estagnação = sem aumento do melhor 1RM estimado em 3 sessões consecutivas", arguments: ReviewPerformanceAndFatigueTests.stagnationCases)
    func stagnationTable(_ testCase: StagnationCase) {
        let bench = RF.exercise(1, [.chest])
        let history = RF.history(e1rms: testCase.e1rms, exercise: 1, deloadAt: testCase.deloadAt)

        let report = RF.review(RF.input(exercises: [RF.slot(bench, target: 1, history: history)]))

        #expect(report.stagnantExerciseIDs == (testCase.stagnant ? [bench.id] : []))
    }

    @Test("R1 exercício só com peso corporal (Epley = 0) nunca fica estagnado")
    func bodyweightWithoutLoadIsNeverStagnant() {
        let pushUp = RF.exercise(1, [.chest], equipment: .bodyweight)
        let history = RF.history(e1rms: [0, 0, 0, 0, 0], exercise: 1)

        let report = RF.review(RF.input(exercises: [RF.slot(pushUp, target: 1, history: history)]))

        #expect(report.stagnantExerciseIDs.isEmpty)
        #expect(RF.suggestions(report, .changeRepRange).isEmpty)
    }

    @Test("R1 empate por ruído de ponto flutuante (100 × 6 ≈ 90 × 10) não conta como aumento")
    func floatingPointTiesAreNotProgress() {
        let bench = RF.exercise(1, [.chest])
        let history = (0..<4).map { index -> ExerciseHistoryEntry in
            let date = RF.at(index - 4)
            let set = index.isMultiple(of: 2) ? RF.workingSet(100, 6, at: date) : RF.workingSet(90, 10, at: date)
            return RF.entry(RF.id(10_100 + index), date, [set])
        }

        let report = RF.review(RF.input(exercises: [RF.slot(bench, target: 1, history: history)]))

        #expect(report.stagnantExerciseIDs == [bench.id])
    }

    @Test("R1 histórico em qualquer ordem produz o mesmo relatório (R7)")
    func historyOrderDoesNotMatter() {
        let bench = RF.exercise(1, [.chest])
        let history = RF.history(e1rms: [100, 105, 104, 103, 102], exercise: 1)

        let forward = RF.review(RF.input(exercises: [RF.slot(bench, target: 1, history: history)]))
        let backward = RF.review(RF.input(exercises: [RF.slot(bench, target: 1, history: history.reversed())]))

        #expect(forward == backward)
        #expect(forward.stagnantExerciseIDs == [bench.id])
    }

    @Test("R1 o mesmo exercício em dois slots conta uma vez e recebe uma sugestão por slot")
    func sameExerciseInTwoSlotsIsPooled() {
        let bench = RF.exercise(1, [.chest])
        let history = RF.history(e1rms: [100, 100, 100, 100], exercise: 1)

        let report = RF.review(
            RF.input(exercises: [
                RF.slot(bench, target: 1, day: 1, history: history),
                RF.slot(bench, target: 2, day: 2, history: history),
            ])
        )

        #expect(report.stagnantExerciseIDs == [bench.id])
        #expect(RF.suggestions(report, .changeRepRange).map(\.targetIDs) == [[RF.id(201)], [RF.id(202)]])
    }

    @Test("R1 sessões com data depois de now são ignoradas")
    func futureSessionsAreIgnored() {
        let bench = RF.exercise(1, [.chest])
        let future = RF.now.addingTimeInterval(RF.oneDay)
        let history = RF.history(e1rms: [100, 100, 100, 100], exercise: 1)
            + [RF.entry(RF.id(19_999), future, [RF.workingSet(150, 1, at: future)])]

        let report = RF.review(RF.input(exercises: [RF.slot(bench, target: 1, history: history)]))

        #expect(report.stagnantExerciseIDs == [bench.id])
    }

    @Test("R1 duas entradas da mesma sessão (exercício repetido) são somadas antes de avaliar")
    func entriesOfTheSameSessionArePooled() {
        let bench = RF.exercise(1, [.chest])
        var history = RF.history(e1rms: [100, 100, 100, 100], exercise: 1)
        let last = history[history.count - 1]
        history.append(RF.entry(last.sessionID, last.date, [RF.workingSet(105, 1, at: last.date)]))

        let report = RF.review(RF.input(exercises: [RF.slot(bench, target: 1, history: history)]))

        #expect(report.stagnantExerciseIDs.isEmpty)
    }

    // MARK: - R2: RIR 0 share

    struct ReserveCase: Sendable, CustomTestStringConvertible {
        let zero: Int
        let rated: Int
        let unrated: Int
        let warmupZero: Int
        let negative: Int
        let fatigue: Bool
        let label: String

        init(zero: Int, rated: Int, unrated: Int = 0, warmupZero: Int = 0, negative: Int = 0, fatigue: Bool, _ label: String) {
            self.zero = zero
            self.rated = rated
            self.unrated = unrated
            self.warmupZero = warmupZero
            self.negative = negative
            self.fatigue = fatigue
            self.label = label
        }

        var testDescription: String { label }
    }

    static let reserveCases: [ReserveCase] = [
        ReserveCase(zero: 3, rated: 7, fatigue: false, "fronteira: 30 % exatos não é fadiga"),
        ReserveCase(zero: 30, rated: 70, fatigue: false, "fronteira: 30 de 100"),
        ReserveCase(zero: 31, rated: 69, fatigue: true, "31 de 100"),
        ReserveCase(zero: 4, rated: 6, fatigue: true, "40 %"),
        ReserveCase(zero: 3, rated: 6, unrated: 5, fatigue: true, "séries sem RIR ficam fora da conta: 3 de 9"),
        ReserveCase(zero: 3, rated: 7, warmupZero: 5, fatigue: false, "aquecimentos com RIR 0 não contam (P1)"),
        ReserveCase(zero: 0, rated: 6, negative: 4, fatigue: true, "RIR negativo conta como 0"),
        ReserveCase(zero: 0, rated: 0, unrated: 10, fatigue: false, "nenhum RIR registrado"),
    ]

    @Test("R2 fadiga: séries de trabalho com RIR 0 nas últimas 2 semanas > 30 %", arguments: ReviewPerformanceAndFatigueTests.reserveCases)
    func reserveShareTable(_ testCase: ReserveCase) {
        let bench = RF.exercise(1, [.chest])
        let date = RF.at(-1)
        var sets: [SetResult] = []
        sets += Array(repeating: RF.workingSet(50, 10, rir: 0, at: date), count: testCase.zero)
        sets += Array(repeating: RF.workingSet(50, 10, rir: 2, at: date), count: testCase.rated)
        sets += Array(repeating: RF.workingSet(50, 10, rir: nil, at: date), count: testCase.unrated)
        sets += Array(repeating: RF.warmup(30, 10, rir: 0, at: date), count: testCase.warmupZero)
        sets += Array(repeating: RF.workingSet(50, 10, rir: -1, at: date), count: testCase.negative)
        let history = [RF.entry(RF.id(10_100), date, sets)]

        let report = RF.review(RF.input(exercises: [RF.slot(bench, target: 1, history: history)]))

        #expect(report.fatigueHigh == testCase.fatigue)
        #expect(RF.suggestions(report, .deload).map(\.rule) == (testCase.fatigue ? ["R2"] : []))
    }

    @Test("R2 fronteira da janela: exatamente 14 dias antes de now entra; 1 s antes fica fora")
    func reserveWindowBoundary() {
        let bench = RF.exercise(1, [.chest])
        let recent = RF.at(-1)
        let recentEntry = RF.entry(
            RF.id(10_101),
            recent,
            Array(repeating: RF.workingSet(52.5, 10, rir: 2, at: recent), count: 6)
        )

        func report(oldSessionAt old: Date) -> ReviewReport {
            let oldEntry = RF.entry(RF.id(10_100), old, Array(repeating: RF.workingSet(50, 10, rir: 0, at: old), count: 4))
            return RF.review(RF.input(exercises: [RF.slot(bench, target: 1, history: [oldEntry, recentEntry])]))
        }

        let boundary = RF.now.addingTimeInterval(-14 * RF.oneDay)
        #expect(report(oldSessionAt: boundary).fatigueHigh)
        #expect(!report(oldSessionAt: boundary.addingTimeInterval(-1)).fatigueHigh)
    }

    @Test("R2 séries de uma sessão de deload recente entram na proporção")
    func deloadSetsCountTowardsTheShare() {
        let bench = RF.exercise(1, [.chest])
        let hard = RF.at(-8)
        let light = RF.at(-1)
        let history = [
            RF.entry(RF.id(10_100), hard, Array(repeating: RF.workingSet(50, 10, rir: 0, at: hard), count: 4)),
            RF.entry(RF.id(10_101), light, Array(repeating: RF.workingSet(40, 10, rir: 4, at: light), count: 10), deload: true),
        ]

        let report = RF.review(RF.input(exercises: [RF.slot(bench, target: 1, history: history)]))

        // 4 of 14 = 28.6 %: the deload week dilutes the share below the threshold.
        #expect(!report.fatigueHigh)
    }

    // MARK: - R2: prescriptions

    struct PrescriptionCase: Sendable, CustomTestStringConvertible {
        let notes: [PrescriptionNote]
        let fatigue: Bool
        let label: String

        init(_ notes: [PrescriptionNote], fatigue: Bool, _ label: String) {
            self.notes = notes
            self.fatigue = fatigue
            self.label = label
        }

        var testDescription: String { label }
    }

    static let prescriptionCases: [PrescriptionCase] = [
        PrescriptionCase([.decrease, .hold], fatigue: true, "fronteira: 50 % com decrease"),
        PrescriptionCase([.retry, .decrease, .increase, .hold], fatigue: true, "fronteira: 2 de 4 com retry/decrease"),
        PrescriptionCase([.retry, .hold, .hold], fatigue: false, "1 de 3 (33 %)"),
        PrescriptionCase([.decrease, .calibrate, .calibrate, .hold], fatigue: true, "calibrate fica fora da base: 1 de 2"),
        PrescriptionCase([.calibrate, .calibrate], fatigue: false, "só calibrate: nada a julgar"),
        PrescriptionCase([], fatigue: false, "sem prescrições"),
        PrescriptionCase([.returning, .hold, .retry], fatigue: false, "returning conta na base: 1 de 3"),
        PrescriptionCase([.retry, .retry, .increase], fatigue: true, "2 de 3 com retry"),
    ]

    @Test("R2 fadiga: ≥ 50 % das prescrições atuais (exceto calibrate) com decrease ou retry", arguments: ReviewPerformanceAndFatigueTests.prescriptionCases)
    func prescriptionShareTable(_ testCase: PrescriptionCase) {
        let bench = RF.exercise(1, [.chest])
        let prescriptions = testCase.notes.enumerated().map { RF.prescription($1, exercise: $0 + 1) }

        let report = RF.review(RF.input(exercises: [RF.slot(bench, target: 1)], prescriptions: prescriptions))

        #expect(report.fatigueHigh == testCase.fatigue)
        #expect(RF.suggestions(report, .deload).map(\.rule) == (testCase.fatigue ? ["R2"] : []))
    }

    @Test("R2 motivo do deload traz os números dos dois sinais")
    func deloadReasonListsBothSignals() throws {
        let bench = RF.exercise(1, [.chest])
        let date = RF.at(-1)
        let sets = Array(repeating: RF.workingSet(50, 10, rir: 0, at: date), count: 4)
            + Array(repeating: RF.workingSet(50, 10, rir: 2, at: date), count: 6)
        let history = [RF.entry(RF.id(10_100), date, sets)]

        let report = RF.review(
            RF.input(
                exercises: [RF.slot(bench, target: 1, history: history)],
                prescriptions: [RF.prescription(.decrease, exercise: 1), RF.prescription(.hold, exercise: 2)]
            )
        )

        let deload = try #require(RF.suggestions(report, .deload).first)
        #expect(deload.id == "deload:\(RF.week)")
        #expect(deload.rule == "R2")
        #expect(deload.title == "Semana mais leve")
        #expect(deload.referenceTopic == "rule.D")
        #expect(deload.strength == .recommended)
        #expect(deload.targetIDs.isEmpty)
        #expect(
            deload.reason
                == "Nas últimas 2 semanas, 4 de 10 séries (40%) terminaram sem nenhuma repetição de sobra; "
                + "em 1 de 2 exercícios (50%) a última sessão ficou abaixo do mínimo de repetições. "
                + "Uma semana com menos séries e cargas um pouco menores ajuda o corpo a se recuperar "
                + "e a voltar a progredir."
        )
    }
}
