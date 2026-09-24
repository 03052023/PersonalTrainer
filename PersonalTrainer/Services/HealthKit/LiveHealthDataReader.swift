import Foundation
import HealthKit
import os
import TrainerCore

/// `HealthDataReading` real sobre `HKHealthStore` (SPEC §7.10, ARCHITECTURE §8; T5.2).
///
/// Lê, sempre agregado, o que as regras A1–A4 precisam e devolve `HealthInput`:
/// - treinos aeróbicos dos últimos 28 dias, com a FC média de cada minuto do treino (A1);
/// - VO2max dos últimos 180 dias (A3);
/// - HRV (SDNN), FC de repouso e horas de sono por dia, 28 dias + hoje (A4);
/// - passos por dia, 28 dias + hoje (§7.9);
/// - data de nascimento e sexo, opcionais, só para FCmáx e faixa de VO2max.
///
/// As consultas são feitas em sequência: são poucas (uma por categoria e uma de FC por
/// treino) e a ordem fixa deixa o comportamento simples de depurar. Toda API de callback é
/// envolvida em `withCheckedThrowingContinuation`, e cada callback converte os objetos do
/// HealthKit em structs `Sendable` antes de retomar, para que nenhum `HKSample` atravesse
/// a fronteira de concorrência.
///
/// `@unchecked Sendable`: o único estado é o `HKHealthStore`, que a Apple documenta como
/// seguro para uso de qualquer thread (um store por app, consultas de qualquer fila), e o
/// `Logger`, que é `Sendable`. Nada mutável é guardado aqui.
final class LiveHealthDataReader: HealthDataReading, @unchecked Sendable {
    /// Dias completos antes de hoje lidos para treinos, recuperação e passos (A1, A4).
    static let lookbackDays = 28
    /// Janela do VO2max: cobre a tendência de 90 dias e o aviso de 60 dias sem estimativa (A3).
    static let vo2MaxLookbackDays = 180
    /// Deslocamento que define a "noite" de um trecho de sono: o trecho pertence ao dia de
    /// `fim + 6 h`. Com isso a noite inteira (inclusive o trecho que acaba às 23h30 da véspera)
    /// cai no dia em que termina, e um cochilo antes das 18h fica no próprio dia.
    static let nightCutoffShiftHours = 6

    let store = HKHealthStore()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "HealthDataReader"
    )

    init() {}

    // MARK: HealthDataReading

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestReadAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        do {
            try await store.requestAuthorization(toShare: [], read: LiveHealthDataReader.readTypes())
        } catch {
            logger.error("Pedido de leitura do Saúde falhou: \(error.localizedDescription, privacy: .public)")
            throw HealthKitErrorMapper.map(error, fallback: .notAuthorized)
        }
    }

    func healthInput(now: Date, calendar: Calendar, recentSessions: [SessionSummary]) async throws -> HealthInput {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        let window = ReadWindow(now: now, calendar: calendar)

        do {
            let workouts = try await aerobicWorkouts(in: window)
            let vo2Max = try await vo2MaxSamples(from: window.vo2MaxStart, to: now)
            let hrv = try await dailyValues(of: .heartRateVariability, in: window, calendar: calendar)
            let restingHeartRate = try await dailyValues(of: .restingHeartRate, in: window, calendar: calendar)
            let sleepHours = try await sleepHoursByDay(in: window, calendar: calendar)
            let steps = try await dailyValues(of: .steps, in: window, calendar: calendar)
            let physiology = readPhysiology(calendar: calendar)

            logger.debug(
                "Saúde lida: \(workouts.count, privacy: .public) treinos aeróbicos, \(vo2Max.count, privacy: .public) VO2max, \(sleepHours.count, privacy: .public) noites"
            )

            return HealthInput(
                physiology: physiology,
                aerobicWorkouts: workouts,
                recovery: LiveHealthDataReader.mergeRecovery(
                    hrv: hrv,
                    restingHeartRate: restingHeartRate,
                    sleepHours: sleepHours
                ),
                steps: LiveHealthDataReader.dailySteps(from: steps),
                vo2Max: vo2Max,
                recentSessions: recentSessions
            )
        } catch let error as HealthKitServiceError {
            logger.error("Leitura do Saúde falhou: \(String(describing: error), privacy: .public)")
            throw error
        } catch {
            logger.error("Leitura do Saúde falhou: \(error.localizedDescription, privacy: .public)")
            throw HealthKitErrorMapper.map(error, fallback: nil)
        }
    }

    // MARK: Tipos lidos

    /// Tudo que `healthInput` consulta. Nada de escrita (`toShare` vazio): gravar treinos de
    /// musculação é do `HealthKitServicing`, que pede a própria autorização.
    static func readTypes() -> Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.vo2Max),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.stepCount),
            HKCategoryType(.sleepAnalysis),
        ]
        if let dateOfBirth = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            types.insert(dateOfBirth)
        }
        if let biologicalSex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
            types.insert(biologicalSex)
        }
        return types
    }

    // MARK: Treinos aeróbicos (A1)

    private func aerobicWorkouts(in window: ReadWindow) async throws -> [AerobicWorkoutSample] {
        let records = try await workoutRecords(from: window.start, to: window.now)
        var workouts: [AerobicWorkoutSample] = []
        workouts.reserveCapacity(records.count)
        for record in records {
            // Uma consulta por treino, com baldes de 1 min ancorados no início do treino.
            let minutes = try await intervalValues(
                of: .heartRate,
                from: record.start,
                to: record.end,
                anchor: record.start,
                interval: DateComponents(minute: 1)
            )
            workouts.append(
                AerobicWorkoutSample(
                    id: record.id,
                    activity: record.activity,
                    start: record.start,
                    end: record.end,
                    minuteHeartRates: minutes.map(\.value)
                )
            )
        }
        return workouts
    }

    /// Treinos que começaram na janela, já filtrados (força e mente-corpo fora) e convertidos.
    private func workoutRecords(from start: Date, to end: Date) async throws -> [WorkoutRecord] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[WorkoutRecord], Error>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    HealthKitErrorMapper.resumeEmptyOrThrow(continuation, error: error, empty: [])
                    return
                }
                var records: [WorkoutRecord] = []
                for sample in samples ?? [] {
                    guard
                        let workout = sample as? HKWorkout,
                        workout.endDate > workout.startDate,
                        let activity = LiveHealthDataReader.aerobicActivity(for: workout.workoutActivityType)
                    else { continue }
                    records.append(
                        WorkoutRecord(
                            id: workout.uuid,
                            activity: activity,
                            start: workout.startDate,
                            end: workout.endDate
                        )
                    )
                }
                continuation.resume(returning: records)
            }
            store.execute(query)
        }
    }

    /// `HKWorkoutActivityType` → `AerobicActivity`. `nil` = não entra na conta aeróbica:
    /// musculação (inclusive a gravada por este app e o treino de core), mente-corpo,
    /// alongamento, desaquecimento e recuperação, e esportes de precisão ou lazer parado
    /// (arco, boliche, curling, pesca, golfe, caça, vela, hipismo). Esses últimos ficam de fora
    /// porque, sem FC, `.other` vale como moderado pela duração inteira (A1) e uma partida de
    /// golfe de 4 h viraria 240 min aeróbicos. Qualquer outro tipo (lutas, esportes coletivos,
    /// corda, esqui…) conta como `.other` e é classificado pela FC; sem FC, moderado.
    static func aerobicActivity(for type: HKWorkoutActivityType) -> AerobicActivity? {
        switch type {
        case .walking:
            return .walking
        case .running:
            return .running
        case .cycling:
            return .cycling
        case .swimming:
            return .swimming
        case .rowing:
            return .rowing
        case .elliptical:
            return .elliptical
        case .hiking:
            return .hiking
        case .stairClimbing, .stairs:
            return .stairs
        case .highIntensityIntervalTraining:
            return .hiit
        case .cardioDance, .socialDance:
            return .dance
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining,
             .yoga, .pilates, .mindAndBody, .taiChi, .flexibility, .cooldown, .preparationAndRecovery,
             .archery, .bowling, .curling, .fishing, .golf, .hunting, .sailing, .equestrianSports:
            return nil
        default:
            return .other
        }
    }

    // MARK: VO2max (A3)

    private func vo2MaxSamples(from start: Date, to end: Date) async throws -> [Vo2MaxSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Vo2MaxSample], Error>) in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.vo2Max),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    HealthKitErrorMapper.resumeEmptyOrThrow(continuation, error: error, empty: [])
                    return
                }
                let unit = LiveHealthDataReader.vo2MaxUnit()
                var values: [Vo2MaxSample] = []
                for sample in samples ?? [] {
                    guard let quantitySample = sample as? HKQuantitySample else { continue }
                    values.append(
                        Vo2MaxSample(
                            date: quantitySample.startDate,
                            value: quantitySample.quantity.doubleValue(for: unit)
                        )
                    )
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    /// mL/(kg·min), montado por composição em vez de `HKUnit(from:)` com string: uma string
    /// inválida em `HKUnit(from:)` derruba o app com exceção Objective-C.
    static func vo2MaxUnit() -> HKUnit {
        HKUnit.literUnit(with: .milli).unitDivided(
            by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.minute())
        )
    }

    // MARK: Médias e somas por dia (A4, passos)

    /// Um valor por dia do calendário do usuário, chaveado pelo início do dia.
    /// A âncora é o início de hoje; `HKStatisticsCollectionQuery` passa os baldes diários.
    /// O HealthKit avança os baldes com o calendário do sistema; no app o `calendar` injetado
    /// é `.current`, então os dois coincidem, e a chave é normalizada com `startOfDay` mesmo assim.
    private func dailyValues(
        of measure: QuantityMeasure,
        in window: ReadWindow,
        calendar: Calendar
    ) async throws -> [Date: Double] {
        let values = try await intervalValues(
            of: measure,
            from: window.start,
            to: window.now,
            anchor: window.today,
            interval: DateComponents(day: 1)
        )
        var byDay: [Date: Double] = [:]
        for value in values {
            byDay[calendar.startOfDay(for: value.start)] = value.value
        }
        return byDay
    }

    /// Estatística por intervalo via `HKStatisticsCollectionQuery`. Intervalos sem amostra
    /// ficam de fora (por isso `minuteHeartRates` pode ter menos itens que a duração do treino).
    /// Sem `statisticsUpdateHandler`, a consulta para sozinha depois dos resultados iniciais.
    private func intervalValues(
        of measure: QuantityMeasure,
        from start: Date,
        to end: Date,
        anchor: Date,
        interval: DateComponents
    ) async throws -> [IntervalValue] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[IntervalValue], Error>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: measure.quantityType(),
                quantitySamplePredicate: predicate,
                options: measure.options(),
                anchorDate: anchor,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    HealthKitErrorMapper.resumeEmptyOrThrow(continuation, error: error, empty: [])
                    return
                }
                var values: [IntervalValue] = []
                for statistics in collection?.statistics() ?? [] {
                    guard let value = measure.value(of: statistics) else { continue }
                    values.append(IntervalValue(start: statistics.startDate, value: value))
                }
                values.sort { $0.start < $1.start }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    // MARK: Sono (A4)

    /// Horas dormidas por noite, na janela de recuperação (28 dias + a noite que terminou hoje).
    private func sleepHoursByDay(in window: ReadWindow, calendar: Calendar) async throws -> [Date: Double] {
        let segments = try await sleepSegments(from: window.sleepQueryStart, to: window.now)
        let byDay = LiveHealthDataReader.sleepHoursByDay(segments, calendar: calendar)
        return byDay.filter { day, _ in day >= window.start && day <= window.today }
    }

    /// Trechos "dormindo" (não conta `inBed` nem `awake`) que sobrepõem o intervalo.
    private func sleepSegments(from start: Date, to end: Date) async throws -> [SleepSegment] {
        // Sem `.strictStartDate`: qualquer trecho que sobreponha o intervalo entra; a
        // atribuição ao dia e o recorte da janela são feitos depois, em memória.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[SleepSegment], Error>) in
            let query = HKSampleQuery(
                sampleType: HKCategoryType(.sleepAnalysis),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    HealthKitErrorMapper.resumeEmptyOrThrow(continuation, error: error, empty: [])
                    return
                }
                var segments: [SleepSegment] = []
                for sample in samples ?? [] {
                    guard
                        let category = sample as? HKCategorySample,
                        LiveHealthDataReader.isAsleep(categoryValue: category.value),
                        category.endDate > category.startDate
                    else { continue }
                    segments.append(
                        SleepSegment(
                            start: category.startDate,
                            end: category.endDate,
                            isFromWatch: LiveHealthDataReader.isAppleWatch(
                                productType: category.sourceRevision.productType,
                                deviceModel: category.device?.model
                            )
                        )
                    )
                }
                continuation.resume(returning: segments)
            }
            store.execute(query)
        }
    }

    /// Estágios que contam como sono: não especificado, core, profundo e REM.
    /// Comparação por `rawValue` para não depender de `switch` exaustivo sobre um enum
    /// importado que ganha casos a cada versão (e tem o alias obsoleto `.asleep`).
    static func isAsleep(categoryValue: Int) -> Bool {
        categoryValue == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
            || categoryValue == HKCategoryValueSleepAnalysis.asleepCore.rawValue
            || categoryValue == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
            || categoryValue == HKCategoryValueSleepAnalysis.asleepREM.rawValue
    }

    /// Apple Watch: `productType` começa com "Watch" (ex.: "Watch7,3") ou o `HKDevice`
    /// se declara "Watch". Qualquer um dos dois basta.
    static func isAppleWatch(productType: String?, deviceModel: String?) -> Bool {
        if let productType, productType.hasPrefix("Watch") {
            return true
        }
        return deviceModel == "Watch"
    }

    // MARK: Fisiologia (opcional)

    /// Data de nascimento e sexo: `try?` porque negar ou não preencher é normal e só tira a
    /// FCmáx por idade e a faixa de VO2max (A1, A3). Nunca lança.
    private func readPhysiology(calendar: Calendar) -> UserPhysiology {
        let birthDate = (try? store.dateOfBirthComponents()).flatMap {
            LiveHealthDataReader.birthDate(from: $0, timeZone: calendar.timeZone)
        }
        let sex = (try? store.biologicalSex()).flatMap {
            LiveHealthDataReader.biologicalSexValue($0.biologicalSex)
        }
        return UserPhysiology(birthDate: birthDate, sex: sex, maxHeartRateOverride: nil)
    }

    /// O HealthKit entrega a data de nascimento como componentes do calendário gregoriano.
    /// Monta a data em calendário gregoriano no fuso do usuário, independentemente do
    /// calendário configurado no aparelho, para que o ano não seja reinterpretado.
    static func birthDate(from components: DateComponents, timeZone: TimeZone) -> Date? {
        guard let year = components.year else {
            return nil
        }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        return gregorian.date(from: DateComponents(year: year, month: components.month ?? 1, day: components.day ?? 1))
    }

    static func biologicalSexValue(_ sex: HKBiologicalSex) -> BiologicalSexValue? {
        switch sex {
        case .female:
            return .female
        case .male:
            return .male
        case .other:
            return .other
        case .notSet:
            return nil
        @unknown default:
            return nil
        }
    }
}

// MARK: - Agregação pura (sem HealthKit, testável)

extension LiveHealthDataReader {
    /// Trecho de sono já extraído de um `HKCategorySample` com valor "dormindo".
    struct SleepSegment: Sendable, Hashable {
        let start: Date
        let end: Date
        let isFromWatch: Bool
    }

    /// Dia ao qual pertence um trecho de sono que termina em `end` (ver `nightCutoffShiftHours`).
    static func nightDay(endingAt end: Date, calendar: Calendar) -> Date {
        let shifted = calendar.date(byAdding: .hour, value: nightCutoffShiftHours, to: end)
            ?? end.addingTimeInterval(TimeInterval(nightCutoffShiftHours) * 3_600)
        return calendar.startOfDay(for: shifted)
    }

    /// Horas dormidas por dia (início do dia → horas).
    ///
    /// Várias fontes gravam a mesma noite (Apple Watch, iPhone, apps de terceiros). Por noite:
    /// se houver algum trecho do Apple Watch, usa só os trechos do Watch, que medem por sensor
    /// e já vêm por estágio; senão usa todos. Depois une os trechos sobrepostos antes de somar,
    /// para que duplicatas e estágios encavalados não contem duas vezes.
    static func sleepHoursByDay(_ segments: [SleepSegment], calendar: Calendar) -> [Date: Double] {
        var segmentsByDay: [Date: [SleepSegment]] = [:]
        for segment in segments where segment.end > segment.start {
            segmentsByDay[nightDay(endingAt: segment.end, calendar: calendar), default: []].append(segment)
        }
        var hoursByDay: [Date: Double] = [:]
        for (day, daySegments) in segmentsByDay {
            let watchSegments = daySegments.filter(\.isFromWatch)
            let chosen = watchSegments.isEmpty ? daySegments : watchSegments
            let seconds = unionDuration(of: chosen)
            if seconds > 0 {
                hoursByDay[day] = seconds / 3_600
            }
        }
        return hoursByDay
    }

    /// Duração total da união dos intervalos, em segundos.
    static func unionDuration(of segments: [SleepSegment]) -> TimeInterval {
        let sorted = segments.sorted { lhs, rhs in
            lhs.start == rhs.start ? lhs.end < rhs.end : lhs.start < rhs.start
        }
        var total: TimeInterval = 0
        var current: (start: Date, end: Date)?
        for segment in sorted {
            if let open = current {
                if segment.start <= open.end {
                    current = (open.start, max(open.end, segment.end))
                } else {
                    total += open.end.timeIntervalSince(open.start)
                    current = (segment.start, segment.end)
                }
            } else {
                current = (segment.start, segment.end)
            }
        }
        if let open = current {
            total += open.end.timeIntervalSince(open.start)
        }
        return total
    }

    /// Junta HRV, FC de repouso e sono por dia. Dias sem nenhum dos três ficam de fora:
    /// a ausência de um dia é o sinal de "sem dado noturno" que A4 conta.
    static func mergeRecovery(
        hrv: [Date: Double],
        restingHeartRate: [Date: Double],
        sleepHours: [Date: Double]
    ) -> [DailyRecoverySample] {
        let days = Set(hrv.keys).union(restingHeartRate.keys).union(sleepHours.keys).sorted()
        return days.map { day in
            DailyRecoverySample(
                day: day,
                hrvSDNN: hrv[day],
                restingHeartRate: restingHeartRate[day],
                sleepHours: sleepHours[day]
            )
        }
    }

    /// Soma diária de passos → `DailyStepCount`, em ordem de dia.
    static func dailySteps(from byDay: [Date: Double]) -> [DailyStepCount] {
        byDay.keys.sorted().compactMap { day in
            guard let steps = byDay[day] else {
                return nil
            }
            return DailyStepCount(day: day, steps: Int(steps.rounded()))
        }
    }
}

// MARK: - Tipos privados

/// Janelas de leitura calculadas uma vez a partir do relógio e do calendário injetados.
private struct ReadWindow {
    let now: Date
    /// Início de hoje no calendário do usuário.
    let today: Date
    /// Início do dia `lookbackDays` antes de hoje: treinos, recuperação e passos.
    let start: Date
    /// `now` menos `vo2MaxLookbackDays`.
    let vo2MaxStart: Date
    /// `start` menos o deslocamento da noite, para pegar os trechos que caem no primeiro dia.
    let sleepQueryStart: Date

    init(now: Date, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -LiveHealthDataReader.lookbackDays, to: today)
            ?? today.addingTimeInterval(-TimeInterval(LiveHealthDataReader.lookbackDays) * 86_400)
        self.now = now
        self.today = today
        self.start = start
        self.vo2MaxStart = calendar.date(byAdding: .day, value: -LiveHealthDataReader.vo2MaxLookbackDays, to: now)
            ?? now.addingTimeInterval(-TimeInterval(LiveHealthDataReader.vo2MaxLookbackDays) * 86_400)
        self.sleepQueryStart = start.addingTimeInterval(-TimeInterval(LiveHealthDataReader.nightCutoffShiftHours) * 3_600)
    }
}

/// Treino já filtrado e convertido dentro do callback do HealthKit.
private struct WorkoutRecord: Sendable {
    let id: UUID
    let activity: AerobicActivity
    let start: Date
    let end: Date
}

/// Valor de um intervalo de `HKStatisticsCollectionQuery` (minuto ou dia).
private struct IntervalValue: Sendable {
    let start: Date
    let value: Double
}

/// Grandezas lidas por `HKStatisticsCollectionQuery`. Tipos e unidades do HealthKit são
/// criados sob demanda (e não guardados em `static let`) porque não são `Sendable`.
private enum QuantityMeasure: Sendable {
    case heartRate
    case heartRateVariability
    case restingHeartRate
    case steps

    func quantityType() -> HKQuantityType {
        switch self {
        case .heartRate:
            return HKQuantityType(.heartRate)
        case .heartRateVariability:
            return HKQuantityType(.heartRateVariabilitySDNN)
        case .restingHeartRate:
            return HKQuantityType(.restingHeartRate)
        case .steps:
            return HKQuantityType(.stepCount)
        }
    }

    /// FC, HRV e FC de repouso são discretas (média); passos são cumulativos (soma, que o
    /// HealthKit já deduplica entre iPhone e Watch).
    func options() -> HKStatisticsOptions {
        switch self {
        case .heartRate, .heartRateVariability, .restingHeartRate:
            return .discreteAverage
        case .steps:
            return .cumulativeSum
        }
    }

    func value(of statistics: HKStatistics) -> Double? {
        switch self {
        case .heartRate, .restingHeartRate:
            return statistics.averageQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
        case .heartRateVariability:
            return statistics.averageQuantity()?.doubleValue(for: HKUnit.secondUnit(with: .milli))
        case .steps:
            return statistics.sumQuantity()?.doubleValue(for: HKUnit.count())
        }
    }
}

/// Converte erros do HealthKit em `HealthKitServiceError`. "Sem dados" nunca é erro.
private enum HealthKitErrorMapper {
    static func isNoData(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == HKErrorDomain && nsError.code == HKError.Code.errorNoData.rawValue
    }

    /// - Parameter fallback: erro usado quando o código não é reconhecido; `nil` usa
    ///   `.queryFailed` com a descrição original.
    static func map(_ error: Error, fallback: HealthKitServiceError?) -> HealthKitServiceError {
        if let serviceError = error as? HealthKitServiceError {
            return serviceError
        }
        let nsError = error as NSError
        if nsError.domain == HKErrorDomain {
            switch nsError.code {
            case HKError.Code.errorHealthDataUnavailable.rawValue,
                 HKError.Code.errorHealthDataRestricted.rawValue:
                return .unavailable
            case HKError.Code.errorAuthorizationNotDetermined.rawValue,
                 HKError.Code.errorAuthorizationDenied.rawValue:
                return .notAuthorized
            default:
                break
            }
        }
        return fallback ?? .queryFailed(underlying: error.localizedDescription)
    }

    /// Retoma com `empty` se o erro é "sem dados"; senão lança o erro mapeado.
    static func resumeEmptyOrThrow<Value: Sendable>(
        _ continuation: CheckedContinuation<Value, Error>,
        error: Error,
        empty: Value
    ) {
        if isNoData(error) {
            continuation.resume(returning: empty)
        } else {
            continuation.resume(throwing: map(error, fallback: nil))
        }
    }
}
