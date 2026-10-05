import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// SPEC §7.18 L3 (contrato docs/V25-CONTRACT.md §5.4): o store do último pedido de avaliação e o
/// `RatingPromptGate`, que junta o store, o histórico e o Saúde. As sessões são criadas só pelo caminho
/// oficial (planner e coordinator, AGENTS R4) sobre um container in-memory; o Saúde, pelo
/// `HealthKitWorkoutRecorder` com o `FakeHealthKitService`. A tabela da regra pura está no TrainerCore
/// (`RatingPromptPolicyTests`).
@MainActor
final class RatingPromptTests: XCTestCase {
    private let day: TimeInterval = 86_400
    /// Início da primeira sessão concluída do histórico.
    private let firstStart = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: - LiveRatingPromptStore

    func testL3_liveStoreRoundTrip() throws {
        let suiteName = "RatingPromptTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LiveRatingPromptStore(defaults: defaults, bundle: .main)
        XCTAssertNil(store.lastRequest(), "Nunca pediu")

        let record = RatingPromptRecord(version: "1.0.0", date: Date(timeIntervalSince1970: 1_790_000_123.5))
        store.recordRequest(record)

        XCTAssertEqual(store.lastRequest(), record)
        XCTAssertEqual(defaults.string(forKey: "ratingPromptLastVersion"), "1.0.0")
        XCTAssertEqual(defaults.double(forKey: "ratingPromptLastRequestAt"), 1_790_000_123.5)
        let reopened = LiveRatingPromptStore(defaults: defaults, bundle: .main)
        XCTAssertEqual(reopened.lastRequest(), record, "Outra instância lê o mesmo pedido")
        XCTAssertFalse(reopened.isStoreInstall, "No simulador nunca é instalação da loja")

        let newer = RatingPromptRecord(version: "1.1.0", date: Date(timeIntervalSince1970: 1_800_000_000))
        store.recordRequest(newer)
        XCTAssertEqual(store.lastRequest(), newer, "Guarda só o último pedido")
    }

    func testL3_storeInstallNeedsNoProfileAndDevice() {
        XCTAssertTrue(LiveRatingPromptStore.isStoreInstall(hasEmbeddedProfile: false, isSimulator: false))
        XCTAssertFalse(
            LiveRatingPromptStore.isStoreInstall(hasEmbeddedProfile: true, isSimulator: false),
            "Cópia de teste ou build de desenvolvimento: tem o perfil embutido"
        )
        XCTAssertFalse(LiveRatingPromptStore.isStoreInstall(hasEmbeddedProfile: false, isSimulator: true))
        XCTAssertFalse(LiveRatingPromptStore.isStoreInstall(hasEmbeddedProfile: true, isSimulator: true))
    }

    // MARK: - RatingPromptGate

    func testL3_gateAsksWhenAllConditionsHold() throws {
        let fixture = try makeFixture()
        let lastID = try makeHistory(fixture)
        let store = FakeRatingPromptStore(isStoreInstall: true, currentVersion: "1.0.0")
        let gate = RatingPromptGate(store: store, planner: fixture.planner, recorder: nil)
        var requests = 0

        let asked = gate.requestIfAllowed(sessionID: lastID, healthOutcome: gate.healthOutcome(for: lastID), now: now) {
            requests += 1
        }

        XCTAssertTrue(asked)
        XCTAssertEqual(requests, 1, "Chama a caixa do sistema uma vez")
        let input = try XCTUnwrap(gate.input(forSessionID: lastID, healthOutcome: .notAttempted))
        XCTAssertEqual(input.completedSessionCount, 3, "Conta a sessão que acabou de terminar")
        XCTAssertEqual(input.firstCompletedSessionStart, firstStart)
        XCTAssertEqual(input.sessionEnding, .completed)
    }

    func testL3_gateNeverAsksOutsideStore() throws {
        let fixture = try makeFixture()
        let lastID = try makeHistory(fixture)
        let store = FakeRatingPromptStore(isStoreInstall: false, currentVersion: "1.0.0")
        let gate = RatingPromptGate(store: store, planner: fixture.planner, recorder: nil)
        var requests = 0

        let asked = gate.requestIfAllowed(sessionID: lastID, healthOutcome: .notAttempted, now: now) {
            requests += 1
        }

        XCTAssertFalse(asked)
        XCTAssertEqual(requests, 0)
        XCTAssertTrue(store.recorded.isEmpty)
    }

    func testL3_gateNeverAsksAfterAbandon() throws {
        let fixture = try makeFixture()
        _ = try makeSession(fixture, startedAt: firstStart)
        _ = try makeSession(fixture, startedAt: firstStart.addingTimeInterval(3 * day))
        _ = try makeSession(fixture, startedAt: firstStart.addingTimeInterval(6 * day))
        // Três concluídas antes e uma semana passada: só o "Sair sem registrar" impede o pedido.
        let abandonedID = try makeSession(fixture, startedAt: lastStart, ending: .abandon)
        let store = FakeRatingPromptStore(isStoreInstall: true)
        let gate = RatingPromptGate(store: store, planner: fixture.planner, recorder: nil)
        var requests = 0

        let asked = gate.requestIfAllowed(sessionID: abandonedID, healthOutcome: .notAttempted, now: now) {
            requests += 1
        }

        XCTAssertFalse(asked)
        XCTAssertEqual(requests, 0)
        XCTAssertTrue(store.recorded.isEmpty)
        let input = try XCTUnwrap(gate.input(forSessionID: abandonedID, healthOutcome: .notAttempted))
        XCTAssertEqual(input.sessionEnding, .abandoned)
        XCTAssertEqual(input.completedSessionCount, 3, "A abandonada não conta")
    }

    func testL3_gateRecordsVersionAndDate() throws {
        let fixture = try makeFixture()
        let lastID = try makeHistory(fixture)
        let store = FakeRatingPromptStore(isStoreInstall: true, currentVersion: "1.2.0")
        let gate = RatingPromptGate(store: store, planner: fixture.planner, recorder: nil)

        gate.requestIfAllowed(sessionID: lastID, healthOutcome: .saved, now: now, request: {})

        let expected = RatingPromptRecord(version: "1.2.0", date: now)
        XCTAssertEqual(store.recorded, [expected])
        XCTAssertEqual(store.lastRequest(), expected)
    }

    func testL3_gateSameVersionDoesNotAskAgain() throws {
        let fixture = try makeFixture()
        let lastID = try makeHistory(fixture)
        let store = FakeRatingPromptStore(isStoreInstall: true, currentVersion: "1.0.0")
        let gate = RatingPromptGate(store: store, planner: fixture.planner, recorder: nil)
        XCTAssertTrue(gate.requestIfAllowed(sessionID: lastID, healthOutcome: .saved, now: now, request: {}))

        // 130 dias depois, ainda na mesma versão: não pede de novo.
        let laterStart = lastStart.addingTimeInterval(130 * day)
        let laterID = try makeSession(fixture, startedAt: laterStart)
        let laterNow = laterStart.addingTimeInterval(3_602)
        var requests = 0
        let asked = gate.requestIfAllowed(sessionID: laterID, healthOutcome: .saved, now: laterNow) {
            requests += 1
        }

        XCTAssertFalse(asked)
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(store.recorded.count, 1)

        // Numa versão nova, passados os 120 dias, pode pedir de novo.
        let updated = FakeRatingPromptStore(isStoreInstall: true, currentVersion: "1.1.0", lastRequest: store.lastRequest())
        let updatedGate = RatingPromptGate(store: updated, planner: fixture.planner, recorder: nil)
        XCTAssertTrue(updatedGate.requestIfAllowed(sessionID: laterID, healthOutcome: .saved, now: laterNow, request: {}))
    }

    func testL3_gateNeverAsksBeforeAWeekOrThreeSessions() throws {
        let fixture = try makeFixture()
        _ = try makeSession(fixture, startedAt: firstStart)
        let secondID = try makeSession(fixture, startedAt: lastStart)
        let store = FakeRatingPromptStore(isStoreInstall: true)
        let gate = RatingPromptGate(store: store, planner: fixture.planner, recorder: nil)

        XCTAssertFalse(gate.requestIfAllowed(sessionID: secondID, healthOutcome: .saved, now: now, request: {}), "Só 2 sessões")

        let soonFixture = try makeFixture()
        _ = try makeSession(soonFixture, startedAt: firstStart)
        _ = try makeSession(soonFixture, startedAt: firstStart.addingTimeInterval(day))
        let soonID = try makeSession(soonFixture, startedAt: firstStart.addingTimeInterval(2 * day))
        let soonGate = RatingPromptGate(store: store, planner: soonFixture.planner, recorder: nil)
        let soonNow = firstStart.addingTimeInterval(2 * day + 3_602)

        XCTAssertFalse(soonGate.requestIfAllowed(sessionID: soonID, healthOutcome: .saved, now: soonNow, request: {}), "Menos de 7 dias")
        XCTAssertTrue(store.recorded.isEmpty)
    }

    func testL3_gateSessionWithoutWorkingSetsDoesNotAsk() throws {
        let fixture = try makeFixture()
        _ = try makeSession(fixture, startedAt: firstStart)
        _ = try makeSession(fixture, startedAt: firstStart.addingTimeInterval(3 * day))
        _ = try makeSession(fixture, startedAt: firstStart.addingTimeInterval(6 * day))
        // "Encerrar só com o que marquei" sem nenhuma série: concluída no estado, mas não conta (W2).
        let emptyID = try makeSession(fixture, startedAt: lastStart, workingSets: 0)
        let store = FakeRatingPromptStore(isStoreInstall: true)
        let gate = RatingPromptGate(store: store, planner: fixture.planner, recorder: nil)

        XCTAssertFalse(gate.requestIfAllowed(sessionID: emptyID, healthOutcome: .saved, now: now, request: {}))
        XCTAssertEqual(gate.input(forSessionID: emptyID, healthOutcome: .saved)?.sessionEnding, .abandoned)
    }

    func testL3_gateNeverAsksAfterHealthFailure() async throws {
        let fixture = try makeFixture()
        let lastID = try makeHistory(fixture)
        let healthKit = FakeHealthKitService()
        await healthKit.setShouldFailSave(true)
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        await recorder.process(finishedEvent(lastID, endedAt: lastStart.addingTimeInterval(3_600)))
        let store = FakeRatingPromptStore(isStoreInstall: true)
        let gate = RatingPromptGate(store: store, planner: fixture.planner, recorder: recorder)

        let outcome = gate.healthOutcome(for: lastID)
        XCTAssertEqual(outcome, .failed)
        XCTAssertFalse(gate.requestIfAllowed(sessionID: lastID, healthOutcome: outcome, now: now, request: {}))
        XCTAssertTrue(store.recorded.isEmpty)
    }

    func testL3_gateNeverAsksWhileHealthIsPending() throws {
        let fixture = try makeFixture()
        let lastID = try makeHistory(fixture)
        // O gravador ainda não recebeu o `sessionFinished`: no fim da espera, vale erro.
        let recorder = HealthKitWorkoutRecorder(healthKit: FakeHealthKitService(), coordinator: fixture.coordinator)
        let store = FakeRatingPromptStore(isStoreInstall: true)
        let gate = RatingPromptGate(store: store, planner: fixture.planner, recorder: recorder)

        let outcome = gate.healthOutcome(for: lastID)
        XCTAssertEqual(outcome, .pending)
        XCTAssertFalse(gate.requestIfAllowed(sessionID: lastID, healthOutcome: outcome, now: now, request: {}))
        XCTAssertEqual(gate.input(forSessionID: lastID, healthOutcome: outcome)?.sessionEnding, .failed)
    }

    func testL3_gateAsksAfterHealthSaved() async throws {
        let fixture = try makeFixture()
        let lastID = try makeHistory(fixture)
        let healthKit = FakeHealthKitService()
        let recorder = HealthKitWorkoutRecorder(healthKit: healthKit, coordinator: fixture.coordinator)
        await recorder.process(finishedEvent(lastID, endedAt: lastStart.addingTimeInterval(3_600)))
        let store = FakeRatingPromptStore(isStoreInstall: true)
        let gate = RatingPromptGate(store: store, planner: fixture.planner, recorder: recorder)

        let outcome = gate.healthOutcome(for: lastID)
        XCTAssertEqual(outcome, .saved)
        XCTAssertTrue(gate.requestIfAllowed(sessionID: lastID, healthOutcome: outcome, now: now, request: {}))
    }

    func testL3_gateWithoutRecorderTreatsHealthAsNotAttempted() throws {
        let fixture = try makeFixture()
        let gate = RatingPromptGate(store: FakeRatingPromptStore(isStoreInstall: true), planner: fixture.planner, recorder: nil)

        XCTAssertEqual(gate.healthOutcome(for: UUID()), .notAttempted)
    }

    func testL3_gateUnreadableHistoryDoesNotAsk() {
        let store = FakeRatingPromptStore(isStoreInstall: true)
        let gate = RatingPromptGate(store: store, planner: UnreadableHistoryPlanner(), recorder: nil)
        var requests = 0

        let asked = gate.requestIfAllowed(sessionID: UUID(), healthOutcome: .saved, now: now) {
            requests += 1
        }

        XCTAssertFalse(asked)
        XCTAssertEqual(requests, 0)
        XCTAssertNil(gate.input(forSessionID: UUID(), healthOutcome: .saved))
        XCTAssertTrue(store.recorded.isEmpty)
    }

    func testL3_fakeStoreDefaultsNeverAsk() {
        let store = FakeRatingPromptStore()

        XCTAssertFalse(store.isStoreInstall, "Previews e testes que não tratam da avaliação nunca pedem")
        XCTAssertEqual(store.currentVersion, "1.0.0")
        XCTAssertNil(store.lastRequest())
    }

    // MARK: - Fixtures

    /// Início da sessão que acabou de terminar: 8 dias depois da primeira.
    private var lastStart: Date { firstStart.addingTimeInterval(8 * day) }
    /// O resumo aparece no fim da sessão (1 h) e o pedido vem uns 2 s depois.
    private var now: Date { lastStart.addingTimeInterval(3_602) }

    private struct Fixture {
        let container: ModelContainer
        let coordinator: SessionCoordinator
        let planner: SessionPlanner
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainerFactory.make(.inMemory)
        let coordinator = SessionCoordinator(
            modelContext: container.mainContext,
            appliedEvents: AppliedEventStore.inMemory()
        )
        let planner = SessionPlanner(modelContext: container.mainContext, coordinator: coordinator)
        return Fixture(container: container, coordinator: coordinator, planner: planner)
    }

    /// Três sessões concluídas, nos dias 0, 3 e 8; devolve a última, a que acabou de terminar.
    private func makeHistory(_ fixture: Fixture) throws -> UUID {
        _ = try makeSession(fixture, startedAt: firstStart)
        _ = try makeSession(fixture, startedAt: firstStart.addingTimeInterval(3 * day))
        return try makeSession(fixture, startedAt: lastStart)
    }

    private enum Ending {
        case finish
        case abandon
    }

    /// Uma sessão de 1 h com um exercício e `workingSets` séries de trabalho, pelo planner (início) e pelo
    /// coordinator (séries e fim), como o app faz.
    private func makeSession(
        _ fixture: Fixture,
        startedAt: Date,
        workingSets: Int = 3,
        ending: Ending = .finish
    ) throws -> UUID {
        let exerciseID = UUID()
        let definition = ExerciseDefinition(
            id: exerciseID,
            slug: "supino-\(exerciseID.uuidString)",
            name: "Supino",
            primaryMuscles: [.chest],
            equipment: .barbell,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )
        let planned = PlannedExercise(
            id: UUID(),
            exercise: definition,
            target: ExerciseTarget(exerciseID: exerciseID, order: 0),
            prescription: ExercisePrescription(exerciseID: exerciseID)
        )
        let plan = SessionPlan(
            programID: UUID(),
            programName: "Programa",
            programDayID: UUID(),
            programDayName: "Dia A",
            exercises: [planned],
            generatedAt: startedAt
        )
        let sessionID = try fixture.planner.startSession(from: plan, now: startedAt)
        for index in 0..<workingSets {
            try fixture.coordinator.logSet(
                sessionID: sessionID,
                sessionExerciseID: planned.id,
                index: index,
                load: 40,
                reps: 8,
                rir: nil,
                isWarmup: false,
                now: startedAt.addingTimeInterval(TimeInterval(60 * (index + 1)))
            )
        }
        let endedAt = startedAt.addingTimeInterval(3_600)
        switch ending {
        case .finish:
            try fixture.coordinator.finishSession(sessionID: sessionID, now: endedAt)
        case .abandon:
            try fixture.coordinator.abandonSession(sessionID: sessionID, now: endedAt)
        }
        return sessionID
    }

    /// O `sessionFinished` que o gravador recebe do stream (já aplicado por `finishSession`).
    private func finishedEvent(_ sessionID: UUID, endedAt: Date) -> SessionEvent {
        SessionEvent(
            sessionID: sessionID,
            occurredAt: endedAt,
            source: .iphone,
            kind: .sessionFinished(endedAt: endedAt)
        )
    }
}

// MARK: - Double do planejador

private enum UnreadableHistoryError: Error {
    case unreadable
}

/// Planejador cujo histórico não pode ser lido: o portão não pede (contrato §5.4).
@MainActor
private final class UnreadableHistoryPlanner: SessionPlanning {
    func nextPlan(now: Date) throws -> SessionPlan? {
        nil
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        nil
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        throw UnreadableHistoryError.unreadable
    }

    func finishedSessionSummaries() throws -> [SessionSummary] {
        throw UnreadableHistoryError.unreadable
    }
}
