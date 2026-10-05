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

    // 2.4 (F5, F7) — também com padrão na extensão. Quem implementa usa EXATAMENTE estas assinaturas:
    // com outro rótulo ou tipo, o Swift usa o padrão em silêncio.
    func saveWorkout(_ kind: WorkoutRecordKind, start: Date, end: Date, sessionUUID: UUID) async throws -> UUID
    func findOverlappingWorkout(_ kind: WorkoutRecordKind, start: Date, end: Date) async throws -> UUID?
    func heartRateMinutes(start: Date, end: Date) async throws -> [Double]
}

// MARK: - M2 (contrato; T2.1)

extension HealthKitServicing {
    /// UUID de um treino de força gravado por OUTRO app (ex.: app Exercício do Watch) que cobre
    /// ≥ 50 % de `[start, end]` (SPEC RF-13). O gravador vincula esse treino em vez de criar outro.
    /// `nil` se não houver. Implementação padrão devolve `nil` (fakes antigos).
    func findOverlappingStrengthWorkout(start: Date, end: Date) async throws -> UUID? { nil }

    /// Apaga o treino que ESTE app gravou para a sessão (achado pela `HKMetadataKeyExternalUUID`,
    /// seja de força ou aeróbico: a consulta não olha o tipo). Termina sem erro quando não há treino
    /// deste app para a sessão: na volta, nenhum treino deste app sobrou para ela. Usado só na
    /// reconciliação, quando o treino do app Exercício chegou depois e o do iPhone virou duplicata
    /// (RF-13: um treino por sessão). O HealthKit nunca deixa apagar dados de outros apps.
    /// Implementação padrão lança `.unavailable`: sem apagar, o gravador mantém o vínculo que já tinha.
    func removeOwnStrengthWorkout(sessionUUID: UUID) async throws {
        throw HealthKitServiceError.unavailable
    }
}

// MARK: - 2.4 (contrato; T10.4)

extension HealthKitServicing {
    /// Grava o treino do tipo `kind` e devolve o `HKWorkout.uuid` (SPEC RF-13, F5). Padrão: grava um
    /// treino de força, como antes da 2.4 (fakes antigos).
    func saveWorkout(_ kind: WorkoutRecordKind, start: Date, end: Date, sessionUUID: UUID) async throws -> UUID {
        try await saveStrengthWorkout(start: start, end: end, sessionUUID: sessionUUID)
    }

    /// UUID de um treino de OUTRO app do mesmo tipo que cobre ≥ 50 % de `[start, end]` (RF-13): força
    /// vincula com força; aeróbico vincula com qualquer treino aeróbico. Padrão: força usa
    /// `findOverlappingStrengthWorkout` e aeróbico devolve `nil` (fakes antigos).
    func findOverlappingWorkout(_ kind: WorkoutRecordKind, start: Date, end: Date) async throws -> UUID? {
        switch kind {
        case .strength:
            return try await findOverlappingStrengthWorkout(start: start, end: end)
        case .aerobic, .jumpRope:
            return nil
        }
    }

    /// FC média de cada minuto de `[start, end]`, em bpm, na ordem do tempo; minuto sem leitura fica
    /// de fora (F7). Só leitura, só para exibição (SPEC P12). Padrão: lista vazia (sem FC).
    func heartRateMinutes(start: Date, end: Date) async throws -> [Double] { [] }
}
