import Foundation
import XCTest
@testable import PersonalTrainer

/// Cobre os fakes de T0.8 (ARCHITECTURE §8, §9, §10). Não constrói `ActiveSessionSnapshot`
/// nem `SessionEvent` de propósito: os inicializadores são de T0.7 e ainda não estão
/// fechados; o Noop é exercitado só pelo stream, que basta para provar que nunca emite.
final class FakeServicesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private var end: Date { start.addingTimeInterval(3_600) }

    // MARK: - FakeHealthKitService

    func testHealthKitFake_returnsConfiguredSummaryAndRecordsQuery() async throws {
        let summary = HeartRateSummary(averageBPM: 121, maxBPM: 158, sampleCount: 42)
        let service = FakeHealthKitService(summaryToReturn: summary)

        let result = try await service.heartRateSummary(start: start, end: end)

        XCTAssertEqual(result, summary)
        let queries = await service.heartRateQueries
        XCTAssertEqual(queries, [FakeHealthKitService.HeartRateQuery(start: start, end: end)])
    }

    func testHealthKitFake_returnsNilWhenNoSummaryConfigured() async throws {
        let service = FakeHealthKitService(summaryToReturn: nil)

        let result = try await service.heartRateSummary(start: start, end: end)

        XCTAssertNil(result)
    }

    func testHealthKitFake_summaryCanBeReconfiguredAfterInit() async throws {
        let service = FakeHealthKitService()
        let replacement = HeartRateSummary(averageBPM: 99, maxBPM: 130, sampleCount: 7)

        await service.setSummaryToReturn(replacement)
        let result = try await service.heartRateSummary(start: start, end: end)

        XCTAssertEqual(result, replacement)
    }

    func testHealthKitFake_recordsSavedWorkoutsWithReturnedUUID() async throws {
        let service = FakeHealthKitService()
        let sessionUUID = UUID()
        try await service.requestAuthorization()

        let returned = try await service.saveStrengthWorkout(start: start, end: end, sessionUUID: sessionUUID)
        let returnedAgain = try await service.saveStrengthWorkout(start: start, end: end, sessionUUID: UUID())

        let saved = await service.savedWorkouts
        XCTAssertEqual(saved.count, 2)
        XCTAssertEqual(saved.first?.start, start)
        XCTAssertEqual(saved.first?.end, end)
        XCTAssertEqual(saved.first?.sessionUUID, sessionUUID)
        XCTAssertEqual(saved.first?.returnedUUID, returned)
        XCTAssertNotEqual(returned, returnedAgain, "Cada gravação simula um HKWorkout distinto")
    }

    func testHealthKitFake_authorizationFailureThrowsNotAuthorized() async {
        let service = FakeHealthKitService(shouldFailAuthorization: true)

        do {
            try await service.requestAuthorization()
            XCTFail("Esperava HealthKitServiceError.notAuthorized")
        } catch let error as HealthKitServiceError {
            XCTAssertEqual(error, .notAuthorized)
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }

        let authorized = await service.isAuthorized
        XCTAssertFalse(authorized)
        let requestCount = await service.authorizationRequestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testHealthKitFake_authorizationSucceedsAfterFailureIsCleared() async throws {
        let service = FakeHealthKitService(shouldFailAuthorization: true)

        await service.setShouldFailAuthorization(false)
        try await service.requestAuthorization()

        let authorized = await service.isAuthorized
        XCTAssertTrue(authorized)
    }

    func testHealthKitFake_saveWithoutAuthorizationThrowsNotAuthorized() async {
        let service = FakeHealthKitService()

        do {
            _ = try await service.saveStrengthWorkout(start: start, end: end, sessionUUID: UUID())
            XCTFail("Esperava HealthKitServiceError.notAuthorized")
        } catch let error as HealthKitServiceError {
            XCTAssertEqual(error, .notAuthorized)
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }

        let saved = await service.savedWorkouts
        XCTAssertTrue(saved.isEmpty)
    }

    func testHealthKitFake_saveWithEndBeforeStartThrowsSaveFailed() async throws {
        let service = FakeHealthKitService()
        try await service.requestAuthorization()

        do {
            _ = try await service.saveStrengthWorkout(start: end, end: start, sessionUUID: UUID())
            XCTFail("Esperava HealthKitServiceError.saveFailed")
        } catch let error as HealthKitServiceError {
            XCTAssertEqual(error, .saveFailed(underlying: "end precedes start"))
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }

    func testHealthKitFake_unavailableThrowsUnavailableEverywhere() async {
        let service = FakeHealthKitService(isAvailable: false)
        XCTAssertFalse(service.isAvailable)

        do {
            try await service.requestAuthorization()
            XCTFail("Esperava HealthKitServiceError.unavailable")
        } catch let error as HealthKitServiceError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }

        do {
            _ = try await service.heartRateSummary(start: start, end: end)
            XCTFail("Esperava HealthKitServiceError.unavailable")
        } catch let error as HealthKitServiceError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }

        let requestCount = await service.authorizationRequestCount
        XCTAssertEqual(requestCount, 0, "Sem HealthKit a chamada nem chega ao registro")
    }

    // MARK: - NoopWatchSyncService

    func testNoopWatchSync_isNotSupportedAndNeverEmits() async {
        let service = NoopWatchSyncService()
        XCTAssertFalse(service.isSupported)
        XCTAssertFalse(service.isReachable)

        let collector = Task { () -> Int in
            var received = 0
            for await _ in service.incomingEvents {
                received += 1
            }
            return received
        }

        service.finish()
        let received = await collector.value

        XCTAssertEqual(received, 0)
    }

    func testNoopWatchSync_finishIsIdempotent() async {
        let service = NoopWatchSyncService()

        service.finish()
        service.finish()

        var received = 0
        for await _ in service.incomingEvents {
            received += 1
        }
        XCTAssertEqual(received, 0)
    }

    // MARK: - FakeNotificationScheduler

    func testNotificationFake_recordsScheduleAndCancel() async {
        let scheduler = FakeNotificationScheduler()
        let fireDate = start.addingTimeInterval(120)
        let request = FakeNotificationScheduler.ScheduledRequest(
            fireDate: fireDate,
            identifier: "rest-timer",
            body: "Descanso terminou"
        )

        await scheduler.scheduleRestTimerEnd(at: fireDate, identifier: "rest-timer", body: "Descanso terminou")
        let pendingAfterSchedule = await scheduler.pendingRequests
        XCTAssertEqual(pendingAfterSchedule, [request])

        await scheduler.cancel(identifier: "rest-timer")
        let pendingAfterCancel = await scheduler.pendingRequests
        XCTAssertTrue(pendingAfterCancel.isEmpty)

        let scheduled = await scheduler.scheduledRequests
        XCTAssertEqual(scheduled, [request], "O log de agendamentos não é apagado pelo cancel")
        let cancelled = await scheduler.cancelledIdentifiers
        XCTAssertEqual(cancelled, ["rest-timer"])
    }

    func testNotificationFake_reschedulingSameIdentifierReplacesPending() async {
        let scheduler = FakeNotificationScheduler()
        let firstFireDate = start.addingTimeInterval(90)
        let secondFireDate = start.addingTimeInterval(120)

        await scheduler.scheduleRestTimerEnd(at: firstFireDate, identifier: "rest-timer", body: "Descanso terminou")
        await scheduler.scheduleRestTimerEnd(at: secondFireDate, identifier: "rest-timer", body: "Descanso terminou")

        let pending = await scheduler.pendingRequests
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.fireDate, secondFireDate)
        let scheduled = await scheduler.scheduledRequests
        XCTAssertEqual(scheduled.count, 2)
    }

    func testNotificationFake_cancelUnknownIdentifierIsRecordedAndHarmless() async {
        let scheduler = FakeNotificationScheduler()

        await scheduler.cancel(identifier: "nothing-here")

        let cancelled = await scheduler.cancelledIdentifiers
        XCTAssertEqual(cancelled, ["nothing-here"])
        let pending = await scheduler.pendingRequests
        XCTAssertTrue(pending.isEmpty)
    }

    func testNotificationFake_authorizationHonoursConfiguration() async {
        let scheduler = FakeNotificationScheduler(authorizationToGrant: false)

        let denied = await scheduler.requestAuthorization()
        XCTAssertFalse(denied)

        await scheduler.setAuthorizationToGrant(true)
        let granted = await scheduler.requestAuthorization()
        XCTAssertTrue(granted)

        let requestCount = await scheduler.authorizationRequestCount
        XCTAssertEqual(requestCount, 2)
    }
}
