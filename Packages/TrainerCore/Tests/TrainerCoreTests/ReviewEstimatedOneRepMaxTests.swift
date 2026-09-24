import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.8 R1: 1RM estimate = load × (1 + reps/30) (Epley) over the best working set.

private typealias RF = ReviewFixtures

@Suite("Review — EstimatedOneRepMax (SPEC R1)")
struct ReviewEstimatedOneRepMaxTests {
    struct EpleyCase: Sendable, CustomTestStringConvertible {
        let load: Double
        let reps: Int
        let expected: Double

        var testDescription: String { "\(load) × \(reps) → \(expected)" }
    }

    static let epleyCases: [EpleyCase] = [
        EpleyCase(load: 100, reps: 10, expected: 100 * (1 + 10.0 / 30)),
        EpleyCase(load: 60, reps: 30, expected: 120),
        EpleyCase(load: 100, reps: 6, expected: 120),
        EpleyCase(load: 52.5, reps: 8, expected: 52.5 * (1 + 8.0 / 30)),
        EpleyCase(load: 100, reps: 1, expected: 100),
        EpleyCase(load: 100, reps: 0, expected: 0),
        EpleyCase(load: 100, reps: -3, expected: 0),
        EpleyCase(load: .nan, reps: 5, expected: 0),
        EpleyCase(load: .infinity, reps: 5, expected: 0),
        EpleyCase(load: -.infinity, reps: 5, expected: 0),
        EpleyCase(load: 0, reps: 10, expected: 0),
        EpleyCase(load: -20, reps: 10, expected: 0),
    ]

    @Test(
        "R1 Epley: carga × (1 + reps/30); reps ≤ 0, carga não finita ou ≤ 0 → 0; 1 rep → a própria carga",
        arguments: ReviewEstimatedOneRepMaxTests.epleyCases
    )
    func epleyTable(_ testCase: EpleyCase) {
        let estimate = EstimatedOneRepMax.epley(load: testCase.load, reps: testCase.reps)

        #expect(RF.isClose(estimate, testCase.expected))
    }

    @Test("R1 Epley: 1 rep devolve a carga exata, sem ruído de ponto flutuante")
    func singleRepIsExact() {
        #expect(EstimatedOneRepMax.epley(load: 102.5, reps: 1) == 102.5)
    }

    @Test("R1 estimativas iguais por caminhos diferentes (90 × 10 e 100 × 6) não contam como aumento")
    func equalEstimatesAreNotAnImprovement() {
        let fromTen = EstimatedOneRepMax.epley(load: 90, reps: 10)
        let fromSix = EstimatedOneRepMax.epley(load: 100, reps: 6)

        #expect(!EstimatedOneRepMax.isImprovement(fromTen, over: fromSix))
        #expect(!EstimatedOneRepMax.isImprovement(fromSix, over: fromTen))
        #expect(EstimatedOneRepMax.isImprovement(120.5, over: fromSix))
    }

    @Test("R1 melhor série ignora aquecimentos (P1) e cargas não finitas")
    func bestWorkingSetIgnoresWarmupsAndNonFiniteLoads() throws {
        let date = RF.at(-1)
        let sets = [
            RF.warmup(120, 5, at: date),
            SetResult(load: .nan, reps: 10, rir: 2, isWarmup: false, completedAt: date),
            SetResult(load: .infinity, reps: 3, rir: 2, isWarmup: false, completedAt: date),
            RF.workingSet(105, 5, at: date),
            RF.workingSet(100, 8, at: date),
        ]

        let best = try #require(EstimatedOneRepMax.bestWorkingSet(sets))

        #expect(best.set.load == 100)
        #expect(best.set.reps == 8)
        #expect(RF.isClose(best.e1rm, 100 * (1 + 8.0 / 30)))
    }

    @Test("R1 melhor série: sem série de trabalho → nil")
    func bestWorkingSetNilWithoutWorkingSets() {
        let date = RF.at(-1)

        let empty = EstimatedOneRepMax.bestWorkingSet([])
        let onlyWarmups = EstimatedOneRepMax.bestWorkingSet([RF.warmup(60, 10, at: date)])
        let onlyCorrupt = EstimatedOneRepMax.bestWorkingSet([
            SetResult(load: .nan, reps: 10, isWarmup: false, completedAt: date),
        ])

        // The result is an optional tuple (not Equatable); compare its estimate instead.
        #expect(empty.map { $0.e1rm } == nil)
        #expect(onlyWarmups.map { $0.e1rm } == nil)
        #expect(onlyCorrupt.map { $0.e1rm } == nil)
    }

    @Test("R1 melhor série: empate de estimativa → maior carga, independente da ordem (R7)")
    func bestWorkingSetTieBreaksOnHeavierLoad() throws {
        let date = RF.at(-1)
        // 60 × 30 and 120 × 1 are both exactly 120.
        let light = RF.workingSet(60, 30, at: date)
        let heavy = RF.workingSet(120, 1, at: date)

        let forward = try #require(EstimatedOneRepMax.bestWorkingSet([light, heavy]))
        let backward = try #require(EstimatedOneRepMax.bestWorkingSet([heavy, light]))

        #expect(forward.set == heavy)
        #expect(backward.set == heavy)
        #expect(forward.e1rm == 120)
    }

    @Test("R1 melhor série: séries idênticas exceto RIR → menor RIR, independente da ordem (R7)")
    func bestWorkingSetTieBreaksOnLowerRIR() throws {
        let date = RF.at(-1)
        let hard = RF.workingSet(100, 5, rir: 1, at: date)
        let easy = RF.workingSet(100, 5, rir: 3, at: date)
        let unrated = RF.workingSet(100, 5, rir: nil, at: date)

        let first = try #require(EstimatedOneRepMax.bestWorkingSet([easy, hard, unrated]))
        let second = try #require(EstimatedOneRepMax.bestWorkingSet([unrated, hard, easy]))
        let withoutHard = try #require(EstimatedOneRepMax.bestWorkingSet([unrated, easy]))

        #expect(first.set == hard)
        #expect(second.set == hard)
        #expect(withoutHard.set == easy)
    }
}
