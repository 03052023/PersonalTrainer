import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.14 F3 (versão 2.3, D2 e D4): a progressão do aeróbico é P4–P6 sobre os minutos, sem regra
// nova. Sem carga (o normal), a meta sobe 1 minuto por sessão até o topo e fica lá (P8 D3); com o
// nível da máquina registrado, P4 sobe 1 nível e os minutos recomeçam no mínimo. Todo instante é
// fixo (SPEC P11).

private let cardioNow = Date(timeIntervalSince1970: 1_800_000_000)
private let cardioDay: TimeInterval = 86_400
private let cardioExerciseID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
private let cardioTargetID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!

/// Caminhada rápida (peso do corpo, kg) ou bicicleta ergométrica (máquina medida em nível).
private func cardioExercise(machine: Bool) -> ExerciseDefinition {
    ExerciseDefinition(
        id: cardioExerciseID,
        slug: machine ? "stationary-bike" : "brisk-walk",
        name: machine ? "Bicicleta ergométrica" : "Caminhada rápida",
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.hamstrings, .calves],
        equipment: machine ? .machine : .bodyweight,
        loadUnit: machine ? .level : .kilograms,
        loadIncrement: machine ? 1 : 2.5,
        movementPattern: .cardio
    )
}

/// Meta em minutos: `sets` × `minMinutes`–`maxMinutes`, RIR 3 (o do Fôlego), descanso 60 s.
private func cardioTarget(sets: Int = 1, minMinutes: Int, maxMinutes: Int, rest: Int = 60) -> ExerciseTarget {
    ExerciseTarget(
        id: cardioTargetID,
        exerciseID: cardioExerciseID,
        order: 0,
        sets: sets,
        repMin: minMinutes,
        repMax: maxMinutes,
        targetRIR: 3,
        restSeconds: rest,
        startingLoad: nil
    )
}

/// Uma sessão `daysAgo` dias antes de `cardioNow`: uma série por item de `minutes`, todas com a
/// mesma carga (0 = sem carga; na bicicleta, o nível). Séries novas não têm RIR (RF-41).
private func cardioSession(
    daysAgo: Double,
    minutes: [Int],
    load: Double = 0,
    wasDeload: Bool = false
) -> ExerciseHistoryEntry {
    let date = cardioNow.addingTimeInterval(-daysAgo * cardioDay)
    let stamp = String(UInt64(date.timeIntervalSince1970), radix: 16)
    let suffix = String(repeating: "0", count: max(0, 12 - stamp.count)) + stamp
    let sessionID = UUID(uuidString: "00000000-0000-0000-0002-" + suffix)!
    let sets = minutes.enumerated().map { offset, value in
        SetResult(load: load, reps: value, rir: nil, isWarmup: false, completedAt: date.addingTimeInterval(Double(offset) * 300))
    }
    return ExerciseHistoryEntry(sessionID: sessionID, date: date, sets: sets, wasDeload: wasDeload)
}

/// O Dia B do seed: 4 blocos de 3–4 min de corrida, recuperação de 180 s (SPEC §7.14 F2, F6).
private func dayBTarget() -> ExerciseTarget {
    cardioTarget(sets: 4, minMinutes: 3, maxMinutes: 4, rest: 180)
}

private func prescribeCardio(
    _ history: [ExerciseHistoryEntry],
    target: ExerciseTarget,
    machine: Bool = false,
    now: Date = cardioNow
) -> ExercisePrescription {
    DoubleProgressionRule().prescribe(target: target, exercise: cardioExercise(machine: machine), history: history, now: now)
}

struct CardioProgressionTests {
    // MARK: - F3 sem carga: +1 minuto por sessão até o topo

    @Test("F3 minutos sobem 1 por sessão até o topo e ficam lá, sem carga (P5 + P8 D3)")
    func minutesClimbOnePerSessionToTheTop() {
        let target = cardioTarget(minMinutes: 20, maxMinutes: 25)
        var history: [ExerciseHistoryEntry] = []
        var goals: [Int] = []

        // Primeira vez (P2): meta no mínimo, carga vazia; a ficha grava 0 (RF-04, D3).
        let first = prescribeCardio(history, target: target, now: cardioNow.addingTimeInterval(-15 * cardioDay))
        #expect(first.note == .calibrate)
        #expect(first.targetReps == 20)
        var goal = first.targetReps

        // Sessões a cada 2 dias, fazendo exatamente a meta de hoje.
        for daysAgo in stride(from: 14.0, through: 2.0, by: -2.0) {
            history.append(cardioSession(daysAgo: daysAgo, minutes: [goal]))
            let next = prescribeCardio(history, target: target, now: cardioNow.addingTimeInterval(-(daysAgo - 1) * cardioDay))
            #expect(next.load == 0, "\(daysAgo) dias")
            #expect(next.note == .hold, "\(daysAgo) dias")
            goal = next.targetReps
            goals.append(goal)
        }

        #expect(goals == [21, 22, 23, 24, 25, 25, 25])
    }

    @Test("F3 a meta sobe a partir do menor minuto feito, como P5 nas repetições")
    func goalFollowsTheShortestSet() {
        let history = [cardioSession(daysAgo: 2, minutes: [32])]

        let result = prescribeCardio(history, target: cardioTarget(minMinutes: 30, maxMinutes: 60))

        #expect(result.load == 0)
        #expect(result.targetReps == 33)
        #expect(result.note == .hold)
    }

    @Test("F6 intervalos 4 × 2–4 min: todos no topo e sem carga, entra mais um bloco (antes, na 2.3, ficava no topo)")
    func intervalsAtTheTopEarnOneMoreBlock() {
        let history = [cardioSession(daysAgo: 2, minutes: [4, 4, 4, 4])]

        let result = prescribeCardio(history, target: cardioTarget(sets: 4, minMinutes: 2, maxMinutes: 4, rest: 180))

        #expect(result.load == 0)
        #expect(result.targetReps == 2)
        #expect(result.sets == 5)
        #expect(result.restSeconds == 180)
        #expect(result.note == .increase)
    }

    @Test("F3 aeróbico sem carga nunca ganha carga sozinho, nem na caminhada de peso do corpo")
    func unloadedCardioNeverGainsLoad() {
        let history = [
            cardioSession(daysAgo: 6, minutes: [45]),
            cardioSession(daysAgo: 4, minutes: [45]),
            cardioSession(daysAgo: 2, minutes: [45]),
        ]

        let walk = prescribeCardio(history, target: cardioTarget(minMinutes: 20, maxMinutes: 45))
        let bike = prescribeCardio(history, target: cardioTarget(minMinutes: 20, maxMinutes: 45), machine: true)

        #expect(walk.load == 0)
        #expect(walk.note == .hold)
        #expect(walk.targetReps == 45)
        #expect(bike.load == 0)
        #expect(bike.note == .hold)
        #expect(bike.targetReps == 45)
    }

    // MARK: - F3 com o nível da máquina (opcional)

    @Test("F3 aeróbico com nível: no topo sobe 1 nível e os minutos recomeçam no mínimo")
    func levelRisesOneStepAndMinutesRestart() {
        let history = [cardioSession(daysAgo: 2, minutes: [60], load: 3)]

        let result = prescribeCardio(history, target: cardioTarget(minMinutes: 30, maxMinutes: 60), machine: true)

        #expect(result.load == 4)
        #expect(result.targetReps == 30)
        #expect(result.note == .increase)
    }

    @Test("F3 aeróbico com nível no meio da faixa: mantém o nível e soma 1 minuto")
    func levelHoldsInsideTheRange() {
        let history = [cardioSession(daysAgo: 2, minutes: [40], load: 5)]

        let result = prescribeCardio(history, target: cardioTarget(minMinutes: 30, maxMinutes: 60), machine: true)

        #expect(result.load == 5)
        #expect(result.targetReps == 41)
        #expect(result.note == .hold)
    }

    @Test("F3 menos minutos que o mínimo repete a meta (P6)")
    func belowTheMinimumRetries() {
        let unloaded = prescribeCardio([cardioSession(daysAgo: 2, minutes: [15])], target: cardioTarget(minMinutes: 20, maxMinutes: 45))
        let leveled = prescribeCardio(
            [cardioSession(daysAgo: 2, minutes: [25], load: 3)],
            target: cardioTarget(minMinutes: 30, maxMinutes: 60),
            machine: true
        )

        #expect(unloaded.load == 0)
        #expect(unloaded.targetReps == 20)
        #expect(unloaded.note == .retry)
        #expect(leveled.load == 3)
        #expect(leveled.targetReps == 30)
        #expect(leveled.note == .retry)
    }

    @Test("F3 duas sessões seguidas abaixo do mínimo sem carga continuam retry em 0 (P6 D3)")
    func repeatedShortSessionsWithoutLoadRetry() {
        let history = [
            cardioSession(daysAgo: 4, minutes: [15]),
            cardioSession(daysAgo: 2, minutes: [16]),
        ]

        let result = prescribeCardio(history, target: cardioTarget(minMinutes: 20, maxMinutes: 45))

        #expect(result.load == 0)
        #expect(result.targetReps == 20)
        #expect(result.note == .retry)
    }

    @Test("F3 pausa de mais de 21 dias recomeça no mínimo (P9), sem carga")
    func longPauseRestartsAtTheMinimum() {
        let result = prescribeCardio([cardioSession(daysAgo: 30, minutes: [45])], target: cardioTarget(minMinutes: 20, maxMinutes: 45))

        #expect(result.load == 0)
        #expect(result.targetReps == 20)
        #expect(result.note == .returning)
    }

    @Test("F3 §7.5 semana leve de um aeróbico sem carga fica em 0 e com menos séries")
    func deloadOfUnloadedCardioStaysAtZero() {
        let normal = prescribeCardio([cardioSession(daysAgo: 2, minutes: [4, 4, 4, 4])], target: cardioTarget(sets: 4, minMinutes: 2, maxMinutes: 4, rest: 180))

        let deload = DeloadPolicy.deloadPrescription(from: normal, loadIncrement: 2.5, isBodyweight: true)
        let machineDeload = DeloadPolicy.deloadPrescription(from: normal, loadIncrement: 1, isBodyweight: false)

        #expect(deload.load == 0)
        #expect(machineDeload.load == 0)
        #expect(deload.sets == 3)
        #expect(deload.note == .deload)
    }
}

// MARK: - F6 blocos dos intervalos (2.4)

extension CardioProgressionTests {
    /// Uma sessão de referência do Dia B (4 × 3–4 min, sem carga) há 2 dias, e o que vem depois.
    struct BlocksCase: Sendable, CustomTestStringConvertible {
        let label: String
        /// Minutos de cada bloco da sessão de referência; vazio = sem histórico.
        let minutes: [Int]
        let sets: Int
        let targetReps: Int
        let note: PrescriptionNote

        var testDescription: String { label }

        static let all: [BlocksCase] = [
            BlocksCase(label: "sem histórico: 4 × 3 (P2)", minutes: [], sets: 4, targetReps: 3, note: .calibrate),
            BlocksCase(label: "4 × 3 feito: 4 × 4 (P5)", minutes: [3, 3, 3, 3], sets: 4, targetReps: 4, note: .hold),
            BlocksCase(label: "4 × 4 no topo: 5 × 3, mais um bloco", minutes: [4, 4, 4, 4], sets: 5, targetReps: 3, note: .increase),
            BlocksCase(label: "5 × 3 feito: 5 × 4 (P5)", minutes: [3, 3, 3, 3, 3], sets: 5, targetReps: 4, note: .hold),
            BlocksCase(label: "5 × 4 no topo: fica em 5 × 4", minutes: [4, 4, 4, 4, 4], sets: 5, targetReps: 4, note: .hold),
            BlocksCase(label: "6 blocos no topo: B fica em 5, e fica", minutes: [4, 4, 4, 4, 4, 4], sets: 5, targetReps: 4, note: .hold),
            BlocksCase(label: "incompleto: 3 de 4 blocos no topo mantém 4 blocos", minutes: [4, 4, 4], sets: 4, targetReps: 4, note: .hold),
            BlocksCase(label: "5 blocos no meio da faixa: P5 com 5 blocos", minutes: [3, 4, 3, 4, 3], sets: 5, targetReps: 4, note: .hold),
            BlocksCase(label: "um bloco abaixo do mínimo: repete a meta com os mesmos 5 blocos (P6)",
                       minutes: [4, 2, 4, 4, 4], sets: 5, targetReps: 3, note: .retry),
        ]
    }

    @Test("F6 blocos dos intervalos sem carga: B vem da sessão de referência, entre S e 5", arguments: CardioProgressionTests.BlocksCase.all)
    func intervalBlocksTable(_ testCase: BlocksCase) {
        let history = testCase.minutes.isEmpty ? [] : [cardioSession(daysAgo: 2, minutes: testCase.minutes)]

        let result = prescribeCardio(history, target: dayBTarget())

        #expect(result.sets == testCase.sets)
        #expect(result.targetReps == testCase.targetReps)
        #expect(result.note == testCase.note)
        #expect(result.repMin == 3)
        #expect(result.repMax == 4)
        #expect(result.restSeconds == 180)
        if !testCase.minutes.isEmpty {
            #expect(result.load == 0, "aeróbico sem carga nunca ganha carga (F3)")
        }
    }

    @Test("F6 o caminho do Dia B: 4 × 3 → 4 × 4 → 5 × 3 → 5 × 4 → fica")
    func dayBPath() {
        var history: [ExerciseHistoryEntry] = []
        var path: [String] = []
        let first = prescribeCardio(history, target: dayBTarget(), now: cardioNow.addingTimeInterval(-11 * cardioDay))
        var current = first
        path.append("\(current.sets) × \(current.targetReps)")

        // Sessões a cada 2 dias, fazendo exatamente o que foi prescrito.
        for daysAgo in stride(from: 10.0, through: 2.0, by: -2.0) {
            history.append(cardioSession(daysAgo: daysAgo, minutes: Array(repeating: current.targetReps, count: current.sets)))
            current = prescribeCardio(history, target: dayBTarget(), now: cardioNow.addingTimeInterval(-(daysAgo - 1) * cardioDay))
            path.append("\(current.sets) × \(current.targetReps)")
        }

        #expect(path == ["4 × 3", "4 × 4", "5 × 3", "5 × 4", "5 × 4", "5 × 4"])
        #expect(DoubleProgressionRule.maxIntervalBlocks == 5)
    }

    @Test("F6 pausa de mais de 21 dias volta a S blocos no mínimo (P9)")
    func pauseGoesBackToPlannedBlocks() {
        let history = [cardioSession(daysAgo: 30, minutes: [4, 4, 4, 4, 4])]

        let result = prescribeCardio(history, target: dayBTarget())

        #expect(result.sets == 4)
        #expect(result.targetReps == 3)
        #expect(result.note == .returning)
        #expect(result.load == 0)
    }

    @Test("F6 a semana leve não muda B: vale a última sessão normal (P3)")
    func deloadSessionDoesNotChangeTheBlocks() {
        let history = [
            cardioSession(daysAgo: 4, minutes: [4, 4, 4, 4]),
            cardioSession(daysAgo: 2, minutes: [3, 3, 3], wasDeload: true),
        ]

        let result = prescribeCardio(history, target: dayBTarget())

        #expect(result.sets == 5)
        #expect(result.targetReps == 3)
        #expect(result.note == .increase)
    }

    @Test("F6 com nível registrado vale F3: sobe o nível, sem bloco novo")
    func levelKeepsF3() {
        let history = [cardioSession(daysAgo: 2, minutes: [4, 4, 4, 4], load: 3)]

        let result = prescribeCardio(history, target: dayBTarget(), machine: true)

        #expect(result.load == 4)
        #expect(result.sets == 4)
        #expect(result.targetReps == 3)
        #expect(result.note == .increase)
    }

    @Test("F6 aeróbico de 1 série não ganha blocos")
    func singleSetCardioHasNoBlocks() {
        let history = [cardioSession(daysAgo: 2, minutes: [45])]

        let result = prescribeCardio(history, target: cardioTarget(minMinutes: 30, maxMinutes: 45))

        #expect(result.sets == 1)
        #expect(result.targetReps == 45)
        #expect(result.note == .hold)
    }

    @Test("F6 força com várias séries não muda: o número de séries é o do plano")
    func strengthKeepsItsSets() {
        let pushUp = ExerciseDefinition(
            id: cardioExerciseID,
            slug: "push-up",
            name: "Flexão",
            primaryMuscles: [.chest],
            equipment: .bodyweight,
            loadUnit: .kilograms,
            loadIncrement: 2.5,
            movementPattern: .horizontalPush
        )
        let target = cardioTarget(sets: 3, minMinutes: 8, maxMinutes: 12)
        let history = [cardioSession(daysAgo: 2, minutes: [12, 12, 12, 12])]

        let result = DoubleProgressionRule().prescribe(target: target, exercise: pushUp, history: history, now: cardioNow)

        // P4 no peso do corpo sem carga (RF-46): a carga extra, com as séries do plano.
        #expect(result.sets == 3)
        #expect(result.load == 2.5)
        #expect(result.targetReps == 8)
        #expect(result.note == .increase)
    }
}

// MARK: - F5 semana leve no aeróbico (2.4)

extension CardioProgressionTests {
    struct LightWeekCase: Sendable, CustomTestStringConvertible {
        let label: String
        let sets: Int
        let repMin: Int
        let repMax: Int
        let isCardio: Bool
        let expectedSets: Int
        let expectedReps: Int

        var testDescription: String { label }

        static let all: [LightWeekCase] = [
            LightWeekCase(label: "1 série de 45–60 min: 27 min", sets: 1, repMin: 45, repMax: 60, isCardio: true,
                          expectedSets: 1, expectedReps: 27),
            LightWeekCase(label: "1 série de 30–45 min: 18 min", sets: 1, repMin: 30, repMax: 45, isCardio: true,
                          expectedSets: 1, expectedReps: 18),
            LightWeekCase(label: "1 série de 20–25 min: 12 min", sets: 1, repMin: 20, repMax: 25, isCardio: true,
                          expectedSets: 1, expectedReps: 12),
            LightWeekCase(label: "1 série de 1 min: no mínimo 1", sets: 1, repMin: 1, repMax: 2, isCardio: true,
                          expectedSets: 1, expectedReps: 1),
            LightWeekCase(label: "intervalos 5 × 3–4: 3 blocos de 3 min", sets: 5, repMin: 3, repMax: 4, isCardio: true,
                          expectedSets: 3, expectedReps: 3),
            LightWeekCase(label: "intervalos 4 × 3–4: 3 blocos de 3 min", sets: 4, repMin: 3, repMax: 4, isCardio: true,
                          expectedSets: 3, expectedReps: 3),
            LightWeekCase(label: "intervalos 2 × 3–4: 2 blocos de 3 min", sets: 2, repMin: 3, repMax: 4, isCardio: true,
                          expectedSets: 2, expectedReps: 3),
            LightWeekCase(label: "sem isCardio, 1 série: a meta fica no mínimo, como antes", sets: 1, repMin: 45, repMax: 60,
                          isCardio: false, expectedSets: 1, expectedReps: 45),
            LightWeekCase(label: "sem isCardio, 3 séries: como antes", sets: 3, repMin: 8, repMax: 12, isCardio: false,
                          expectedSets: 2, expectedReps: 8),
        ]
    }

    @Test("F5 semana leve no aeróbico: 1 série encurta os minutos; nos intervalos, menos blocos no mínimo",
          arguments: CardioProgressionTests.LightWeekCase.all)
    func lightWeekTable(_ testCase: LightWeekCase) {
        let normal = ExercisePrescription(
            exerciseID: cardioExerciseID,
            load: 0,
            sets: testCase.sets,
            repMin: testCase.repMin,
            repMax: testCase.repMax,
            targetReps: testCase.repMax,
            targetRIR: 3,
            restSeconds: 180,
            note: .hold
        )

        let result = DeloadPolicy.deloadPrescription(
            from: normal,
            loadIncrement: 2.5,
            isBodyweight: true,
            isCardio: testCase.isCardio
        )

        #expect(result.sets == testCase.expectedSets)
        #expect(result.targetReps == testCase.expectedReps)
        #expect(result.repMin == testCase.repMin)
        #expect(result.repMax == testCase.repMax)
        #expect(result.load == 0)
        #expect(result.targetRIR == DeloadPolicy.deloadTargetRIR)
        #expect(result.note == .deload)
    }

    @Test("F5 semana leve do Dia B com 5 blocos no topo: 3 blocos de 3 min")
    func lightWeekOfDayBAfterFiveBlocks() {
        let normal = prescribeCardio([cardioSession(daysAgo: 2, minutes: [4, 4, 4, 4, 4])], target: dayBTarget())

        let light = DeloadPolicy.deloadPrescription(from: normal, loadIncrement: 2.5, isBodyweight: true, isCardio: true)

        #expect(normal.sets == 5)
        #expect(light.sets == 3)
        #expect(light.targetReps == 3)
        #expect(light.load == 0)
    }

    @Test("F5 semana leve no aeróbico com nível: o nível cai como a carga, 15 %")
    func lightWeekWithLevel() {
        let normal = ExercisePrescription(
            exerciseID: cardioExerciseID,
            load: 5,
            sets: 1,
            repMin: 45,
            repMax: 75,
            targetReps: 50,
            targetRIR: 3,
            restSeconds: 60,
            note: .hold
        )

        let light = DeloadPolicy.deloadPrescription(from: normal, loadIncrement: 1, isBodyweight: false, isCardio: true)

        #expect(light.load == 4)
        #expect(light.sets == 1)
        #expect(light.targetReps == 27)
    }
}
