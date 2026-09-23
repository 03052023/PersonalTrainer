import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T2.4 (SPEC RF-18, RNF-04; CA2-5): `BackupService` exporta o store inteiro e a importação
/// substitui tudo, validando o arquivo antes de tocar no banco. Containers in-memory, datas fixas
/// em segundos inteiros (o JSON guarda milissegundos) e tudo em `@MainActor` (ARCHITECTURE §10).
@MainActor
final class BackupServiceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    /// Mantém os containers vivos até o fim de cada teste.
    private var containers: [ModelContainer] = []

    // MARK: - Round-trip

    func testRF18_roundTripIntoFreshContainer_preservesCountsAndFields() throws {
        let source = try makeContext()
        let fixture = try insertFixture(into: source)
        let data = try makeService(source).exportBackup(now: now)

        let target = try makeContext()
        let report = try makeService(target).importBackup(data)

        XCTAssertEqual(report, BackupImportReport(exercises: 3, programs: 2, sessions: 2, sets: 4))
        XCTAssertEqual(try counts(in: target), Counts(
            exercises: 3, programs: 2, days: 3, targets: 4,
            sessions: 2, sessionExercises: 3, sets: 4, settings: 1
        ))

        // Catálogo, incluindo os campos do SchemaV2 e o estado do usuário.
        let exercises = try target.fetch(FetchDescriptor<ExerciseModel>())
        let legPress = try XCTUnwrap(exercises.first { $0.uuid == fixture.legPressID })
        XCTAssertEqual(legPress.slug, "leg-press-45")
        XCTAssertEqual(legPress.name, "Leg press 45°")
        XCTAssertEqual(legPress.primaryMuscles, [.quads, .glutes])
        XCTAssertEqual(legPress.secondaryMuscles, [.hamstrings])
        XCTAssertEqual(legPress.equipmentRaw, Equipment.machine.rawValue)
        XCTAssertEqual(legPress.loadUnitRaw, LoadUnit.kilograms.rawValue)
        XCTAssertEqual(legPress.loadIncrement, 5)
        XCTAssertFalse(legPress.isUnilateral)
        XCTAssertEqual(legPress.machineNotes, "Banco na posição 3")
        XCTAssertFalse(legPress.isArchived)
        XCTAssertEqual(legPress.movementPatternRaw, MovementPattern.squat.rawValue)
        XCTAssertFalse(legPress.isCustom)

        let customRow = try XCTUnwrap(exercises.first { $0.uuid == fixture.customRowID })
        XCTAssertEqual(customRow.slug, "remada-unilateral-custom")
        XCTAssertEqual(customRow.loadUnitRaw, LoadUnit.level.rawValue)
        XCTAssertEqual(customRow.loadIncrement, 1)
        XCTAssertTrue(customRow.isUnilateral)
        XCTAssertNil(customRow.machineNotes)
        XCTAssertTrue(customRow.isArchived)
        XCTAssertTrue(customRow.isCustom)
        XCTAssertEqual(customRow.movementPatternRaw, MovementPattern.horizontalPull.rawValue)

        let bench = try XCTUnwrap(exercises.first { $0.uuid == fixture.benchID })
        XCTAssertNil(bench.movementPatternRaw)

        // Programas: objetivo, resumo, datas, dias ordenados e alvos ligados ao catálogo.
        let programs = try target.fetch(FetchDescriptor<ProgramModel>())
        let active = try XCTUnwrap(programs.first { $0.uuid == fixture.activeProgramID })
        XCTAssertEqual(active.name, "Força ABC")
        XCTAssertTrue(active.isActive)
        XCTAssertEqual(active.createdAt, now.addingTimeInterval(-86_400 * 30))
        XCTAssertEqual(active.goalRaw, ProgramGoal.strength.rawValue)
        XCTAssertEqual(active.summary, "Força em três dias")
        let days = active.days.sorted { $0.order < $1.order }
        XCTAssertEqual(days.map { $0.name }, ["Dia A", "Dia B"])
        XCTAssertEqual(days.map { $0.uuid }, [fixture.dayAID, fixture.dayBID])
        XCTAssertEqual(days.first?.program?.uuid, fixture.activeProgramID)
        let dayATargets = try XCTUnwrap(days.first).exercises.sorted { $0.order < $1.order }
        XCTAssertEqual(dayATargets.map { $0.exercise?.uuid }, [fixture.legPressID, fixture.customRowID])
        let firstTarget = try XCTUnwrap(dayATargets.first)
        XCTAssertEqual(firstTarget.uuid, fixture.legPressTargetID)
        XCTAssertEqual(firstTarget.sets, 4)
        XCTAssertEqual(firstTarget.repMin, 6)
        XCTAssertEqual(firstTarget.repMax, 10)
        XCTAssertEqual(firstTarget.targetRIR, 1)
        XCTAssertEqual(firstTarget.restSeconds, 150)
        XCTAssertEqual(firstTarget.startingLoad, 100)
        XCTAssertEqual(firstTarget.day?.uuid, fixture.dayAID)
        XCTAssertNil(dayATargets.last?.startingLoad)

        let inactive = try XCTUnwrap(programs.first { $0.uuid == fixture.inactiveProgramID })
        XCTAssertFalse(inactive.isActive)
        XCTAssertEqual(inactive.goalRaw, ProgramGoal.hypertrophy.rawValue)
        XCTAssertNil(inactive.summary)

        // Sessões: todos os campos do snapshot, relações e séries.
        let sessions = try target.fetch(FetchDescriptor<WorkoutSessionModel>())
        let completed = try XCTUnwrap(sessions.first { $0.uuid == fixture.completedSessionID })
        XCTAssertEqual(completed.programDayUUID, fixture.dayAID)
        XCTAssertEqual(completed.programDayName, "Dia A")
        XCTAssertEqual(completed.status, .completed)
        XCTAssertEqual(completed.startedAt, now.addingTimeInterval(-86_400 * 2))
        XCTAssertEqual(completed.endedAt, now.addingTimeInterval(-86_400 * 2 + 3_600))
        XCTAssertEqual(completed.notes, "Joelho ok")
        XCTAssertEqual(completed.hkWorkoutUUID, fixture.hkWorkoutID)
        XCTAssertEqual(completed.avgHeartRate, 128.5)
        XCTAssertEqual(completed.maxHeartRate, 171)
        XCTAssertFalse(completed.isDeload)
        XCTAssertEqual(completed.sourceRaw, DeviceSource.iphone.rawValue)

        let completedExercises = completed.exercises.sorted { $0.order < $1.order }
        XCTAssertEqual(completedExercises.count, 2)
        let legPressEntry = try XCTUnwrap(completedExercises.first)
        XCTAssertEqual(legPressEntry.uuid, fixture.legPressEntryID)
        XCTAssertEqual(legPressEntry.exerciseUUID, fixture.legPressID)
        XCTAssertEqual(legPressEntry.exerciseName, "Leg press 45°")
        XCTAssertEqual(legPressEntry.exercise?.uuid, fixture.legPressID)
        XCTAssertEqual(legPressEntry.session?.uuid, fixture.completedSessionID)
        XCTAssertEqual(legPressEntry.prescribedLoad, 100)
        XCTAssertEqual(legPressEntry.prescribedSets, 4)
        XCTAssertEqual(legPressEntry.prescribedRepMin, 6)
        XCTAssertEqual(legPressEntry.prescribedRepMax, 10)
        XCTAssertEqual(legPressEntry.prescribedTargetReps, 8)
        XCTAssertEqual(legPressEntry.prescribedRIR, 1)
        XCTAssertEqual(legPressEntry.restSeconds, 150)
        XCTAssertEqual(legPressEntry.note, .increase)
        XCTAssertFalse(legPressEntry.wasSkipped)
        XCTAssertNil(legPressEntry.substitutedFromUUID)

        let sets = legPressEntry.sets.sorted { $0.index < $1.index }
        XCTAssertEqual(sets.map { $0.index }, [0, 1, 2])
        XCTAssertEqual(sets.map { $0.load }, [60, 100, 100])
        XCTAssertEqual(sets.map { $0.reps }, [12, 10, 9])
        XCTAssertEqual(sets.map { $0.rir }, [nil, 1, 0])
        XCTAssertEqual(sets.map { $0.isWarmup }, [true, false, false])
        XCTAssertEqual(sets[1].uuid, fixture.workingSetID)
        XCTAssertEqual(sets[1].completedAt, now.addingTimeInterval(-86_400 * 2 + 360))
        XCTAssertEqual(sets[1].updatedAt, now.addingTimeInterval(-86_400 * 2 + 400))
        XCTAssertEqual(sets[1].sourceRaw, DeviceSource.iphone.rawValue)
        XCTAssertEqual(sets[1].sessionExercise?.uuid, fixture.legPressEntryID)

        let substitutedEntry = try XCTUnwrap(completedExercises.last)
        XCTAssertEqual(substitutedEntry.exerciseUUID, fixture.customRowID)
        XCTAssertEqual(substitutedEntry.substitutedFromUUID, fixture.benchID)
        XCTAssertTrue(substitutedEntry.wasSkipped)
        XCTAssertNil(substitutedEntry.prescribedLoad)
        XCTAssertEqual(substitutedEntry.prescribedTargetReps, 0)
        XCTAssertTrue(substitutedEntry.sets.isEmpty)

        let abandoned = try XCTUnwrap(sessions.first { $0.uuid == fixture.abandonedSessionID })
        XCTAssertEqual(abandoned.status, .abandoned)
        XCTAssertTrue(abandoned.isDeload)
        XCTAssertEqual(abandoned.sourceRaw, DeviceSource.watch.rawValue)
        XCTAssertNil(abandoned.hkWorkoutUUID)
        XCTAssertNil(abandoned.avgHeartRate)
        let ghostEntry = try XCTUnwrap(abandoned.exercises.first)
        // Snapshot de exercício fora do catálogo: volta sem relação, como o coordinator grava.
        XCTAssertEqual(ghostEntry.exerciseUUID, fixture.ghostExerciseID)
        XCTAssertEqual(ghostEntry.exerciseName, "Fantasma")
        XCTAssertNil(ghostEntry.exercise)
        XCTAssertEqual(ghostEntry.sets.first?.sourceRaw, DeviceSource.watch.rawValue)

        // Configuração.
        let settings = try XCTUnwrap(try target.fetch(FetchDescriptor<UserSettingsModel>()).first)
        XCTAssertEqual(settings.uuid, fixture.settingsID)
        XCTAssertFalse(settings.weekStartsOnMonday)
        XCTAssertEqual(settings.weeklyTargetsRaw, "{\"chest\":3}")
        XCTAssertTrue(settings.healthKitEnabled)
        XCTAssertEqual(settings.defaultRestSeconds, 90)
        XCTAssertEqual(settings.schemaSeedVersion, 2)

        // A prova mais forte de que nada se perdeu: reexportar dá o mesmo arquivo, byte a byte.
        XCTAssertEqual(try makeService(target).exportBackup(now: now), data)
    }

    func testRF18_reimportIntoSameStore_replacesWithoutDuplicatingUniqueIDs() throws {
        let context = try makeContext()
        _ = try insertFixture(into: context)
        let data = try makeService(context).exportBackup(now: now)

        // Mudanças depois do backup: somem na importação.
        context.insert(makeExercise(slug: "crucifixo", name: "Crucifixo"))
        let program = try XCTUnwrap(try context.fetch(FetchDescriptor<ProgramModel>()).first { $0.isActive })
        program.name = "Renomeado"
        try context.save()

        // Mesmos `uuid`/`slug` `.unique` já presentes no store: não pode virar upsert nem duplicar.
        let report = try makeService(context).importBackup(data)

        XCTAssertEqual(report, BackupImportReport(exercises: 3, programs: 2, sessions: 2, sets: 4))
        XCTAssertEqual(try counts(in: context), Counts(
            exercises: 3, programs: 2, days: 3, targets: 4,
            sessions: 2, sessionExercises: 3, sets: 4, settings: 1
        ))
        XCTAssertNil(try context.fetch(FetchDescriptor<ExerciseModel>()).first { $0.slug == "crucifixo" })
        XCTAssertEqual(try makeService(context).exportBackup(now: now), data)
    }

    func testRF18_emptyBackup_clearsStore() throws {
        let empty = try makeContext()
        let data = try makeService(empty).exportBackup(now: now)

        let context = try makeContext()
        _ = try insertFixture(into: context)
        let report = try makeService(context).importBackup(data)

        XCTAssertEqual(report, BackupImportReport(exercises: 0, programs: 0, sessions: 0, sets: 0))
        XCTAssertEqual(try counts(in: context), Counts(
            exercises: 0, programs: 0, days: 0, targets: 0,
            sessions: 0, sessionExercises: 0, sets: 0, settings: 0
        ))
    }

    // MARK: - Importação inválida não altera nada

    func testRF18_invalidImports_throwAndLeaveStoreUntouched() throws {
        let context = try makeContext()
        _ = try insertFixture(into: context)
        let service = makeService(context)
        let baseline = try service.exportBackup(now: now)
        let document = try BackupDocument.decode(from: baseline)

        var duplicatedSet = document
        let firstSetID = try XCTUnwrap(duplicatedSet.sessions.first?.exercises.first?.sets.first?.uuid)
        duplicatedSet.sessions[0].exercises[0].sets[1].uuid = firstSetID

        var duplicatedSlug = document
        duplicatedSlug.exercises[1].definition = renamedSlug(
            duplicatedSlug.exercises[1].definition,
            to: duplicatedSlug.exercises[0].definition.slug
        )

        var missingExercise = document
        let activeIndex = try XCTUnwrap(missingExercise.programs.firstIndex { $0.template.isActive })
        missingExercise.programs[activeIndex].template = appendingTarget(
            ExerciseTarget(id: UUID(), exerciseID: UUID(), order: 9),
            to: missingExercise.programs[activeIndex].template
        )

        var twoActive = document
        let inactiveIndex = try XCTUnwrap(twoActive.programs.firstIndex { !$0.template.isActive })
        twoActive.programs[inactiveIndex].template = activated(twoActive.programs[inactiveIndex].template)

        var unknownStatus = document
        unknownStatus.sessions[0].statusRaw = "paused"

        var futureVersion = document
        futureVersion.schemaVersion = 2

        let futureVersionData = try futureVersion.encoded()
        let duplicatedSetData = try duplicatedSet.encoded()
        let duplicatedSlugData = try duplicatedSlug.encoded()
        let missingExerciseData = try missingExercise.encoded()
        let twoActiveData = try twoActive.encoded()
        let unknownStatusData = try unknownStatus.encoded()

        let cases: [(name: String, data: Data, expected: ExpectedFailure)] = [
            ("não é JSON", Data("isto não é um backup".utf8), .exact(.corrupted)),
            ("JSON vazio", Data("{}".utf8), .exact(.corrupted)),
            ("versão futura só no cabeçalho", Data("{\"schemaVersion\": 7}".utf8), .exact(.unsupportedVersion(7))),
            ("versão futura", futureVersionData, .exact(.unsupportedVersion(2))),
            ("campos faltando", Data("{\"schemaVersion\": 1}".utf8), .exact(.corrupted)),
            ("série repetida", duplicatedSetData, .referentialIntegrity),
            ("slug repetido", duplicatedSlugData, .referentialIntegrity),
            ("alvo sem exercício", missingExerciseData, .referentialIntegrity),
            ("dois programas ativos", twoActiveData, .referentialIntegrity),
            ("status desconhecido", unknownStatusData, .referentialIntegrity),
        ]

        for testCase in cases {
            do {
                _ = try service.importBackup(testCase.data)
                XCTFail("Esperava erro: \(testCase.name)")
            } catch let error as BackupError {
                switch (testCase.expected, error) {
                case (.exact(let expected), _):
                    XCTAssertEqual(error, expected, testCase.name)
                case (.referentialIntegrity, .referentialIntegrity(let detail)):
                    XCTAssertFalse(detail.isEmpty, testCase.name)
                case (.referentialIntegrity, _):
                    XCTFail("Esperava referentialIntegrity em \(testCase.name), veio \(error)")
                }
            } catch {
                XCTFail("Erro inesperado em \(testCase.name): \(error)")
            }
            XCTAssertEqual(try service.exportBackup(now: now), baseline, "Store alterado por: \(testCase.name)")
        }
    }

    func testRF18_importWithSessionInProgress_throwsAndLeavesStoreUntouched() throws {
        let other = try makeContext()
        _ = try insertFixture(into: other)
        let data = try makeService(other).exportBackup(now: now)

        let context = try makeContext()
        let active = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: SessionStatus.inProgress.rawValue,
            startedAt: now,
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: DeviceSource.iphone.rawValue
        )
        context.insert(active)
        try context.save()
        let service = makeService(context)
        let baseline = try service.exportBackup(now: now)

        XCTAssertThrowsError(try service.importBackup(data)) { error in
            XCTAssertEqual(error as? BackupError, .inProgressSession)
        }
        XCTAssertEqual(try service.exportBackup(now: now), baseline)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSessionModel>()), 1)
    }

    // MARK: - Formato

    func testRF18_exportFormat_isVersionedSortedISO8601() throws {
        let context = try makeContext()
        _ = try insertFixture(into: context)

        let data = try makeService(context).exportBackup(now: now)

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["appVersion"] as? String, "9.9.9 (99)")
        XCTAssertEqual(object["exportedAt"] as? String, "2023-11-14T22:13:20.000Z")
        XCTAssertEqual((object["exercises"] as? [Any])?.count, 3)
        XCTAssertEqual((object["programs"] as? [Any])?.count, 2)
        XCTAssertEqual((object["sessions"] as? [Any])?.count, 2)
        XCTAssertNotNil(object["settings"] as? [String: Any])

        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("\n"), "JSON indentado para ser legível (RNF-04)")
        // `sortedKeys`: chaves de topo em ordem alfabética.
        let appVersionRange = try XCTUnwrap(text.range(of: "\"appVersion\""))
        let settingsRange = try XCTUnwrap(text.range(of: "\"settings\""))
        XCTAssertLessThan(appVersionRange.lowerBound, settingsRange.lowerBound)
    }

    func testRF18_dates_keepMillisecondsAndAcceptPlainISO8601() throws {
        let precise = Date(timeIntervalSince1970: 1_700_000_000.25)
        let text = BackupDocument.iso8601String(from: precise)
        XCTAssertEqual(text, "2023-11-14T22:13:20.250Z")
        let parsed = try XCTUnwrap(BackupDocument.date(fromISO8601: text))
        XCTAssertEqual(parsed.timeIntervalSince1970, precise.timeIntervalSince1970, accuracy: 0.0005)

        let plain = try XCTUnwrap(BackupDocument.date(fromISO8601: "2023-11-14T22:13:20Z"))
        XCTAssertEqual(plain, now)
        XCTAssertNil(BackupDocument.date(fromISO8601: "14/11/2023"))
    }

    func testRF18_suggestedFileName_usesDayInConfiguredTimeZone() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let saoPaulo = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        // 2026-09-23 01:30 UTC = 2026-09-22 22:30 em São Paulo (UTC−3).
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 1, minute: 30)))
        let context = try makeContext()

        XCTAssertEqual(
            BackupService(modelContext: context, appVersion: "t", timeZone: utc).suggestedFileName(now: date),
            "PersonalTrainer-backup-2026-09-23.json"
        )
        XCTAssertEqual(
            BackupService(modelContext: context, appVersion: "t", timeZone: saoPaulo).suggestedFileName(now: date),
            "PersonalTrainer-backup-2026-09-22.json"
        )
    }

    // MARK: - Apoio

    private enum ExpectedFailure {
        case exact(BackupError)
        /// Qualquer `referentialIntegrity`; o texto é para o usuário e pode mudar.
        case referentialIntegrity
    }

    private struct Counts: Equatable {
        let exercises: Int
        let programs: Int
        let days: Int
        let targets: Int
        let sessions: Int
        let sessionExercises: Int
        let sets: Int
        let settings: Int
    }

    private struct Fixture {
        let legPressID: UUID
        let customRowID: UUID
        let benchID: UUID
        let ghostExerciseID: UUID
        let activeProgramID: UUID
        let inactiveProgramID: UUID
        let dayAID: UUID
        let dayBID: UUID
        let legPressTargetID: UUID
        let completedSessionID: UUID
        let abandonedSessionID: UUID
        let legPressEntryID: UUID
        let workingSetID: UUID
        let hkWorkoutID: UUID
        let settingsID: UUID
    }

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(.inMemory)
        containers.append(container)
        return container.mainContext
    }

    private func makeService(_ context: ModelContext) -> BackupService {
        BackupService(modelContext: context, appVersion: "9.9.9 (99)", timeZone: TimeZone(secondsFromGMT: 0) ?? .current)
    }

    private func counts(in context: ModelContext) throws -> Counts {
        try Counts(
            exercises: context.fetchCount(FetchDescriptor<ExerciseModel>()),
            programs: context.fetchCount(FetchDescriptor<ProgramModel>()),
            days: context.fetchCount(FetchDescriptor<ProgramDayModel>()),
            targets: context.fetchCount(FetchDescriptor<ProgramExerciseModel>()),
            sessions: context.fetchCount(FetchDescriptor<WorkoutSessionModel>()),
            sessionExercises: context.fetchCount(FetchDescriptor<SessionExerciseModel>()),
            sets: context.fetchCount(FetchDescriptor<SetLogModel>()),
            settings: context.fetchCount(FetchDescriptor<UserSettingsModel>())
        )
    }

    private func makeExercise(
        uuid: UUID = UUID(),
        slug: String,
        name: String,
        primary: [MuscleGroup] = [.chest],
        secondary: [MuscleGroup] = [],
        loadUnit: LoadUnit = .kilograms,
        loadIncrement: Double = 2.5,
        isUnilateral: Bool = false,
        machineNotes: String? = nil,
        isArchived: Bool = false
    ) -> ExerciseModel {
        ExerciseModel(
            uuid: uuid,
            slug: slug,
            name: name,
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups(primary),
            secondaryMusclesRaw: SchemaV1.encodeMuscleGroups(secondary),
            equipmentRaw: Equipment.machine.rawValue,
            loadUnitRaw: loadUnit.rawValue,
            loadIncrement: loadIncrement,
            isUnilateral: isUnilateral,
            machineNotes: machineNotes,
            isArchived: isArchived
        )
    }

    /// Store com tudo que o backup precisa carregar: catálogo com campos do SchemaV2 (exercício
    /// arquivado e customizado), dois programas (um ativo, com objetivo e resumo), uma sessão
    /// concluída com aquecimento e substituição, uma abandonada no relógio com exercício fora do
    /// catálogo e a linha de configuração. Insere antes de ligar relações.
    private func insertFixture(into context: ModelContext) throws -> Fixture {
        let legPress = makeExercise(
            slug: "leg-press-45",
            name: "Leg press 45°",
            primary: [.quads, .glutes],
            secondary: [.hamstrings],
            loadIncrement: 5,
            machineNotes: "Banco na posição 3"
        )
        context.insert(legPress)
        legPress.movementPatternRaw = MovementPattern.squat.rawValue

        let customRow = makeExercise(
            slug: "remada-unilateral-custom",
            name: "Remada unilateral na máquina",
            primary: [.back],
            secondary: [.biceps],
            loadUnit: .level,
            loadIncrement: 1,
            isUnilateral: true,
            isArchived: true
        )
        context.insert(customRow)
        customRow.movementPatternRaw = MovementPattern.horizontalPull.rawValue
        customRow.isCustom = true

        let bench = makeExercise(slug: "supino-maquina", name: "Supino na máquina", secondary: [.triceps])
        context.insert(bench)

        // Programa ativo: dois dias.
        let active = ProgramModel(
            uuid: UUID(),
            name: "Força ABC",
            isActive: true,
            createdAt: now.addingTimeInterval(-86_400 * 30)
        )
        context.insert(active)
        active.goalRaw = ProgramGoal.strength.rawValue
        active.summary = "Força em três dias"

        let dayA = ProgramDayModel(uuid: UUID(), name: "Dia A", order: 0)
        context.insert(dayA)
        active.days.append(dayA)
        let legPressTarget = ProgramExerciseModel(
            uuid: UUID(), order: 0, sets: 4, repMin: 6, repMax: 10, targetRIR: 1, restSeconds: 150, startingLoad: 100
        )
        context.insert(legPressTarget)
        legPressTarget.exercise = legPress
        dayA.exercises.append(legPressTarget)
        let rowTarget = ProgramExerciseModel(
            uuid: UUID(), order: 1, sets: 3, repMin: 8, repMax: 12, targetRIR: 2, restSeconds: 90, startingLoad: nil
        )
        context.insert(rowTarget)
        rowTarget.exercise = customRow
        dayA.exercises.append(rowTarget)

        let dayB = ProgramDayModel(uuid: UUID(), name: "Dia B", order: 1)
        context.insert(dayB)
        active.days.append(dayB)
        let benchTarget = ProgramExerciseModel(
            uuid: UUID(), order: 0, sets: 3, repMin: 8, repMax: 12, targetRIR: 2, restSeconds: 120, startingLoad: 40
        )
        context.insert(benchTarget)
        benchTarget.exercise = bench
        dayB.exercises.append(benchTarget)

        // Programa inativo, com o objetivo padrão e sem resumo.
        let inactive = ProgramModel(
            uuid: UUID(),
            name: "Hipertrofia antigo",
            isActive: false,
            createdAt: now.addingTimeInterval(-86_400 * 90)
        )
        context.insert(inactive)
        let oldDay = ProgramDayModel(uuid: UUID(), name: "Único", order: 0)
        context.insert(oldDay)
        inactive.days.append(oldDay)
        let oldTarget = ProgramExerciseModel(
            uuid: UUID(), order: 0, sets: 3, repMin: 10, repMax: 15, targetRIR: 2, restSeconds: 90, startingLoad: nil
        )
        context.insert(oldTarget)
        oldTarget.exercise = bench
        oldDay.exercises.append(oldTarget)

        // Sessão concluída no iPhone, com FC e treino do Saúde vinculados.
        let completedStart = now.addingTimeInterval(-86_400 * 2)
        let hkWorkoutID = UUID()
        let completed = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: dayA.uuid,
            programDayName: "Dia A",
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: completedStart,
            endedAt: completedStart.addingTimeInterval(3_600),
            notes: "Joelho ok",
            hkWorkoutUUID: hkWorkoutID,
            avgHeartRate: 128.5,
            maxHeartRate: 171,
            isDeload: false,
            sourceRaw: DeviceSource.iphone.rawValue
        )
        context.insert(completed)

        let legPressEntry = SessionExerciseModel(
            uuid: UUID(),
            order: 0,
            exerciseUUID: legPress.uuid,
            exerciseName: legPress.name,
            prescribedLoad: 100,
            prescribedSets: 4,
            prescribedRepMin: 6,
            prescribedRepMax: 10,
            prescribedRIR: 1,
            restSeconds: 150,
            noteRaw: PrescriptionNote.increase.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(legPressEntry)
        legPressEntry.prescribedTargetReps = 8
        legPressEntry.exercise = legPress
        completed.exercises.append(legPressEntry)

        let setSpecs: [(load: Double, reps: Int, rir: Int?, isWarmup: Bool)] = [
            (60, 12, nil, true),
            (100, 10, 1, false),
            (100, 9, 0, false),
        ]
        var workingSetID = UUID()
        for (index, spec) in setSpecs.enumerated() {
            let completedAt = completedStart.addingTimeInterval(Double(index + 1) * 180)
            let setLog = SetLogModel(
                uuid: UUID(),
                index: index,
                load: spec.load,
                reps: spec.reps,
                rir: spec.rir,
                isWarmup: spec.isWarmup,
                completedAt: completedAt,
                sourceRaw: DeviceSource.iphone.rawValue,
                // A série 1 foi corrigida depois (RF-19): `updatedAt` ≠ `completedAt`.
                updatedAt: index == 1 ? completedAt.addingTimeInterval(40) : completedAt
            )
            context.insert(setLog)
            legPressEntry.sets.append(setLog)
            if index == 1 {
                workingSetID = setLog.uuid
            }
        }

        // Supino trocado pela remada customizada e depois pulado, sem séries.
        let substitutedEntry = SessionExerciseModel(
            uuid: UUID(),
            order: 1,
            exerciseUUID: customRow.uuid,
            exerciseName: customRow.name,
            prescribedLoad: nil,
            prescribedSets: 3,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: 2,
            restSeconds: 90,
            noteRaw: PrescriptionNote.calibrate.rawValue,
            wasSkipped: true,
            substitutedFromUUID: bench.uuid
        )
        context.insert(substitutedEntry)
        substitutedEntry.exercise = customRow
        completed.exercises.append(substitutedEntry)

        // Sessão abandonada no relógio, em deload, com exercício que não está no catálogo.
        let abandonedStart = now.addingTimeInterval(-86_400)
        let abandoned = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: dayB.uuid,
            programDayName: "Dia B",
            statusRaw: SessionStatus.abandoned.rawValue,
            startedAt: abandonedStart,
            endedAt: abandonedStart.addingTimeInterval(1_200),
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: true,
            sourceRaw: DeviceSource.watch.rawValue
        )
        context.insert(abandoned)

        let ghostID = UUID()
        let ghostEntry = SessionExerciseModel(
            uuid: UUID(),
            order: 0,
            exerciseUUID: ghostID,
            exerciseName: "Fantasma",
            prescribedLoad: 20,
            prescribedSets: 2,
            prescribedRepMin: 12,
            prescribedRepMax: 15,
            prescribedRIR: 3,
            restSeconds: 60,
            noteRaw: PrescriptionNote.deload.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(ghostEntry)
        ghostEntry.prescribedTargetReps = 12
        abandoned.exercises.append(ghostEntry)

        let ghostSet = SetLogModel(
            uuid: UUID(),
            index: 0,
            load: 20,
            reps: 15,
            rir: 3,
            isWarmup: false,
            completedAt: abandonedStart.addingTimeInterval(300),
            sourceRaw: DeviceSource.watch.rawValue,
            updatedAt: abandonedStart.addingTimeInterval(300)
        )
        context.insert(ghostSet)
        ghostEntry.sets.append(ghostSet)

        let settings = UserSettingsModel(
            uuid: UUID(),
            weekStartsOnMonday: false,
            weeklyTargetsRaw: "{\"chest\":3}",
            healthKitEnabled: true,
            defaultRestSeconds: 90,
            schemaSeedVersion: 2
        )
        context.insert(settings)

        try context.save()

        return Fixture(
            legPressID: legPress.uuid,
            customRowID: customRow.uuid,
            benchID: bench.uuid,
            ghostExerciseID: ghostID,
            activeProgramID: active.uuid,
            inactiveProgramID: inactive.uuid,
            dayAID: dayA.uuid,
            dayBID: dayB.uuid,
            legPressTargetID: legPressTarget.uuid,
            completedSessionID: completed.uuid,
            abandonedSessionID: abandoned.uuid,
            legPressEntryID: legPressEntry.uuid,
            workingSetID: workingSetID,
            hkWorkoutID: hkWorkoutID,
            settingsID: settings.uuid
        )
    }

    // MARK: - Documentos alterados (os DTOs de domínio são imutáveis; reconstrói-se o valor)

    private func renamedSlug(_ definition: ExerciseDefinition, to slug: String) -> ExerciseDefinition {
        ExerciseDefinition(
            id: definition.id,
            slug: slug,
            name: definition.name,
            primaryMuscles: definition.primaryMuscles,
            secondaryMuscles: definition.secondaryMuscles,
            equipment: definition.equipment,
            loadUnit: definition.loadUnit,
            loadIncrement: definition.loadIncrement,
            isUnilateral: definition.isUnilateral,
            machineNotes: definition.machineNotes,
            movementPattern: definition.movementPattern,
            isCustom: definition.isCustom
        )
    }

    private func appendingTarget(_ target: ExerciseTarget, to program: ProgramTemplate) -> ProgramTemplate {
        var days = program.days
        if let first = days.first {
            days[0] = ProgramDayTemplate(
                id: first.id,
                name: first.name,
                order: first.order,
                exercises: first.exercises + [target]
            )
        }
        return ProgramTemplate(
            id: program.id,
            name: program.name,
            days: days,
            isActive: program.isActive,
            goal: program.goal,
            summary: program.summary
        )
    }

    private func activated(_ program: ProgramTemplate) -> ProgramTemplate {
        ProgramTemplate(
            id: program.id,
            name: program.name,
            days: program.days,
            isActive: true,
            goal: program.goal,
            summary: program.summary
        )
    }
}
