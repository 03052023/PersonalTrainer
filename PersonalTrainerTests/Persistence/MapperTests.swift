import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T0.9: mappers ida e volta em container in-memory. Tudo em `@MainActor` (ARCHITECTURE §10).
@MainActor
final class MapperTests: XCTestCase {
    // MARK: - ExerciseMapper

    func testExerciseMapper_definitionToModelAndBack_isIdentity() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let definition = sampleDefinition()

        let model = ExerciseMapper.model(from: definition)
        XCTAssertFalse(model.isArchived)
        XCTAssertEqual(model.uuid, definition.id)
        XCTAssertEqual(model.slug, definition.slug)
        XCTAssertEqual(model.primaryMusclesRaw, "quads,glutes")
        XCTAssertEqual(model.secondaryMusclesRaw, "hamstrings")
        XCTAssertEqual(model.equipmentRaw, "machine")
        XCTAssertEqual(model.loadUnitRaw, "kilograms")
        context.insert(model)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ExerciseModel>())
        XCTAssertEqual(fetched.count, 1)
        let stored = try XCTUnwrap(fetched.first)
        let roundTripped = try ExerciseMapper.definition(from: stored)
        XCTAssertEqual(roundTripped, definition)
    }

    func testExerciseMapper_unknownEquipmentRaw_throws() {
        let model = ExerciseMapper.model(from: sampleDefinition())
        model.equipmentRaw = "hologram"

        XCTAssertThrowsError(try ExerciseMapper.definition(from: model)) { error in
            XCTAssertEqual(
                error as? MappingError,
                .invalidRawValue(model: "ExerciseModel", field: "equipmentRaw", value: "hologram")
            )
        }
    }

    func testExerciseMapper_unknownLoadUnitRaw_throws() {
        let model = ExerciseMapper.model(from: sampleDefinition())
        model.loadUnitRaw = "stones"

        XCTAssertThrowsError(try ExerciseMapper.definition(from: model)) { error in
            XCTAssertEqual(
                error as? MappingError,
                .invalidRawValue(model: "ExerciseModel", field: "loadUnitRaw", value: "stones")
            )
        }
    }

    // MARK: - ProgramMapper

    func testProgramMapper_ordersDaysAndExercisesByOrder() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let squat = insertExercise(slug: "agachamento", primary: [.quads], into: context)
        let bench = insertExercise(slug: "supino", primary: [.chest], into: context)
        let row = insertExercise(slug: "remada", primary: [.back], into: context)

        let program = ProgramModel(
            uuid: UUID(),
            name: "ABC",
            isActive: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        context.insert(program)

        // Inseridos fora de ordem de propósito: o mapper ordena por `order`, não por inserção.
        let dayB = ProgramDayModel(uuid: UUID(), name: "Dia B", order: 1)
        context.insert(dayB)
        program.days.append(dayB)
        let dayA = ProgramDayModel(uuid: UUID(), name: "Dia A", order: 0)
        context.insert(dayA)
        program.days.append(dayA)

        let benchTarget = insertProgramExercise(order: 1, exercise: bench, startingLoad: 40, into: context, day: dayA)
        let squatTarget = insertProgramExercise(order: 0, exercise: squat, startingLoad: nil, into: context, day: dayA)
        let rowTarget = insertProgramExercise(order: 0, exercise: row, startingLoad: 30, into: context, day: dayB)
        try context.save()

        let template = try ProgramMapper.template(from: program)

        let expected = ProgramTemplate(
            id: program.uuid,
            name: "ABC",
            days: [
                ProgramDayTemplate(
                    id: dayA.uuid,
                    name: "Dia A",
                    order: 0,
                    exercises: [
                        ExerciseTarget(
                            id: squatTarget.uuid,
                            exerciseID: squat.uuid,
                            order: 0,
                            sets: 3,
                            repMin: 8,
                            repMax: 12,
                            targetRIR: 2,
                            restSeconds: 120,
                            startingLoad: nil
                        ),
                        ExerciseTarget(
                            id: benchTarget.uuid,
                            exerciseID: bench.uuid,
                            order: 1,
                            sets: 3,
                            repMin: 8,
                            repMax: 12,
                            targetRIR: 2,
                            restSeconds: 120,
                            startingLoad: 40
                        ),
                    ]
                ),
                ProgramDayTemplate(
                    id: dayB.uuid,
                    name: "Dia B",
                    order: 1,
                    exercises: [
                        ExerciseTarget(
                            id: rowTarget.uuid,
                            exerciseID: row.uuid,
                            order: 0,
                            sets: 3,
                            repMin: 8,
                            repMax: 12,
                            targetRIR: 2,
                            restSeconds: 120,
                            startingLoad: 30
                        ),
                    ]
                ),
            ],
            isActive: true
        )
        XCTAssertEqual(template, expected)
    }

    func testProgramMapper_missingExerciseRelation_throws() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext

        let program = ProgramModel(
            uuid: UUID(),
            name: "ABC",
            isActive: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        context.insert(program)
        let day = ProgramDayModel(uuid: UUID(), name: "Dia A", order: 0)
        context.insert(day)
        program.days.append(day)
        let orphan = insertProgramExercise(order: 0, exercise: nil, startingLoad: nil, into: context, day: day)
        try context.save()

        XCTAssertThrowsError(try ProgramMapper.template(from: program)) { error in
            XCTAssertEqual(error as? MappingError, .missingExercise(programExerciseUUID: orphan.uuid))
        }
    }

    // MARK: - HistoryMapper

    func testHistoryMapper_filtersByExerciseAndStatus_sortsNewestFirst() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let legPress = insertExercise(slug: "leg-press-45", primary: [.quads], into: context)
        let bench = insertExercise(slug: "supino", primary: [.chest], into: context)

        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(86_400 * 2)
        let day3 = day1.addingTimeInterval(86_400 * 4)

        // Sessão 1: concluída, em deload → entra, com `wasDeload = true`.
        let session1 = insertSession(status: .completed, startedAt: day1, isDeload: true, into: context)
        let session1LegPress = insertSessionExercise(order: 0, exercise: legPress, into: context, session: session1)
        // Séries inseridas fora de ordem: o mapper ordena por `index`.
        insertSet(index: 1, load: 100, reps: 10, rir: 2, isWarmup: false, at: day1.addingTimeInterval(300), into: context, sessionExercise: session1LegPress)
        insertSet(index: 0, load: 60, reps: 12, rir: nil, isWarmup: true, at: day1.addingTimeInterval(120), into: context, sessionExercise: session1LegPress)
        let session1Bench = insertSessionExercise(order: 1, exercise: bench, into: context, session: session1)
        insertSet(index: 0, load: 50, reps: 10, rir: 2, isWarmup: false, at: day1.addingTimeInterval(600), into: context, sessionExercise: session1Bench)

        // Sessão 2: abandonada → entra (SPEC P3 conta `abandoned`).
        let session2 = insertSession(status: .abandoned, startedAt: day2, isDeload: false, into: context)
        let session2LegPress = insertSessionExercise(order: 0, exercise: legPress, into: context, session: session2)
        insertSet(index: 0, load: 105, reps: 8, rir: 1, isWarmup: false, at: day2.addingTimeInterval(120), into: context, sessionExercise: session2LegPress)

        // Sessão 3: em andamento → fora.
        let session3 = insertSession(status: .inProgress, startedAt: day3, isDeload: false, into: context)
        let session3LegPress = insertSessionExercise(order: 0, exercise: legPress, into: context, session: session3)
        insertSet(index: 0, load: 105, reps: 9, rir: 2, isWarmup: false, at: day3.addingTimeInterval(120), into: context, sessionExercise: session3LegPress)
        try context.save()

        // Caminho real: o app filtra por `exerciseUUID` no banco; o mapper refiltra por status.
        let legPressUUID = legPress.uuid
        let sessionExercises = try context.fetch(
            FetchDescriptor<SessionExerciseModel>(
                predicate: #Predicate<SessionExerciseModel> { $0.exerciseUUID == legPressUUID }
            )
        )
        XCTAssertEqual(sessionExercises.count, 3)

        let history = try HistoryMapper.historyEntries(from: sessionExercises, exerciseUUID: legPress.uuid)

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].sessionID, session2.uuid)
        XCTAssertEqual(history[0].date, day2)
        XCTAssertFalse(history[0].wasDeload)
        XCTAssertEqual(
            history[0].sets,
            [SetResult(load: 105, reps: 8, rir: 1, isWarmup: false, completedAt: day2.addingTimeInterval(120))]
        )
        XCTAssertEqual(history[1].sessionID, session1.uuid)
        XCTAssertEqual(history[1].date, day1)
        XCTAssertTrue(history[1].wasDeload)
        XCTAssertEqual(
            history[1].sets,
            [
                SetResult(load: 60, reps: 12, rir: nil, isWarmup: true, completedAt: day1.addingTimeInterval(120)),
                SetResult(load: 100, reps: 10, rir: 2, isWarmup: false, completedAt: day1.addingTimeInterval(300)),
            ]
        )

        // Passar a lista inteira (sem filtro no banco) dá o mesmo resultado: o mapper filtra.
        let all = try context.fetch(FetchDescriptor<SessionExerciseModel>())
        XCTAssertEqual(all.count, 4)
        XCTAssertEqual(try HistoryMapper.historyEntries(from: all, exerciseUUID: legPress.uuid), history)
        XCTAssertEqual(try HistoryMapper.historyEntries(from: all, exerciseUUID: UUID()), [])
    }

    func testHistoryMapper_skippedExercise_yieldsEntryWithoutSets() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let legPress = insertExercise(slug: "leg-press-45", primary: [.quads], into: context)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = insertSession(status: .completed, startedAt: startedAt, isDeload: false, into: context)
        let skipped = insertSessionExercise(order: 0, exercise: legPress, into: context, session: session)
        skipped.wasSkipped = true
        try context.save()

        let history = try HistoryMapper.historyEntries(from: [skipped], exerciseUUID: legPress.uuid)

        // SPEC P7: 0 séries de trabalho → o motor ignora a sessão; o mapper só reporta.
        XCTAssertEqual(history, [ExerciseHistoryEntry(sessionID: session.uuid, date: startedAt, sets: [], wasDeload: false)])
    }

    func testHistoryMapper_unknownStatusRaw_throws() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let legPress = insertExercise(slug: "leg-press-45", primary: [.quads], into: context)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = insertSession(status: .completed, startedAt: startedAt, isDeload: false, into: context)
        session.statusRaw = "paused"
        let sessionExercise = insertSessionExercise(order: 0, exercise: legPress, into: context, session: session)
        try context.save()

        // Mesma política de SessionSummaryMapper: raw desconhecido é erro, não sessão ignorada.
        XCTAssertThrowsError(try HistoryMapper.historyEntries(from: [sessionExercise], exerciseUUID: legPress.uuid)) { error in
            XCTAssertEqual(
                error as? MappingError,
                .invalidRawValue(model: "WorkoutSessionModel", field: "statusRaw", value: "paused")
            )
        }
    }

    // MARK: - SessionSummaryMapper

    func testSessionSummaryMapper_countsWorkingSetsAndPrimaryMuscles() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let bench = insertExercise(slug: "supino", primary: [.chest], secondary: [.triceps], into: context)
        let row = insertExercise(slug: "remada", primary: [.back], into: context)
        let squat = insertExercise(slug: "agachamento", primary: [.quads], into: context)
        // Rosca só existe no catálogo passado como dicionário: simula relação anulada.
        let curl = ExerciseDefinition(
            id: UUID(),
            slug: "rosca-direta",
            name: "Rosca direta",
            primaryMuscles: [.biceps],
            equipment: .barbell,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = insertSession(status: .completed, startedAt: startedAt, isDeload: false, into: context)
        session.endedAt = startedAt.addingTimeInterval(3_600)

        // Supino: 1 aquecimento + 2 trabalho → chest conta; triceps é secundário e não conta.
        let benchExercise = insertSessionExercise(order: 0, exercise: bench, into: context, session: session)
        insertSet(index: 0, load: 40, reps: 12, rir: nil, isWarmup: true, at: startedAt.addingTimeInterval(60), into: context, sessionExercise: benchExercise)
        insertSet(index: 1, load: 60, reps: 10, rir: 2, isWarmup: false, at: startedAt.addingTimeInterval(240), into: context, sessionExercise: benchExercise)
        insertSet(index: 2, load: 60, reps: 9, rir: 1, isWarmup: false, at: startedAt.addingTimeInterval(420), into: context, sessionExercise: benchExercise)

        // Remada: só aquecimento → back não conta (SPEC §7.4 exige série de trabalho).
        let rowExercise = insertSessionExercise(order: 1, exercise: row, into: context, session: session)
        insertSet(index: 0, load: 30, reps: 12, rir: nil, isWarmup: true, at: startedAt.addingTimeInterval(600), into: context, sessionExercise: rowExercise)

        // Agachamento: pulado, 0 séries → quads não conta.
        let squatExercise = insertSessionExercise(order: 2, exercise: squat, into: context, session: session)
        squatExercise.wasSkipped = true

        // Rosca: sem relação com o catálogo, 1 série de trabalho → biceps via dicionário.
        let curlExercise = insertSessionExercise(order: 3, exercise: nil, exerciseUUID: curl.id, into: context, session: session)
        insertSet(index: 0, load: 20, reps: 10, rir: 2, isWarmup: false, at: startedAt.addingTimeInterval(900), into: context, sessionExercise: curlExercise)
        try context.save()

        let summary = try SessionSummaryMapper.summary(from: session, catalog: [curl.id: curl])

        XCTAssertEqual(summary.id, session.uuid)
        XCTAssertEqual(summary.programDayID, session.programDayUUID)
        XCTAssertEqual(summary.startedAt, startedAt)
        XCTAssertEqual(summary.endedAt, startedAt.addingTimeInterval(3_600))
        XCTAssertEqual(summary.status, .completed)
        XCTAssertEqual(summary.workingSetCount, 3)
        XCTAssertEqual(summary.primaryMusclesTrained, [.chest, .biceps])

        // Sem o catálogo, a rosca (relação anulada) não contribui grupo, mas a série conta.
        let withoutCatalog = try SessionSummaryMapper.summary(from: session)
        XCTAssertEqual(withoutCatalog.workingSetCount, 3)
        XCTAssertEqual(withoutCatalog.primaryMusclesTrained, [.chest])
    }

    func testSessionSummaryMapper_inProgressSessionWithoutSets_isEmptySummary() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = insertSession(status: .inProgress, startedAt: startedAt, isDeload: false, into: context)
        try context.save()

        let summary = try SessionSummaryMapper.summary(from: session)

        XCTAssertEqual(summary.status, .inProgress)
        XCTAssertNil(summary.endedAt)
        XCTAssertEqual(summary.workingSetCount, 0)
        XCTAssertTrue(summary.primaryMusclesTrained.isEmpty)
    }

    func testSessionSummaryMapper_unknownStatusRaw_throws() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: "paused",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: "iphone"
        )
        context.insert(session)

        XCTAssertThrowsError(try SessionSummaryMapper.summary(from: session)) { error in
            XCTAssertEqual(
                error as? MappingError,
                .invalidRawValue(model: "WorkoutSessionModel", field: "statusRaw", value: "paused")
            )
        }
    }

    // MARK: - Fixtures

    private func sampleDefinition() -> ExerciseDefinition {
        ExerciseDefinition(
            id: UUID(),
            slug: "leg-press-45",
            name: "Leg press 45°",
            primaryMuscles: [.quads, .glutes],
            secondaryMuscles: [.hamstrings],
            equipment: .machine,
            loadUnit: .kilograms,
            loadIncrement: 5,
            isUnilateral: false,
            machineNotes: "Banco 3"
        )
    }

    private func insertExercise(
        slug: String,
        primary: [MuscleGroup],
        secondary: [MuscleGroup] = [],
        into context: ModelContext
    ) -> ExerciseModel {
        let model = ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: slug,
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups(primary),
            secondaryMusclesRaw: SchemaV1.encodeMuscleGroups(secondary),
            equipmentRaw: Equipment.machine.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        context.insert(model)
        return model
    }

    @discardableResult
    private func insertProgramExercise(
        order: Int,
        exercise: ExerciseModel?,
        startingLoad: Double?,
        into context: ModelContext,
        day: ProgramDayModel
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

    private func insertSession(
        status: SessionStatus,
        startedAt: Date,
        isDeload: Bool,
        into context: ModelContext
    ) -> WorkoutSessionModel {
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: status.rawValue,
            startedAt: startedAt,
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: isDeload,
            sourceRaw: "iphone"
        )
        context.insert(session)
        return session
    }

    private func insertSessionExercise(
        order: Int,
        exercise: ExerciseModel?,
        exerciseUUID: UUID? = nil,
        into context: ModelContext,
        session: WorkoutSessionModel
    ) -> SessionExerciseModel {
        let resolvedUUID: UUID
        if let exerciseUUID {
            resolvedUUID = exerciseUUID
        } else if let exercise {
            resolvedUUID = exercise.uuid
        } else {
            resolvedUUID = UUID()
        }

        let model = SessionExerciseModel(
            uuid: UUID(),
            order: order,
            exerciseUUID: resolvedUUID,
            exerciseName: exercise?.name ?? "Exercício",
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
        at completedAt: Date,
        into context: ModelContext,
        sessionExercise: SessionExerciseModel
    ) -> SetLogModel {
        let model = SetLogModel(
            uuid: UUID(),
            index: index,
            load: load,
            reps: reps,
            rir: rir,
            isWarmup: isWarmup,
            completedAt: completedAt,
            sourceRaw: "iphone",
            updatedAt: completedAt
        )
        context.insert(model)
        sessionExercise.sets.append(model)
        return model
    }
}
