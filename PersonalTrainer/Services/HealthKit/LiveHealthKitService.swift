import Foundation
import HealthKit

/// Implementação real do `HealthKitServicing` (ARCHITECTURE §8; T2.1, T2.2; SPEC RF-13, RF-14).
/// É o único arquivo do app que importa HealthKit: o resto do app só conhece o protocolo e os
/// tipos de valor (`HeartRateSummary`, `HealthKitServiceError`), então nenhum `HKObject` sai daqui
/// e amostras brutas de FC nunca chegam a quem chama (ARCHITECTURE §8, AGENTS R2).
///
/// `@unchecked Sendable`: o único estado é `store`, um `let` nunca reatribuído. `HKHealthStore` é
/// thread-safe (feito para ser um objeto único e de longa duração, compartilhado pelo app inteiro,
/// que responde em filas próprias), mas nem todo SDK o anota como `Sendable`; declarar a
/// conformidade à mão evita depender disso. Nenhum outro estado mutável pode entrar nesta classe.
final class LiveHealthKitService: HealthKitServicing, @unchecked Sendable {
    /// Intervalo de um treino candidato ao vínculo, já sem nada do HealthKit: dá para testar a
    /// regra de sobreposição (SPEC RF-13) sem aparelho.
    struct WorkoutInterval: Sendable, Hashable {
        let uuid: UUID
        let start: Date
        let end: Date
    }

    /// SPEC RF-13: vincula o treino de outro app que cobre pelo menos metade da sessão.
    static let minimumOverlapFraction = 0.5

    private let store = HKHealthStore()

    init() {}

    // MARK: - HealthKitServicing

    /// `false` em iPad e em aparelhos sem o app Saúde.
    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    /// Escrita: treinos. Leitura: FC (RF-14) e treinos (para achar o do app Exercício, RF-13, e o
    /// próprio treino pela `HKMetadataKeyExternalUUID`).
    func requestAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        let typesToShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        let typesToRead: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate)]
        do {
            try await store.requestAuthorization(toShare: typesToShare, read: typesToRead)
        } catch {
            // Erro aqui é de configuração (entitlement, strings do Info.plist), não do usuário.
            throw HealthKitServiceError.notAuthorized
        }
        // O pedido termina sem erro mesmo quando o usuário nega; só o status de escrita é
        // visível (o de leitura é opaco, ARCHITECTURE §15).
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            throw HealthKitServiceError.notAuthorized
        }
    }

    /// Grava um `HKWorkout` de musculação com início/fim reais da sessão (RF-13). Idempotente por
    /// `sessionUUID`: se este app já gravou um treino com essa `HKMetadataKeyExternalUUID`, devolve
    /// o UUID dele em vez de criar outro (invariante "um HKWorkout por sessão", ARCHITECTURE §8).
    func saveStrengthWorkout(start: Date, end: Date, sessionUUID: UUID) async throws -> UUID {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else {
            throw HealthKitServiceError.notAuthorized
        }
        guard end > start else {
            throw HealthKitServiceError.saveFailed(underlying: "end does not follow start")
        }
        // Uma falha na busca não impede a gravação: sem leitura de treinos a lista vem vazia de
        // qualquer jeito, e perder o treino é pior que o risco raro de duplicar.
        if let existing = try? await ownWorkoutUUID(forSession: sessionUUID) {
            return existing
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: HKDevice.local())

        // Formas com completion handler (existem desde o iOS 12 com estes nomes), adaptadas com
        // continuations; o builder aceita datas passadas, que é o caso aqui (sessão já terminou).
        do {
            try await Self.awaitCompletion { completion in
                builder.beginCollection(withStart: start, completion: completion)
            }
            try await Self.awaitCompletion { completion in
                builder.addMetadata([HKMetadataKeyExternalUUID: sessionUUID.uuidString], completion: completion)
            }
            try await Self.awaitCompletion { completion in
                builder.endCollection(withEnd: end, completion: completion)
            }
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UUID, any Error>) in
                builder.finishWorkout { workout, error in
                    // Converte aqui dentro: só o UUID (`Sendable`) atravessa a continuation.
                    if let workout {
                        continuation.resume(returning: workout.uuid)
                    } else {
                        continuation.resume(throwing: error ?? HealthKitServiceError.saveFailed(
                            underlying: "finishWorkout returned no workout"
                        ))
                    }
                }
            }
        } catch let error as HealthKitServiceError {
            builder.discardWorkout()
            throw error
        } catch {
            builder.discardWorkout()
            throw HealthKitServiceError.saveFailed(underlying: String(describing: error))
        }
    }

    /// Média e máxima das amostras de FC em `[start, end]` (RF-14). `nil` sem amostras, o que
    /// também cobre leitura negada: o HealthKit devolve lista vazia em vez de erro.
    func heartRateSummary(start: Date, end: Date) async throws -> HeartRateSummary? {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        guard end > start else {
            return nil
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        do {
            let sampleCount = try await heartRateSampleCount(matching: predicate)
            guard sampleCount > 0 else {
                return nil
            }
            return try await heartRateStatistics(matching: predicate, sampleCount: sampleCount)
        } catch {
            throw HealthKitServiceError.queryFailed(underlying: String(describing: error))
        }
    }

    /// Treino de força de OUTRO app que cobre ≥ 50 % de `[start, end]` (RF-13), o de maior
    /// sobreposição. Treinos gravados por este app (mesmo bundle id) nunca contam.
    func findOverlappingStrengthWorkout(start: Date, end: Date) async throws -> UUID? {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else {
            return nil
        }
        // Janela expandida pela duração da sessão; sem `options` o predicado já aceita qualquer
        // treino que cruze a janela, e a sobreposição exata é medida em memória.
        let predicate = HKQuery.predicateForSamples(
            withStart: start.addingTimeInterval(-duration),
            end: end.addingTimeInterval(duration),
            options: []
        )
        let ownBundleID = Bundle.main.bundleIdentifier
        let candidates: [WorkoutInterval]
        do {
            candidates = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[WorkoutInterval], any Error>) in
                let query = HKSampleQuery(
                    sampleType: HKObjectType.workoutType(),
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: nil
                ) { _, samples, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    // Converte aqui dentro: só valores `Sendable` atravessam a continuation.
                    var intervals: [WorkoutInterval] = []
                    for sample in samples ?? [] {
                        guard let workout = sample as? HKWorkout else {
                            continue
                        }
                        let activity = workout.workoutActivityType
                        guard activity == .traditionalStrengthTraining || activity == .functionalStrengthTraining else {
                            continue
                        }
                        guard workout.sourceRevision.source.bundleIdentifier != ownBundleID else {
                            continue
                        }
                        intervals.append(WorkoutInterval(uuid: workout.uuid, start: workout.startDate, end: workout.endDate))
                    }
                    continuation.resume(returning: intervals)
                }
                store.execute(query)
            }
        } catch {
            throw HealthKitServiceError.queryFailed(underlying: String(describing: error))
        }
        return Self.bestOverlappingWorkout(among: candidates, start: start, end: end)
    }

    // MARK: - Regra de vínculo (pura, testável sem HealthKit)

    /// UUID do candidato com maior sobreposição com `[start, end]`, desde que ela seja pelo menos
    /// `minimumOverlapFraction` da duração da sessão (SPEC RF-13). Empate: o primeiro da lista.
    static func bestOverlappingWorkout(among candidates: [WorkoutInterval], start: Date, end: Date) -> UUID? {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else {
            return nil
        }
        let minimumOverlap = duration * minimumOverlapFraction
        var best: (uuid: UUID, overlap: TimeInterval)?
        for candidate in candidates {
            let overlap = min(end, candidate.end).timeIntervalSince(max(start, candidate.start))
            guard overlap >= minimumOverlap else {
                continue
            }
            if let current = best, current.overlap >= overlap {
                continue
            }
            best = (candidate.uuid, overlap)
        }
        return best?.uuid
    }

    // MARK: - Adaptadores de callback

    /// Espera um método do `HKWorkoutBuilder` que responde `(Bool, Error?)`.
    private static func awaitCompletion(
        _ operation: (@escaping @Sendable (Bool, (any Error)?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            operation { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? HealthKitServiceError.saveFailed(
                        underlying: "HealthKit reported failure without an error"
                    ))
                }
            }
        }
    }

    // MARK: - Consultas

    /// Treino que este app já gravou para a sessão, achado pela `HKMetadataKeyExternalUUID`.
    private func ownWorkoutUUID(forSession sessionUUID: UUID) async throws -> UUID? {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [sessionUUID.uuidString]
        )
        let ownBundleID = Bundle.main.bundleIdentifier
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UUID?, any Error>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let match = (samples ?? []).first { sample in
                    sample.sourceRevision.source.bundleIdentifier == ownBundleID
                }
                continuation.resume(returning: match?.uuid)
            }
            store.execute(query)
        }
    }

    /// Quantidade de amostras de FC; zero também quando a leitura foi negada.
    private func heartRateSampleCount(matching predicate: NSPredicate) async throws -> Int {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, any Error>) in
            let query = HKSampleQuery(
                sampleType: HKQuantityType(.heartRate),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.count ?? 0)
            }
            store.execute(query)
        }
    }

    /// Média e máxima discretas em batimentos por minuto. "Sem dados" do HealthKit vira `nil`.
    private func heartRateStatistics(matching predicate: NSPredicate, sampleCount: Int) async throws -> HeartRateSummary? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HeartRateSummary?, any Error>) in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.heartRate),
                quantitySamplePredicate: predicate,
                options: [.discreteAverage, .discreteMax]
            ) { _, statistics, error in
                if let error {
                    if let healthKitError = error as? HKError, healthKitError.code == .errorNoData {
                        continuation.resume(returning: nil)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                // Converte aqui dentro: só valores `Sendable` atravessam a continuation.
                let beatsPerMinute = HKUnit.count().unitDivided(by: HKUnit.minute())
                guard
                    let average = statistics?.averageQuantity()?.doubleValue(for: beatsPerMinute),
                    let maximum = statistics?.maximumQuantity()?.doubleValue(for: beatsPerMinute)
                else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: HeartRateSummary(
                    averageBPM: average,
                    maxBPM: maximum,
                    sampleCount: sampleCount
                ))
            }
            store.execute(query)
        }
    }
}
