import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Réplica do `PersonalTrainerMigrationPlan` da M1 (só V1, sem estágios), para gravar o store
/// V1 exatamente como o app instalado o gravava.
private enum SchemaV1OnlyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// T2.11 (AGENTS R6): um store gravado com `SchemaV1` em disco abre com `SchemaV2` pelo
/// `PersonalTrainerMigrationPlan` (estágio leve), preserva todos os dados e preenche os campos
/// novos com os padrões declarados. Também cobre os campos novos de V2 em container in-memory.
/// Tudo em `@MainActor` (ARCHITECTURE §10).
@MainActor
final class SchemaV2MigrationTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Esquema e plano

    func testSchemaV2_declaresEightModelsAtVersion2() {
        XCTAssertEqual(SchemaV2.versionIdentifier, Schema.Version(2, 0, 0))
        XCTAssertEqual(SchemaV2.models.count, 8)
        XCTAssertEqual(CurrentSchema.versionIdentifier, SchemaV2.versionIdentifier)
    }

    func testMigrationPlan_listsV1ThenV2WithOneStage() {
        XCTAssertEqual(
            PersonalTrainerMigrationPlan.schemas.map { $0.versionIdentifier },
            [Schema.Version(1, 0, 0), Schema.Version(2, 0, 0)]
        )
        XCTAssertEqual(PersonalTrainerMigrationPlan.stages.count, 1)
    }

    // MARK: - Migração V1 → V2 em disco

    func testV1Store_opensWithV2_preservesDataAndFillsDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SchemaV2MigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("PersonalTrainer.store", isDirectory: false)

        // O pool garante que container, contexto e modelos V1 sejam liberados (e o SQLite
        // fechado) antes de o store ser reaberto com V2, como num relançamento do app.
        let fixture = try autoreleasepool {
            try writeV1Store(at: storeURL)
        }

        let schemaV2 = Schema(versionedSchema: SchemaV2.self)
        let container = try ModelContainer(
            for: schemaV2,
            migrationPlan: PersonalTrainerMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schemaV2, url: storeURL)]
        )
        let context = container.mainContext

        // Catálogo: dados preservados; campos novos nos padrões.
        let exercises = try context.fetch(FetchDescriptor<ExerciseModel>())
        XCTAssertEqual(exercises.count, 1)
        let exercise = try XCTUnwrap(exercises.first)
        XCTAssertEqual(exercise.uuid, fixture.exerciseID)
        XCTAssertEqual(exercise.slug, "leg-press-45")
        XCTAssertEqual(exercise.name, "Leg press 45°")
        XCTAssertEqual(exercise.primaryMuscles, [.quads, .glutes])
        XCTAssertEqual(exercise.secondaryMuscles, [.hamstrings])
        XCTAssertEqual(exercise.equipment, .machine)
        XCTAssertEqual(exercise.loadUnit, .kilograms)
        XCTAssertEqual(exercise.loadIncrement, 5)
        XCTAssertEqual(exercise.machineNotes, "Banco 3")
        XCTAssertTrue(exercise.isArchived)
        XCTAssertNil(exercise.movementPatternRaw)
        XCTAssertNil(exercise.movementPattern)
        XCTAssertFalse(exercise.isCustom)

        // Programa: grafo preservado; objetivo vira hipertrofia.
        let programs = try context.fetch(FetchDescriptor<ProgramModel>())
        XCTAssertEqual(programs.count, 1)
        let program = try XCTUnwrap(programs.first)
        XCTAssertEqual(program.uuid, fixture.programID)
        XCTAssertEqual(program.name, "Programa ABC")
        XCTAssertTrue(program.isActive)
        XCTAssertEqual(program.createdAt, startedAt)
        XCTAssertEqual(program.goalRaw, "hypertrophy")
        XCTAssertEqual(program.goal, .hypertrophy)
        XCTAssertNil(program.summary)
        XCTAssertEqual(program.days.count, 1)
        let day = try XCTUnwrap(program.days.first)
        XCTAssertEqual(day.name, "Dia A")
        XCTAssertEqual(day.exercises.count, 1)
        let target = try XCTUnwrap(day.exercises.first)
        XCTAssertEqual(target.repMin, 8)
        XCTAssertEqual(target.repMax, 12)
        XCTAssertEqual(target.startingLoad, 40)
        XCTAssertEqual(target.exercise?.uuid, fixture.exerciseID)

        // O mapper lê o programa migrado sem erro, com o objetivo padrão.
        let template = try ProgramMapper.template(from: program)
        XCTAssertEqual(template.goal, .hypertrophy)
        XCTAssertEqual(template.days.first?.exercises.first?.exerciseID, fixture.exerciseID)

        // Sessão: snapshot e séries preservados; meta de reps desconhecida (0).
        let sessions = try context.fetch(FetchDescriptor<WorkoutSessionModel>())
        XCTAssertEqual(sessions.count, 1)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(session.uuid, fixture.sessionID)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.startedAt, startedAt)
        XCTAssertEqual(session.endedAt, startedAt.addingTimeInterval(3_600))
        XCTAssertEqual(session.sourceRaw, "iphone")
        XCTAssertEqual(session.exercises.count, 1)
        let sessionExercise = try XCTUnwrap(session.exercises.first)
        XCTAssertEqual(sessionExercise.exerciseUUID, fixture.exerciseID)
        XCTAssertEqual(sessionExercise.exerciseName, "Leg press 45°")
        XCTAssertEqual(sessionExercise.prescribedLoad, 100)
        XCTAssertEqual(sessionExercise.prescribedRepMin, 8)
        XCTAssertEqual(sessionExercise.prescribedRepMax, 12)
        XCTAssertEqual(sessionExercise.note, .hold)
        XCTAssertEqual(sessionExercise.prescribedTargetReps, 0)
        XCTAssertEqual(sessionExercise.exercise?.uuid, fixture.exerciseID)

        let sets = sessionExercise.sets.sorted { $0.index < $1.index }
        XCTAssertEqual(sets.map(\.uuid), fixture.setIDs)
        XCTAssertEqual(sets.map(\.load), [60, 100])
        XCTAssertEqual(sets.map(\.reps), [12, 10])
        XCTAssertEqual(sets.map(\.rir), [nil, 2])
        XCTAssertEqual(sets.map(\.isWarmup), [true, false])

        // O histórico que o motor lê sai igual do store migrado.
        let history = try HistoryMapper.historyEntries(
            from: [sessionExercise],
            exerciseUUID: fixture.exerciseID
        )
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.sets.count, 2)

        // Configuração intacta.
        let settingsRows = try context.fetch(FetchDescriptor<UserSettingsModel>())
        XCTAssertEqual(settingsRows.count, 1)
        let settings = try XCTUnwrap(settingsRows.first)
        XCTAssertEqual(settings.uuid, fixture.settingsID)
        XCTAssertEqual(settings.schemaSeedVersion, 1)
        XCTAssertEqual(settings.defaultRestSeconds, 90)
        XCTAssertEqual(settings.weeklyTargets, [.chest: 2])

        // O store migrado aceita escrita dos campos novos.
        program.goal = .strength
        program.summary = "Força 3×/semana"
        exercise.movementPattern = .squat
        sessionExercise.prescribedTargetReps = 10
        try context.save()
        let reloaded = try XCTUnwrap(context.fetch(FetchDescriptor<ProgramModel>()).first)
        XCTAssertEqual(reloaded.goalRaw, "strength")
        XCTAssertEqual(reloaded.summary, "Força 3×/semana")
    }

    // MARK: - Campos novos de V2 (in-memory)

    func testV2NewFields_persistAndRoundTrip() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext

        let exercise = ExerciseModel(
            uuid: UUID(),
            slug: "meu-exercicio",
            name: "Meu exercício",
            primaryMusclesRaw: CurrentSchema.encodeMuscleGroups([.chest]),
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.cable.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 2.5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false,
            movementPatternRaw: MovementPattern.chestFly.rawValue,
            isCustom: true
        )
        context.insert(exercise)

        let program = ProgramModel(
            uuid: UUID(),
            name: "Força",
            isActive: false,
            createdAt: startedAt,
            goalRaw: ProgramGoal.strength.rawValue,
            summary: "Básicos pesados"
        )
        context.insert(program)

        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: SessionStatus.inProgress.rawValue,
            startedAt: startedAt,
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: "iphone"
        )
        context.insert(session)
        let sessionExercise = SessionExerciseModel(
            uuid: UUID(),
            order: 0,
            exerciseUUID: exercise.uuid,
            exerciseName: exercise.name,
            prescribedLoad: 20,
            prescribedSets: 3,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: 2,
            restSeconds: 90,
            noteRaw: PrescriptionNote.hold.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil,
            prescribedTargetReps: 11
        )
        context.insert(sessionExercise)
        session.exercises.append(sessionExercise)
        try context.save()

        let storedExercise = try XCTUnwrap(context.fetch(FetchDescriptor<ExerciseModel>()).first)
        XCTAssertEqual(storedExercise.movementPattern, .chestFly)
        XCTAssertTrue(storedExercise.isCustom)

        let storedProgram = try XCTUnwrap(context.fetch(FetchDescriptor<ProgramModel>()).first)
        XCTAssertEqual(storedProgram.goal, .strength)
        XCTAssertEqual(storedProgram.summary, "Básicos pesados")

        let storedSessionExercise = try XCTUnwrap(context.fetch(FetchDescriptor<SessionExerciseModel>()).first)
        XCTAssertEqual(storedSessionExercise.prescribedTargetReps, 11)
    }

    func testV2Inits_withoutNewArguments_useDeclaredDefaults() throws {
        // Container vivo durante o teste: o esquema fica registrado antes de criar `@Model`.
        let container = try ModelContainerFactory.make(.inMemory)
        // Call sites escritos contra V1 continuam compilando e caem nos padrões de V2.
        let exercise = ExerciseModel(
            uuid: UUID(),
            slug: "supino",
            name: "Supino",
            primaryMusclesRaw: "chest",
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.barbell.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 2.5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        XCTAssertNil(exercise.movementPatternRaw)
        XCTAssertFalse(exercise.isCustom)

        let program = ProgramModel(uuid: UUID(), name: "ABC", isActive: true, createdAt: startedAt)
        XCTAssertEqual(program.goalRaw, "hypertrophy")
        XCTAssertEqual(program.goal, .hypertrophy)
        XCTAssertNil(program.summary)

        let sessionExercise = SessionExerciseModel(
            uuid: UUID(),
            order: 0,
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
        XCTAssertEqual(sessionExercise.prescribedTargetReps, 0)
        withExtendedLifetime(container) {}
    }

    func testV2ComputedEnums_unknownRawValues_areNilAndNilGoalWritesDefault() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let exercise = ExerciseModel(
            uuid: UUID(),
            slug: "supino",
            name: "Supino",
            primaryMusclesRaw: "chest",
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.barbell.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 2.5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false,
            movementPatternRaw: "teleport"
        )
        XCTAssertNil(exercise.movementPattern)
        exercise.movementPattern = .horizontalPush
        XCTAssertEqual(exercise.movementPatternRaw, "horizontalPush")
        exercise.movementPattern = nil
        XCTAssertNil(exercise.movementPatternRaw)

        let program = ProgramModel(
            uuid: UUID(),
            name: "Futuro",
            isActive: false,
            createdAt: startedAt,
            goalRaw: "parkour"
        )
        XCTAssertNil(program.goal)
        program.goal = .combat
        XCTAssertEqual(program.goalRaw, "combat")
        program.goal = nil
        XCTAssertEqual(program.goalRaw, "hypertrophy")
        withExtendedLifetime(container) {}
    }

    // MARK: - Fixture V1

    private struct V1Fixture {
        let exerciseID: UUID
        let programID: UUID
        let sessionID: UUID
        let setIDs: [UUID]
        let settingsID: UUID
    }

    /// Grava um store V1 completo (catálogo, programa, sessão com séries, configuração) usando
    /// os tipos de `SchemaV1` explicitamente — os typealiases já apontam para V2 — e devolve só
    /// valores, para nada de V1 sobreviver ao retorno.
    private func writeV1Store(at url: URL) throws -> V1Fixture {
        let schemaV1 = Schema(versionedSchema: SchemaV1.self)
        // Mesmo plano que o app da M1 usava (só V1, sem estágios).
        let container = try ModelContainer(
            for: schemaV1,
            migrationPlan: SchemaV1OnlyMigrationPlan.self,
            configurations: [ModelConfiguration(schema: schemaV1, url: url)]
        )
        let context = container.mainContext

        let exercise = SchemaV1.ExerciseModel(
            uuid: UUID(),
            slug: "leg-press-45",
            name: "Leg press 45°",
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.quads, .glutes]),
            secondaryMusclesRaw: SchemaV1.encodeMuscleGroups([.hamstrings]),
            equipmentRaw: Equipment.machine.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 5,
            isUnilateral: false,
            machineNotes: "Banco 3",
            isArchived: true
        )
        context.insert(exercise)

        let program = SchemaV1.ProgramModel(
            uuid: UUID(),
            name: "Programa ABC",
            isActive: true,
            createdAt: startedAt
        )
        context.insert(program)
        let day = SchemaV1.ProgramDayModel(uuid: UUID(), name: "Dia A", order: 0)
        context.insert(day)
        program.days.append(day)
        let target = SchemaV1.ProgramExerciseModel(
            uuid: UUID(),
            order: 0,
            sets: 3,
            repMin: 8,
            repMax: 12,
            targetRIR: 2,
            restSeconds: 120,
            startingLoad: 40
        )
        context.insert(target)
        target.exercise = exercise
        day.exercises.append(target)

        let session = SchemaV1.WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: day.uuid,
            programDayName: day.name,
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3_600),
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: "iphone"
        )
        context.insert(session)
        let sessionExercise = SchemaV1.SessionExerciseModel(
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
            noteRaw: PrescriptionNote.hold.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(sessionExercise)
        sessionExercise.exercise = exercise
        session.exercises.append(sessionExercise)

        let setSpecs: [(load: Double, reps: Int, rir: Int?, isWarmup: Bool)] = [
            (60, 12, nil, true),
            (100, 10, 2, false),
        ]
        var setIDs: [UUID] = []
        for (index, spec) in setSpecs.enumerated() {
            let completedAt = startedAt.addingTimeInterval(Double(index + 1) * 180)
            let set = SchemaV1.SetLogModel(
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
            setIDs.append(set.uuid)
        }

        let settings = SchemaV1.UserSettingsModel(
            uuid: UUID(),
            weekStartsOnMonday: true,
            weeklyTargetsRaw: "{\"chest\":2}",
            healthKitEnabled: false,
            defaultRestSeconds: 90,
            schemaSeedVersion: 1
        )
        context.insert(settings)

        try context.save()

        return V1Fixture(
            exerciseID: exercise.uuid,
            programID: program.uuid,
            sessionID: session.uuid,
            setIDs: setIDs,
            settingsID: settings.uuid
        )
    }
}
