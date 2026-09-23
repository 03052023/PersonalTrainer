import Foundation
import Testing
@testable import TrainerCore

// Table cases for SPEC §7.2 (P1–P12). Every instant is fixed (SPEC P11): `referenceNow`
// plays the role of "today" and history entries are placed N days before it.

// MARK: - Fixtures

private let referenceNow = Date(timeIntervalSince1970: 1_800_000_000)
private let day: TimeInterval = 86_400
private let fixedExerciseID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
private let fixedTargetID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!

private func makeExercise(
    increment: Double = 2.5,
    equipment: Equipment = .barbell
) -> ExerciseDefinition {
    ExerciseDefinition(
        id: fixedExerciseID,
        slug: "bench-press",
        name: "Supino reto",
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps],
        equipment: equipment,
        loadUnit: .kilograms,
        loadIncrement: increment
    )
}

private func makeTarget(
    sets: Int = 3,
    repMin: Int = 8,
    repMax: Int = 12,
    targetRIR: Int = 2,
    restSeconds: Int = 120,
    startingLoad: Double? = nil
) -> ExerciseTarget {
    ExerciseTarget(
        id: fixedTargetID,
        exerciseID: fixedExerciseID,
        order: 0,
        sets: sets,
        repMin: repMin,
        repMax: repMax,
        targetRIR: targetRIR,
        restSeconds: restSeconds,
        startingLoad: startingLoad
    )
}

private struct SetSpec {
    let load: Double
    let reps: Int
    let rir: Int?
    let isWarmup: Bool
}

private func working(_ load: Double, _ reps: Int, rir: Int? = 2) -> SetSpec {
    SetSpec(load: load, reps: reps, rir: rir, isWarmup: false)
}

private func warmup(_ load: Double, _ reps: Int) -> SetSpec {
    SetSpec(load: load, reps: reps, rir: nil, isWarmup: true)
}

/// Builds a history entry `daysAgo` days before `referenceNow`. The session ID is
/// derived from the date so identical inputs always produce identical entries.
private func entry(daysAgo: Double, sets: [SetSpec], wasDeload: Bool = false) -> ExerciseHistoryEntry {
    let date = referenceNow.addingTimeInterval(-daysAgo * day)
    let stamp = String(UInt64(date.timeIntervalSince1970), radix: 16)
    let suffix = String(repeating: "0", count: max(0, 12 - stamp.count)) + stamp
    let sessionID = UUID(uuidString: "00000000-0000-0000-0000-" + suffix)!
    let results = sets.enumerated().map { offset, spec in
        SetResult(
            load: spec.load,
            reps: spec.reps,
            rir: spec.rir,
            isWarmup: spec.isWarmup,
            completedAt: date.addingTimeInterval(Double(offset) * 180)
        )
    }
    return ExerciseHistoryEntry(sessionID: sessionID, date: date, sets: results, wasDeload: wasDeload)
}

private func prescribe(
    _ history: [ExerciseHistoryEntry],
    target: ExerciseTarget = makeTarget(),
    exercise: ExerciseDefinition = makeExercise(),
    now: Date = referenceNow
) -> ExercisePrescription {
    DoubleProgressionRule().prescribe(target: target, exercise: exercise, history: history, now: now)
}

// MARK: - P2 no history

@Test("P2 sem histórico com startingLoad prescreve a carga inicial com nota calibrate")
func P2_noHistoryWithStartingLoad_calibratesAtStartingLoad() {
    let result = prescribe([], target: makeTarget(startingLoad: 40))

    #expect(result.load == 40)
    #expect(result.targetReps == 8)
    #expect(result.targetRIR == 2)
    #expect(result.note == .calibrate)
}

@Test("P2 sem histórico e sem startingLoad deixa a carga vazia e RIR alvo T + 1")
func P2_noHistoryWithoutStartingLoad_leavesLoadEmpty() {
    let result = prescribe([])

    #expect(result.load == nil)
    #expect(result.targetReps == 8)
    #expect(result.targetRIR == 3)
    #expect(result.note == .calibrate)
}

@Test("P2 startingLoad fora do incremento é arredondado para baixo")
func P2_startingLoadOffIncrement_roundsDown() {
    let result = prescribe([], target: makeTarget(startingLoad: 41))

    #expect(result.load == 40)
    #expect(result.note == .calibrate)
}

// MARK: - P3 reference load

@Test("P3 carga de referência é a moda das cargas das séries de trabalho")
func P3_referenceLoadIsModeOfWorkingSets() {
    let history = [entry(daysAgo: 2, sets: [working(62.5, 10), working(60, 10), working(60, 10)])]

    let result = prescribe(history)

    #expect(result.load == 60)
    #expect(result.note == .hold)
}

@Test("P3 empate na moda escolhe a carga maior")
func P3_modeTie_prefersHeavierLoad() {
    let history = [entry(daysAgo: 2, sets: [working(60, 10), working(62.5, 10)])]

    #expect(prescribe(history).load == 62.5)
}

// MARK: - P4 success

@Test("P4 todas as séries em repMax sobe um incremento")
func P4_allSetsAtRepMax_increasesOneIncrement() {
    let history = [entry(daysAgo: 2, sets: [working(60, 12, rir: 2), working(60, 12, rir: 1), working(60, 13, rir: 1)])]

    let result = prescribe(history)

    #expect(result.load == 62.5)
    #expect(result.targetReps == 8)
    #expect(result.targetRIR == 2)
    #expect(result.note == .increase)
}

@Test("P4 min(RIR) ≥ T + 2 em todas as séries sobe dois incrementos")
func P4_highReserveOnEverySet_increasesTwoIncrements() {
    let history = [entry(daysAgo: 2, sets: [working(60, 12, rir: 4), working(60, 13, rir: 4), working(60, 12, rir: 5)])]

    let result = prescribe(history)

    #expect(result.load == 65)
    #expect(result.note == .increase)
}

@Test("P4 sem bônus quando alguma série não tem RIR")
func P4_missingRIROnOneSet_noBonus() {
    let history = [entry(daysAgo: 2, sets: [working(60, 12, rir: 4), working(60, 12, rir: nil), working(60, 12, rir: 4)])]

    let result = prescribe(history)

    #expect(result.load == 62.5)
    #expect(result.note == .increase)
}

@Test("P4 sem bônus quando min(RIR) < T + 2")
func P4_lowestReserveBelowThreshold_noBonus() {
    let history = [entry(daysAgo: 2, sets: [working(60, 12, rir: 4), working(60, 12, rir: 3), working(60, 12, rir: 4)])]

    #expect(prescribe(history).load == 62.5)
}

@Test("P4 mais séries de trabalho do que S ainda conta como sucesso")
func P4_moreSetsThanTarget_stillSucceeds() {
    let history = [entry(daysAgo: 2, sets: [working(60, 12), working(60, 12), working(60, 12), working(60, 12)])]

    let result = prescribe(history)

    #expect(result.load == 62.5)
    #expect(result.note == .increase)
}

// MARK: - P5 hold

@Test("P5 manter: mesma carga e meta = menor reps + 1")
func P5_allSetsAboveRepMinButNotRepMax_holdsWithLowestRepsPlusOne() {
    let history = [entry(daysAgo: 2, sets: [working(60, 11), working(60, 9), working(60, 10)])]

    let result = prescribe(history)

    #expect(result.load == 60)
    #expect(result.targetReps == 10)
    #expect(result.note == .hold)
}

@Test("P5 meta de reps é limitada a repMax")
func P5_holdTarget_isCappedAtRepMax() {
    // Two sets at/above repMax with S = 3: not a success (P7), so P5 applies and
    // lowest reps + 1 = 13 must be capped at repMax = 12.
    let history = [entry(daysAgo: 2, sets: [working(60, 13), working(60, 12)])]

    let result = prescribe(history)

    #expect(result.load == 60)
    #expect(result.targetReps == 12)
    #expect(result.note == .hold)
}

// MARK: - P6 failure

@Test("P6 primeira falha repete a carga com nota retry")
func P6_firstFailure_retriesSameLoad() {
    let history = [
        entry(daysAgo: 4, sets: [working(60, 10), working(60, 10), working(60, 9)]),
        entry(daysAgo: 2, sets: [working(60, 8), working(60, 7), working(60, 6)]),
    ]

    let result = prescribe(history)

    #expect(result.load == 60)
    #expect(result.targetReps == 8)
    #expect(result.note == .retry)
}

@Test("P6 falha isolada sem sessão anterior é retry")
func P6_failureWithoutPreviousSession_retries() {
    let history = [entry(daysAgo: 2, sets: [working(60, 8), working(60, 8), working(60, 7)])]

    let result = prescribe(history)

    #expect(result.load == 60)
    #expect(result.note == .retry)
}

@Test("P6 segunda falha consecutiva na mesma carga reduz com arredondamento e piso L − inc")
func P6_secondConsecutiveFailureSameLoad_decreases() {
    // L = 60, inc = 5: round-down(54) = 50 but the floor L − inc = 55 wins.
    let history = [
        entry(daysAgo: 4, sets: [working(60, 7), working(60, 7), working(60, 6)]),
        entry(daysAgo: 2, sets: [working(60, 8), working(60, 7), working(60, 7)]),
    ]

    let result = prescribe(history, exercise: makeExercise(increment: 5))

    #expect(result.load == 55)
    #expect(result.targetReps == 8)
    #expect(result.note == .decrease)
}

@Test("P6 segunda falha em carga diferente volta a ser retry")
func P6_secondFailureAtDifferentLoad_retries() {
    let history = [
        entry(daysAgo: 4, sets: [working(55, 7), working(55, 7), working(55, 6)]),
        entry(daysAgo: 2, sets: [working(60, 7), working(60, 7), working(60, 7)]),
    ]

    let result = prescribe(history)

    #expect(result.load == 60)
    #expect(result.note == .retry)
}

@Test("P6 após decrease a próxima falha na nova carga é retry, não decrease")
func P6_failureAfterDecreaseAtNewLoad_retries() {
    let history = [
        entry(daysAgo: 6, sets: [working(60, 7), working(60, 7), working(60, 6)]),
        entry(daysAgo: 4, sets: [working(60, 7), working(60, 7), working(60, 6)]),
        entry(daysAgo: 2, sets: [working(57.5, 7), working(57.5, 7), working(57.5, 7)]),
    ]

    let result = prescribe(history)

    #expect(result.load == 57.5)
    #expect(result.note == .retry)
}

// MARK: - P7 incomplete sessions

@Test("P7 séries incompletas nunca sobem a carga")
func P7_fewerSetsThanTarget_neverIncreases() {
    let history = [entry(daysAgo: 2, sets: [working(60, 12), working(60, 12)])]

    let result = prescribe(history)

    #expect(result.load == 60)
    #expect(result.note == .hold)
}

@Test("P7 séries incompletas ainda podem falhar")
func P7_fewerSetsThanTarget_canStillFail() {
    let history = [entry(daysAgo: 2, sets: [working(60, 7)])]

    let result = prescribe(history)

    #expect(result.load == 60)
    #expect(result.note == .retry)
}

@Test("P7 sessão com 0 séries de trabalho é ignorada e usa-se a anterior")
func P7_zeroWorkingSets_isIgnoredAndPreviousIsUsed() {
    let history = [
        entry(daysAgo: 3, sets: [working(60, 12), working(60, 12), working(60, 12)]),
        entry(daysAgo: 1, sets: [warmup(20, 5)]),
        entry(daysAgo: 0.5, sets: []),
    ]

    let result = prescribe(history)

    #expect(result.load == 62.5)
    #expect(result.note == .increase)
}

@Test("P7 histórico só com sessões vazias cai em P2")
func P7_onlyEmptySessions_fallsBackToCalibration() {
    let history = [entry(daysAgo: 1, sets: [warmup(20, 5)])]

    let result = prescribe(history, target: makeTarget(startingLoad: 40))

    #expect(result.load == 40)
    #expect(result.note == .calibrate)
}

// MARK: - P1 warmups

@Test("P1 aquecimentos não entram na avaliação nem na carga de referência")
func P1_warmupSets_areIgnored() {
    let history = [entry(daysAgo: 2, sets: [
        warmup(20, 5),
        warmup(40, 5),
        working(60, 12), working(60, 12), working(60, 12),
    ])]

    let result = prescribe(history)

    #expect(result.load == 62.5)
    #expect(result.note == .increase)
}

// MARK: - P8 rounding and minimum load

@Test("P8 carga prescrita nunca fica abaixo de um incremento")
func P8_minimumPrescribedLoad_isOneIncrement() {
    // L = 5, inc = 5: round-down(4.5) = 0 and L − inc = 0, so the minimum applies.
    let history = [
        entry(daysAgo: 4, sets: [working(5, 6), working(5, 6), working(5, 6)]),
        entry(daysAgo: 2, sets: [working(5, 6), working(5, 6), working(5, 6)]),
    ]

    let result = prescribe(history, exercise: makeExercise(increment: 5))

    #expect(result.load == 5)
    #expect(result.note == .decrease)
}

@Test("P8 peso corporal tem mínimo 0")
func P8_bodyweightMinimumLoad_isZero() {
    let history = [
        entry(daysAgo: 4, sets: [working(5, 6), working(5, 6), working(5, 6)]),
        entry(daysAgo: 2, sets: [working(5, 6), working(5, 6), working(5, 6)]),
    ]

    let result = prescribe(history, exercise: makeExercise(increment: 5, equipment: .bodyweight))

    #expect(result.load == 0)
    #expect(result.note == .decrease)
}

@Test("P8 carga de referência fora do incremento é normalizada para baixo")
func P8_offIncrementReferenceLoad_isRoundedDown() {
    let history = [entry(daysAgo: 2, sets: [working(41, 10), working(41, 10), working(41, 10)])]

    let result = prescribe(history)

    #expect(result.load == 40)
    #expect(result.note == .hold)
}

@Test("P8 startingLoad abaixo do incremento sobe para o mínimo")
func P8_startingLoadBelowIncrement_isRaisedToMinimum() {
    let result = prescribe([], target: makeTarget(startingLoad: 1))

    #expect(result.load == 2.5)
}

// MARK: - P9 returning after a pause

@Test("P9 retorno após 22 dias reduz 10 % com nota returning e prevalece sobre P4")
func P9_after22Days_returnsAtReducedLoad() {
    // Full success with high RIR would otherwise be +2·inc.
    let history = [entry(daysAgo: 22, sets: [working(60, 12, rir: 4), working(60, 12, rir: 4), working(60, 12, rir: 4)])]

    let result = prescribe(history)

    #expect(result.load == 52.5)
    #expect(result.targetReps == 8)
    #expect(result.targetRIR == 2)
    #expect(result.note == .returning)
}

@Test("P9 20 dias não é retorno")
func P9_after20Days_isNotReturning() {
    let history = [entry(daysAgo: 20, sets: [working(60, 12), working(60, 12), working(60, 12)])]

    let result = prescribe(history)

    #expect(result.load == 62.5)
    #expect(result.note == .increase)
}

@Test("P9 fronteira: exatamente 21 dias não é retorno")
func P9_exactly21Days_isNotReturning() {
    let history = [entry(daysAgo: 21, sets: [working(60, 12), working(60, 12), working(60, 12)])]

    #expect(prescribe(history).note == .increase)
}

@Test("P9 prevalece sobre P6")
func P9_prevailsOverFailure() {
    let history = [
        entry(daysAgo: 24, sets: [working(60, 7), working(60, 7), working(60, 7)]),
        entry(daysAgo: 22, sets: [working(60, 7), working(60, 7), working(60, 7)]),
    ]

    let result = prescribe(history)

    #expect(result.load == 52.5)
    #expect(result.note == .returning)
}

@Test("P9 respeita a carga mínima")
func P9_respectsMinimumLoad() {
    let history = [entry(daysAgo: 22, sets: [working(5, 12), working(5, 12), working(5, 12)])]

    let result = prescribe(history, exercise: makeExercise(increment: 5))

    #expect(result.load == 5)
    #expect(result.note == .returning)
}

@Test("P9 usa a data da última sessão válida, não de uma sessão vazia")
func P9_pauseIsMeasuredFromLastEvaluableSession() {
    let history = [
        entry(daysAgo: 22, sets: [working(60, 12), working(60, 12), working(60, 12)]),
        entry(daysAgo: 1, sets: [warmup(20, 5)]),
    ]

    #expect(prescribe(history).note == .returning)
}

// MARK: - P10 override

@Test("P10 o registro real prevalece: a carga digitada vira a referência")
func P10_actualRecordedLoad_becomesReference() {
    let history = [entry(daysAgo: 2, sets: [working(62.5, 10), working(62.5, 10), working(62.5, 10)])]

    let result = prescribe(history, target: makeTarget(startingLoad: 60))

    #expect(result.load == 62.5)
    #expect(result.note == .hold)
}

// MARK: - Deload (SPEC 7.5)

@Test("Deload não conta como sucesso nem falha e é ignorado (SPEC 7.5)")
func deloadSessions_areIgnored() {
    let history = [
        entry(daysAgo: 5, sets: [working(60, 12), working(60, 12), working(60, 12)]),
        entry(daysAgo: 2, sets: [working(50, 8), working(50, 7)], wasDeload: true),
    ]

    let result = prescribe(history)

    #expect(result.load == 62.5)
    #expect(result.note == .increase)
}

// MARK: - P11 determinism

@Test("P11 duas chamadas com a mesma entrada dão o mesmo resultado")
func P11_sameInputTwice_sameOutput() {
    let history = [
        entry(daysAgo: 6, sets: [working(60, 10), working(60, 9), working(60, 9)]),
        entry(daysAgo: 4, sets: [working(60, 7), working(60, 7), working(60, 6)]),
        entry(daysAgo: 2, sets: [working(60, 8), working(60, 7), working(60, 7)]),
    ]

    let first = prescribe(history)
    let second = prescribe(history)

    #expect(first == second)
    #expect(first.note == .decrease)
}

@Test("P11 ordem do histórico embaralhada dá o mesmo resultado")
func P11_shuffledHistoryOrder_sameOutput() {
    let oldest = entry(daysAgo: 6, sets: [working(60, 10), working(60, 9), working(60, 9)])
    let middle = entry(daysAgo: 4, sets: [working(60, 7), working(60, 7), working(60, 6)])
    let latest = entry(daysAgo: 2, sets: [working(60, 8), working(60, 7), working(60, 7)])

    let newestFirst = prescribe([latest, middle, oldest])
    let oldestFirst = prescribe([oldest, middle, latest])
    let mixed = prescribe([middle, latest, oldest])

    #expect(newestFirst.note == .decrease)
    #expect(newestFirst == oldestFirst)
    #expect(newestFirst == mixed)
}

// MARK: - P12 no heart rate

@Test("P12 tipos de entrada do motor não têm campo de frequência cardíaca")
func P12_engineInputTypes_haveNoHeartRateField() {
    let set = SetResult(load: 60, reps: 10, rir: 2, completedAt: referenceNow)
    let history = ExerciseHistoryEntry(sessionID: fixedTargetID, date: referenceNow, sets: [set])

    let labels = Mirror(reflecting: set).children.compactMap(\.label)
        + Mirror(reflecting: history).children.compactMap(\.label)
        + Mirror(reflecting: makeTarget()).children.compactMap(\.label)

    let suspicious = labels.filter {
        let lowered = $0.lowercased()
        return lowered.contains("heart") || lowered.contains("bpm")
    }

    #expect(suspicious.isEmpty)
}

// MARK: - Structural fields

@Test("Prescrição copia séries, faixa de reps, RIR alvo e descanso do target")
func prescription_copiesStructuralFieldsFromTarget() {
    let target = makeTarget(sets: 4, repMin: 6, repMax: 10, targetRIR: 1, restSeconds: 180)
    let history = [entry(daysAgo: 2, sets: [working(80, 10), working(80, 10), working(80, 10), working(80, 10)])]

    let result = prescribe(history, target: target, exercise: makeExercise(increment: 5))

    #expect(result.exerciseID == fixedExerciseID)
    #expect(result.load == 85)
    #expect(result.sets == 4)
    #expect(result.repMin == 6)
    #expect(result.repMax == 10)
    #expect(result.targetReps == 6)
    #expect(result.targetRIR == 1)
    #expect(result.restSeconds == 180)
    #expect(result.note == .increase)
}
