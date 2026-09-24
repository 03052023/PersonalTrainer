import Foundation

/// Fronteira com o HealthKit (ARCHITECTURE §8). Implementações: `FakeHealthKitService`
/// (simulador, previews, testes) e `LiveHealthKitService` (T2.1, a única que importa o framework).
///
/// - `Sendable` porque o serviço é injetado pelo `AppEnvironment` e chamado de tarefas
///   assíncronas; cada implementação protege o próprio estado.
/// - Nenhuma falha aqui pode interromper a sessão (AGENTS §4): quem chama trata o erro
///   e segue sem FC, exibindo "FC indisponível" (ARCHITECTURE §15).
/// - Autorização só é pedida na primeira ação que precisa dela (AGENTS §7), nunca no launch.
protocol HealthKitServicing: Sendable {
    /// `false` em simulador e iPad (`HKHealthStore.isHealthDataAvailable()`). Com `false`,
    /// os demais métodos lançam `HealthKitServiceError.unavailable`.
    var isAvailable: Bool { get }

    /// Pede escrita de treinos e leitura de frequência cardíaca.
    /// Lança `HealthKitServiceError.notAuthorized` quando a escrita é negada.
    func requestAuthorization() async throws

    /// Grava um `HKWorkout` de musculação e devolve o `HKWorkout.uuid`, que o
    /// `SessionCoordinator` guarda em `hkWorkoutUUID` (invariante: um treino por sessão).
    /// `sessionUUID` vai em `HKMetadataKeyExternalUUID` para reconciliar duplicatas.
    func saveStrengthWorkout(start: Date, end: Date, sessionUUID: UUID) async throws -> UUID

    /// Resume as amostras de FC em `[start, end]`. Devolve `nil` quando não há amostras
    /// ou quando a leitura foi negada: o sistema não distingue os dois casos.
    func heartRateSummary(start: Date, end: Date) async throws -> HeartRateSummary?

    // M2 — requisitos para despacho dinâmico; padrões na extensão abaixo.
    func findOverlappingStrengthWorkout(start: Date, end: Date) async throws -> UUID?
    func removeOwnStrengthWorkout(sessionUUID: UUID) async throws
}

// MARK: - M2 (contrato; T2.1)

extension HealthKitServicing {
    /// UUID de um treino de força gravado por OUTRO app (ex.: app Exercício do Watch) que cobre
    /// ≥ 50 % de `[start, end]` (SPEC RF-13). O gravador vincula esse treino em vez de criar outro.
    /// `nil` se não houver. Implementação padrão devolve `nil` (fakes antigos).
    func findOverlappingStrengthWorkout(start: Date, end: Date) async throws -> UUID? { nil }

    /// Apaga o treino que ESTE app gravou para a sessão (achado pela `HKMetadataKeyExternalUUID`).
    /// Termina sem erro quando não há treino deste app para a sessão: na volta, nenhum treino deste
    /// app sobrou para ela. Usado só na reconciliação, quando o treino do app Exercício chegou depois
    /// e o do iPhone virou duplicata (RF-13: um treino por sessão). O HealthKit nunca deixa apagar
    /// dados de outros apps. Implementação padrão lança `.unavailable`: sem apagar, o gravador mantém
    /// o vínculo que já tinha.
    func removeOwnStrengthWorkout(sessionUUID: UUID) async throws {
        throw HealthKitServiceError.unavailable
    }
}
