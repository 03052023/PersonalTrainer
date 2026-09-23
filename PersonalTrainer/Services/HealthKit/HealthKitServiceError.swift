import Foundation

/// Erros do `HealthKitServicing`. Os casos de falha carregam a descrição do erro
/// original como `String`, e não como `any Error`, para manter o enum `Sendable` e
/// `Equatable`: dá para comparar em testes e atravessar fronteiras de isolamento.
enum HealthKitServiceError: Error, Sendable, Equatable {
    /// HealthKit não existe neste aparelho (simulador, iPad).
    case unavailable
    /// Escrita negada ou ainda não concedida.
    case notAuthorized
    /// `HKWorkoutBuilder`/`HKHealthStore.save` falhou.
    case saveFailed(underlying: String)
    /// A consulta de amostras falhou.
    case queryFailed(underlying: String)
}
