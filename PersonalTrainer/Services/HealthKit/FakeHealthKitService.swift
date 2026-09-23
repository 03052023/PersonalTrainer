import Foundation

/// Implementação em memória do `HealthKitServicing` (ARCHITECTURE §8): roda no simulador,
/// nos previews e nos testes; devolve FC sintética e registra cada chamada para asserções.
///
/// Isolamento: o estado mutável fica num `actor` interno em vez de marcar a classe
/// `@MainActor`. Assim o fake tem a mesma forma de isolamento que `LiveHealthKitService`
/// terá (tipo `Sendable` não isolado, chamável de qualquer executor, já que o
/// `HKHealthStore` responde em filas de fundo), `@MainActor` fica reservado para SwiftData
/// e UI (ARCHITECTURE §10) e os testes não precisam ser `@MainActor` para ler os registros.
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

    /// FC sintética padrão, plausível para uma sessão de musculação de cerca de 60 min.
    static let syntheticSummary = HeartRateSummary(averageBPM: 118, maxBPM: 152, sampleCount: 90)

    let isAvailable: Bool

    private let state: State

    /// - Parameters:
    ///   - isAvailable: `false` simula simulador/iPad: todos os métodos lançam `.unavailable`.
    ///   - shouldFailAuthorization: `true` faz `requestAuthorization()` lançar `.notAuthorized`.
    ///   - summaryToReturn: resposta de `heartRateSummary`; `nil` simula "sem amostras"
    ///     ou "leitura negada" (ARCHITECTURE §15 trata os dois igual).
    init(
        isAvailable: Bool = true,
        shouldFailAuthorization: Bool = false,
        summaryToReturn: HeartRateSummary? = FakeHealthKitService.syntheticSummary
    ) {
        self.isAvailable = isAvailable
        self.state = State(
            shouldFailAuthorization: shouldFailAuthorization,
            summaryToReturn: summaryToReturn
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

    func setShouldFailAuthorization(_ shouldFail: Bool) async {
        await state.setShouldFailAuthorization(shouldFail)
    }

    func setSummaryToReturn(_ summary: HeartRateSummary?) async {
        await state.setSummaryToReturn(summary)
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

    // MARK: Estado protegido

    private actor State {
        private(set) var shouldFailAuthorization: Bool
        private(set) var summaryToReturn: HeartRateSummary?
        private(set) var isAuthorized = false
        private(set) var authorizationRequestCount = 0
        private(set) var savedWorkouts: [SavedWorkout] = []
        private(set) var heartRateQueries: [HeartRateQuery] = []

        init(shouldFailAuthorization: Bool, summaryToReturn: HeartRateSummary?) {
            self.shouldFailAuthorization = shouldFailAuthorization
            self.summaryToReturn = summaryToReturn
        }

        func setShouldFailAuthorization(_ shouldFail: Bool) {
            shouldFailAuthorization = shouldFail
        }

        func setSummaryToReturn(_ summary: HeartRateSummary?) {
            summaryToReturn = summary
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
    }
}
