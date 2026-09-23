import Foundation
import Testing
@testable import TrainerCore

// Fixed instants (SPEC P11: tests never read the clock).
private let sessionStart = Date(timeIntervalSince1970: 1_700_000_000)
private let sessionEnd = Date(timeIntervalSince1970: 1_700_003_600) // start + 1 h

private func working(_ load: Double, _ reps: Int, rir: Int? = 2) -> SetResult {
    SetResult(load: load, reps: reps, rir: rir, isWarmup: false, completedAt: sessionStart)
}

private func warmup(_ load: Double, _ reps: Int) -> SetResult {
    SetResult(load: load, reps: reps, rir: nil, isWarmup: true, completedAt: sessionStart)
}

@Test("RF-12 tonelagem soma carga × reps só das séries de trabalho, ignorando aquecimentos")
func sessionStatsTonnageIgnoresWarmups() {
    let benchPress = [warmup(20, 10), warmup(40, 5), working(60, 10), working(60, 9), working(60, 8)]
    let squat = [warmup(40, 8), working(100, 5), working(100, 5)]

    let stats = SessionStats.compute(startedAt: sessionStart, endedAt: sessionEnd, exerciseSets: [benchPress, squat])

    // 60×(10+9+8) + 100×(5+5) = 1620 + 1000
    #expect(stats.tonnage == 2620)
    #expect(stats.workingSetCount == 5)
    #expect(stats.warmupSetCount == 3)
    #expect(stats.exerciseCount == 2)
}

@Test("RF-12 sessão só com aquecimentos tem tonelagem zero")
func sessionStatsOnlyWarmupsHasZeroTonnage() {
    let stats = SessionStats.compute(
        startedAt: sessionStart,
        endedAt: sessionEnd,
        exerciseSets: [[warmup(20, 10), warmup(30, 8)]]
    )

    #expect(stats.tonnage == 0)
    #expect(stats.workingSetCount == 0)
    #expect(stats.warmupSetCount == 2)
    #expect(stats.exerciseCount == 0)
}

@Test("RF-12 tonelagem aceita cargas fracionárias")
func sessionStatsTonnageWithFractionalLoads() {
    let stats = SessionStats.compute(
        startedAt: sessionStart,
        endedAt: sessionEnd,
        exerciseSets: [[working(62.5, 8), working(62.5, 8)]]
    )

    #expect(stats.tonnage == 1000)
}

@Test("RF-12 duração é endedAt − startedAt")
func sessionStatsDurationIsEndMinusStart() {
    let stats = SessionStats.compute(startedAt: sessionStart, endedAt: sessionEnd, exerciseSets: [[working(60, 10)]])

    #expect(stats.duration == 3_600)
}

@Test("RF-12 duração é nil quando endedAt é nil (sessão em andamento)")
func sessionStatsDurationIsNilWhileInProgress() {
    let stats = SessionStats.compute(startedAt: sessionStart, endedAt: nil, exerciseSets: [[working(60, 10)]])

    #expect(stats.duration == nil)
    // The other totals are still available for the live session screen.
    #expect(stats.workingSetCount == 1)
    #expect(stats.tonnage == 600)
}

@Test("RF-12 duração nunca é negativa quando endedAt precede startedAt")
func sessionStatsDurationClampsToZero() {
    let stats = SessionStats.compute(
        startedAt: sessionEnd,
        endedAt: sessionStart,
        exerciseSets: []
    )

    #expect(stats.duration == 0)
}

@Test("RF-12 sessão sem exercícios produz zeros")
func sessionStatsEmptySessionIsAllZeros() {
    let stats = SessionStats.compute(startedAt: sessionStart, endedAt: sessionEnd, exerciseSets: [])

    #expect(stats.duration == 3_600)
    #expect(stats.workingSetCount == 0)
    #expect(stats.warmupSetCount == 0)
    #expect(stats.tonnage == 0)
    #expect(stats.exerciseCount == 0)
}

@Test("RF-12 exercícios sem séries (pulados) produzem zeros e não contam como exercício")
func sessionStatsSkippedExercisesAreAllZeros() {
    let stats = SessionStats.compute(startedAt: sessionStart, endedAt: sessionEnd, exerciseSets: [[], [], []])

    #expect(stats.workingSetCount == 0)
    #expect(stats.warmupSetCount == 0)
    #expect(stats.tonnage == 0)
    #expect(stats.exerciseCount == 0)
}

@Test("RF-12 exerciseCount conta só exercícios com ≥ 1 série de trabalho (P1/P7)")
func sessionStatsExerciseCountRequiresWorkingSet() {
    let performed = [working(60, 10)]
    let skipped: [SetResult] = []
    let warmupOnly = [warmup(20, 10)]

    let stats = SessionStats.compute(
        startedAt: sessionStart,
        endedAt: sessionEnd,
        exerciseSets: [performed, skipped, warmupOnly, performed]
    )

    #expect(stats.exerciseCount == 2)
    #expect(stats.workingSetCount == 2)
    #expect(stats.warmupSetCount == 1)
}

@Test("RF-12 séries com zero reps não somam tonelagem mas contam como série")
func sessionStatsZeroRepsCountAsSet() {
    let stats = SessionStats.compute(
        startedAt: sessionStart,
        endedAt: sessionEnd,
        exerciseSets: [[working(80, 0), working(80, 6)]]
    )

    #expect(stats.tonnage == 480)
    #expect(stats.workingSetCount == 2)
}

@Test("P11 SessionStats é determinístico: mesma entrada duas vezes dá o mesmo valor")
func sessionStatsIsDeterministic() {
    let sets = [[warmup(20, 10), working(60, 10), working(60, 8)], [working(100, 5)]]

    let first = SessionStats.compute(startedAt: sessionStart, endedAt: sessionEnd, exerciseSets: sets)
    let second = SessionStats.compute(startedAt: sessionStart, endedAt: sessionEnd, exerciseSets: sets)

    #expect(first == second)
    #expect(first.hashValue == second.hashValue)
}
