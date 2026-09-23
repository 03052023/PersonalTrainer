import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T1.2: `SessionPlanner` sobre container in-memory, tudo em `@MainActor` (ARCHITECTURE §10).
/// O coordinator é um double que só registra chamadas: o planejador nunca grava nada sozinho.
@MainActor
final class SessionPlannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Sem programa ativo

    func testNextPlan_withoutAnyProgram_returnsNil() throws {
        let fixture = try makeFixture()

        XCTAssertNil(try fixture.planner.nextPlan(now: now))
        XCTAssertNil(try fixture.planner.plan(forDayID: UUID(), now: now))
    }

    func testNextPlan_withOnlyInactiveProgram_returnsNil() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let program = insertProgram(name: "Antigo", isActive: false, createdAt: now, into: context)
        let day = insertDay(name: "Dia A", order: 0, program: program, into: context)
        let bench = insertExercise(slug: "supino-reto", name: "Supino reto", primary: [.chest], equipment: .barbell, increment: 2.5, into: context)
        insertProgramExercise(order: 0, exercise: bench, startingLoad: 40, day: day, into: context)
        try context.save()

        XCTAssertNil(try fixture.planner.nextPlan(now: now))
        XCTAssertNil(try fixture.planner.plan(forDayID: day.uuid, now: now))
    }

    func testNextPlan_activeProgramWithoutDays_returnsNil() throws {
        let fixture = try makeFixture()
        insertProgram(name: "Vazio", isActive: true, createdAt: now, into: fixture.context)
        try fixture.context.save()

        XCTAssertNil(try fixture.planner.nextPlan(now: now))
    }

    // MARK: - Programa ativo sem histórico (SPEC S2 → D1, P2 → calibrate)

    func testP2_activeProgramWithoutHistory_plansDayAWithCalibration() throws {
        let fixture = try makeFixture()
        let abc = try insertABCProgram(into: fixture.context)

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))

        XCTAssertEqual(plan.programID, abc.program.uuid)
        XCTAssertEqual(plan.programName, "ABC")
        XCTAssertEqual(plan.programDayID, abc.dayA.uuid)
        XCTAssertEqual(plan.programDayName, "Dia A")
        XCTAssertEqual(plan.generatedAt, now)
        // Inseridos fora de ordem na fixture: o plano segue `order`, não a inserção.
        XCTAssertEqual(plan.exercises.map(\.exercise.slug), ["supino-reto", "agachamento"])
        XCTAssertEqual(plan.exercises.map(\.target.order), [0, 1])

        let bench = try XCTUnwrap(plan.exercises.first)
        XCTAssertEqual(bench.exercise.id, abc.bench.uuid)
        XCTAssertEqual(bench.exercise.loadIncrement, 2.5)
        XCTAssertEqual(bench.target.id, abc.benchTarget.uuid)
        XCTAssertEqual(bench.target.exerciseID, abc.bench.uuid)
        XCTAssertEqual(bench.target.startingLoad, 40)
        // SPEC P2 com `startingLoad`: carga = startingLoad, meta = repMin, nota calibrate.
        XCTAssertEqual(bench.prescription.exerciseID, abc.bench.uuid)
        XCTAssertEqual(bench.prescription.load, 40)
        XCTAssertEqual(bench.prescription.note, .calibrate)
        XCTAssertEqual(bench.prescription.targetReps, 8)
        XCTAssertEqual(bench.prescription.targetRIR, 2)
        XCTAssertEqual(bench.prescription.sets, 3)
        XCTAssertEqual(bench.prescription.repMin, 8)
        XCTAssertEqual(bench.prescription.repMax, 12)
        XCTAssertEqual(bench.prescription.restSeconds, 120)

        let squat = try XCTUnwrap(plan.exercises.last)
        XCTAssertEqual(squat.exercise.id, abc.squat.uuid)
        XCTAssertEqual(squat.target.id, abc.squatTarget.uuid)
        // SPEC P2 sem `startingLoad`: carga vazia e RIR alvo = T + 1.
        XCTAssertNil(squat.prescription.load)
        XCTAssertEqual(squat.prescription.note, .calibrate)
        XCTAssertEqual(squat.prescription.targetReps, 8)
        XCTAssertEqual(squat.prescription.targetRIR, 3)

        XCTAssertNotEqual(bench.id, squat.id, "Cada PlannedExercise nasce com id próprio")

        // Planejar não grava nada nem toca o coordinator.
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<WorkoutSessionModel>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<SessionExerciseModel>()), 0)
        XCTAssertTrue(fixture.coordinator.startCalls.isEmpty)
        XCTAssertTrue(fixture.coordinator.appliedEvents.isEmpty)
    }

    func testPlanForDayID_returnsChosenDayRegardlessOfRotation() throws {
        let fixture = try makeFixture()
        let abc = try insertABCProgram(into: fixture.context)

        // SPEC S4: sem histórico a rotação aponta para o Dia A, mas o usuário pede o Dia B.
        let plan = try XCTUnwrap(try fixture.planner.plan(forDayID: abc.dayB.uuid, now: now))

        XCTAssertEqual(plan.programID, abc.program.uuid)
        XCTAssertEqual(plan.programDayID, abc.dayB.uuid)
        XCTAssertEqual(plan.programDayName, "Dia B")
        XCTAssertEqual(plan.exercises.map(\.exercise.slug), ["remada-baixa"])
        let row = try XCTUnwrap(plan.exercises.first)
        XCTAssertEqual(row.prescription.load, 30)
        XCTAssertEqual(row.prescription.note, .calibrate)
    }

    func testPlanForDayID_unknownDay_returnsNil() throws {
        let fixture = try makeFixture()
        _ = try insertABCProgram(into: fixture.context)

        XCTAssertNil(try fixture.planner.plan(forDayID: UUID(), now: now))
    }

    // MARK: - Rotação e progressão a partir do histórico

    func testS2_completedDayAWithWorkingSets_nextPlanIsDayB_andP4_dayAIncreases() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let abc = try insertABCProgram(into: context)

        // Dia A concluído há 2 dias: supino 3 × 12 @ 40 kg (inc 2,5), RIR 2.
        let startedAt = now.addingTimeInterval(-2 * 86_400)
        let session = insertSession(status: .completed, day: abc.dayA, startedAt: startedAt, into: context)
        let benchInSession = insertSessionExercise(order: 0, exercise: abc.bench, session: session, into: context)
        for index in 0..<3 {
            insertSet(
                index: index,
                load: 40,
                reps: 12,
                rir: 2,
                isWarmup: false,
                completedAt: startedAt.addingTimeInterval(Double(index + 1) * 180),
                sessionExercise: benchInSession,
                into: context
            )
        }
        try context.save()

        // SPEC S2: o dia seguinte ao da última sessão concluída com série de trabalho.
        let next = try XCTUnwrap(try fixture.planner.nextPlan(now: now))
        XCTAssertEqual(next.programDayID, abc.dayB.uuid)
        XCTAssertEqual(next.programDayName, "Dia B")
        XCTAssertEqual(next.exercises.map(\.exercise.slug), ["remada-baixa"])
        let row = try XCTUnwrap(next.exercises.first)
        XCTAssertEqual(row.prescription.load, 30)
        XCTAssertEqual(row.prescription.note, .calibrate)

        // SPEC S4 + P4: pedir o Dia A de novo prescreve L + inc = 42,5 com nota increase.
        let dayA = try XCTUnwrap(try fixture.planner.plan(forDayID: abc.dayA.uuid, now: now))
        XCTAssertEqual(dayA.programDayID, abc.dayA.uuid)
        let bench = try XCTUnwrap(dayA.exercises.first(where: { $0.exercise.id == abc.bench.uuid }))
        XCTAssertEqual(bench.prescription.load, 42.5)
        XCTAssertEqual(bench.prescription.note, .increase)
        XCTAssertEqual(bench.prescription.targetReps, 8)
        XCTAssertEqual(bench.prescription.targetRIR, 2)
        // Agachamento não tem histórico: continua em calibração (SPEC P2).
        let squat = try XCTUnwrap(dayA.exercises.first(where: { $0.exercise.id == abc.squat.uuid }))
        XCTAssertNil(squat.prescription.load)
        XCTAssertEqual(squat.prescription.note, .calibrate)
    }

    func testS2_abandonedSessionWithoutWorkingSets_doesNotMoveRotation() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let abc = try insertABCProgram(into: context)

        // Dia A abandonado há 1 dia só com uma série de aquecimento: 0 séries de trabalho.
        let startedAt = now.addingTimeInterval(-86_400)
        let session = insertSession(status: .abandoned, day: abc.dayA, startedAt: startedAt, into: context)
        let benchInSession = insertSessionExercise(order: 0, exercise: abc.bench, session: session, into: context)
        insertSet(
            index: 0,
            load: 20,
            reps: 12,
            rir: nil,
            isWarmup: true,
            completedAt: startedAt.addingTimeInterval(120),
            sessionExercise: benchInSession,
            into: context
        )
        try context.save()

        // SPEC S2: sessão sem série de trabalho não é referência → continua no Dia A.
        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))
        XCTAssertEqual(plan.programDayID, abc.dayA.uuid)

        // SPEC P1/P7: só aquecimento → sessão ignorada pelo motor → ainda calibrate com startingLoad.
        let bench = try XCTUnwrap(plan.exercises.first(where: { $0.exercise.id == abc.bench.uuid }))
        XCTAssertEqual(bench.prescription.load, 40)
        XCTAssertEqual(bench.prescription.note, .calibrate)
    }

    func testS3_inProgressSessionIsIgnoredByRotationAndHistory() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let abc = try insertABCProgram(into: context)

        // Sessão em andamento no Dia A com 3 séries de trabalho já registradas.
        let startedAt = now.addingTimeInterval(-1_800)
        let session = insertSession(status: .inProgress, day: abc.dayA, startedAt: startedAt, into: context)
        let benchInSession = insertSessionExercise(order: 0, exercise: abc.bench, session: session, into: context)
        for index in 0..<3 {
            insertSet(
                index: index,
                load: 40,
                reps: 12,
                rir: 2,
                isWarmup: false,
                completedAt: startedAt.addingTimeInterval(Double(index + 1) * 180),
                sessionExercise: benchInSession,
                into: context
            )
        }
        try context.save()

        // O seletor ignora `inProgress` (S3 é de quem chama) e o mapper de histórico também (P3).
        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))
        XCTAssertEqual(plan.programDayID, abc.dayA.uuid)
        let bench = try XCTUnwrap(plan.exercises.first(where: { $0.exercise.id == abc.bench.uuid }))
        XCTAssertEqual(bench.prescription.load, 40)
        XCTAssertEqual(bench.prescription.note, .calibrate)
    }

    // MARK: - Programa ativo: escolha e integridade

    func testNextPlan_twoActivePrograms_usesOldestCreated() throws {
        let fixture = try makeFixture()
        let context = fixture.context

        let newer = insertProgram(name: "Novo", isActive: true, createdAt: now, into: context)
        let newerDay = insertDay(name: "Dia X", order: 0, program: newer, into: context)
        let row = insertExercise(slug: "remada-baixa", name: "Remada baixa", primary: [.back], equipment: .machine, increment: 5, into: context)
        insertProgramExercise(order: 0, exercise: row, startingLoad: 30, day: newerDay, into: context)

        let older = insertProgram(name: "Antigo", isActive: true, createdAt: now.addingTimeInterval(-30 * 86_400), into: context)
        let olderDay = insertDay(name: "Dia A", order: 0, program: older, into: context)
        let bench = insertExercise(slug: "supino-reto", name: "Supino reto", primary: [.chest], equipment: .barbell, increment: 2.5, into: context)
        insertProgramExercise(order: 0, exercise: bench, startingLoad: 40, day: olderDay, into: context)
        try context.save()

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))
        XCTAssertEqual(plan.programID, older.uuid)
        XCTAssertEqual(plan.programName, "Antigo")
        XCTAssertEqual(plan.programDayID, olderDay.uuid)

        // O dia do outro programa ativo não pertence ao programa escolhido.
        XCTAssertNil(try fixture.planner.plan(forDayID: newerDay.uuid, now: now))
    }

    func testPlan_programExerciseWithoutCatalogRelation_throwsExerciseNotFound() throws {
        let fixture = try makeFixture()
        let context = fixture.context
        let program = insertProgram(name: "ABC", isActive: true, createdAt: now, into: context)
        let day = insertDay(name: "Dia A", order: 0, program: program, into: context)
        let orphan = insertProgramExercise(order: 0, exercise: nil, startingLoad: nil, day: day, into: context)
        try context.save()

        // Mesmo erro nos dois caminhos: relação anulada é store corrompido (ARCHITECTURE §5).
        XCTAssertThrowsError(try fixture.planner.nextPlan(now: now)) { error in
            XCTAssertEqual(error as? PlanningError, .exerciseNotFound(orphan.uuid))
        }
        XCTAssertThrowsError(try fixture.planner.plan(forDayID: day.uuid, now: now)) { error in
            XCTAssertEqual(error as? PlanningError, .exerciseNotFound(orphan.uuid))
        }
    }

    // MARK: - startSession

    func testStartSession_withoutActiveSession_delegatesToCoordinatorWithIphoneSource() throws {
        let fixture = try makeFixture()
        _ = try insertABCProgram(into: fixture.context)
        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))
        let expectedID = UUID()
        fixture.coordinator.sessionIDToReturn = expectedID
        let startedAt = now.addingTimeInterval(60)

        let sessionID = try fixture.planner.startSession(from: plan, now: startedAt)

        XCTAssertEqual(sessionID, expectedID)
        XCTAssertEqual(fixture.coordinator.startCalls.count, 1)
        let call = try XCTUnwrap(fixture.coordinator.startCalls.first)
        XCTAssertEqual(call.plan, plan)
        XCTAssertEqual(call.now, startedAt)
        XCTAssertEqual(call.source, .iphone)
        // O planejador não grava a sessão: isso é do coordinator (ARCHITECTURE §7).
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<WorkoutSessionModel>()), 0)
    }

    func testStartSession_whenSessionInProgress_throwsAndDoesNotCallCoordinator() throws {
        let fixture = try makeFixture()
        _ = try insertABCProgram(into: fixture.context)
        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))
        let active = makeSession(
            status: .inProgress,
            dayUUID: plan.programDayID,
            dayName: plan.programDayName,
            startedAt: now.addingTimeInterval(-600)
        )
        fixture.coordinator.activeSession = active

        // RF-02: só uma sessão em andamento.
        XCTAssertThrowsError(try fixture.planner.startSession(from: plan, now: now)) { error in
            XCTAssertEqual(error as? PlanningError, .sessionAlreadyInProgress(active.uuid))
        }
        XCTAssertTrue(fixture.coordinator.startCalls.isEmpty)
    }

    // MARK: - Fixtures

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let coordinator: PlannerTestCoordinator
        let planner: SessionPlanner
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let coordinator = PlannerTestCoordinator()
        let planner = SessionPlanner(modelContext: context, coordinator: coordinator)
        return Fixture(container: container, context: context, coordinator: coordinator, planner: planner)
    }

    /// Programa "ABC" ativo com dois dias. Dia A: supino (startingLoad 40, inc 2,5) e agachamento
    /// (sem startingLoad); Dia B: remada baixa (startingLoad 30, inc 5).
    private struct ABCProgram {
        let program: ProgramModel
        let dayA: ProgramDayModel
        let dayB: ProgramDayModel
        let bench: ExerciseModel
        let squat: ExerciseModel
        let row: ExerciseModel
        let benchTarget: ProgramExerciseModel
        let squatTarget: ProgramExerciseModel
        let rowTarget: ProgramExerciseModel
    }

    private func insertABCProgram(into context: ModelContext) throws -> ABCProgram {
        let bench = insertExercise(slug: "supino-reto", name: "Supino reto", primary: [.chest], equipment: .barbell, increment: 2.5, into: context)
        let squat = insertExercise(slug: "agachamento", name: "Agachamento", primary: [.quads], equipment: .barbell, increment: 2.5, into: context)
        let row = insertExercise(slug: "remada-baixa", name: "Remada baixa", primary: [.back], equipment: .machine, increment: 5, into: context)

        let program = insertProgram(name: "ABC", isActive: true, createdAt: now.addingTimeInterval(-60 * 86_400), into: context)
        // Dias e exercícios inseridos fora de ordem de propósito: `order` é a ordem de verdade.
        let dayB = insertDay(name: "Dia B", order: 1, program: program, into: context)
        let dayA = insertDay(name: "Dia A", order: 0, program: program, into: context)
        let squatTarget = insertProgramExercise(order: 1, exercise: squat, startingLoad: nil, day: dayA, into: context)
        let benchTarget = insertProgramExercise(order: 0, exercise: bench, startingLoad: 40, day: dayA, into: context)
        let rowTarget = insertProgramExercise(order: 0, exercise: row, startingLoad: 30, day: dayB, into: context)
        try context.save()

        return ABCProgram(
            program: program,
            dayA: dayA,
            dayB: dayB,
            bench: bench,
            squat: squat,
            row: row,
            benchTarget: benchTarget,
            squatTarget: squatTarget,
            rowTarget: rowTarget
        )
    }

    private func insertExercise(
        slug: String,
        name: String,
        primary: [MuscleGroup],
        equipment: Equipment,
        increment: Double,
        into context: ModelContext
    ) -> ExerciseModel {
        let model = ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: name,
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups(primary),
            secondaryMusclesRaw: "",
            equipmentRaw: equipment.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: increment,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        context.insert(model)
        return model
    }

    @discardableResult
    private func insertProgram(
        name: String,
        isActive: Bool,
        createdAt: Date,
        into context: ModelContext
    ) -> ProgramModel {
        let model = ProgramModel(uuid: UUID(), name: name, isActive: isActive, createdAt: createdAt)
        context.insert(model)
        return model
    }

    private func insertDay(
        name: String,
        order: Int,
        program: ProgramModel,
        into context: ModelContext
    ) -> ProgramDayModel {
        let model = ProgramDayModel(uuid: UUID(), name: name, order: order)
        context.insert(model)
        program.days.append(model)
        return model
    }

    @discardableResult
    private func insertProgramExercise(
        order: Int,
        exercise: ExerciseModel?,
        startingLoad: Double?,
        day: ProgramDayModel,
        into context: ModelContext
    ) -> ProgramExerciseModel {
        let model = ProgramExerciseModel(
            uuid: UUID(),
            order: order,
            sets: 3,
            repMin: 8,
            repMax: 12,
            targetRIR: 2,
            restSeconds: 120,
            startingLoad: startingLoad
        )
        context.insert(model)
        model.exercise = exercise
        day.exercises.append(model)
        return model
    }

    private func makeSession(
        status: SessionStatus,
        dayUUID: UUID,
        dayName: String,
        startedAt: Date
    ) -> WorkoutSessionModel {
        WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: dayUUID,
            programDayName: dayName,
            statusRaw: status.rawValue,
            startedAt: startedAt,
            endedAt: status == .inProgress ? nil : startedAt.addingTimeInterval(3_600),
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: DeviceSource.iphone.rawValue
        )
    }

    private func insertSession(
        status: SessionStatus,
        day: ProgramDayModel,
        startedAt: Date,
        into context: ModelContext
    ) -> WorkoutSessionModel {
        let model = makeSession(status: status, dayUUID: day.uuid, dayName: day.name, startedAt: startedAt)
        context.insert(model)
        return model
    }

    private func insertSessionExercise(
        order: Int,
        exercise: ExerciseModel,
        session: WorkoutSessionModel,
        into context: ModelContext
    ) -> SessionExerciseModel {
        let model = SessionExerciseModel(
            uuid: UUID(),
            order: order,
            exerciseUUID: exercise.uuid,
            exerciseName: exercise.name,
            prescribedLoad: nil,
            prescribedSets: 3,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: 2,
            restSeconds: 120,
            noteRaw: PrescriptionNote.calibrate.rawValue,
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
        rir: Int?,
        isWarmup: Bool,
        completedAt: Date,
        sessionExercise: SessionExerciseModel,
        into context: ModelContext
    ) -> SetLogModel {
        let model = SetLogModel(
            uuid: UUID(),
            index: index,
            load: load,
            reps: reps,
            rir: rir,
            isWarmup: isWarmup,
            completedAt: completedAt,
            sourceRaw: DeviceSource.iphone.rawValue,
            updatedAt: completedAt
        )
        context.insert(model)
        sessionExercise.sets.append(model)
        return model
    }
}

// MARK: - Double do coordinator

/// Registra chamadas e devolve o que o teste configurar. Nunca toca o `ModelContext`: o que se
/// verifica é que o planejador delega a escrita (ARCHITECTURE §7) e mais nada.
@MainActor
private final class PlannerTestCoordinator: SessionCoordinating {
    struct StartCall: Equatable {
        let plan: SessionPlan
        let now: Date
        let source: DeviceSource
    }

    var activeSession: WorkoutSessionModel?
    var sessionIDToReturn = UUID()
    private(set) var startCalls: [StartCall] = []
    private(set) var appliedEvents: [SessionEvent] = []

    func session(withID id: UUID) -> WorkoutSessionModel? {
        guard let activeSession, activeSession.uuid == id else {
            return nil
        }
        return activeSession
    }

    func startSession(plan: SessionPlan, now: Date, source: DeviceSource) throws -> UUID {
        startCalls.append(StartCall(plan: plan, now: now, source: source))
        return sessionIDToReturn
    }

    func apply(_ event: SessionEvent) throws {
        appliedEvents.append(event)
    }

    var eventsApplied: AsyncStream<SessionEvent> {
        AsyncStream<SessionEvent> { continuation in
            continuation.finish()
        }
    }
}
