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
    /// Uma chamada a `saveWorkout` (ou `saveStrengthWorkout`) e o UUID devolvido por ela.
    struct SavedWorkout: Sendable, Hashable {
        let start: Date
        let end: Date
        let sessionUUID: UUID
        let returnedUUID: UUID
        /// O tipo pedido; `saveStrengthWorkout` grava `.strength`.
        let kind: WorkoutRecordKind

        init(start: Date, end: Date, sessionUUID: UUID, returnedUUID: UUID, kind: WorkoutRecordKind = .strength) {
            self.start = start
            self.end = end
            self.sessionUUID = sessionUUID
            self.returnedUUID = returnedUUID
            self.kind = kind
        }
    }

    /// Uma chamada a `heartRateSummary(start:end:)` ou a `heartRateMinutes(start:end:)`.
    struct HeartRateQuery: Sendable, Hashable {
        let start: Date
        let end: Date
    }

    /// Uma chamada a `findOverlappingWorkout` (ou a `findOverlappingStrengthWorkout`).
    struct OverlapQuery: Sendable, Hashable {
        let start: Date
        let end: Date
        /// O tipo pedido; `findOverlappingStrengthWorkout` consulta `.strength`.
        let kind: WorkoutRecordKind

        init(start: Date, end: Date, kind: WorkoutRecordKind = .strength) {
            self.start = start
            self.end = end
            self.kind = kind
        }
    }

    /// FC sintética padrão, plausível para uma sessão de musculação de cerca de 60 min.
    static let syntheticSummary = HeartRateSummary(averageBPM: 118, maxBPM: 152, sampleCount: 90)

    /// FC por minuto sintética e determinística para `[start, end]`: três minutos de aquecimento e
    /// depois uma oscilação pequena entre 118 e 138 bpm, um valor por minuto inteiro do intervalo
    /// (no máximo 600). Intervalo menor que 1 min dá lista vazia.
    static func syntheticMinuteHeartRates(start: Date, end: Date) -> [Double] {
        let seconds = end.timeIntervalSince(start)
        guard seconds.isFinite, seconds >= 60 else {
            return []
        }
        let minutes = Int(min(seconds / 60, 600))
        var values: [Double] = []
        values.reserveCapacity(minutes)
        for minute in 0..<minutes {
            if minute < 3 {
                values.append(Double(100 + 8 * minute))
            } else {
                let swing = (minute % 6) * 4
                values.append(Double(118 + swing))
            }
        }
        return values
    }

    let isAvailable: Bool

    private let state: State

    /// - Parameters:
    ///   - isAvailable: `false` simula simulador/iPad: todos os métodos lançam `.unavailable`.
    ///   - shouldFailAuthorization: `true` faz `requestAuthorization()` lançar `.notAuthorized`.
    ///   - summaryToReturn: resposta de `heartRateSummary`; `nil` simula "sem amostras"
    ///     ou "leitura negada" (ARCHITECTURE §15 trata os dois igual).
    ///   - overlappingWorkoutToReturn: resposta de `findOverlappingWorkout(.strength, …)`; um UUID
    ///     simula um treino de força de outro app (ex.: app Exercício do Watch) cobrindo
    ///     ≥ 50 % da sessão (SPEC RF-13). `nil` (padrão) = nenhum treino para vincular.
    ///   - overlappingAerobicWorkoutToReturn: o mesmo para o aeróbico (`.aerobic` e `.jumpRope`),
    ///     que não enxerga o treino de força acima (F5: o vínculo é pelo mesmo tipo).
    ///   - minuteHeartRatesToReturn: resposta de `heartRateMinutes`; `nil` (padrão) devolve a série
    ///     sintética de `syntheticMinuteHeartRates`, e uma lista vazia simula "sem FC" (F7).
    init(
        isAvailable: Bool = true,
        shouldFailAuthorization: Bool = false,
        summaryToReturn: HeartRateSummary? = FakeHealthKitService.syntheticSummary,
        overlappingWorkoutToReturn: UUID? = nil,
        overlappingAerobicWorkoutToReturn: UUID? = nil,
        minuteHeartRatesToReturn: [Double]? = nil
    ) {
        self.isAvailable = isAvailable
        self.state = State(
            shouldFailAuthorization: shouldFailAuthorization,
            summaryToReturn: summaryToReturn,
            overlappingWorkoutToReturn: overlappingWorkoutToReturn,
            overlappingAerobicWorkoutToReturn: overlappingAerobicWorkoutToReturn,
            minuteHeartRatesToReturn: minuteHeartRatesToReturn
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

    /// Intervalos consultados em `heartRateMinutes`, na ordem das chamadas.
    var heartRateMinuteQueries: [HeartRateQuery] {
        get async { await state.heartRateMinuteQueries }
    }

    /// Consultas de treino sobreposto (`findOverlappingWorkout` e `findOverlappingStrengthWorkout`),
    /// na ordem das chamadas.
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

    func setOverlappingAerobicWorkoutToReturn(_ workoutUUID: UUID?) async {
        await state.setOverlappingAerobicWorkoutToReturn(workoutUUID)
    }

    func setMinuteHeartRatesToReturn(_ minutes: [Double]?) async {
        await state.setMinuteHeartRatesToReturn(minutes)
    }

    /// `true` faz `saveStrengthWorkout` e `saveWorkout` lançarem `.saveFailed` (ex.: builder inválido).
    func setShouldFailSave(_ shouldFail: Bool) async {
        await state.setShouldFailSave(shouldFail)
    }

    /// `true` faz `findOverlappingStrengthWorkout` e `findOverlappingWorkout` lançarem `.queryFailed`
    /// (ex.: banco do Saúde inacessível com o aparelho bloqueado).
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
        try await saveWorkout(.strength, start: start, end: end, sessionUUID: sessionUUID)
    }

    func saveWorkout(_ kind: WorkoutRecordKind, start: Date, end: Date, sessionUUID: UUID) async throws -> UUID {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        return try await state.saveWorkout(kind, start: start, end: end, sessionUUID: sessionUUID)
    }

    func heartRateSummary(start: Date, end: Date) async throws -> HeartRateSummary? {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        return await state.heartRateSummary(start: start, end: end)
    }

    func heartRateMinutes(start: Date, end: Date) async throws -> [Double] {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        return await state.heartRateMinutes(start: start, end: end)
    }

    func findOverlappingStrengthWorkout(start: Date, end: Date) async throws -> UUID? {
        try await findOverlappingWorkout(.strength, start: start, end: end)
    }

    func findOverlappingWorkout(_ kind: WorkoutRecordKind, start: Date, end: Date) async throws -> UUID? {
        guard isAvailable else {
            throw HealthKitServiceError.unavailable
        }
        return try await state.findOverlappingWorkout(kind, start: start, end: end)
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
        private(set) var overlappingAerobicWorkoutToReturn: UUID?
        private(set) var minuteHeartRatesToReturn: [Double]?
        private(set) var shouldFailSave = false
        private(set) var shouldFailOverlapQuery = false
        private(set) var isAuthorized = false
        private(set) var authorizationRequestCount = 0
        private(set) var savedWorkouts: [SavedWorkout] = []
        private(set) var heartRateQueries: [HeartRateQuery] = []
        private(set) var heartRateMinuteQueries: [HeartRateQuery] = []
        private(set) var overlapQueries: [OverlapQuery] = []
        private(set) var removedWorkoutSessions: [UUID] = []

        init(
            shouldFailAuthorization: Bool,
            summaryToReturn: HeartRateSummary?,
            overlappingWorkoutToReturn: UUID?,
            overlappingAerobicWorkoutToReturn: UUID?,
            minuteHeartRatesToReturn: [Double]?
        ) {
            self.shouldFailAuthorization = shouldFailAuthorization
            self.summaryToReturn = summaryToReturn
            self.overlappingWorkoutToReturn = overlappingWorkoutToReturn
            self.overlappingAerobicWorkoutToReturn = overlappingAerobicWorkoutToReturn
            self.minuteHeartRatesToReturn = minuteHeartRatesToReturn
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

        func setOverlappingAerobicWorkoutToReturn(_ workoutUUID: UUID?) {
            overlappingAerobicWorkoutToReturn = workoutUUID
        }

        func setMinuteHeartRatesToReturn(_ minutes: [Double]?) {
            minuteHeartRatesToReturn = minutes
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
        func saveWorkout(_ kind: WorkoutRecordKind, start: Date, end: Date, sessionUUID: UUID) throws -> UUID {
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
                SavedWorkout(start: start, end: end, sessionUUID: sessionUUID, returnedUUID: returnedUUID, kind: kind)
            )
            return returnedUUID
        }

        /// Não exige autorização: o status de leitura é opaco no HealthKit real
        /// (ARCHITECTURE §15); `summaryToReturn == nil` cobre "negado" e "sem amostras".
        func heartRateSummary(start: Date, end: Date) -> HeartRateSummary? {
            heartRateQueries.append(HeartRateQuery(start: start, end: end))
            return summaryToReturn
        }

        /// Também é leitura, sem autorização. Sem configuração, a série sintética do intervalo.
        func heartRateMinutes(start: Date, end: Date) -> [Double] {
            heartRateMinuteQueries.append(HeartRateQuery(start: start, end: end))
            if let configured = minuteHeartRatesToReturn {
                return configured
            }
            return FakeHealthKitService.syntheticMinuteHeartRates(start: start, end: end)
        }

        /// Também é leitura: não exige autorização, pelo mesmo motivo de `heartRateSummary`
        /// (com leitura negada o HealthKit real devolve lista vazia, ou seja, `nil` aqui). O treino
        /// de força e o aeróbico têm respostas separadas: o vínculo é pelo mesmo tipo (RF-13).
        func findOverlappingWorkout(_ kind: WorkoutRecordKind, start: Date, end: Date) throws -> UUID? {
            overlapQueries.append(OverlapQuery(start: start, end: end, kind: kind))
            guard !shouldFailOverlapQuery else {
                throw HealthKitServiceError.queryFailed(underlying: "fake overlap query failure")
            }
            switch kind {
            case .strength:
                return overlappingWorkoutToReturn
            case .aerobic, .jumpRope:
                return overlappingAerobicWorkoutToReturn
            }
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
