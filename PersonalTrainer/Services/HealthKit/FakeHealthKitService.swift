import Foundation

/// Implementação em memória do `HealthKitServicing` (ARCHITECTURE §8): roda no simulador,
/// nos previews e nos testes; devolve FC sintética e registra cada chamada para asserções.
///
/// Isolamento: o estado mutável fica num `actor` interno em vez de marcar a classe
/// `@MainActor`. Assim o fake tem a mesma forma de isolamento que `LiveHealthKitService`
/// (tipo `Sendable` não isolado, chamável de qualquer executor, já que o `HKHealthStore`
/// responde em filas de fundo), `@MainActor` fica reservado para SwiftData e UI
/// (ARCHITECTURE §10) e os testes não precisam ser `@MainActor` para ler os registros.
/// O custo é que configuração posterior e leitura de registros são `async`; a configuração
/// inicial continua síncrona no `init`, o que basta para previews e `AppEnvironment`.
final class FakeHealthKitService: HealthKitServicing {
    /// Uma chamada a `saveStrengthWorkout` e o UUID devolvido por ela.
    struct SavedWorkout: Sendable, Hashable {
        let start: Date
        let end: Date
        let sessionUUID: UUID
        let returnedUUID: UUID
    }

    /// Uma chamada a `heartRateSummary(start:end:)`.
    struct HeartRateQuery: Sendable, Hashable {
        let start: Date
        let end: Date
    }

    /// Uma chamada a `findOverlappingStrengthWorkout(start:end:)`.
    struct OverlapQuery: Sendable, Hashable {
        let start: Date
        let end: Date
    }

    /// FC sintética padrão, plausível para uma sessão de musculação de cerca de 60 min.
    static let syntheticSummary = HeartRateSummary(averageBPM: 118, maxBPM: 152, sampleCount: 90)

    let isAvailable: Bool

    private let state: State

    /// - Parameters:
    ///   - isAvailable: `false` simula simulador/iPad: todos os métodos lançam `.unavailable`.
    ///   - shouldFailAuthorization: `true` faz `requestAuthorization()` lançar `.notAuthorized`.
    ///   - summaryToReturn: resposta de `heartRateSummary`; `nil` simula "sem amostras"
    ///     ou "leitura negada" (ARCHITECTURE §15 trata os dois igual).
    ///   - overlappingWorkoutToReturn: resposta de `findOverlappingStrengthWorkout`; um UUID
    ///     simula um treino de força de outro app (ex.: app Exercício do Watch) cobrindo
    ///     ≥ 50 % da sessão (SPEC RF-13). `nil` (padrão) = nenhum treino para vincular.
    init(
        isAvailable: Bool = true,
        shouldFailAuthorization: Bool = false,
        summaryToReturn: HeartRateSummary? = FakeHealthKitService.syntheticSummary,
        overlappingWorkoutToReturn: UUID? = nil
    ) {
        self.isAvailable = isAvailable
        self.state = State(
            shouldFailAuthorization: shouldFailAuthorization,
            summaryToReturn: summaryToReturn,
            overlappingWorkoutToReturn: overlappingWorkoutToReturn
        )
    }

    // MARK: Registros e configuração (testes e previews)

    /// `true` depois de um `requestAuthorization()` bem-sucedido.
    var isAuthorized: Bool {
        get async { await state.isAuthorized }
    }

    /// Quantas vezes `requestAuthorization()` chegou ao serviço com HealthKit disponível.
    var authorizationRequestCount: Int {
        get async { await state.authorizationRequestCount }
    }

    /// Treinos gravados, na ordem das chamadas.
    var savedWorkouts: [SavedWorkout] {
        get async { await state.savedWorkouts }
    }

    /// Intervalos consultados em `heartRateSummary`, na ordem das chamadas.
    var heartRateQueries: [HeartRateQuery] {
        get async { await state.heartRateQueries }
    }

    /// Intervalos consultados em `findOverlappingStrengthWorkout`, na ordem das chamadas.
    var overlapQueries: [OverlapQuery] {
        get async { await state.overlapQueries }
    }

    /// Sessões cujo treino deste app foi apagado por `removeOwnStrengthWorkout`, na ordem das
    /// chamadas bem-sucedidas. `savedWorkouts` continua sendo o registro das gravações.
    var removedWorkoutSessions: [UUID] {
        get async { await state.removedWorkoutSessions }
    }

    func setShouldFailAuthorization(_ shouldFail: Bool) async {
        await state.setShouldFailAuthorization(shouldFail)
    }

    func setSummaryToReturn(_ summary: HeartRateSummary?) async {
        await state.setSummaryToReturn(summary)
    }

    func setOverlappingWorkoutToReturn(_ workoutUUID: UUID?) async {
        await state.setOverlappingWorkoutToReturn(workoutUUID)
    }

    /// `true` faz `saveStrengthWorkout` lançar `.saveFailed` (ex.: builder inválido).
    func setShouldFailSave(_ shouldFail: Bool) async {
        await state.setShouldFailSave(shouldFail)
    }

    /// `true` faz `findOverlappingStrengthWorkout` lançar `.queryFailed` (ex.: banco do Saúde
    /// inacessível com o aparelho bloqueado).
    func setShouldFailOverlapQuery(_ shouldFail: Bool) async {
        await state.setShouldFailOverlapQuery(shouldFail)
    }

    // MARK: HealthKitServicing

    func requestAuthorization() async throws {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        try await state.requestAuthorization()
    }

    func saveStrengthWorkout(start: Date, end: Date, sessionUUID: UUID) async throws -> UUID {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        return try await state.saveStrengthWorkout(start: start, end: end, sessionUUID: sessionUUID)
    }

    func heartRateSummary(start: Date, end: Date) async throws -> HeartRateSummary? {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        return await state.heartRateSummary(start: start, end: end)
    }

    func findOverlappingStrengthWorkout(start: Date, end: Date) async throws -> UUID? {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        return try await state.findOverlappingStrengthWorkout(start: start, end: end)
    }

    func removeOwnStrengthWorkout(sessionUUID: UUID) async throws {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        try await state.removeOwnStrengthWorkout(sessionUUID: sessionUUID)
    }

    // MARK: Estado protegido

    private actor State {
        private(set) var shouldFailAuthorization: Bool
        private(set) var summaryToReturn: HeartRateSummary?
        private(set) var overlappingWorkoutToReturn: UUID?
        private(set) var shouldFailSave = false
        private(set) var shouldFailOverlapQuery = false
        private(set) var isAuthorized = false
        private(set) var authorizationRequestCount = 0
        private(set) var savedWorkouts: [SavedWorkout] = []
        private(set) var heartRateQueries: [HeartRateQuery] = []
        private(set) var overlapQueries: [OverlapQuery] = []
        private(set) var removedWorkoutSessions: [UUID] = []

        init(shouldFailAuthorization: Bool, summaryToReturn: HeartRateSummary?, overlappingWorkoutToReturn: UUID?) {
            self.shouldFailAuthorization = shouldFailAuthorization
            self.summaryToReturn = summaryToReturn
            self.overlappingWorkoutToReturn = overlappingWorkoutToReturn
        }

        func setShouldFailAuthorization(_ shouldFail: Bool) {
            shouldFailAuthorization = shouldFail
        }

        func setSummaryToReturn(_ summary: HeartRateSummary?) {
            summaryToReturn = summary
        }

        func setOverlappingWorkoutToReturn(_ workoutUUID: UUID?) {
            overlappingWorkoutToReturn = workoutUUID
        }

        func setShouldFailSave(_ shouldFail: Bool) {
            shouldFailSave = shouldFail
        }

        func setShouldFailOverlapQuery(_ shouldFail: Bool) {
            shouldFailOverlapQuery = shouldFail
        }

        func requestAuthorization() throws {
            authorizationRequestCount += 1
            if shouldFailAuthorization {
                throw HealthKitServiceError.notAuthorized
            }
            isAuthorized = true
        }

        /// Exige autorização prévia, como o HealthKit real: um gravador que esquecer
        /// `requestAuthorization()` falha já no simulador, não só no aparelho.
        func saveStrengthWorkout(start: Date, end: Date, sessionUUID: UUID) throws -> UUID {
            guard isAuthorized else {
                throw HealthKitServiceError.notAuthorized
            }
            guard !shouldFailSave else {
                throw HealthKitServiceError.saveFailed(underlying: "fake save failure")
            }
            guard end >= start else {
                throw HealthKitServiceError.saveFailed(underlying: "end precedes start")
            }
            let returnedUUID = UUID()
            savedWorkouts.append(
                SavedWorkout(start: start, end: end, sessionUUID: sessionUUID, returnedUUID: returnedUUID)
            )
            return returnedUUID
        }

        /// Não exige autorização: o status de leitura é opaco no HealthKit real
        /// (ARCHITECTURE §15); `summaryToReturn == nil` cobre "negado" e "sem amostras".
        func heartRateSummary(start: Date, end: Date) -> HeartRateSummary? {
            heartRateQueries.append(HeartRateQuery(start: start, end: end))
            return summaryToReturn
        }

        /// Também é leitura: não exige autorização, pelo mesmo motivo de `heartRateSummary`
        /// (com leitura negada o HealthKit real devolve lista vazia, ou seja, `nil` aqui).
        func findOverlappingStrengthWorkout(start: Date, end: Date) throws -> UUID? {
            overlapQueries.append(OverlapQuery(start: start, end: end))
            guard !shouldFailOverlapQuery else {
                throw HealthKitServiceError.queryFailed(underlying: "fake overlap query failure")
            }
            return overlappingWorkoutToReturn
        }

        /// Escrita, como no HealthKit real: exige autorização prévia.
        func removeOwnStrengthWorkout(sessionUUID: UUID) throws {
            guard isAuthorized else {
                throw HealthKitServiceError.notAuthorized
            }
            removedWorkoutSessions.append(sessionUUID)
        }
    }
}
