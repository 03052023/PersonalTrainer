import Foundation
import TrainerCore

/// `HealthDataReading` em memória (AGENTS R9): roda no simulador, nos previews e nos testes.
/// Devolve o `HealthInput` configurado ou, sem configuração, `sampleInput(now:calendar:)`.
///
/// Sem estado mutável: só `let` de tipos `Sendable`, então a classe é `Sendable` verificada
/// pelo compilador, com a mesma forma de isolamento do `LiveHealthDataReader` (não isolada,
/// chamável de qualquer executor).
final class FakeHealthDataReader: HealthDataReading {
    let isAvailable: Bool

    private let input: HealthInput?
    private let authorizationError: HealthKitServiceError?
    private let readError: HealthKitServiceError?

    /// - Parameters:
    ///   - input: resposta de `healthInput`; `nil` usa `sampleInput(now:calendar:)` com o
    ///     relógio e o calendário da chamada.
    ///   - isAvailable: `false` simula simulador/iPad: os dois métodos lançam `.unavailable`.
    ///   - authorizationError: se não `nil`, `requestReadAuthorization()` lança este erro.
    ///   - readError: se não `nil`, `healthInput(...)` lança este erro (tela de erro nos previews).
    init(
        input: HealthInput? = nil,
        isAvailable: Bool = true,
        authorizationError: HealthKitServiceError? = nil,
        readError: HealthKitServiceError? = nil
    ) {
        self.input = input
        self.isAvailable = isAvailable
        self.authorizationError = authorizationError
        self.readError = readError
    }

    // MARK: HealthDataReading

    func requestReadAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        if let authorizationError {
            throw authorizationError
        }
    }

    /// Como o `LiveHealthDataReader`, repassa `recentSessions` da chamada e ignora as
    /// sessões que estiverem no `input` configurado.
    func healthInput(now: Date, calendar: Calendar, recentSessions: [SessionSummary]) async throws -> HealthInput {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        if let readError {
            throw readError
        }
        let base = input ?? FakeHealthDataReader.sampleInput(now: now, calendar: calendar)
        return HealthInput(
            physiology: base.physiology,
            aerobicWorkouts: base.aerobicWorkouts,
            recovery: base.recovery,
            steps: base.steps,
            vo2Max: base.vo2Max,
            recentSessions: recentSessions
        )
    }

    // MARK: Dados de exemplo

    /// Quatro semanas plausíveis e determinísticas, relativas a `now` (mesma entrada, mesma
    /// saída; `now` um dia depois desloca tudo um dia):
    /// - treinos: a cada bloco de 7 dias, 3 caminhadas (35–40 min, FC 118–126 após 3 min de
    ///   aquecimento) e 1 corrida (30 min, FC 150–155); os últimos 7 dias têm exatamente
    ///   3 caminhadas e 1 corrida, e nenhum treino cai hoje (ainda pode não ter acontecido);
    /// - VO2max de 41,4 a 44,0 em 180 dias, 42,0 há 90 dias e o último há 3 dias;
    /// - recuperação dos últimos 28 dias (hoje incluso): HRV ~55 ms, FC de repouso ~58 bpm,
    ///   sono ~6,8 h; nas noites de 2 e 5 dias atrás o relógio ficou fora do pulso (sem HRV
    ///   nem sono, com FC de repouso do dia);
    /// - passos dos 28 dias completos antes de hoje, média de 8.000 em qualquer semana;
    /// - 38 anos, sexo masculino, sem FCmáx informada; `recentSessions` vazio.
    static func sampleInput(now: Date, calendar: Calendar) -> HealthInput {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: today)
                ?? today.addingTimeInterval(TimeInterval(offset) * 86_400)
        }

        return HealthInput(
            physiology: UserPhysiology(
                birthDate: calendar.date(byAdding: .year, value: -38, to: today),
                sex: .male,
                maxHeartRateOverride: nil
            ),
            aerobicWorkouts: sampleWorkouts(day: day),
            recovery: sampleRecovery(day: day),
            steps: sampleSteps(day: day),
            vo2Max: sampleVo2Max(day: day),
            recentSessions: []
        )
    }

    // MARK: Geradores

    /// Um treino do padrão semanal: dias antes de hoje, tipo, horário de início e duração.
    private struct WorkoutTemplate {
        let daysAgo: Int
        let activity: AerobicActivity
        let startMinuteOfDay: Int
        let durationMinutes: Int
    }

    private static let weeklyWorkouts: [WorkoutTemplate] = [
        WorkoutTemplate(daysAgo: 1, activity: .walking, startMinuteOfDay: 7 * 60, durationMinutes: 40),
        WorkoutTemplate(daysAgo: 2, activity: .running, startMinuteOfDay: 18 * 60 + 30, durationMinutes: 30),
        WorkoutTemplate(daysAgo: 4, activity: .walking, startMinuteOfDay: 7 * 60, durationMinutes: 40),
        WorkoutTemplate(daysAgo: 6, activity: .walking, startMinuteOfDay: 12 * 60 + 15, durationMinutes: 35),
    ]

    private static func sampleWorkouts(day: (Int) -> Date) -> [AerobicWorkoutSample] {
        var workouts: [AerobicWorkoutSample] = []
        for week in 0..<4 {
            for (index, template) in weeklyWorkouts.enumerated() {
                let start = day(-(week * 7 + template.daysAgo))
                    .addingTimeInterval(TimeInterval(template.startMinuteOfDay) * 60)
                let end = start.addingTimeInterval(TimeInterval(template.durationMinutes) * 60)
                workouts.append(
                    AerobicWorkoutSample(
                        id: sampleID(kind: 1, index: week * weeklyWorkouts.count + index),
                        activity: template.activity,
                        start: start,
                        end: end,
                        minuteHeartRates: minuteHeartRates(
                            for: template.activity,
                            minutes: template.durationMinutes
                        )
                    )
                )
            }
        }
        return workouts.sorted { $0.start < $1.start }
    }

    /// Três minutos de aquecimento e depois uma oscilação pequena e fixa.
    private static func minuteHeartRates(for activity: AerobicActivity, minutes: Int) -> [Double] {
        (0..<minutes).map { minute in
            switch activity {
            case .running:
                return minute < 3 ? Double(120 + 8 * minute) : Double(150 + minute % 6)
            default:
                return minute < 3 ? Double(100 + 6 * minute) : Double(118 + (minute % 5) * 2)
            }
        }
    }

    private static let vo2MaxHistory: [(daysAgo: Int, value: Double)] = [
        (160, 41.4), (125, 41.8), (90, 42.0), (62, 42.6), (41, 43.1), (20, 43.5), (3, 44.0),
    ]

    private static func sampleVo2Max(day: (Int) -> Date) -> [Vo2MaxSample] {
        vo2MaxHistory.map { entry in
            Vo2MaxSample(date: day(-entry.daysAgo).addingTimeInterval(8 * 3_600), value: entry.value)
        }
    }

    /// Ciclos de 7 dias com soma zero em torno da média, para que qualquer semana completa
    /// tenha a média exata (sono em décimos de hora para evitar ruído de ponto flutuante).
    private static let hrvDeltas: [Double] = [0, 4, -3, 5, -4, 2, -4]
    private static let restingHeartRateDeltas: [Double] = [0, 1, -1, 2, -2, 1, -1]
    private static let sleepTenths: [Int] = [70, 65, 72, 63, 69, 71, 66]
    private static let stepDeltas: [Int] = [400, -700, 1_200, -300, -900, 600, -300]
    /// Noites sem o relógio no pulso (dias antes de hoje).
    private static let nightsWithoutWatch: Set<Int> = [2, 5]

    private static func sampleRecovery(day: (Int) -> Date) -> [DailyRecoverySample] {
        (0..<28).reversed().map { daysAgo in
            let cycle = (27 - daysAgo) % 7
            let woreWatch = !nightsWithoutWatch.contains(daysAgo)
            return DailyRecoverySample(
                day: day(-daysAgo),
                hrvSDNN: woreWatch ? 55 + hrvDeltas[cycle] : nil,
                restingHeartRate: 58 + restingHeartRateDeltas[cycle],
                sleepHours: woreWatch ? Double(sleepTenths[cycle]) / 10 : nil
            )
        }
    }

    private static func sampleSteps(day: (Int) -> Date) -> [DailyStepCount] {
        (1...28).reversed().map { daysAgo in
            DailyStepCount(day: day(-daysAgo), steps: 8_000 + stepDeltas[(28 - daysAgo) % 7])
        }
    }

    /// UUID fixo (versão 4, variante RFC 4122) a partir de um tipo e um índice < 256.
    private static func sampleID(kind: UInt8, index: Int) -> UUID {
        UUID(uuid: (0xFA, 0xCE, 0x5A, 0x3B, 0x00, 0x00, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, kind, UInt8(truncatingIfNeeded: index)))
    }
}
