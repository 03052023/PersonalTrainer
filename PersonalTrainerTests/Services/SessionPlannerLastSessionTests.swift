import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// `SessionPlanner.lastSession(forExerciseID:)` (SPEC RF-47; docs/V22-CONTRACT.md §2.1, §3.2):
/// "Da última vez" na folha "Informações do exercício". Container in-memory, tudo em `@MainActor`
/// (ARCHITECTURE §10), sem programa: a busca é só sobre `SessionExerciseModel`/`WorkoutSessionModel`.
@MainActor
final class SessionPlannerLastSessionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testRF47_lastSession_picksLatestFinishedWithWorkingSets() throws {
        let fixture = try makeFixture()
        let squat = insertExercise(slug: "agachamento", name: "Agachamento", into: fixture.context)

        // Mais antiga: concluída, com série de trabalho — só valeria se nada mais recente contasse.
        let oldest = insertSession(status: .completed, startedAt: day(-10), into: fixture.context)
        let oldestExercise = insertSessionExercise(exercise: squat, session: oldest, into: fixture.context)
        insertSet(index: 0, load: 40, reps: 8, isWarmup: false, sessionExercise: oldestExercise, into: fixture.context)

        // Abandonada, com semana leve: mais recente que a de cima e com série de trabalho — é a
        // que deveria valer ("Da última vez" inclui abandonada e semana leve, SPEC P3/§7.5), desde
        // que as duas sessões mais recentes abaixo sejam corretamente ignoradas.
        let abandonedDeload = insertSession(status: .abandoned, startedAt: day(-2), isDeload: true, into: fixture.context)
        let abandonedExercise = insertSessionExercise(exercise: squat, session: abandonedDeload, into: fixture.context)
        insertSet(index: 1, load: 35, reps: 6, isWarmup: false, sessionExercise: abandonedExercise, into: fixture.context)
        insertSet(index: 0, load: 35, reps: 5, isWarmup: true, sessionExercise: abandonedExercise, into: fixture.context)
        insertSet(index: 2, load: 35, reps: 6, isWarmup: false, sessionExercise: abandonedExercise, into: fixture.context)

        // Só aquecimento, mais recente que a abandonada: não tem série de trabalho, então não
        // conta, mesmo sendo mais recente — prova que "nenhuma série de trabalho" é pulada, e não
        // só a mais antiga da lista.
        let warmupOnly = insertSession(status: .completed, startedAt: day(-1), into: fixture.context)
        let warmupOnlyExercise = insertSessionExercise(exercise: squat, session: warmupOnly, into: fixture.context)
        insertSet(index: 0, load: 20, reps: 8, isWarmup: true, sessionExercise: warmupOnlyExercise, into: fixture.context)

        // Em andamento, mais recente de todas: nunca conta como "última vez" (SPEC S3), mesmo à
        // frente de tudo na data.
        let inProgress = insertSession(status: .inProgress, startedAt: day(0), into: fixture.context)
        let inProgressExercise = insertSessionExercise(exercise: squat, session: inProgress, into: fixture.context)
        insertSet(index: 0, load: 37.5, reps: 6, isWarmup: false, sessionExercise: inProgressExercise, into: fixture.context)

        try fixture.context.save()

        let result = try XCTUnwrap(try fixture.planner.lastSession(forExerciseID: squat.uuid))

        XCTAssertEqual(result.sessionID, abandonedDeload.uuid)
        XCTAssertEqual(result.date, abandonedDeload.startedAt)
        XCTAssertTrue(result.wasDeload)
        // Só as séries de trabalho, na ordem de `index`; o aquecimento (index 0) fica de fora.
        XCTAssertEqual(result.sets.map(\.reps), [6, 6])
        XCTAssertEqual(result.sets.map(\.load), [35, 35])
        XCTAssertTrue(result.sets.allSatisfy { !$0.isWarmup })
    }

    func testRF47_lastSession_tieBreaksBySessionID() throws {
        let fixture = try makeFixture()
        let bench = insertExercise(slug: "supino-reto", name: "Supino reto", into: fixture.context)

        let sessionA = insertSession(status: .completed, startedAt: day(-1), into: fixture.context)
        let exerciseA = insertSessionExercise(exercise: bench, session: sessionA, into: fixture.context)
        insertSet(index: 0, load: 50, reps: 8, isWarmup: false, sessionExercise: exerciseA, into: fixture.context)

        let sessionB = insertSession(status: .completed, startedAt: day(-1), into: fixture.context)
        let exerciseB = insertSessionExercise(exercise: bench, session: sessionB, into: fixture.context)
        insertSet(index: 0, load: 52.5, reps: 8, isWarmup: false, sessionExercise: exerciseB, into: fixture.context)

        try fixture.context.save()

        // Mesma data: SPEC P11/RF-47 desempata pelo `sessionID` (o mesmo critério de
        // `HistoryMapper`, maior `uuidString` primeiro).
        let expected = sessionA.uuid.uuidString > sessionB.uuid.uuidString ? sessionA : sessionB

        let result = try XCTUnwrap(try fixture.planner.lastSession(forExerciseID: bench.uuid))
        XCTAssertEqual(result.sessionID, expected.uuid)
    }

    func testRF47_lastSession_returnsNilWithoutHistory() throws {
        let fixture = try makeFixture()
        let squat = insertExercise(slug: "agachamento", name: "Agachamento", into: fixture.context)
        try fixture.context.save()

        XCTAssertNil(try fixture.planner.lastSession(forExerciseID: squat.uuid))
        // Nunca visto: id qualquer também devolve `nil`, sem lançar.
        XCTAssertNil(try fixture.planner.lastSession(forExerciseID: UUID()))
    }

    func testRF47_lastSession_ignoresOtherExercises() throws {
        let fixture = try makeFixture()
        let squat = insertExercise(slug: "agachamento", name: "Agachamento", into: fixture.context)
        let bench = insertExercise(slug: "supino-reto", name: "Supino reto", into: fixture.context)

        let session = insertSession(status: .completed, startedAt: day(-1), into: fixture.context)
        let benchExercise = insertSessionExercise(exercise: bench, session: session, into: fixture.context)
        insertSet(index: 0, load: 50, reps: 8, isWarmup: false, sessionExercise: benchExercise, into: fixture.context)
        try fixture.context.save()

        XCTAssertNil(try fixture.planner.lastSession(forExerciseID: squat.uuid))
        XCTAssertNotNil(try fixture.planner.lastSession(forExerciseID: bench.uuid))
    }

    // MARK: - Fixture

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let planner: SessionPlanner
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let coordinator = LastSessionTestCoordinator()
        let planner = SessionPlanner(modelContext: context, coordinator: coordinator)
        return Fixture(container: container, context: context, planner: planner)
    }

    private func day(_ offset: Int) -> Date {
        now.addingTimeInterval(TimeInterval(offset) * 86_400)
    }

    private func insertExercise(slug: String, name: String, into context: ModelContext) -> ExerciseModel {
        let model = ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: name,
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.quads]),
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.barbell.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 2.5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        context.insert(model)
        return model
    }

    @discardableResult
    private func insertSession(
        status: SessionStatus,
        startedAt: Date,
        isDeload: Bool = false,
        into context: ModelContext
    ) -> WorkoutSessionModel {
        let model = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: status.rawValue,
            startedAt: startedAt,
            endedAt: status == .inProgress ? nil : startedAt.addingTimeInterval(3_600),
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: isDeload,
            sourceRaw: DeviceSource.iphone.rawValue
        )
        context.insert(model)
        return model
    }

    private func insertSessionExercise(
        exercise: ExerciseModel,
        session: WorkoutSessionModel,
        into context: ModelContext
    ) -> SessionExerciseModel {
        let model = SessionExerciseModel(
            uuid: UUID(),
            order: 0,
            exerciseUUID: exercise.uuid,
            exerciseName: exercise.name,
            prescribedLoad: nil,
            prescribedSets: 3,
            prescribedRepMin: 6,
            prescribedRepMax: 10,
            prescribedRIR: 2,
            restSeconds: 120,
            noteRaw: PrescriptionNote.hold.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(model)
        model.exercise = exercise
        session.exercises.append(model)
        return model
    }

    @discardableResult
    private func insertSet(
        index: Int,
        load: Double,
        reps: Int,
        isWarmup: Bool,
        sessionExercise: SessionExerciseModel,
        into context: ModelContext
    ) -> SetLogModel {
        let model = SetLogModel(
            uuid: UUID(),
            index: index,
            load: load,
            reps: reps,
            rir: nil,
            isWarmup: isWarmup,
            completedAt: now,
            sourceRaw: DeviceSource.iphone.rawValue,
            updatedAt: now
        )
        context.insert(model)
        sessionExercise.sets.append(model)
        return model
    }
}

// MARK: - Double do coordinator

/// `SessionPlanner` só precisa de um `SessionCoordinating` para construir; `lastSession` nunca
/// escreve nem consulta o coordinator, então este double não faz nada além de existir.
@MainActor
private final class LastSessionTestCoordinator: SessionCoordinating {
    var activeSession: WorkoutSessionModel?

    func session(withID id: UUID) -> WorkoutSessionModel? { nil }

    func startSession(plan: SessionPlan, now: Date, source: DeviceSource) throws -> UUID {
        UUID()
    }

    func apply(_ event: SessionEvent) throws {}

    var eventsApplied: AsyncStream<SessionEvent> {
        AsyncStream<SessionEvent> { continuation in
            continuation.finish()
        }
    }
}
