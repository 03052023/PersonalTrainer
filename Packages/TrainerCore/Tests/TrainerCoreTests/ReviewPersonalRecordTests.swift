import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.11 C6: a new best estimated 1RM (Epley) of an exercise in the latest session.

private typealias RF = ReviewFixtures

@Suite("Review — C6 marco pessoal")
struct ReviewPersonalRecordTests {
    static let exerciseID = RF.id(101)
    static let earlier = RF.id(40_001)
    static let previous = RF.id(40_002)
    static let latest = RF.id(40_003)
    static let later = RF.id(40_004)

    static func session(_ id: UUID, dayOffset: Int, _ sets: [(load: Double, reps: Int)], deload: Bool = false) -> ExerciseHistoryEntry {
        let date = RF.at(dayOffset)
        return RF.entry(id, date, sets.map { RF.workingSet($0.load, $0.reps, at: date) }, deload: deload)
    }

    struct RecordCase: Sendable, CustomTestStringConvertible {
        let previous: [(load: Double, reps: Int)]
        let latest: [(load: Double, reps: Int)]
        let record: Bool
        let label: String

        var testDescription: String { label }
    }

    static let recordCases: [RecordCase] = [
        RecordCase(previous: [(100, 5)], latest: [(105, 5)], record: true, label: "mais carga, mesmas reps"),
        RecordCase(previous: [(100, 5)], latest: [(100, 6)], record: true, label: "mesma carga, mais reps"),
        RecordCase(previous: [(100, 5)], latest: [(100, 5)], record: false, label: "empate não é recorde"),
        RecordCase(previous: [(100, 6)], latest: [(90, 10)], record: false, label: "empate por ruído (100 × 6 ≈ 90 × 10)"),
        RecordCase(previous: [(100, 5)], latest: [(95, 5)], record: false, label: "abaixo do melhor"),
        RecordCase(previous: [(100, 5), (80, 12)], latest: [(90, 8), (95, 6)], record: false, label: "melhor série de cada sessão: 114 não supera 116,7"),
        RecordCase(previous: [(100, 5), (80, 12)], latest: [(90, 8), (97.5, 6)], record: true, label: "melhor série de cada sessão: 117 supera 116,7"),
    ]

    @Test("C6 recorde = melhor 1RM estimado da sessão maior que o de todas as anteriores", arguments: ReviewPersonalRecordTests.recordCases)
    func recordTable(_ testCase: RecordCase) {
        let histories = [
            Self.exerciseID: [
                Self.session(Self.previous, dayOffset: -3, testCase.previous),
                Self.session(Self.latest, dayOffset: -1, testCase.latest),
            ],
        ]

        let records = PersonalRecordDetector.newRecords(latestSessionID: Self.latest, histories: histories)

        #expect(records.count == (testCase.record ? 1 : 0))
    }

    @Test("C6 recorde traz a estimativa, a melhor anterior e a série que o gerou")
    func recordCarriesItsNumbers() throws {
        let histories = [
            Self.exerciseID: [
                Self.session(Self.earlier, dayOffset: -5, [(90, 5)]),
                Self.session(Self.previous, dayOffset: -3, [(100, 5), (95, 5)]),
                Self.session(Self.latest, dayOffset: -1, [(105, 5), (100, 6)]),
            ],
        ]

        let record = try #require(PersonalRecordDetector.newRecords(latestSessionID: Self.latest, histories: histories).first)
        let previousBest = try #require(record.previousBest)

        #expect(record.exerciseID == Self.exerciseID)
        #expect(RF.isClose(record.e1rm, 105 * (1 + 5.0 / 30)))
        #expect(RF.isClose(previousBest, 100 * (1 + 5.0 / 30)))
        #expect(record.load == 105)
        #expect(record.reps == 5)
    }

    @Test("C6 primeira sessão do exercício não é recorde")
    func firstSessionIsNotARecord() {
        let histories = [Self.exerciseID: [Self.session(Self.latest, dayOffset: -1, [(100, 5)])]]

        #expect(PersonalRecordDetector.newRecords(latestSessionID: Self.latest, histories: histories).isEmpty)
    }

    @Test("C6 sessões posteriores à sessão avaliada não entram na comparação")
    func laterSessionsAreIgnored() throws {
        let histories = [
            Self.exerciseID: [
                Self.session(Self.later, dayOffset: 0, [(120, 5)]),
                Self.session(Self.latest, dayOffset: -1, [(105, 5)]),
                Self.session(Self.previous, dayOffset: -3, [(100, 5)]),
            ],
        ]

        let record = try #require(PersonalRecordDetector.newRecords(latestSessionID: Self.latest, histories: histories).first)
        let previousBest = try #require(record.previousBest)

        #expect(record.load == 105)
        #expect(RF.isClose(previousBest, 100 * (1 + 5.0 / 30)))
    }

    @Test("C6 aquecimentos não contam; sessões de deload anteriores contam como marca real")
    func warmupsIgnoredAndDeloadSessionsCount() {
        let latestDate = RF.at(-1)
        let latestWithHeavyWarmup = RF.entry(
            Self.latest,
            latestDate,
            [RF.warmup(200, 5, at: latestDate), RF.workingSet(100, 5, at: latestDate)]
        )

        let warmupHistories = [
            Self.exerciseID: [Self.session(Self.previous, dayOffset: -3, [(100, 5)]), latestWithHeavyWarmup],
        ]
        let deloadHistories = [
            Self.exerciseID: [
                Self.session(Self.previous, dayOffset: -3, [(110, 5)], deload: true),
                Self.session(Self.latest, dayOffset: -1, [(105, 5)]),
            ],
        ]

        #expect(PersonalRecordDetector.newRecords(latestSessionID: Self.latest, histories: warmupHistories).isEmpty)
        #expect(PersonalRecordDetector.newRecords(latestSessionID: Self.latest, histories: deloadHistories).isEmpty)
    }

    @Test("C6 duas entradas da mesma sessão (exercício repetido) são somadas")
    func entriesOfTheLatestSessionArePooled() throws {
        let date = RF.at(-1)
        let histories = [
            Self.exerciseID: [
                Self.session(Self.previous, dayOffset: -3, [(100, 5)]),
                RF.entry(Self.latest, date, [RF.workingSet(95, 5, at: date)]),
                RF.entry(Self.latest, date, [RF.workingSet(110, 5, at: date)]),
            ],
        ]

        let record = try #require(PersonalRecordDetector.newRecords(latestSessionID: Self.latest, histories: histories).first)

        #expect(record.load == 110)
    }

    @Test("C6 peso corporal sem carga não é medido: a primeira sessão com carga não é recorde")
    func bodyweightSessionsAreNotMeasured() {
        let bodyweightOnly = [
            Self.exerciseID: [
                Self.session(Self.previous, dayOffset: -3, [(0, 12)]),
                Self.session(Self.latest, dayOffset: -1, [(0, 15)]),
            ],
        ]
        let firstLoaded = [
            Self.exerciseID: [
                Self.session(Self.previous, dayOffset: -3, [(0, 12)]),
                Self.session(Self.latest, dayOffset: -1, [(10, 8)]),
            ],
        ]

        #expect(PersonalRecordDetector.newRecords(latestSessionID: Self.latest, histories: bodyweightOnly).isEmpty)
        #expect(PersonalRecordDetector.newRecords(latestSessionID: Self.latest, histories: firstLoaded).isEmpty)
    }

    @Test("C6 vários exercícios: um recorde por exercício, ordenados por id; exercício fora da sessão não aparece")
    func severalExercisesAreSortedById() {
        let second = RF.id(102)
        let third = RF.id(103)
        let histories = [
            third: [
                Self.session(Self.previous, dayOffset: -3, [(40, 10)]),
                Self.session(Self.latest, dayOffset: -1, [(42.5, 10)]),
            ],
            Self.exerciseID: [
                Self.session(Self.previous, dayOffset: -3, [(100, 5)]),
                Self.session(Self.latest, dayOffset: -1, [(102.5, 5)]),
            ],
            second: [
                Self.session(Self.earlier, dayOffset: -5, [(60, 8)]),
                Self.session(Self.previous, dayOffset: -3, [(62.5, 8)]),
            ],
        ]

        let records = PersonalRecordDetector.newRecords(latestSessionID: Self.latest, histories: histories)

        #expect(records.map(\.exerciseID) == [Self.exerciseID, third])
    }

    @Test("C6 histórico em qualquer ordem → mesmos recordes (R7)")
    func historyOrderDoesNotMatter() {
        let entries = [
            Self.session(Self.earlier, dayOffset: -5, [(90, 5)]),
            Self.session(Self.previous, dayOffset: -3, [(100, 5)]),
            Self.session(Self.latest, dayOffset: -1, [(102.5, 5)]),
        ]

        let forward = PersonalRecordDetector.newRecords(latestSessionID: Self.latest, histories: [Self.exerciseID: entries])
        let backward = PersonalRecordDetector.newRecords(
            latestSessionID: Self.latest,
            histories: [Self.exerciseID: entries.reversed()]
        )

        #expect(forward == backward)
        #expect(forward.count == 1)
    }
}
