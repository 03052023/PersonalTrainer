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
/// derived from the date so identical inputs always produce identical entries; pass
/// `sessionID` to build two entries on the same date (SPEC P11 tie-break) or two
/// entries of the same session (the same exercise twice in one day).
private func entry(
    daysAgo: Double,
    sets: [SetSpec],
    wasDeload: Bool = false,
    sessionID: UUID? = nil
) -> ExerciseHistoryEntry {
    let date = referenceNow.addingTimeInterval(-daysAgo * day)
    let stamp = String(UInt64(date.timeIntervalSince1970), radix: 16)
    let suffix = String(repeating: "0", count: max(0, 12 - stamp.count)) + stamp
    let derivedID = UUID(uuidString: "00000000-0000-0000-0000-" + suffix)!
    let results = sets.enumerated().map { offset, spec in
        SetResult(
            load: spec.load,
            reps: spec.reps,
            rir: spec.rir,
            isWarmup: spec.isWarmup,
            completedAt: date.addingTimeInterval(Double(offset) * 180)
        )
    }
    return ExerciseHistoryEntry(
        sessionID: sessionID ?? derivedID,
        date: date,
        sets: results,
        wasDeload: wasDeload
    )
}

/// Explicit session IDs in a group that can never collide with the date-derived ones.
private func fixedSessionID(_ n: UInt8) -> UUID {
    let hex = String(n, radix: 16).uppercased()
    let suffix = String(repeating: "0", count: 12 - hex.count) + hex
    return UUID(uuidString: "00000000-0000-0000-0001-" + suffix)!
}

private func labels<T>(of value: T) -> [String] {
    Mirror(reflecting: value).children.compactMap(\.label)
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

@Test("P3 a moda vence a carga da última série")
func P3_modeDiffersFromLastSet_usesMode() {
    // Last working set is 62.5 but 60 was used twice.
    let history = [entry(daysAgo: 2, sets: [working(60, 10), working(60, 10), working(62.5, 10)])]

    let result = prescribe(history)

    #expect(result.load == 60)
    #expect(result.targetReps == 11)
    #expect(result.note == .hold)
}

@Test("P3 a moda vence a carga mais pesada isolada e a última série")
func P3_modeBeatsHeaviestSingleAndLastSet() {
    let history = [entry(daysAgo: 2, sets: [
        working(60, 10), working(62.5, 10), working(62.5, 10), working(62.5, 10), working(65, 10),
    ])]

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

@Test("P6 segunda falha consecutiva na mesma carga reduz para min(round↓(0,9·L), L − inc)")
func P6_secondConsecutiveFailureSameLoad_decreases() {
    // L = 60, inc = 5: round-down(54) = 50 and L − inc = 55; the smaller, 50, wins.
    let history = [
        entry(daysAgo: 4, sets: [working(60, 7), working(60, 7), working(60, 6)]),
        entry(daysAgo: 2, sets: [working(60, 8), working(60, 7), working(60, 7)]),
    ]

    let result = prescribe(history, exercise: makeExercise(increment: 5))

    #expect(result.load == 50)
    #expect(result.targetReps == 8)
    #expect(result.note == .decrease)
}

@Test("P6 exemplo da SPEC: L = 60, inc = 2,5 → 52,5")
func P6_specExample_60by2_5_decreasesTo52_5() {
    let history = [
        entry(daysAgo: 4, sets: [working(60, 7), working(60, 7), working(60, 6)]),
        entry(daysAgo: 2, sets: [working(60, 7), working(60, 7), working(60, 7)]),
    ]

    let result = prescribe(history)

    #expect(result.load == 52.5)
    #expect(result.note == .decrease)
}

@Test("P6 exemplo da SPEC: L = 10, inc = 2,5 → 7,5")
func P6_specExample_10by2_5_decreasesTo7_5() {
    // round-down(9) = 7.5 and L − inc = 7.5: the 10 % cut and the one-increment drop agree.
    let history = [
        entry(daysAgo: 4, sets: [working(10, 7), working(10, 7), working(10, 6)]),
        entry(daysAgo: 2, sets: [working(10, 7), working(10, 7), working(10, 7)]),
    ]

    let result = prescribe(history)

    #expect(result.load == 7.5)
    #expect(result.note == .decrease)
}

@Test("P6 exemplo da SPEC: L = 5, inc = 2,5 → 2,5 pelo piso P8")
func P6_specExample_5by2_5_floorsAt2_5() {
    let history = [
        entry(daysAgo: 4, sets: [working(5, 7), working(5, 7), working(5, 6)]),
        entry(daysAgo: 2, sets: [working(5, 7), working(5, 7), working(5, 7)]),
    ]

    let result = prescribe(history)

    #expect(result.load == 2.5)
    #expect(result.note == .decrease)
}

@Test("P6 referência fora do incremento: a redução continua na grade P8")
func P6_offIncrementReference_decreaseStaysOnGrid() {
    // L = 6 (override, SPEC P10), inc = 2.5: base 5, round-down(5.4) = 5, base − inc = 2.5.
    let history = [
        entry(daysAgo: 4, sets: [working(6, 7), working(6, 7), working(6, 6)]),
        entry(daysAgo: 2, sets: [working(6, 7), working(6, 7), working(6, 7)]),
    ]

    let result = prescribe(history)

    #expect(result.load == 2.5)
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
    // 60 → 52.5 after two failures (P6), then a first failure at 52.5.
    let history = [
        entry(daysAgo: 6, sets: [working(60, 7), working(60, 7), working(60, 6)]),
        entry(daysAgo: 4, sets: [working(60, 7), working(60, 7), working(60, 6)]),
        entry(daysAgo: 2, sets: [working(52.5, 7), working(52.5, 7), working(52.5, 7)]),
    ]

    let result = prescribe(history)

    #expect(result.load == 52.5)
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

@Test("P8 séries com carga não finita são ignoradas e nunca chegam à prescrição")
func P8_nonFiniteLoads_areIgnored() {
    let onlyBroken = [entry(daysAgo: 2, sets: [working(.nan, 10), working(.infinity, 10)])]
    let mixed = [entry(daysAgo: 2, sets: [working(.nan, 12), working(60, 12), working(60, 12), working(60, 12)])]

    let calibrated = prescribe(onlyBroken, target: makeTarget(startingLoad: 40))
    let increased = prescribe(mixed)

    // No usable working set → SPEC P2, as if the session had never been recorded.
    #expect(calibrated.load == 40)
    #expect(calibrated.note == .calibrate)
    // The broken set is dropped; the three valid ones are a full success.
    #expect(increased.load == 62.5)
    #expect(increased.note == .increase)
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

@Test("P9 deload recente zera a pausa; P4–P6 avaliam a última sessão normal")
func P9_recentDeloadResetsPause_evaluatesLastNormalSession() {
    // Normal session 25 days ago, deload 5 days ago: the exercise was trained 5 days
    // ago, so this is not a return; the verdict comes from the normal session (P4).
    let history = [
        entry(daysAgo: 25, sets: [working(60, 12), working(60, 12), working(60, 12)]),
        entry(daysAgo: 5, sets: [working(50, 8), working(50, 7)], wasDeload: true),
    ]

    let result = prescribe(history)

    #expect(result.load == 62.5)
    #expect(result.note == .increase)
}

@Test("P9 deload antigo não zera a pausa e não fornece L: retorno a partir da sessão normal")
func P9_oldDeloadDoesNotResetPause_isReturning() {
    // Last training of any kind was 25 days ago → returning. L is 60 (normal
    // session), not 50 (deload): 0.9 × 60 = 54 → 52.5, whereas 0.9 × 50 would give 45.
    let history = [
        entry(daysAgo: 30, sets: [working(60, 12), working(60, 12), working(60, 12)]),
        entry(daysAgo: 25, sets: [working(50, 8), working(50, 7)], wasDeload: true),
    ]

    let result = prescribe(history)

    #expect(result.load == 52.5)
    #expect(result.note == .returning)
}

@Test("P9 deload sem séries de trabalho não zera a pausa (P7)")
func P9_deloadWithoutWorkingSets_doesNotResetPause() {
    let history = [
        entry(daysAgo: 25, sets: [working(60, 12), working(60, 12), working(60, 12)]),
        entry(daysAgo: 2, sets: [warmup(20, 5)], wasDeload: true),
    ]

    #expect(prescribe(history).note == .returning)
}

@Test("P9/P3 histórico só com deload não tem carga de referência e cai em P2")
func P9_deloadOnlyHistory_fallsBackToCalibration() {
    let history = [entry(daysAgo: 2, sets: [working(50, 8), working(50, 8)], wasDeload: true)]

    let result = prescribe(history, target: makeTarget(startingLoad: 40))

    #expect(result.load == 40)
    #expect(result.note == .calibrate)
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

@Test("P11 datas iguais: o maior id de sessão é tratado como a mais recente")
func P11_equalDates_higherSessionIDIsTreatedAsLatest() {
    let success = [working(60, 12), working(60, 12), working(60, 12)]
    let failure = [working(60, 7), working(60, 7), working(60, 7)]

    // Failure carries the higher id → it is "latest"; the success before it is not a
    // failure, so this is a first failure: retry.
    let failureLast = [
        entry(daysAgo: 2, sets: success, sessionID: fixedSessionID(1)),
        entry(daysAgo: 2, sets: failure, sessionID: fixedSessionID(2)),
    ]
    // Swapping the ids swaps the verdict: the success is now "latest" → increase.
    let successLast = [
        entry(daysAgo: 2, sets: success, sessionID: fixedSessionID(2)),
        entry(daysAgo: 2, sets: failure, sessionID: fixedSessionID(1)),
    ]

    #expect(prescribe(failureLast).note == .retry)
    #expect(prescribe(failureLast) == prescribe(failureLast.reversed()))
    #expect(prescribe(successLast).note == .increase)
    #expect(prescribe(successLast) == prescribe(successLast.reversed()))
}

@Test("P11 mesmo exercício duas vezes na mesma sessão: as séries são somadas, em qualquer ordem")
func P11_sameExerciseTwiceInOneSession_setsAreMerged() {
    let sessionID = fixedSessionID(7)
    let firstHalf = entry(daysAgo: 2, sets: [working(60, 12), working(60, 12), working(60, 12)], sessionID: sessionID)
    let secondHalf = entry(daysAgo: 2, sets: [working(60, 7)], sessionID: sessionID)

    let forward = prescribe([firstHalf, secondHalf])
    let backward = prescribe([secondHalf, firstHalf])

    // All four sets belong to one session: the 7-rep set makes it a failure (P6),
    // never a success on the first three sets alone.
    #expect(forward == backward)
    #expect(forward.load == 60)
    #expect(forward.note == .retry)
}

@Test("P11 reps = Int.max não trava o motor (P5 satura a meta em repMax)")
func P11_repsAtIntMax_doesNotTrap() {
    let history = [entry(daysAgo: 2, sets: [working(60, Int.max)])]

    let result = prescribe(history)

    #expect(result.load == 60)
    #expect(result.targetReps == 12)
    #expect(result.note == .hold)
}

@Test("P2 RIR alvo = Int.max não trava o motor (T + 1 satura)")
func P2_targetRIRAtIntMax_doesNotTrap() {
    let result = prescribe([], target: makeTarget(targetRIR: Int.max))

    #expect(result.load == nil)
    #expect(result.targetRIR == Int.max)
    #expect(result.note == .calibrate)
}

@Test("P4 RIR alvo próximo de Int.max não trava e não concede o bônus")
func P4_targetRIRNearIntMax_noBonusAndNoTrap() {
    let history = [entry(daysAgo: 2, sets: [working(60, 12, rir: 4), working(60, 12, rir: 4), working(60, 12, rir: 4)])]

    let result = prescribe(history, target: makeTarget(targetRIR: Int.max - 1))

    #expect(result.load == 62.5)
    #expect(result.note == .increase)
}

// MARK: - P12 no heart rate

@Test("P12 tipos de entrada do motor não têm campo de frequência cardíaca")
func P12_engineInputTypes_haveNoHeartRateField() {
    let set = SetResult(load: 60, reps: 10, rir: 2, completedAt: referenceNow)
    let history = ExerciseHistoryEntry(sessionID: fixedTargetID, date: referenceNow, sets: [set])
    let summary = SessionSummary(
        id: fixedTargetID,
        programDayID: fixedTargetID,
        startedAt: referenceNow,
        status: .completed,
        primaryMusclesTrained: [.chest],
        workingSetCount: 3
    )

    // AGENTS R2 names these two structs explicitly: their exact shape is pinned so
    // any new field forces a conscious review.
    #expect(labels(of: set) == ["load", "reps", "rir", "isWarmup", "completedAt"])
    #expect(labels(of: history) == ["sessionID", "date", "sets", "wasDeload"])

    // Every input of `prescribe` and `nextDay` is scanned for cardiovascular vocabulary.
    let allLabels = labels(of: set)
        + labels(of: history)
        + labels(of: makeTarget())
        + labels(of: makeExercise())
        + labels(of: summary)
    let forbiddenTerms = ["heart", "bpm", "pulse", "cardio"]
    let suspicious = allLabels.filter { label in
        let lowered = label.lowercased()
        return forbiddenTerms.contains { lowered.contains($0) }
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
