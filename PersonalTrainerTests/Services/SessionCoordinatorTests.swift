import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T1.3: `SessionCoordinator` é o único caminho de escrita de sessão (ARCHITECTURE §7). Cobre
/// `startSession`, cada `SessionEvent.Kind`, idempotência por `event.id` e por `setID` (RF-22),
/// last-write-wins em `setUpdated`, persistência imediata (RF-06) e o fan-out de `eventsApplied`.
/// Tudo em `@MainActor` com container in-memory (ARCHITECTURE §10).
@MainActor
final class SessionCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - startSession

    func testStartSession_createsSessionAndExercisesFromPlan() throws {
        let fixture = try makeFixture()

        let sessionID = try startSession(fixture)

        let session = try fetchSession(sessionID, in: fixture.context)
        XCTAssertEqual(session.programDayUUID, fixture.plan.programDayID)
        XCTAssertEqual(session.programDayName, "Dia A")
        XCTAssertEqual(session.status, .inProgress)
        XCTAssertEqual(session.startedAt, now)
        XCTAssertNil(session.endedAt)
        XCTAssertEqual(session.notes, "")
        XCTAssertFalse(session.isDeload)
        XCTAssertEqual(session.sourceRaw, DeviceSource.iphone.rawValue)
        XCTAssertNil(session.hkWorkoutUUID)
        XCTAssertNil(session.avgHeartRate)
        XCTAssertNil(session.maxHeartRate)

        // To-many não garante ordem; `order` é a ordem de verdade.
        let exercises = session.exercises.sorted { $0.order < $1.order }
        XCTAssertEqual(exercises.count, 2)
        XCTAssertEqual(exercises.map { $0.uuid }, fixture.plan.exercises.map { $0.id })
        XCTAssertEqual(exercises.map { $0.order }, [0, 1])

        let first = exercises[0]
        XCTAssertEqual(first.exerciseUUID, fixture.legPress.uuid)
        XCTAssertEqual(first.exerciseName, "Leg press 45°")
        XCTAssertEqual(first.prescribedLoad, 100)
        XCTAssertEqual(first.prescribedSets, 4)
        XCTAssertEqual(first.prescribedRepMin, 6)
        XCTAssertEqual(first.prescribedRepMax, 10)
        XCTAssertEqual(first.prescribedRIR, 1)
        XCTAssertEqual(first.restSeconds, 90)
        XCTAssertEqual(first.note, .increase)
        XCTAssertFalse(first.wasSkipped)
        XCTAssertNil(first.substitutedFromUUID)
        XCTAssertEqual(first.exercise?.uuid, fixture.legPress.uuid)
        XCTAssertEqual(first.session?.uuid, sessionID)
        XCTAssertTrue(first.sets.isEmpty)

        let second = exercises[1]
        XCTAssertEqual(second.exerciseUUID, fixture.squat.uuid)
        XCTAssertEqual(second.exerciseName, "Agachamento livre")
        XCTAssertNil(second.prescribedLoad, "Prescrição de calibração sem carga (SPEC P2)")
        XCTAssertEqual(second.prescribedSets, 3)
        XCTAssertEqual(second.prescribedRepMin, 8)
        XCTAssertEqual(second.prescribedRepMax, 12)
        XCTAssertEqual(second.prescribedRIR, 2)
        XCTAssertEqual(second.restSeconds, 120)
        XCTAssertEqual(second.note, .calibrate)
        XCTAssertEqual(second.exercise?.uuid, fixture.squat.uuid)

        XCTAssertEqual(fixture.coordinator.activeSession?.uuid, sessionID)
        XCTAssertEqual(fixture.coordinator.session(withID: sessionID)?.uuid, sessionID)
        XCTAssertNil(fixture.coordinator.session(withID: UUID()))
    }

    func testStartSession_exerciseMissingFromCatalog_keepsSnapshotWithoutRelation() throws {
        let fixture = try makeFixture()
        let ghost = ExerciseDefinition(
            slug: "fantasma",
            name: "Fantasma",
            primaryMuscles: [.core],
            equipment: .bodyweight,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )
        let plan = SessionPlan(
            programID: fixture.plan.programID,
            programName: fixture.plan.programName,
            programDayID: UUID(),
            programDayName: "Dia X",
            exercises: [
                PlannedExercise(
                    id: UUID(),
                    exercise: ghost,
                    target: ExerciseTarget(exerciseID: ghost.id, order: 0),
                    prescription: ExercisePrescription(exerciseID: ghost.id)
                ),
            ],
            generatedAt: now
        )

        let sessionID = try fixture.coordinator.startSession(plan: plan, now: now, source: .watch)

        let session = try fetchSession(sessionID, in: fixture.context)
        XCTAssertEqual(session.sourceRaw, DeviceSource.watch.rawValue)
        let exercise = try XCTUnwrap(session.exercises.first)
        XCTAssertEqual(exercise.exerciseUUID, ghost.id)
        XCTAssertEqual(exercise.exerciseName, "Fantasma")
        XCTAssertNil(exercise.exercise)
    }

    func testStartSession_whenAnotherInProgress_throwsSessionAlreadyInProgress() throws {
        let fixture = try makeFixture()
        let first = try startSession(fixture)

        assertThrows(.sessionAlreadyInProgress(first)) {
            _ = try fixture.coordinator.startSession(
                plan: makePlan(legPress: fixture.legPress, squat: fixture.squat),
                now: now.addingTimeInterval(60),
                source: .iphone
            )
        }

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<WorkoutSessionModel>()), 1)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<SessionExerciseModel>()), 2)
    }

    func testStartSession_afterFinish_allowsNewSession() throws {
        let fixture = try makeFixture()
        let first = try startSession(fixture)
        try fixture.coordinator.finishSession(sessionID: first, now: now.addingTimeInterval(3_600))
        XCTAssertNil(fixture.coordinator.activeSession)

        let second = try fixture.coordinator.startSession(
            plan: makePlan(legPress: fixture.legPress, squat: fixture.squat),
            now: now.addingTimeInterval(86_400),
            source: .iphone
        )

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(fixture.coordinator.activeSession?.uuid, second)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<WorkoutSessionModel>()), 2)
    }

    // MARK: - setLogged

    func testLogSet_createsSetsAttachedToSessionExercise() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let exerciseID = fixture.plan.exercises[0].id
        let warmupAt = now.addingTimeInterval(60)
        let workAt = now.addingTimeInterval(240)

        let warmupID = try fixture.coordinator.logSet(
            sessionID: sessionID,
            sessionExerciseID: exerciseID,
            index: 0,
            load: 60,
            reps: 12,
            rir: nil,
            isWarmup: true,
            now: warmupAt
        )
        let workID = try fixture.coordinator.logSet(
            sessionID: sessionID,
            sessionExerciseID: exerciseID,
            index: 1,
            load: 100,
            reps: 10,
            rir: 2,
            isWarmup: false,
            now: workAt,
            source: .watch
        )

        let sets = try fetchSets(in: fixture.context)
        XCTAssertEqual(sets.count, 2)
        XCTAssertNotEqual(warmupID, workID)

        let warmup = sets[0]
        XCTAssertEqual(warmup.uuid, warmupID)
        XCTAssertEqual(warmup.index, 0)
        XCTAssertEqual(warmup.load, 60)
        XCTAssertEqual(warmup.reps, 12)
        XCTAssertNil(warmup.rir)
        XCTAssertTrue(warmup.isWarmup)
        XCTAssertEqual(warmup.completedAt, warmupAt)
        XCTAssertEqual(warmup.updatedAt, warmupAt)
        XCTAssertEqual(warmup.sourceRaw, DeviceSource.iphone.rawValue)
        XCTAssertEqual(warmup.sessionExercise?.uuid, exerciseID)

        let work = sets[1]
        XCTAssertEqual(work.uuid, workID)
        XCTAssertEqual(work.index, 1)
        XCTAssertEqual(work.load, 100)
        XCTAssertEqual(work.reps, 10)
        XCTAssertEqual(work.rir, 2)
        XCTAssertFalse(work.isWarmup)
        XCTAssertEqual(work.completedAt, workAt)
        XCTAssertEqual(work.sourceRaw, DeviceSource.watch.rawValue)
        XCTAssertEqual(work.sessionExercise?.session?.uuid, sessionID)

        let sessionExercise = try fetchSessionExercise(exerciseID, in: fixture.context)
        XCTAssertEqual(Set(sessionExercise.sets.map { $0.uuid }), [warmupID, workID])
    }

    func testLogSet_unknownSessionExercise_throwsAndPersistsNothing() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let unknown = UUID()

        assertThrows(.sessionExerciseNotFound(unknown)) {
            _ = try fixture.coordinator.logSet(
                sessionID: sessionID,
                sessionExerciseID: unknown,
                index: 0,
                load: 100,
                reps: 10,
                rir: 2,
                isWarmup: false,
                now: now
            )
        }

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<SetLogModel>()), 0)
    }

    // MARK: - Idempotência (RF-22)

    func testApply_sameEventTwice_createsOneSet() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let event = setLoggedEvent(sessionID: sessionID, sessionExerciseID: fixture.plan.exercises[0].id)

        try fixture.coordinator.apply(event)
        try fixture.coordinator.apply(event)

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<SetLogModel>()), 1)
    }

    func testApply_sameSetIDFromDifferentEvents_createsOneSetAndKeepsFirst() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let exerciseID = fixture.plan.exercises[0].id
        let setID = UUID()
        let first = setLoggedEvent(sessionID: sessionID, sessionExerciseID: exerciseID, setID: setID, load: 100)
        let retry = setLoggedEvent(
            sessionID: sessionID,
            sessionExerciseID: exerciseID,
            setID: setID,
            load: 999,
            occurredAt: now.addingTimeInterval(5),
            source: .watch
        )

        try fixture.coordinator.apply(first)
        try fixture.coordinator.apply(retry)

        let sets = try fetchSets(in: fixture.context)
        XCTAssertEqual(sets.count, 1)
        XCTAssertEqual(sets.first?.uuid, setID)
        XCTAssertEqual(sets.first?.load, 100, "Um `setID` já gravado é tratado como aplicado, não como upsert")
    }

    // MARK: - setUpdated

    func testUpdateSet_newerEventWins_olderIsIgnored() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let setID = try fixture.coordinator.logSet(
            sessionID: sessionID,
            sessionExerciseID: fixture.plan.exercises[0].id,
            index: 0,
            load: 100,
            reps: 10,
            rir: 2,
            isWarmup: false,
            now: now
        )
        let newer = now.addingTimeInterval(60)
        let older = now.addingTimeInterval(30)

        try fixture.coordinator.updateSet(sessionID: sessionID, setID: setID, load: 105, reps: 9, rir: 1, now: newer)
        let updated = try XCTUnwrap(try fetchSets(in: fixture.context).first)
        XCTAssertEqual(updated.load, 105)
        XCTAssertEqual(updated.reps, 9)
        XCTAssertEqual(updated.rir, 1)
        XCTAssertEqual(updated.updatedAt, newer)
        XCTAssertEqual(updated.completedAt, now, "Corrigir não muda a hora da conclusão")

        // Evento com `occurredAt` anterior ao último `updatedAt`: último que escreve vence.
        try fixture.coordinator.updateSet(sessionID: sessionID, setID: setID, load: 50, reps: 5, rir: nil, now: older)
        let unchanged = try XCTUnwrap(try fetchSets(in: fixture.context).first)
        XCTAssertEqual(unchanged.load, 105)
        XCTAssertEqual(unchanged.reps, 9)
        XCTAssertEqual(unchanged.rir, 1)
        XCTAssertEqual(unchanged.updatedAt, newer)
    }

    func testUpdateSet_unknownSet_throwsSetNotFound() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let unknown = UUID()

        assertThrows(.setNotFound(unknown)) {
            try fixture.coordinator.updateSet(sessionID: sessionID, setID: unknown, load: 1, reps: 1, rir: nil, now: now)
        }
    }

    func testUpdateSet_setFromAnotherSession_throwsSetNotFound() throws {
        let fixture = try makeFixture()
        let firstSession = try startSession(fixture)
        let setID = try fixture.coordinator.logSet(
            sessionID: firstSession,
            sessionExerciseID: fixture.plan.exercises[0].id,
            index: 0,
            load: 100,
            reps: 10,
            rir: 2,
            isWarmup: false,
            now: now
        )
        try fixture.coordinator.finishSession(sessionID: firstSession, now: now.addingTimeInterval(600))
        let secondSession = try fixture.coordinator.startSession(
            plan: makePlan(legPress: fixture.legPress, squat: fixture.squat),
            now: now.addingTimeInterval(86_400),
            source: .iphone
        )

        assertThrows(.setNotFound(setID)) {
            try fixture.coordinator.updateSet(
                sessionID: secondSession,
                setID: setID,
                load: 1,
                reps: 1,
                rir: nil,
                now: now.addingTimeInterval(86_500)
            )
        }

        let untouched = try XCTUnwrap(try fetchSets(in: fixture.context).first)
        XCTAssertEqual(untouched.load, 100)
    }

    // MARK: - setDeleted

    func testDeleteSet_removesOnlyThatSet() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let exerciseID = fixture.plan.exercises[0].id
        let firstID = try fixture.coordinator.logSet(
            sessionID: sessionID,
            sessionExerciseID: exerciseID,
            index: 0,
            load: 100,
            reps: 10,
            rir: 2,
            isWarmup: false,
            now: now
        )
        let secondID = try fixture.coordinator.logSet(
            sessionID: sessionID,
            sessionExerciseID: exerciseID,
            index: 1,
            load: 100,
            reps: 9,
            rir: 1,
            isWarmup: false,
            now: now.addingTimeInterval(180)
        )

        try fixture.coordinator.deleteSet(sessionID: sessionID, setID: firstID, now: now.addingTimeInterval(200))

        let remaining = try fetchSets(in: fixture.context)
        XCTAssertEqual(remaining.map { $0.uuid }, [secondID])

        // Contexto novo: o que está no store, não o que o contexto ainda tem em memória.
        let fresh = ModelContext(fixture.container)
        let sessionExercise = try fetchSessionExercise(exerciseID, in: fresh)
        XCTAssertEqual(sessionExercise.sets.map { $0.uuid }, [secondID])

        assertThrows(.setNotFound(firstID)) {
            try fixture.coordinator.deleteSet(sessionID: sessionID, setID: firstID, now: now.addingTimeInterval(300))
        }
    }

    // MARK: - exerciseSkipped

    func testSkipExercise_marksWasSkipped_keepsLoggedSets() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let exerciseID = fixture.plan.exercises[0].id
        _ = try fixture.coordinator.logSet(
            sessionID: sessionID,
            sessionExerciseID: exerciseID,
            index: 0,
            load: 100,
            reps: 10,
            rir: 2,
            isWarmup: false,
            now: now
        )

        try fixture.coordinator.skipExercise(sessionID: sessionID, sessionExerciseID: exerciseID, now: now.addingTimeInterval(60))

        let skipped = try fetchSessionExercise(exerciseID, in: fixture.context)
        XCTAssertTrue(skipped.wasSkipped)
        XCTAssertEqual(skipped.sets.count, 1, "Séries já registradas são mantidas (RF-10)")
        let other = try fetchSessionExercise(fixture.plan.exercises[1].id, in: fixture.context)
        XCTAssertFalse(other.wasSkipped)

        let unknown = UUID()
        assertThrows(.sessionExerciseNotFound(unknown)) {
            try fixture.coordinator.skipExercise(sessionID: sessionID, sessionExerciseID: unknown, now: now)
        }
    }

    // MARK: - exerciseSubstituted

    func testExerciseSubstituted_swapsCatalogExerciseAndRecordsOrigin() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let exerciseID = fixture.plan.exercises[0].id
        let event = SessionEvent(
            sessionID: sessionID,
            occurredAt: now.addingTimeInterval(30),
            source: .iphone,
            kind: .exerciseSubstituted(sessionExerciseID: exerciseID, newExerciseID: fixture.squat.uuid)
        )

        try fixture.coordinator.apply(event)

        let substituted = try fetchSessionExercise(exerciseID, in: fixture.context)
        XCTAssertEqual(substituted.exerciseUUID, fixture.squat.uuid)
        XCTAssertEqual(substituted.exerciseName, "Agachamento livre")
        XCTAssertEqual(substituted.exercise?.uuid, fixture.squat.uuid)
        XCTAssertEqual(substituted.substitutedFromUUID, fixture.legPress.uuid)
        XCTAssertEqual(substituted.prescribedLoad, 100, "A prescrição copiada permanece a do exercício original")
        XCTAssertEqual(substituted.order, 0)
    }

    func testExerciseSubstituted_unknownExercise_throwsExerciseNotFound() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let exerciseID = fixture.plan.exercises[0].id
        let unknown = UUID()
        let event = SessionEvent(
            sessionID: sessionID,
            occurredAt: now,
            source: .iphone,
            kind: .exerciseSubstituted(sessionExerciseID: exerciseID, newExerciseID: unknown)
        )

        assertThrows(.exerciseNotFound(unknown)) {
            try fixture.coordinator.apply(event)
        }

        let untouched = try fetchSessionExercise(exerciseID, in: fixture.context)
        XCTAssertEqual(untouched.exerciseUUID, fixture.legPress.uuid)
        XCTAssertNil(untouched.substitutedFromUUID)
    }

    // MARK: - sessionFinished / sessionAbandoned

    func testFinishSession_setsCompletedAndEndedAt_clearsActiveSession() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let endedAt = now.addingTimeInterval(3_600)

        try fixture.coordinator.finishSession(sessionID: sessionID, now: endedAt)

        let session = try fetchSession(sessionID, in: fixture.context)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.endedAt, endedAt)
        XCTAssertNil(fixture.coordinator.activeSession)
        XCTAssertEqual(fixture.coordinator.session(withID: sessionID)?.uuid, sessionID)
    }

    func testAbandonSession_setsAbandonedAndEndedAt_keepsSets() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        _ = try fixture.coordinator.logSet(
            sessionID: sessionID,
            sessionExerciseID: fixture.plan.exercises[0].id,
            index: 0,
            load: 100,
            reps: 10,
            rir: 2,
            isWarmup: false,
            now: now
        )
        let endedAt = now.addingTimeInterval(900)

        try fixture.coordinator.abandonSession(sessionID: sessionID, now: endedAt)

        let session = try fetchSession(sessionID, in: fixture.context)
        XCTAssertEqual(session.status, .abandoned)
        XCTAssertEqual(session.endedAt, endedAt)
        XCTAssertNil(fixture.coordinator.activeSession)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<SetLogModel>()), 1)
    }

    func testApply_mutationAfterFinish_throwsSessionNotInProgress() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let exerciseID = fixture.plan.exercises[0].id
        let setID = try fixture.coordinator.logSet(
            sessionID: sessionID,
            sessionExerciseID: exerciseID,
            index: 0,
            load: 100,
            reps: 10,
            rir: 2,
            isWarmup: false,
            now: now
        )
        try fixture.coordinator.finishSession(sessionID: sessionID, now: now.addingTimeInterval(3_600))
        let later = now.addingTimeInterval(3_700)

        assertThrows(.sessionNotInProgress(sessionID)) {
            _ = try fixture.coordinator.logSet(
                sessionID: sessionID,
                sessionExerciseID: exerciseID,
                index: 1,
                load: 100,
                reps: 10,
                rir: 2,
                isWarmup: false,
                now: later
            )
        }
        assertThrows(.sessionNotInProgress(sessionID)) {
            try fixture.coordinator.updateSet(sessionID: sessionID, setID: setID, load: 1, reps: 1, rir: nil, now: later)
        }
        assertThrows(.sessionNotInProgress(sessionID)) {
            try fixture.coordinator.deleteSet(sessionID: sessionID, setID: setID, now: later)
        }
        assertThrows(.sessionNotInProgress(sessionID)) {
            try fixture.coordinator.skipExercise(sessionID: sessionID, sessionExerciseID: exerciseID, now: later)
        }
        assertThrows(.sessionNotInProgress(sessionID)) {
            try fixture.coordinator.apply(SessionEvent(
                sessionID: sessionID,
                occurredAt: later,
                source: .iphone,
                kind: .exerciseSubstituted(sessionExerciseID: exerciseID, newExerciseID: fixture.squat.uuid)
            ))
        }
        assertThrows(.sessionNotInProgress(sessionID)) {
            try fixture.coordinator.finishSession(sessionID: sessionID, now: later)
        }
        assertThrows(.sessionNotInProgress(sessionID)) {
            try fixture.coordinator.abandonSession(sessionID: sessionID, now: later)
        }

        let session = try fetchSession(sessionID, in: fixture.context)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.endedAt, now.addingTimeInterval(3_600))
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<SetLogModel>()), 1)
    }

    // MARK: - heartRateSummary

    func testHeartRateSummary_afterFinish_isStoredOnSession() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        try fixture.coordinator.finishSession(sessionID: sessionID, now: now.addingTimeInterval(3_600))
        let hkWorkoutUUID = UUID()
        let event = SessionEvent(
            sessionID: sessionID,
            occurredAt: now.addingTimeInterval(3_650),
            source: .watch,
            kind: .heartRateSummary(averageBPM: 121, maxBPM: 158, hkWorkoutUUID: hkWorkoutUUID)
        )

        try fixture.coordinator.apply(event)

        let session = try fetchSession(sessionID, in: fixture.context)
        XCTAssertEqual(session.avgHeartRate, 121)
        XCTAssertEqual(session.maxHeartRate, 158)
        XCTAssertEqual(session.hkWorkoutUUID, hkWorkoutUUID)
        XCTAssertEqual(session.status, .completed, "O resumo de FC não reabre nem altera o status")
    }

    func testHeartRateSummary_duringSession_isStoredWithoutWorkoutUUID() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let event = SessionEvent(
            sessionID: sessionID,
            occurredAt: now.addingTimeInterval(600),
            source: .watch,
            kind: .heartRateSummary(averageBPM: 110, maxBPM: 140, hkWorkoutUUID: nil)
        )

        try fixture.coordinator.apply(event)

        let session = try fetchSession(sessionID, in: fixture.context)
        XCTAssertEqual(session.avgHeartRate, 110)
        XCTAssertEqual(session.maxHeartRate, 140)
        XCTAssertNil(session.hkWorkoutUUID)
        XCTAssertEqual(session.status, .inProgress)
    }

    // MARK: - sessionStarted e sessão inexistente

    func testApply_sessionStartedForExistingSession_isNoOp() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let event = SessionEvent(
            sessionID: sessionID,
            occurredAt: now,
            source: .watch,
            kind: .sessionStarted(programDayID: fixture.plan.programDayID)
        )

        try fixture.coordinator.apply(event)

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<WorkoutSessionModel>()), 1)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<SessionExerciseModel>()), 2)
        let session = try fetchSession(sessionID, in: fixture.context)
        XCTAssertEqual(session.status, .inProgress)
        XCTAssertEqual(session.sourceRaw, DeviceSource.iphone.rawValue)
    }

    func testApply_unknownSession_throwsSessionNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()
        let event = SessionEvent(
            sessionID: unknown,
            occurredAt: now,
            source: .iphone,
            kind: .sessionFinished(endedAt: now)
        )

        assertThrows(.sessionNotFound(unknown)) {
            try fixture.coordinator.apply(event)
        }
        // Um evento rejeitado não fica marcado como aplicado: reenviá-lo depois de a sessão
        // existir deve funcionar. Aqui basta verificar que uma sessão criada depois é intocada.
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<WorkoutSessionModel>()), 0)
    }

    func testApply_rejectedEvent_isNotMarkedAsApplied() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let exerciseID = fixture.plan.exercises[0].id
        let unknownExercise = UUID()
        // Primeiro falha (exercício inexistente); o mesmo `event.id` reutilizado com dados válidos
        // não pode ser descartado como duplicata.
        let eventID = UUID()
        let invalid = SessionEvent(
            id: eventID,
            sessionID: sessionID,
            occurredAt: now,
            source: .iphone,
            kind: .exerciseSkipped(sessionExerciseID: unknownExercise)
        )
        let valid = SessionEvent(
            id: eventID,
            sessionID: sessionID,
            occurredAt: now,
            source: .iphone,
            kind: .exerciseSkipped(sessionExerciseID: exerciseID)
        )

        assertThrows(.sessionExerciseNotFound(unknownExercise)) {
            try fixture.coordinator.apply(invalid)
        }
        try fixture.coordinator.apply(valid)

        let skipped = try fetchSessionExercise(exerciseID, in: fixture.context)
        XCTAssertTrue(skipped.wasSkipped)
    }

    // MARK: - Persistência imediata (RF-06)

    func testApply_setIsVisibleFromFreshContextOnSameContainer() throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let exerciseID = fixture.plan.exercises[0].id
        let setID = try fixture.coordinator.logSet(
            sessionID: sessionID,
            sessionExerciseID: exerciseID,
            index: 0,
            load: 100,
            reps: 10,
            rir: 2,
            isWarmup: false,
            now: now
        )

        let fresh = ModelContext(fixture.container)
        let sets = try fresh.fetch(
            FetchDescriptor<SetLogModel>(predicate: #Predicate<SetLogModel> { $0.uuid == setID })
        )

        XCTAssertEqual(sets.count, 1)
        let stored = try XCTUnwrap(sets.first)
        XCTAssertEqual(stored.load, 100)
        XCTAssertEqual(stored.reps, 10)
        XCTAssertEqual(stored.sessionExercise?.uuid, exerciseID)
        XCTAssertEqual(stored.sessionExercise?.session?.uuid, sessionID)

        let session = try fetchSession(sessionID, in: fresh)
        XCTAssertEqual(session.status, .inProgress)
        XCTAssertEqual(session.exercises.count, 2)
    }

    // MARK: - eventsApplied

    func testEventsApplied_receivesStartedAndAppliedEventsInOrder() async throws {
        let fixture = try makeFixture()
        // Buffer ilimitado: eventos publicados antes da iteração ficam guardados, sem sleep.
        let stream = fixture.coordinator.eventsApplied

        let sessionID = try startSession(fixture)
        let logged = setLoggedEvent(sessionID: sessionID, sessionExerciseID: fixture.plan.exercises[0].id)
        try fixture.coordinator.apply(logged)

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        XCTAssertEqual(first?.sessionID, sessionID)
        XCTAssertEqual(first?.occurredAt, now)
        XCTAssertEqual(first?.source, .iphone)
        XCTAssertEqual(first?.kind, .sessionStarted(programDayID: fixture.plan.programDayID))
        XCTAssertEqual(second, logged)
    }

    func testEventsApplied_fansOutToEveryConsumer_andSkipsDuplicates() async throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        // Streams criados depois do início: não recebem o `sessionStarted` já publicado.
        let streamA = fixture.coordinator.eventsApplied
        let streamB = fixture.coordinator.eventsApplied
        let logged = setLoggedEvent(sessionID: sessionID, sessionExerciseID: fixture.plan.exercises[0].id)
        let endedAt = now.addingTimeInterval(3_600)

        try fixture.coordinator.apply(logged)
        try fixture.coordinator.apply(logged)
        try fixture.coordinator.finishSession(sessionID: sessionID, now: endedAt)

        var iteratorA = streamA.makeAsyncIterator()
        var iteratorB = streamB.makeAsyncIterator()
        let a1 = await iteratorA.next()
        let a2 = await iteratorA.next()
        let b1 = await iteratorB.next()
        let b2 = await iteratorB.next()

        XCTAssertEqual(a1, logged)
        XCTAssertEqual(b1, logged)
        // A duplicata não foi republicada: o segundo elemento já é o `sessionFinished`.
        XCTAssertEqual(a2?.kind, .sessionFinished(endedAt: endedAt))
        XCTAssertEqual(b2?.kind, .sessionFinished(endedAt: endedAt))
    }

    func testEventsApplied_deliversToConsumerWaitingBeforeTheEvent() async throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let stream = fixture.coordinator.eventsApplied
        let received = expectation(description: "evento entregue ao consumidor")

        let consumer = Task { @MainActor () -> SessionEvent? in
            var iterator = stream.makeAsyncIterator()
            let event = await iterator.next()
            received.fulfill()
            return event
        }

        let logged = setLoggedEvent(sessionID: sessionID, sessionExerciseID: fixture.plan.exercises[0].id)
        try fixture.coordinator.apply(logged)

        await fulfillment(of: [received], timeout: 5)
        let delivered = await consumer.value
        XCTAssertEqual(delivered, logged)
    }

    func testEventsApplied_rejectedEventIsNotPublished() async throws {
        let fixture = try makeFixture()
        let sessionID = try startSession(fixture)
        let stream = fixture.coordinator.eventsApplied
        let unknown = UUID()

        assertThrows(.sessionExerciseNotFound(unknown)) {
            try fixture.coordinator.skipExercise(sessionID: sessionID, sessionExerciseID: unknown, now: now)
        }
        let endedAt = now.addingTimeInterval(3_600)
        try fixture.coordinator.finishSession(sessionID: sessionID, now: endedAt)

        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()

        XCTAssertEqual(first?.kind, .sessionFinished(endedAt: endedAt))
    }

    // MARK: - Fixtures

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let coordinator: SessionCoordinator
        let legPress: ExerciseModel
        let squat: ExerciseModel
        let plan: SessionPlan
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext

        let legPress = makeExerciseModel(slug: "leg-press-45", name: "Leg press 45°", loadIncrement: 5)
        let squat = makeExerciseModel(slug: "agachamento-livre", name: "Agachamento livre", loadIncrement: 2.5)
        context.insert(legPress)
        context.insert(squat)
        try context.save()

        let coordinator = SessionCoordinator(modelContext: context, appliedEvents: AppliedEventStore.inMemory())
        return Fixture(
            container: container,
            context: context,
            coordinator: coordinator,
            legPress: legPress,
            squat: squat,
            plan: makePlan(legPress: legPress, squat: squat)
        )
    }

    private func makeExerciseModel(slug: String, name: String, loadIncrement: Double) -> ExerciseModel {
        ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: name,
            primaryMusclesRaw: "quads,glutes",
            secondaryMusclesRaw: "hamstrings",
            equipmentRaw: Equipment.machine.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: loadIncrement,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
    }

    private func definition(from model: ExerciseModel) -> ExerciseDefinition {
        ExerciseDefinition(
            id: model.uuid,
            slug: model.slug,
            name: model.name,
            primaryMuscles: [.quads, .glutes],
            secondaryMuscles: [.hamstrings],
            equipment: .machine,
            loadUnit: .kilograms,
            loadIncrement: model.loadIncrement
        )
    }

    /// Ids novos a cada chamada, como faria o `SessionPlanner`: dois planos nunca compartilham
    /// `PlannedExercise.id`, que vira `SessionExerciseModel.uuid`.
    private func makePlan(legPress: ExerciseModel, squat: ExerciseModel) -> SessionPlan {
        let legPressDefinition = definition(from: legPress)
        let squatDefinition = definition(from: squat)
        return SessionPlan(
            programID: UUID(),
            programName: "Programa padrão",
            programDayID: UUID(),
            programDayName: "Dia A",
            exercises: [
                PlannedExercise(
                    id: UUID(),
                    exercise: legPressDefinition,
                    target: ExerciseTarget(exerciseID: legPress.uuid, order: 0, sets: 4, repMin: 6, repMax: 10, targetRIR: 1, restSeconds: 90),
                    prescription: ExercisePrescription(
                        exerciseID: legPress.uuid,
                        load: 100,
                        sets: 4,
                        repMin: 6,
                        repMax: 10,
                        targetReps: 6,
                        targetRIR: 1,
                        restSeconds: 90,
                        note: .increase
                    )
                ),
                PlannedExercise(
                    id: UUID(),
                    exercise: squatDefinition,
                    target: ExerciseTarget(exerciseID: squat.uuid, order: 1),
                    prescription: ExercisePrescription(exerciseID: squat.uuid)
                ),
            ],
            generatedAt: now
        )
    }

    private func startSession(_ fixture: Fixture) throws -> UUID {
        try fixture.coordinator.startSession(plan: fixture.plan, now: now, source: .iphone)
    }

    private func setLoggedEvent(
        sessionID: UUID,
        sessionExerciseID: UUID,
        setID: UUID = UUID(),
        index: Int = 0,
        load: Double = 100,
        reps: Int = 10,
        rir: Int? = 2,
        isWarmup: Bool = false,
        occurredAt: Date? = nil,
        source: DeviceSource = .iphone
    ) -> SessionEvent {
        SessionEvent(
            sessionID: sessionID,
            occurredAt: occurredAt ?? now,
            source: source,
            kind: .setLogged(
                sessionExerciseID: sessionExerciseID,
                setID: setID,
                index: index,
                load: load,
                reps: reps,
                rir: rir,
                isWarmup: isWarmup
            )
        )
    }

    // MARK: - Consultas

    private func fetchSession(_ id: UUID, in context: ModelContext) throws -> WorkoutSessionModel {
        let descriptor = FetchDescriptor<WorkoutSessionModel>(
            predicate: #Predicate<WorkoutSessionModel> { $0.uuid == id }
        )
        return try XCTUnwrap(try context.fetch(descriptor).first)
    }

    private func fetchSessionExercise(_ id: UUID, in context: ModelContext) throws -> SessionExerciseModel {
        let descriptor = FetchDescriptor<SessionExerciseModel>(
            predicate: #Predicate<SessionExerciseModel> { $0.uuid == id }
        )
        return try XCTUnwrap(try context.fetch(descriptor).first)
    }

    /// Todas as séries do store, por `index` (to-many não garante ordem).
    private func fetchSets(in context: ModelContext) throws -> [SetLogModel] {
        try context.fetch(FetchDescriptor<SetLogModel>()).sorted { $0.index < $1.index }
    }

    private func assertThrows(
        _ expected: SessionCoordinatorError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        do {
            try body()
            XCTFail("Esperava \(expected)", file: file, line: line)
        } catch let error as SessionCoordinatorError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Erro inesperado: \(error)", file: file, line: line)
        }
    }
}
