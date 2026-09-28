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
private func cardioSession(daysAgo: Double, minutes: [Int], load: Double = 0) -> ExerciseHistoryEntry {
    let date = cardioNow.addingTimeInterval(-daysAgo * cardioDay)
    let stamp = String(UInt64(date.timeIntervalSince1970), radix: 16)
    let suffix = String(repeating: "0", count: max(0, 12 - stamp.count)) + stamp
    let sessionID = UUID(uuidString: "00000000-0000-0000-0002-" + suffix)!
    let sets = minutes.enumerated().map { offset, value in
        SetResult(load: load, reps: value, rir: nil, isWarmup: false, completedAt: date.addingTimeInterval(Double(offset) * 300))
    }
    return ExerciseHistoryEntry(sessionID: sessionID, date: date, sets: sets)
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

    @Test("F3 intervalos 4 × 2–4 min: todos no topo e sem carga, a meta fica no topo")
    func intervalsAtTheTopStayThere() {
        let history = [cardioSession(daysAgo: 2, minutes: [4, 4, 4, 4])]

        let result = prescribeCardio(history, target: cardioTarget(sets: 4, minMinutes: 2, maxMinutes: 4, rest: 180))

        #expect(result.load == 0)
        #expect(result.targetReps == 4)
        #expect(result.sets == 4)
        #expect(result.restSeconds == 180)
        #expect(result.note == .hold)
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
