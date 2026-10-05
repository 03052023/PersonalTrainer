import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T2.1/T2.2: `HealthKitWorkoutRecorder` leva a sessão finalizada ao Saúde (ARCHITECTURE §8;
/// SPEC RF-13, RF-14). `FakeHealthKitService` no lugar do HealthKit e `SessionCoordinator` real sobre
/// container in-memory, tudo em `@MainActor` (ARCHITECTURE §10). Os testes chamam `process(_:)` e
/// aguardam o fim; os de `start()` esperam o `heartRateSummary` publicado no stream, sem `Task.sleep`.
/// Também cobre a regra pura de sobreposição ≥ 50 % de `LiveHealthKitService` (RF-13).
@MainActor
final class HealthKitWorkoutRecorderTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private var endedAt: Date { startedAt.addingTimeInterval(3_600) }

    // MARK: - Gravar ou vincular (RF-13)

    func testRF13_noOverlappingWorkout_savesWorkoutAndStoresHeartRate() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.start, startedAt, "Início real da sessão")
        XCTAssertEqual(saved.first?.end, endedAt, "Fim real da sessão")
        XCTAssertEqual(saved.first?.sessionUUID, sessionID)
        let overlapQueries = await healthKit.overlapQueries
        XCTAssertEqual(overlapQueries, [FakeHealthKitService.OverlapQuery(start: startedAt, end: endedAt)])
        let heartRateQueries = await healthKit.heartRateQueries
        XCTAssertEqual(heartRateQueries, [FakeHealthKitService.HeartRateQuery(start: startedAt, end: endedAt)])

        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.hkWorkoutUUID, saved.first?.returnedUUID)
        XCTAssertEqual(session.avgHeartRate, FakeHealthKitService.syntheticSummary.averageBPM)
        XCTAssertEqual(session.maxHeartRate, FakeHealthKitService.syntheticSummary.maxBPM)
        XCTAssertEqual(session.status, .completed)
    }

    func testRF13_overlappingWorkoutFromAnotherApp_linksInsteadOfSaving() async throws {
        let fixture = try makeFixture()
        let exerciseAppWorkout = UUID()
        let healthKit = FakeHealthKitService(overlappingWorkoutToReturn: exerciseAppWorkout)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertTrue(saved.isEmpty, "Vincula o treino do app Exercício em vez de criar outro")
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.hkWorkoutUUID, exerciseAppWorkout)
        XCTAssertEqual(session.avgHeartRate, FakeHealthKitService.syntheticSummary.averageBPM)
        XCTAssertEqual(session.maxHeartRate, FakeHealthKitService.syntheticSummary.maxBPM)
    }

    func testRF13_sameFinishProcessedTwice_savesOnlyOnce() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)
        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.count, 1, "hkWorkoutUUID é a trava: um HKWorkout por sessão")
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.hkWorkoutUUID, saved.first?.returnedUUID)
    }

    func testRF13_sessionAlreadyHasWorkout_touchesNothing() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let sessionID = try startSession(fixture)
        let watchWorkout = UUID()
        // Resumo com treino já gravado (ex.: relógio na M3) antes do fim da sessão.
        try fixture.coordinator.apply(SessionEvent(
            sessionID: sessionID,
            occurredAt: startedAt,
            source: .watch,
            kind: .heartRateSummary(averageBPM: 125, maxBPM: 160, hkWorkoutUUID: watchWorkout)
        ))
        let finished = try finish(sessionID, fixture)

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertTrue(saved.isEmpty)
        let requestCount = await healthKit.authorizationRequestCount
        XCTAssertEqual(requestCount, 0, "Nem pede autorização quando não há nada a fazer")
        let overlapQueries = await healthKit.overlapQueries
        XCTAssertTrue(overlapQueries.isEmpty)
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.hkWorkoutUUID, watchWorkout)
        XCTAssertEqual(session.avgHeartRate, 125)
        XCTAssertEqual(session.maxHeartRate, 160)
    }

    func testRF13_twoSessions_eachGetsItsOwnWorkoutAndAuthorizationIsAskedOnce() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)

        let (firstID, firstFinished) = try startAndFinishSession(fixture)
        await recorder.process(firstFinished)
        let (secondID, secondFinished) = try startAndFinishSession(fixture)
        await recorder.process(secondFinished)

        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.map { $0.sessionUUID }, [firstID, secondID])
        let requestCount = await healthKit.authorizationRequestCount
        XCTAssertEqual(requestCount, 1, "Autorização memorizada depois do primeiro sucesso")
        let first = try XCTUnwrap(fixture.coordinator.session(withID: firstID))
        let second = try XCTUnwrap(fixture.coordinator.session(withID: secondID))
        XCTAssertEqual(first.hkWorkoutUUID, saved.first?.returnedUUID)
        XCTAssertEqual(second.hkWorkoutUUID, saved.last?.returnedUUID)
        XCTAssertNotEqual(first.hkWorkoutUUID, second.hkWorkoutUUID)
    }

    func testRF13_overlapQueryFails_doesNotSaveButKeepsHeartRate() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        await healthKit.setShouldFailOverlapQuery(true)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertTrue(saved.isEmpty, "Sem saber se o app Exercício já gravou, gravar arriscaria duplicar")
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertNil(session.hkWorkoutUUID)
        XCTAssertEqual(session.avgHeartRate, FakeHealthKitService.syntheticSummary.averageBPM)
    }

    func testAbandonedSession_isNotSentToHealth() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let sessionID = try startSession(fixture)
        let abandoned = SessionEvent(
            sessionID: sessionID,
            occurredAt: endedAt,
            source: .iphone,
            kind: .sessionAbandoned(endedAt: endedAt)
        )
        try fixture.coordinator.apply(abandoned)

        await recorder.process(abandoned)

        let requestCount = await healthKit.authorizationRequestCount
        XCTAssertEqual(requestCount, 0)
        let saved = await healthKit.savedWorkouts
        XCTAssertTrue(saved.isEmpty)
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertNil(session.hkWorkoutUUID)
        XCTAssertNil(session.avgHeartRate)
    }

    // MARK: - Falhas nunca quebram o fluxo

    func testHealthKitUnavailable_doesNothing() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService(isAvailable: false)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        let requestCount = await healthKit.authorizationRequestCount
        XCTAssertEqual(requestCount, 0)
        let overlapQueries = await healthKit.overlapQueries
        XCTAssertTrue(overlapQueries.isEmpty)
        let heartRateQueries = await healthKit.heartRateQueries
        XCTAssertTrue(heartRateQueries.isEmpty)
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertNil(session.hkWorkoutUUID)
        XCTAssertNil(session.avgHeartRate)
        XCTAssertNil(session.maxHeartRate)
        XCTAssertEqual(session.status, .completed)
    }

    func testAuthorizationDenied_doesNotSaveButStillReadsHeartRate() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService(shouldFailAuthorization: true)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertTrue(saved.isEmpty)
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertNil(session.hkWorkoutUUID)
        // Leitura tem status opaco: pode estar liberada mesmo com a escrita negada.
        XCTAssertEqual(session.avgHeartRate, FakeHealthKitService.syntheticSummary.averageBPM)
        XCTAssertEqual(session.status, .completed)
    }

    func testAuthorizationDenied_withoutHeartRate_leavesSessionUntouched() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService(shouldFailAuthorization: true, summaryToReturn: nil)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertNil(session.hkWorkoutUUID)
        XCTAssertNil(session.avgHeartRate, "Continua \"FC indisponível\"")
        XCTAssertNil(session.maxHeartRate)
        XCTAssertEqual(session.status, .completed)
    }

    func testAuthorizationDenied_isAskedAgainOnNextSession() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService(shouldFailAuthorization: true)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (_, firstFinished) = try startAndFinishSession(fixture)
        await recorder.process(firstFinished)

        // O usuário liberou em Ajustes > Saúde entre uma sessão e outra.
        await healthKit.setShouldFailAuthorization(false)
        let (secondID, secondFinished) = try startAndFinishSession(fixture)
        await recorder.process(secondFinished)

        let requestCount = await healthKit.authorizationRequestCount
        XCTAssertEqual(requestCount, 2)
        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.map { $0.sessionUUID }, [secondID])
    }

    func testSaveFails_keepsHeartRateWithoutWorkout() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        await healthKit.setShouldFailSave(true)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertNil(session.hkWorkoutUUID, "Nada gravado: a trava continua livre")
        XCTAssertEqual(session.avgHeartRate, FakeHealthKitService.syntheticSummary.averageBPM)
        XCTAssertEqual(session.maxHeartRate, FakeHealthKitService.syntheticSummary.maxBPM)
    }

    func testRF14_noHeartRateSamples_stillStoresWorkoutUUID() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService(summaryToReturn: nil)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.count, 1)
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.hkWorkoutUUID, saved.first?.returnedUUID, "A trava é gravada mesmo sem FC")
        // O evento não tem FC opcional: 0 significa "sem FC". Aceita também `nil`, caso o
        // coordinator passe a converter 0 em "sem valor".
        XCTAssertEqual(session.avgHeartRate ?? 0, 0)
        XCTAssertEqual(session.maxHeartRate ?? 0, 0)
    }

    // MARK: - Reconciliação (RF-13, RF-14; CA2-1, CA2-2)

    func testReconcile_watchWorkoutArrivesAfterFinish_removesOwnWorkoutAndLinksWatch() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)
        // Finalizar no iPhone antes de encerrar o treino no relógio: o iPhone grava o próprio.
        await recorder.process(finished)
        let ownWorkout = await healthKit.savedWorkouts.first?.returnedUUID
        XCTAssertEqual(try XCTUnwrap(fixture.coordinator.session(withID: sessionID)).hkWorkoutUUID, ownWorkout)

        // O treino do app Exercício chega depois.
        let watchWorkout = UUID()
        await healthKit.setOverlappingWorkoutToReturn(watchWorkout)
        await recorder.reconcileRecentSessions(now: endedAt.addingTimeInterval(600))

        let removed = await healthKit.removedWorkoutSessions
        XCTAssertEqual(removed, [sessionID], "O treino do iPhone virou duplicata e é apagado")
        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.count, 1, "Nada é gravado de novo")
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.hkWorkoutUUID, watchWorkout)
        XCTAssertEqual(session.avgHeartRate, FakeHealthKitService.syntheticSummary.averageBPM)
    }

    func testReconcile_heartRateArrivesLater_isStoredWithoutTouchingTheWorkout() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService(summaryToReturn: nil)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)
        await recorder.process(finished)
        let ownWorkout = await healthKit.savedWorkouts.first?.returnedUUID
        XCTAssertNil(try XCTUnwrap(fixture.coordinator.session(withID: sessionID)).avgHeartRate)

        // As amostras do relógio sincronizam com o iPhone depois do fim da sessão.
        await healthKit.setSummaryToReturn(HeartRateSummary(averageBPM: 121, maxBPM: 158, sampleCount: 40))
        await recorder.reconcileRecentSessions(now: endedAt.addingTimeInterval(600))

        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.avgHeartRate, 121)
        XCTAssertEqual(session.maxHeartRate, 158)
        XCTAssertEqual(session.hkWorkoutUUID, ownWorkout)
        let removed = await healthKit.removedWorkoutSessions
        XCTAssertTrue(removed.isEmpty)
    }

    func testReconcile_nothingNew_appliesNoEventAndNeverAsksAuthorization() async throws {
        let fixture = try makeFixture()
        let watchWorkout = UUID()
        let healthKit = FakeHealthKitService(overlappingWorkoutToReturn: watchWorkout)
        let (sessionID, finished) = try startAndFinishSession(fixture)
        await HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator).process(finished)

        // Processo novo (relançamento): nada mudou no Saúde desde o fim da sessão.
        let relaunched = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let observed = fixture.coordinator.eventsApplied
        await relaunched.reconcileRecentSessions(now: endedAt.addingTimeInterval(3_600))
        // Marcador: o próximo evento publicado depois da reconciliação.
        let markerSessionID = try startSession(fixture)

        // Se a reconciliação tivesse aplicado um resumo repetido, ele viria antes do marcador.
        var iterator = observed.makeAsyncIterator()
        let nextEvent = await iterator.next()
        guard let firstEvent = nextEvent, case .sessionStarted = firstEvent.kind, firstEvent.sessionID == markerSessionID else {
            return XCTFail("Esperava só o início do marcador, veio \(String(describing: nextEvent?.kind))")
        }
        let requestCount = await healthKit.authorizationRequestCount
        XCTAssertEqual(requestCount, 1, "Só o fim da sessão pediu autorização")
        let removed = await healthKit.removedWorkoutSessions
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(try XCTUnwrap(fixture.coordinator.session(withID: sessionID)).hkWorkoutUUID, watchWorkout)
    }

    func testReconcile_sessionFinishedBeforeRecorderExisted_linksAndReadsWithoutAskingAuthorization() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        // Ex.: o app foi encerrado logo depois de finalizar, antes de o gravador processar o evento.
        let (sessionID, _) = try startAndFinishSession(fixture)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)

        await recorder.reconcileRecentSessions(now: endedAt.addingTimeInterval(600))

        var session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertNil(session.hkWorkoutUUID, "Sem autorização neste processo, não grava treino")
        XCTAssertEqual(session.avgHeartRate, FakeHealthKitService.syntheticSummary.averageBPM)
        var requestCount = await healthKit.authorizationRequestCount
        XCTAssertEqual(requestCount, 0, "Reconciliar nunca abre o diálogo de autorização (AGENTS §7)")

        let watchWorkout = UUID()
        await healthKit.setOverlappingWorkoutToReturn(watchWorkout)
        await recorder.reconcileRecentSessions(now: endedAt.addingTimeInterval(1_200))

        session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.hkWorkoutUUID, watchWorkout)
        requestCount = await healthKit.authorizationRequestCount
        XCTAssertEqual(requestCount, 0)
        let saved = await healthKit.savedWorkouts
        XCTAssertTrue(saved.isEmpty)
    }

    func testReconcile_sessionOutsideWindow_isIgnored() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)
        await recorder.process(finished)
        let ownWorkout = await healthKit.savedWorkouts.first?.returnedUUID
        await healthKit.setOverlappingWorkoutToReturn(UUID())

        let lateNow = startedAt.addingTimeInterval(HealthKitWorkoutRecorder.reconciliationWindow + 1)
        await recorder.reconcileRecentSessions(now: lateNow)

        let overlapQueries = await healthKit.overlapQueries
        XCTAssertEqual(overlapQueries.count, 1, "Só a consulta do fim da sessão")
        XCTAssertEqual(try XCTUnwrap(fixture.coordinator.session(withID: sessionID)).hkWorkoutUUID, ownWorkout)
    }

    // MARK: - start()/stop()

    func testStart_recordsFinishedSessionFromEventStream() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        recorder.start()
        defer { recorder.stop() }
        let observed = fixture.coordinator.eventsApplied
        let summaryApplied = expectation(description: "heartRateSummary aplicado pelo gravador")
        let consumer = Task { @MainActor () -> SessionEvent? in
            for await event in observed {
                if case .heartRateSummary = event.kind {
                    summaryApplied.fulfill()
                    return event
                }
            }
            return nil
        }

        let (sessionID, _) = try startAndFinishSession(fixture)

        await fulfillment(of: [summaryApplied], timeout: 5)
        let summaryEvent = await consumer.value
        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.sessionUUID, sessionID)
        XCTAssertEqual(summaryEvent?.sessionID, sessionID)
        XCTAssertEqual(summaryEvent?.source, .iphone)
        XCTAssertEqual(summaryEvent?.occurredAt, endedAt)
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.hkWorkoutUUID, saved.first?.returnedUUID)
        XCTAssertEqual(session.avgHeartRate, FakeHealthKitService.syntheticSummary.averageBPM)
    }

    func testStart_calledTwice_keepsSingleObserver() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        recorder.start()
        recorder.start()
        defer { recorder.stop() }
        let observed = fixture.coordinator.eventsApplied
        let firstSummary = expectation(description: "resumo da primeira sessão")
        let secondSummary = expectation(description: "resumo da segunda sessão")
        let consumer = Task { @MainActor () -> Int in
            var summaries = 0
            for await event in observed {
                guard case .heartRateSummary = event.kind else {
                    continue
                }
                summaries += 1
                if summaries == 1 {
                    firstSummary.fulfill()
                } else {
                    secondSummary.fulfill()
                    return summaries
                }
            }
            return summaries
        }

        // A segunda sessão só é finalizada depois do resumo da primeira: se houvesse dois
        // observadores, o segundo já teria gravado outro treino para a primeira sessão antes
        // de o laço único chegar ao `sessionFinished` da segunda (a fila é FIFO).
        let (firstID, _) = try startAndFinishSession(fixture)
        await fulfillment(of: [firstSummary], timeout: 5)
        let (secondID, _) = try startAndFinishSession(fixture)
        await fulfillment(of: [secondSummary], timeout: 5)
        _ = await consumer.value

        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.map { $0.sessionUUID }, [firstID, secondID])
    }

    // MARK: - F5: sessão só de aeróbicos vai como treino aeróbico (RF-13)

    func testF5_cardioSessionRecordsAerobicKind() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture, exercises: [
            ExerciseSpec(slug: "easy-run", pattern: .cardio),
        ])

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.kind, WorkoutRecordKind.aerobic(.running))
        XCTAssertEqual(saved.first?.start, startedAt)
        XCTAssertEqual(saved.first?.end, endedAt)
        XCTAssertEqual(saved.first?.sessionUUID, sessionID)
        let overlapQueries = await healthKit.overlapQueries
        XCTAssertEqual(
            overlapQueries,
            [FakeHealthKitService.OverlapQuery(start: startedAt, end: endedAt, kind: .aerobic(.running))],
            "O vínculo procura o mesmo tipo"
        )
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.hkWorkoutUUID, saved.first?.returnedUUID)
    }

    func testF5_firstWorkedAerobicDecidesTheKind() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        // O circuito só tem aquecimento (não conta); o pular corda é o primeiro com série de trabalho.
        let (_, finished) = try startAndFinishSession(fixture, exercises: [
            ExerciseSpec(slug: "bodyweight-circuit", pattern: .cardio, workSets: 0, warmupSets: 1),
            ExerciseSpec(slug: "jump-rope", pattern: .cardio),
            ExerciseSpec(slug: "brisk-walk", pattern: .cardio),
        ])

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.map(\.kind), [WorkoutRecordKind.jumpRope])
    }

    func testF5_customCardioExerciseRecordsOtherAerobic() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (_, finished) = try startAndFinishSession(fixture, exercises: [
            ExerciseSpec(slug: "meu-cardio-proprio", pattern: .cardio),
        ])

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.map(\.kind), [WorkoutRecordKind.aerobic(.other)])
    }

    func testF5_mixedSessionRecordsStrength() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (_, finished) = try startAndFinishSession(fixture, exercises: [
            ExerciseSpec(slug: "squat-teste", pattern: .squat),
            ExerciseSpec(slug: "brisk-walk", pattern: .cardio),
        ])

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.map(\.kind), [WorkoutRecordKind.strength], "Mistura de força e aeróbico continua como força")
        let overlapQueries = await healthKit.overlapQueries
        XCTAssertEqual(overlapQueries.map(\.kind), [WorkoutRecordKind.strength])
    }

    func testF5_exerciseWithoutMovementPatternKeepsStrength() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (_, finished) = try startAndFinishSession(fixture, exercises: [
            ExerciseSpec(slug: "sem-padrao", pattern: nil),
        ])

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.map(\.kind), [WorkoutRecordKind.strength])
    }

    func testF5_exerciseMissingFromCatalogKeepsStrength() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        // Sem o exercício no catálogo não há como saber que é aeróbico: o caminho seguro é o de força.
        let (_, finished) = try startAndFinishSession(fixture, exercises: [
            ExerciseSpec(slug: "brisk-walk", pattern: .cardio, isInCatalog: false),
        ])

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.map(\.kind), [WorkoutRecordKind.strength])
    }

    func testF5_exerciseWithoutWorkSetsDoesNotMakeTheSessionMixed() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        // A força do plano ficou sem série (pulada): só o que teve série de trabalho conta.
        let (_, finished) = try startAndFinishSession(fixture, exercises: [
            ExerciseSpec(slug: "squat-teste", pattern: .squat, workSets: 0),
            ExerciseSpec(slug: "stationary-bike", pattern: .cardio),
        ])

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.map(\.kind), [WorkoutRecordKind.aerobic(.cycling)])
    }

    func testF5_linksOverlappingAerobicWorkout() async throws {
        let fixture = try makeFixture()
        let strengthWorkout = UUID()
        let aerobicWorkout = UUID()
        let healthKit = FakeHealthKitService(
            overlappingWorkoutToReturn: strengthWorkout,
            overlappingAerobicWorkoutToReturn: aerobicWorkout
        )
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture, exercises: [
            ExerciseSpec(slug: "brisk-walk", pattern: .cardio),
        ])

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertTrue(saved.isEmpty, "Vincula o treino aeróbico do relógio em vez de criar outro")
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.hkWorkoutUUID, aerobicWorkout, "Nunca o treino de força: o vínculo é pelo mesmo tipo")
    }

    func testF5_strengthSessionIgnoresAerobicWorkoutFromAnotherApp() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService(overlappingAerobicWorkoutToReturn: UUID())
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.count, 1, "A força grava o próprio treino: o aeróbico de outro app não serve")
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.hkWorkoutUUID, saved.first?.returnedUUID)
    }

    func testF5_reconcileRelinksAerobicWorkoutFromTheWatchArrivingLater() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture, exercises: [
            ExerciseSpec(slug: "easy-run", pattern: .cardio),
        ])
        await recorder.process(finished)
        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.map(\.kind), [WorkoutRecordKind.aerobic(.running)])

        let watchRun = UUID()
        await healthKit.setOverlappingAerobicWorkoutToReturn(watchRun)
        await recorder.reconcileRecentSessions(now: endedAt.addingTimeInterval(600))

        let removed = await healthKit.removedWorkoutSessions
        XCTAssertEqual(removed, [sessionID], "O treino aeróbico do iPhone virou duplicata e é apagado")
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.hkWorkoutUUID, watchRun)
        let savedAfter = await healthKit.savedWorkouts
        XCTAssertEqual(savedAfter.count, 1, "Nada é gravado de novo")
    }

    func testF5_oldSessionAlreadyRecordedIsNeverRewritten() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture, exercises: [
            ExerciseSpec(slug: "brisk-walk", pattern: .cardio),
        ])
        // Sessão de antes da 2.4: já foi gravada como força e guarda o UUID do treino.
        let oldWorkout = UUID()
        try fixture.coordinator.apply(SessionEvent(
            sessionID: sessionID,
            occurredAt: endedAt,
            source: .iphone,
            kind: .heartRateSummary(averageBPM: 0, maxBPM: 0, hkWorkoutUUID: oldWorkout)
        ))

        await recorder.process(finished)

        let saved = await healthKit.savedWorkouts
        XCTAssertTrue(saved.isEmpty)
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.hkWorkoutUUID, oldWorkout)
    }

    // MARK: - L3 (c): como terminou a ida ao Saúde (SPEC §7.18)

    func testL3_outcomeSavedAfterRecording() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        XCTAssertEqual(recorder.healthOutcome(for: sessionID), .saved)
        let saved = await healthKit.savedWorkouts
        XCTAssertEqual(saved.count, 1)
    }

    func testL3_outcomeSavedWhenLinkingAnotherAppsWorkout() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService(overlappingWorkoutToReturn: UUID())
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        XCTAssertEqual(recorder.healthOutcome(for: sessionID), .saved, "Vincular o treino do relógio também é sucesso")
    }

    func testL3_outcomeFailedWhenSaveFails() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        await healthKit.setShouldFailSave(true)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        XCTAssertEqual(recorder.healthOutcome(for: sessionID), .failed)
        let session = try XCTUnwrap(fixture.coordinator.session(withID: sessionID))
        XCTAssertEqual(session.status, .completed, "A falha só informa: a sessão continua concluída")
    }

    func testL3_outcomeFailedWhenOverlapQueryFails() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        await healthKit.setShouldFailOverlapQuery(true)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        XCTAssertEqual(recorder.healthOutcome(for: sessionID), .failed)
    }

    func testL3_outcomeNotAttemptedWithoutHealth() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService(isAvailable: false)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        XCTAssertEqual(recorder.healthOutcome(for: sessionID), .notAttempted, "Sem o app Saúde não há o que esperar")
        await recorder.process(finished)

        XCTAssertEqual(recorder.healthOutcome(for: sessionID), .notAttempted)
    }

    func testL3_outcomeNotAttemptedWithoutWritePermission() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService(shouldFailAuthorization: true)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        await recorder.process(finished)

        XCTAssertEqual(recorder.healthOutcome(for: sessionID), .notAttempted, "Sem permissão de gravar não é erro")
    }

    func testL3_outcomePendingBeforeEvent() async throws {
        let fixture = try makeFixture()
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        let (sessionID, finished) = try startAndFinishSession(fixture)

        XCTAssertEqual(recorder.healthOutcome(for: sessionID), .pending, "O sessionFinished ainda não chegou")
        await recorder.process(finished)

        XCTAssertEqual(recorder.healthOutcome(for: sessionID), .saved)
    }

    // MARK: - Regra de sobreposição do LiveHealthKitService (RF-13)

    func testRF13_bestOverlap_requiresAtLeastHalfOfTheSession() {
        let exactlyHalf = interval(startOffset: -1_800, endOffset: 1_800)
        let belowHalf = interval(startOffset: -1_800, endOffset: 1_799)

        XCTAssertEqual(
            LiveHealthKitService.bestOverlappingWorkout(among: [exactlyHalf], start: startedAt, end: endedAt),
            exactlyHalf.uuid,
            "50 % exatos contam (≥ 50 %)"
        )
        XCTAssertNil(LiveHealthKitService.bestOverlappingWorkout(among: [belowHalf], start: startedAt, end: endedAt))
    }

    func testRF13_bestOverlap_picksLargestOverlap() {
        let partial = interval(startOffset: 1_200, endOffset: 3_600)
        let covering = interval(startOffset: -600, endOffset: 4_200)
        let disjoint = interval(startOffset: 7_200, endOffset: 9_000)

        let best = LiveHealthKitService.bestOverlappingWorkout(
            among: [partial, disjoint, covering],
            start: startedAt,
            end: endedAt
        )

        XCTAssertEqual(best, covering.uuid)
    }

    func testRF13_bestOverlap_emptyOrZeroLengthSession_returnsNil() {
        let covering = interval(startOffset: -600, endOffset: 4_200)

        XCTAssertNil(LiveHealthKitService.bestOverlappingWorkout(among: [], start: startedAt, end: endedAt))
        XCTAssertNil(LiveHealthKitService.bestOverlappingWorkout(among: [covering], start: startedAt, end: startedAt))
    }

    // MARK: - Fixtures

    private struct Fixture {
        let container: ModelContainer
        let coordinator: SessionCoordinator
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainerFactory.make(.inMemory)
        let coordinator = SessionCoordinator(
            modelContext: container.mainContext,
            appliedEvents: AppliedEventStore.inMemory()
        )
        return Fixture(container: container, coordinator: coordinator)
    }

    /// Sessão sem exercícios: o gravador só usa início, fim e a trava.
    private func startSession(_ fixture: Fixture) throws -> UUID {
        let plan = SessionPlan(
            programID: UUID(),
            programName: "Programa",
            programDayID: UUID(),
            programDayName: "Dia A",
            exercises: [],
            generatedAt: startedAt
        )
        return try fixture.coordinator.startSession(plan: plan, now: startedAt, source: .iphone)
    }

    /// Aplica e devolve o `sessionFinished`, que é o que o gravador recebe do stream.
    private func finish(_ sessionID: UUID, _ fixture: Fixture) throws -> SessionEvent {
        let finished = SessionEvent(
            sessionID: sessionID,
            occurredAt: endedAt,
            source: .iphone,
            kind: .sessionFinished(endedAt: endedAt)
        )
        try fixture.coordinator.apply(finished)
        return finished
    }

    private func startAndFinishSession(_ fixture: Fixture) throws -> (UUID, SessionEvent) {
        let sessionID = try startSession(fixture)
        let finished = try finish(sessionID, fixture)
        return (sessionID, finished)
    }

    /// Um exercício da sessão de teste: quantas séries de trabalho e de aquecimento ele teve, e se
    /// está no catálogo (sem estar, a sessão guarda só o nome e a relação fica vazia).
    private struct ExerciseSpec {
        let slug: String
        let pattern: MovementPattern?
        var workSets = 1
        var warmupSets = 0
        var isInCatalog = true
    }

    /// Sessão com os exercícios de `exercises` (um plano, o catálogo e as séries registradas) já
    /// finalizada. O slug de cada exercício precisa ser único no teste (o catálogo exige).
    private func startAndFinishSession(
        _ fixture: Fixture,
        exercises specs: [ExerciseSpec]
    ) throws -> (UUID, SessionEvent) {
        let context = fixture.container.mainContext
        var planned: [PlannedExercise] = []
        for (order, spec) in specs.enumerated() {
            let exerciseID = UUID()
            if spec.isInCatalog {
                context.insert(ExerciseModel(
                    uuid: exerciseID,
                    slug: spec.slug,
                    name: spec.slug,
                    primaryMusclesRaw: "core",
                    secondaryMusclesRaw: "",
                    equipmentRaw: Equipment.bodyweight.rawValue,
                    loadUnitRaw: LoadUnit.kilograms.rawValue,
                    loadIncrement: 1,
                    isUnilateral: false,
                    machineNotes: nil,
                    isArchived: false,
                    movementPatternRaw: spec.pattern?.rawValue
                ))
            }
            let definition = ExerciseDefinition(
                id: exerciseID,
                slug: spec.slug,
                name: spec.slug,
                primaryMuscles: [.core],
                equipment: .bodyweight,
                loadUnit: .kilograms,
                loadIncrement: 1,
                movementPattern: spec.pattern
            )
            planned.append(PlannedExercise(
                id: UUID(),
                exercise: definition,
                target: ExerciseTarget(exerciseID: exerciseID, order: order),
                prescription: ExercisePrescription(exerciseID: exerciseID)
            ))
        }
        try context.save()

        let plan = SessionPlan(
            programID: UUID(),
            programName: "Programa",
            programDayID: UUID(),
            programDayName: "Dia A",
            exercises: planned,
            generatedAt: startedAt
        )
        let sessionID = try fixture.coordinator.startSession(plan: plan, now: startedAt, source: .iphone)
        for (order, spec) in specs.enumerated() {
            let warmups = [Bool](repeating: true, count: spec.warmupSets)
            let works = [Bool](repeating: false, count: spec.workSets)
            for (index, isWarmup) in (warmups + works).enumerated() {
                try fixture.coordinator.logSet(
                    sessionID: sessionID,
                    sessionExerciseID: planned[order].id,
                    index: index,
                    load: 0,
                    reps: 10,
                    rir: nil,
                    isWarmup: isWarmup,
                    now: startedAt.addingTimeInterval(TimeInterval(60 * (order + 1) + index))
                )
            }
        }
        let finished = try finish(sessionID, fixture)
        return (sessionID, finished)
    }

    private func interval(startOffset: TimeInterval, endOffset: TimeInterval) -> LiveHealthKitService.WorkoutInterval {
        LiveHealthKitService.WorkoutInterval(
            uuid: UUID(),
            start: startedAt.addingTimeInterval(startOffset),
            end: startedAt.addingTimeInterval(endOffset)
        )
    }
}
