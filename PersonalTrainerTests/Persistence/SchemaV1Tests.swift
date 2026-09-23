import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// CA0-5: o esquema V1 abre em container in-memory, persiste a hierarquia de sessão,
/// cascateia exclusões e nunca toca o catálogo. Tudo em `@MainActor` (ARCHITECTURE §10).
@MainActor
final class SchemaV1Tests: XCTestCase {
    // MARK: - Esquema e plano de migração

    func testSchemaV1_declaresEightModelsAtVersion1() {
        XCTAssertEqual(SchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertEqual(SchemaV1.models.count, 8)
    }

    func testMigrationPlan_startsAtV1WithoutStages() {
        XCTAssertEqual(PersonalTrainerMigrationPlan.schemas.count, 1)
        XCTAssertTrue(PersonalTrainerMigrationPlan.stages.isEmpty)
        XCTAssertEqual(
            PersonalTrainerMigrationPlan.schemas.first?.versionIdentifier,
            SchemaV1.versionIdentifier
        )
        // O container abre com `CurrentSchema`, que precisa ser sempre a última versão do plano.
        XCTAssertEqual(
            PersonalTrainerMigrationPlan.schemas.last?.versionIdentifier,
            CurrentSchema.versionIdentifier
        )
    }

    // MARK: - Container

    func testInMemoryContainer_opensEmpty() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramModel>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSessionModel>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserSettingsModel>()), 0)
    }

    // MARK: - Sessão: inserir, salvar, buscar

    func testInsertSessionHierarchy_fetchByUUID_returnsExercisesAndSets() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let fixture = try insertSessionFixture(into: context)
        let sessionUUID = fixture.session.uuid

        let descriptor = FetchDescriptor<WorkoutSessionModel>(
            predicate: #Predicate<WorkoutSessionModel> { $0.uuid == sessionUUID }
        )
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        let session = try XCTUnwrap(fetched.first)
        XCTAssertEqual(session.programDayName, "Dia A")
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.sourceRaw, "iphone")
        XCTAssertEqual(session.exercises.count, 1)

        let sessionExercise = try XCTUnwrap(session.exercises.first)
        XCTAssertEqual(sessionExercise.exerciseName, "Leg press 45°")
        XCTAssertEqual(sessionExercise.exerciseUUID, fixture.exercise.uuid)
        XCTAssertEqual(sessionExercise.exercise?.slug, "leg-press-45")
        XCTAssertEqual(sessionExercise.session?.uuid, sessionUUID)
        XCTAssertEqual(sessionExercise.note, .calibrate)

        // To-many não garante ordem; `index` é a ordem de verdade.
        let sets = sessionExercise.sets.sorted { $0.index < $1.index }
        XCTAssertEqual(sets.map { $0.index }, [0, 1, 2])
        XCTAssertTrue(sets[0].isWarmup)
        XCTAssertNil(sets[0].rir)
        XCTAssertFalse(sets[1].isWarmup)
        XCTAssertEqual(sets[1].load, 100)
        XCTAssertEqual(sets[1].reps, 10)
        XCTAssertEqual(sets[1].rir, 2)
        XCTAssertEqual(sets[2].sessionExercise?.uuid, sessionExercise.uuid)
    }

    func testFetchSessionExercises_byExerciseUUIDPredicate() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let fixture = try insertSessionFixture(into: context)
        let exerciseUUID = fixture.exercise.uuid
        let otherUUID = UUID()

        let matching = try context.fetch(
            FetchDescriptor<SessionExerciseModel>(
                predicate: #Predicate<SessionExerciseModel> { $0.exerciseUUID == exerciseUUID }
            )
        )
        let none = try context.fetch(
            FetchDescriptor<SessionExerciseModel>(
                predicate: #Predicate<SessionExerciseModel> { $0.exerciseUUID == otherUUID }
            )
        )

        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?.uuid, fixture.sessionExercise.uuid)
        XCTAssertTrue(none.isEmpty)
    }

    // MARK: - Exclusão em cascata

    func testDeleteSession_cascadesToExercisesAndSets_keepsCatalog() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let fixture = try insertSessionFixture(into: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionExerciseModel>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLogModel>()), 3)

        context.delete(fixture.session)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSessionModel>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionExerciseModel>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetLogModel>()), 0)
        // `exercise` é `nullify`: apagar a sessão nunca toca o catálogo (ARCHITECTURE §5).
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), 1)
    }

    func testDeleteProgram_cascadesToDaysAndExercises_keepsCatalog() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let program = try insertProgramFixture(into: context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramDayModel>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), 1)

        context.delete(program)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramModel>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramDayModel>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), 1)
    }

    // MARK: - Propriedades computadas (raw ↔ TrainerCore)

    func testExerciseModel_muscleGroupsPersistAsCSV() {
        let exercise = makeExercise(uuid: UUID(), slug: "supino-reto", name: "Supino reto")

        exercise.primaryMuscles = [.chest, .triceps]
        exercise.secondaryMuscles = []

        XCTAssertEqual(exercise.primaryMusclesRaw, "chest,triceps")
        XCTAssertEqual(exercise.primaryMuscles, [.chest, .triceps])
        XCTAssertEqual(exercise.secondaryMusclesRaw, "")
        XCTAssertEqual(exercise.secondaryMuscles, [])
        XCTAssertEqual(exercise.equipment, .machine)
        XCTAssertEqual(exercise.loadUnit, .kilograms)
    }

    func testEnumComputedProperties_returnNilForUnknownRawValue() {
        let exercise = makeExercise(uuid: UUID(), slug: "supino-reto", name: "Supino reto")
        exercise.equipmentRaw = "hologram"
        exercise.loadUnitRaw = "stones"
        XCTAssertNil(exercise.equipment)
        XCTAssertNil(exercise.loadUnit)

        let session = makeSession(statusRaw: "paused", startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(session.status)

        XCTAssertEqual(SchemaV1.decodeMuscleGroups("chest,unknown,back"), [.chest, .back])
        XCTAssertEqual(SchemaV1.decodeMuscleGroups(""), [])
    }

    func testUserSettings_weeklyTargetsRoundTripAsJSON() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let uuid = UUID()
        let settings = UserSettingsModel(
            uuid: uuid,
            weekStartsOnMonday: true,
            weeklyTargetsRaw: "{}",
            healthKitEnabled: false,
            defaultRestSeconds: 120,
            schemaSeedVersion: 0
        )
        context.insert(settings)
        XCTAssertEqual(settings.weeklyTargets, [:])

        settings.weeklyTargets = [.chest: 2, .back: 3]
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<UserSettingsModel>())
        XCTAssertEqual(fetched.count, 1)
        let stored = try XCTUnwrap(fetched.first)
        XCTAssertEqual(stored.uuid, uuid)
        XCTAssertEqual(stored.weeklyTargetsRaw, "{\"back\":3,\"chest\":2}")
        XCTAssertEqual(stored.weeklyTargets, [.chest: 2, .back: 3])
        XCTAssertTrue(stored.weekStartsOnMonday)
        XCTAssertEqual(stored.defaultRestSeconds, 120)
        XCTAssertEqual(stored.schemaSeedVersion, 0)
    }

    // MARK: - Fixtures

    private struct SessionFixture {
        let exercise: ExerciseModel
        let session: WorkoutSessionModel
        let sessionExercise: SessionExerciseModel
    }

    private func makeExercise(uuid: UUID, slug: String, name: String) -> ExerciseModel {
        ExerciseModel(
            uuid: uuid,
            slug: slug,
            name: name,
            primaryMusclesRaw: "quads,glutes",
            secondaryMusclesRaw: "hamstrings",
            equipmentRaw: Equipment.machine.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
    }

    private func makeSession(statusRaw: String, startedAt: Date) -> WorkoutSessionModel {
        WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: statusRaw,
            startedAt: startedAt,
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: "iphone"
        )
    }

    /// Insere tudo antes de ligar as relações: é o caminho mais previsível do SwiftData.
    private func insertSessionFixture(into context: ModelContext) throws -> SessionFixture {
        let exercise = makeExercise(uuid: UUID(), slug: "leg-press-45", name: "Leg press 45°")
        context.insert(exercise)

        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let session = makeSession(statusRaw: SessionStatus.completed.rawValue, startedAt: startedAt)
        session.endedAt = startedAt.addingTimeInterval(3_600)
        context.insert(session)

        let sessionExercise = SessionExerciseModel(
            uuid: UUID(),
            order: 0,
            exerciseUUID: exercise.uuid,
            exerciseName: exercise.name,
            prescribedLoad: 100,
            prescribedSets: 3,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: 2,
            restSeconds: 120,
            noteRaw: PrescriptionNote.calibrate.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(sessionExercise)
        sessionExercise.exercise = exercise
        session.exercises.append(sessionExercise)

        let setSpecs: [(load: Double, reps: Int, rir: Int?, isWarmup: Bool)] = [
            (60, 12, nil, true),
            (100, 10, 2, false),
            (100, 9, 1, false),
        ]
        for (index, spec) in setSpecs.enumerated() {
            let completedAt = startedAt.addingTimeInterval(Double(index) * 180)
            let set = SetLogModel(
                uuid: UUID(),
                index: index,
                load: spec.load,
                reps: spec.reps,
                rir: spec.rir,
                isWarmup: spec.isWarmup,
                completedAt: completedAt,
                sourceRaw: "iphone",
                updatedAt: completedAt
            )
            context.insert(set)
            sessionExercise.sets.append(set)
        }

        try context.save()
        return SessionFixture(exercise: exercise, session: session, sessionExercise: sessionExercise)
    }

    private func insertProgramFixture(into context: ModelContext) throws -> ProgramModel {
        let exercise = makeExercise(uuid: UUID(), slug: "leg-press-45", name: "Leg press 45°")
        context.insert(exercise)

        let program = ProgramModel(
            uuid: UUID(),
            name: "Programa padrão",
            isActive: true,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        context.insert(program)

        let day = ProgramDayModel(uuid: UUID(), name: "Dia A", order: 0)
        context.insert(day)
        program.days.append(day)

        let programExercise = ProgramExerciseModel(
            uuid: UUID(),
            order: 0,
            sets: 3,
            repMin: 8,
            repMax: 12,
            targetRIR: 2,
            restSeconds: 120,
            startingLoad: 40
        )
        context.insert(programExercise)
        programExercise.exercise = exercise
        day.exercises.append(programExercise)

        try context.save()
        return program
    }
}
