import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T1.10 + T2.11: `SeedLoader` v2 grava o seed em container in-memory e
/// `ProgramMapper.model(from:exercises:createdAt:)` monta o grafo do programa.
/// Tudo em `@MainActor` (ARCHITECTURE §10).
///
/// Os JSON do seed são recursos do target do APP, copiados para a raiz do bundle do app
/// (ARCHITECTURE §11). O bundle de testes (`Bundle(for: SeedLoaderTests.self)`) não os
/// contém. Como os testes são hospedados pelo app (TEST_HOST definido pelo XcodeGen a partir
/// da dependência no `project.yml`), `Bundle.main` é o bundle do app e é por ele que o seed
/// é lido aqui — exatamente como o app fará.
///
/// As contagens exatas vêm do próprio seed decodificado; o contrato do M2 fixa só os mínimos
/// (≥ 70 exercícios, 8 programas — decisão 8, 2026-09-23: Completo corpo todo com id novo ao
/// lado do A/B/C legado —, 1 ativo, 5 exercícios por dia no ativo).
@MainActor
final class SeedLoaderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var appBundle: Bundle { Bundle.main }
    /// Mantém os containers vivos até o fim de cada teste, independentemente de o
    /// `ModelContext` reter o seu.
    private var containers: [ModelContainer] = []

    // MARK: - Conteúdo do seed v2 (contrato do M2)

    func testSeedV2_meetsContractMinimums() throws {
        let seed = try decodeSeed()

        // 3 = versão 2.1 (exercícios de casa, RF-42); os arquivos continuam `*.v2.json`.
        XCTAssertEqual(SeedLoader.currentSeedVersion, 3)
        XCTAssertGreaterThanOrEqual(seed.catalog.exercises.count, 70)
        XCTAssertEqual(seed.programs.programs.count, 8)
        XCTAssertEqual(seed.programs.programs.filter(\.isActive).count, 1)
        XCTAssertNoThrow(try SeedValidator.validate(seed))
    }

    // MARK: - Primeiro launch

    func testLoadIfNeeded_firstRun_insertsWholeCatalogAndAllSeedPrograms() throws {
        let context = try makeContext()
        let seed = try decodeSeed()

        let report = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        XCTAssertEqual(
            report,
            SeedLoadReport(
                insertedExercises: seed.catalog.exercises.count,
                updatedExercises: 0,
                insertedPrograms: seed.programs.programs.count,
                skipped: false,
                skippedPrograms: 0
            )
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), seed.catalog.exercises.count)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramModel>()), seed.programs.programs.count)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramDayModel>()), dayCount(in: seed))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), targetCount(in: seed))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserSettingsModel>()), 1)
    }

    func testLoadIfNeeded_firstRun_seedActiveProgramIsTheOnlyActiveWithFiveExercisesPerDay() throws {
        let context = try makeContext()
        let seed = try decodeSeed()
        let seedActive = try XCTUnwrap(seed.programs.programs.first(where: \.isActive))

        _ = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        let programs = try context.fetch(FetchDescriptor<ProgramModel>())
        let active = programs.filter(\.isActive)
        XCTAssertEqual(active.map(\.uuid), [seedActive.id])
        let program = try XCTUnwrap(active.first)
        XCTAssertEqual(program.name, "Hipertrofia — Completo")
        XCTAssertTrue(programs.allSatisfy { $0.createdAt == now })

        // To-many não garante ordem; `order` é a ordem de verdade.
        let days = program.days.sorted { $0.order < $1.order }
        XCTAssertFalse(days.isEmpty)
        for day in days {
            // SPEC §7.9: todo programa gerado por padrão tem 5 exercícios por dia.
            XCTAssertEqual(day.exercises.count, 5, day.name)
            XCTAssertEqual(day.program?.uuid, program.uuid, day.name)
            for programExercise in day.exercises {
                XCTAssertNotNil(programExercise.exercise, "\(day.name) · order \(programExercise.order)")
                XCTAssertEqual(programExercise.day?.uuid, day.uuid, "\(day.name) · order \(programExercise.order)")
            }
        }
    }

    func testLoadIfNeeded_everyProgramRoundTripsToItsSeedTemplate() throws {
        let context = try makeContext()
        let seed = try decodeSeed()

        _ = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        // O grafo gravado volta ao template do JSON (ids, ordem, parâmetros, objetivo, resumo).
        let programs = try context.fetch(FetchDescriptor<ProgramModel>())
        var programsByID: [UUID: ProgramModel] = [:]
        for program in programs {
            programsByID[program.uuid] = program
        }
        for expected in seed.programs.programs {
            let program = try XCTUnwrap(programsByID[expected.id], expected.name)
            XCTAssertEqual(try ProgramMapper.template(from: program), normalized(expected), expected.name)
            XCTAssertEqual(program.goalRaw, expected.effectiveGoal.rawValue, expected.name)
        }
    }

    func testLoadIfNeeded_catalogMatchesSeedDefinitions() throws {
        let context = try makeContext()
        let seed = try decodeSeed()

        _ = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        // Ida e volta pelo mapper: cada modelo inserido reproduz a definição do JSON,
        // inclusive `movementPattern` (RF-34).
        let stored = try context.fetch(FetchDescriptor<ExerciseModel>())
        var definitionsByID: [UUID: ExerciseDefinition] = [:]
        for model in stored {
            definitionsByID[model.uuid] = try ExerciseMapper.definition(from: model)
        }
        XCTAssertEqual(definitionsByID.count, seed.catalog.exercises.count)
        for definition in seed.catalog.exercises {
            XCTAssertEqual(definitionsByID[definition.id], definition, definition.slug)
        }
        XCTAssertTrue(stored.allSatisfy { !$0.isArchived })
        XCTAssertTrue(stored.allSatisfy { !$0.isCustom })
    }

    func testLoadIfNeeded_createsSingleUserSettingsRowAtCurrentSeedVersion() throws {
        let context = try makeContext()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserSettingsModel>()), 0)

        _ = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        let rows = try context.fetch(FetchDescriptor<UserSettingsModel>())
        XCTAssertEqual(rows.count, 1)
        let settings = try XCTUnwrap(rows.first)
        XCTAssertEqual(settings.schemaSeedVersion, 3)
        XCTAssertEqual(settings.schemaSeedVersion, SeedLoader.currentSeedVersion)
        XCTAssertTrue(settings.weekStartsOnMonday)
        XCTAssertFalse(settings.healthKitEnabled)
        XCTAssertEqual(settings.defaultRestSeconds, 120)
        XCTAssertEqual(settings.weeklyTargets, [:])
    }

    // MARK: - Idempotência

    func testLoadIfNeeded_secondRun_isSkippedAndKeepsCounts() throws {
        let context = try makeContext()
        let seed = try decodeSeed()
        _ = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        let report = try SeedLoader.loadIfNeeded(
            context: context,
            bundle: appBundle,
            now: now.addingTimeInterval(86_400)
        )

        XCTAssertEqual(
            report,
            SeedLoadReport(insertedExercises: 0, updatedExercises: 0, insertedPrograms: 0, skipped: true)
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), seed.catalog.exercises.count)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramModel>()), seed.programs.programs.count)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramDayModel>()), dayCount(in: seed))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), targetCount(in: seed))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserSettingsModel>()), 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ProgramModel>()).filter(\.isActive).count, 1)
    }

    func testLoadIfNeeded_settingsAlreadyAtOrAboveCurrentVersion_skipsWithoutTouchingStore() throws {
        // `>=`: a versão corrente e uma versão futura (downgrade do app) são ambas "já instalado".
        for installedVersion in [SeedLoader.currentSeedVersion, SeedLoader.currentSeedVersion + 1] {
            let context = try makeContext()
            let settings = UserSettingsModel(
                uuid: UUID(),
                weekStartsOnMonday: false,
                weeklyTargetsRaw: "{}",
                healthKitEnabled: true,
                defaultRestSeconds: 90,
                schemaSeedVersion: installedVersion
            )
            context.insert(settings)
            try context.save()

            let report = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

            XCTAssertTrue(report.skipped, "versão \(installedVersion)")
            XCTAssertEqual(report.insertedExercises, 0, "versão \(installedVersion)")
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), 0, "versão \(installedVersion)")
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramModel>()), 0, "versão \(installedVersion)")
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserSettingsModel>()), 1, "versão \(installedVersion)")
            // Configuração do usuário intacta, inclusive a versão gravada.
            XCTAssertFalse(settings.weekStartsOnMonday)
            XCTAssertTrue(settings.healthKitEnabled)
            XCTAssertEqual(settings.defaultRestSeconds, 90)
            XCTAssertEqual(settings.schemaSeedVersion, installedVersion)
        }
    }

    // MARK: - Reaplicar o seed preservando edições do usuário

    func testLoadIfNeeded_reseedUpdatesCatalogFromSeedButKeepsUserEdits() throws {
        let context = try makeContext()
        _ = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)
        let seed = try decodeSeed()
        let definition = try XCTUnwrap(seed.catalog.exercises.first)

        // Edições do usuário + campos de catálogo alterados à mão, para provar que o seed
        // sobrescreve só os de catálogo.
        let edited = try XCTUnwrap(fetchExercise(slug: definition.slug, in: context))
        edited.machineNotes = "Banco 3, pino 7"
        edited.isArchived = true
        edited.name = "Nome editado pelo usuário"
        edited.loadIncrement = 100
        edited.movementPatternRaw = "teleport"
        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettingsModel>()).first)
        settings.schemaSeedVersion = 1
        try context.save()

        let report = try SeedLoader.loadIfNeeded(
            context: context,
            bundle: appBundle,
            now: now.addingTimeInterval(86_400)
        )

        XCTAssertEqual(
            report,
            SeedLoadReport(
                insertedExercises: 0,
                updatedExercises: seed.catalog.exercises.count,
                insertedPrograms: 0,
                skipped: false,
                skippedPrograms: seed.programs.programs.count
            )
        )
        // Upsert por slug: nenhum segundo modelo com o mesmo uuid/slug.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), seed.catalog.exercises.count)

        let reloaded = try XCTUnwrap(fetchExercise(slug: definition.slug, in: context))
        XCTAssertEqual(reloaded.uuid, definition.id)
        XCTAssertEqual(reloaded.machineNotes, "Banco 3, pino 7")
        XCTAssertTrue(reloaded.isArchived)
        XCTAssertFalse(reloaded.isCustom)
        XCTAssertEqual(reloaded.name, definition.name)
        XCTAssertEqual(reloaded.loadIncrement, definition.loadIncrement)
        XCTAssertEqual(reloaded.movementPatternRaw, definition.movementPattern?.rawValue)
        XCTAssertEqual(settings.schemaSeedVersion, SeedLoader.currentSeedVersion)

        // Os programas já existiam: o seed não os reinstala nem duplica.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramModel>()), seed.programs.programs.count)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramDayModel>()), dayCount(in: seed))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), targetCount(in: seed))
    }

    func testLoadIfNeeded_upgradeFromSeedV2_insertsOnlyMissingExercisesAndKeepsSeedEdits() throws {
        let context = try makeContext()
        let seed = try decodeSeed()
        _ = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        // Estado de uma instalação com o seed 2: os exercícios de casa da versão 2.1 ainda não
        // existem, e o usuário editou um exercício do seed (o store ainda não marca essa edição).
        let newSlugs = ["bodyweight-squat", "backpack-bent-over-row", "grocery-bag-carry"]
        for slug in newSlugs {
            let model = try XCTUnwrap(fetchExercise(slug: slug, in: context), slug)
            context.delete(model)
        }
        let definition = try XCTUnwrap(seed.catalog.exercises.first)
        let edited = try XCTUnwrap(fetchExercise(slug: definition.slug, in: context))
        edited.name = "Supino do meu jeito"
        edited.loadIncrement = 1
        edited.machineNotes = "Banco 2"
        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettingsModel>()).first)
        settings.schemaSeedVersion = 2
        try context.save()
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<ExerciseModel>()),
            seed.catalog.exercises.count - newSlugs.count
        )

        let report = try SeedLoader.loadIfNeeded(
            context: context,
            bundle: appBundle,
            now: now.addingTimeInterval(86_400)
        )

        XCTAssertEqual(
            report,
            SeedLoadReport(
                insertedExercises: newSlugs.count,
                updatedExercises: 0,
                insertedPrograms: 0,
                skipped: false,
                skippedPrograms: seed.programs.programs.count
            )
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), seed.catalog.exercises.count)
        for slug in newSlugs {
            let inserted = try XCTUnwrap(fetchExercise(slug: slug, in: context), slug)
            XCTAssertFalse(inserted.isCustom, slug)
            XCTAssertFalse(inserted.isArchived, slug)
        }
        XCTAssertEqual(edited.name, "Supino do meu jeito")
        XCTAssertEqual(edited.loadIncrement, 1)
        XCTAssertEqual(edited.machineNotes, "Banco 2")
        XCTAssertEqual(settings.schemaSeedVersion, SeedLoader.currentSeedVersion)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramModel>()), seed.programs.programs.count)
    }

    func testLoadIfNeeded_customExerciseWithSeedSlug_isNeverTouched() throws {
        let context = try makeContext()
        let seed = try decodeSeed()
        let definition = try XCTUnwrap(seed.catalog.exercises.first)
        let custom = ExerciseModel(
            uuid: UUID(),
            slug: definition.slug,
            name: "Meu exercício",
            primaryMusclesRaw: CurrentSchema.encodeMuscleGroups([.calves]),
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.kettlebell.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 1,
            isUnilateral: true,
            machineNotes: "Minha nota",
            isArchived: false,
            movementPatternRaw: nil,
            isCustom: true
        )
        context.insert(custom)
        try context.save()

        let report = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        XCTAssertEqual(report.insertedExercises, seed.catalog.exercises.count - 1)
        XCTAssertEqual(report.updatedExercises, 0)
        XCTAssertEqual(report.insertedPrograms, seed.programs.programs.count)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), seed.catalog.exercises.count)

        let reloaded = try XCTUnwrap(fetchExercise(slug: definition.slug, in: context))
        XCTAssertEqual(reloaded.uuid, custom.uuid)
        XCTAssertTrue(reloaded.isCustom)
        XCTAssertEqual(reloaded.name, "Meu exercício")
        XCTAssertEqual(reloaded.primaryMusclesRaw, "calves")
        XCTAssertEqual(reloaded.equipmentRaw, "kettlebell")
        XCTAssertEqual(reloaded.loadIncrement, 1)
        XCTAssertTrue(reloaded.isUnilateral)
        XCTAssertEqual(reloaded.machineNotes, "Minha nota")
        XCTAssertNil(reloaded.movementPatternRaw)
    }

    // MARK: - Programas em instalações existentes

    func testLoadIfNeeded_upgradeFromSeedV1_insertsNewProgramsInactiveAndKeepsOldProgram() throws {
        let context = try makeContext()
        let seed = try decodeSeed()
        let definition = try XCTUnwrap(seed.catalog.exercises.first)
        let installedAt = now.addingTimeInterval(-30 * 86_400)

        // Estado de uma instalação M1: seed v1 aplicado, exercício sem padrão de movimento e
        // com nota do usuário, um exercício que o v2 não traz mais e o programa antigo ativo.
        let settings = UserSettingsModel(
            uuid: UUID(),
            weekStartsOnMonday: true,
            weeklyTargetsRaw: "{}",
            healthKitEnabled: false,
            defaultRestSeconds: 120,
            schemaSeedVersion: 1
        )
        context.insert(settings)
        let oldExercise = ExerciseModel(
            uuid: definition.id,
            slug: definition.slug,
            name: "Nome da v1",
            primaryMusclesRaw: CurrentSchema.encodeMuscleGroups(definition.primaryMuscles),
            secondaryMusclesRaw: CurrentSchema.encodeMuscleGroups(definition.secondaryMuscles),
            equipmentRaw: definition.equipment.rawValue,
            loadUnitRaw: definition.loadUnit.rawValue,
            loadIncrement: definition.loadIncrement,
            isUnilateral: definition.isUnilateral,
            machineNotes: "Pino 4",
            isArchived: false
        )
        context.insert(oldExercise)
        let retired = ExerciseModel(
            uuid: UUID(),
            slug: "exercicio-que-saiu-do-seed",
            name: "Exercício antigo",
            primaryMusclesRaw: "back",
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.machine.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        context.insert(retired)
        let oldProgram = insertProgram(
            name: "Programa ABC",
            isActive: true,
            createdAt: installedAt,
            exercise: oldExercise,
            into: context
        )
        try context.save()

        let report = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        XCTAssertEqual(
            report,
            SeedLoadReport(
                insertedExercises: seed.catalog.exercises.count - 1,
                updatedExercises: 1,
                insertedPrograms: seed.programs.programs.count,
                skipped: false,
                skippedPrograms: 0
            )
        )
        XCTAssertEqual(settings.schemaSeedVersion, SeedLoader.currentSeedVersion)

        // Programas novos entram todos inativos; o antigo continua o único ativo.
        let programs = try context.fetch(FetchDescriptor<ProgramModel>())
        XCTAssertEqual(programs.count, seed.programs.programs.count + 1)
        XCTAssertEqual(programs.filter(\.isActive).map(\.uuid), [oldProgram.uuid])
        let seedIDs = Set(seed.programs.programs.map(\.id))
        let inserted = programs.filter { seedIDs.contains($0.uuid) }
        XCTAssertEqual(inserted.count, seed.programs.programs.count)
        XCTAssertTrue(inserted.allSatisfy { !$0.isActive })
        XCTAssertTrue(inserted.allSatisfy { $0.createdAt == now })

        // Programa antigo intocado.
        XCTAssertEqual(oldProgram.name, "Programa ABC")
        XCTAssertEqual(oldProgram.createdAt, installedAt)
        XCTAssertEqual(oldProgram.goalRaw, "hypertrophy")
        XCTAssertEqual(oldProgram.days.count, 1)
        XCTAssertEqual(oldProgram.days.first?.exercises.count, 1)
        XCTAssertEqual(oldProgram.days.first?.exercises.first?.exercise?.uuid, oldExercise.uuid)

        // Catálogo: exercício existente atualizado (ganha o padrão) sem perder a nota; o que
        // saiu do seed continua no store (o histórico pode apontar para ele).
        XCTAssertEqual(oldExercise.name, definition.name)
        XCTAssertEqual(oldExercise.movementPatternRaw, definition.movementPattern?.rawValue)
        XCTAssertEqual(oldExercise.machineNotes, "Pino 4")
        XCTAssertNotNil(try fetchExercise(slug: "exercicio-que-saiu-do-seed", in: context))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), seed.catalog.exercises.count + 1)
    }

    func testLoadIfNeeded_existingActiveProgramWithoutSettings_seedProgramsEnterInactive() throws {
        let context = try makeContext()
        let seed = try decodeSeed()
        let custom = ProgramModel(uuid: UUID(), name: "Meu programa", isActive: true, createdAt: now)
        context.insert(custom)
        try context.save()

        let report = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        XCTAssertFalse(report.skipped)
        XCTAssertEqual(report.insertedExercises, seed.catalog.exercises.count)
        XCTAssertEqual(report.insertedPrograms, seed.programs.programs.count)
        let programs = try context.fetch(FetchDescriptor<ProgramModel>())
        XCTAssertEqual(programs.filter(\.isActive).map(\.name), ["Meu programa"])
        XCTAssertEqual(custom.days.count, 0)
    }

    func testLoadIfNeeded_existingProgramsAllInactive_seedActiveProgramBecomesActive() throws {
        let context = try makeContext()
        let seed = try decodeSeed()
        let seedActive = try XCTUnwrap(seed.programs.programs.first(where: \.isActive))
        let dormant = ProgramModel(uuid: UUID(), name: "Parado", isActive: false, createdAt: now)
        context.insert(dormant)
        try context.save()

        _ = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        // SPEC S1 precisa de um programa ativo; sem nenhum, vale o ativo do seed.
        let programs = try context.fetch(FetchDescriptor<ProgramModel>())
        XCTAssertEqual(programs.filter(\.isActive).map(\.uuid), [seedActive.id])
        XCTAssertFalse(dormant.isActive)
    }

    func testLoadIfNeeded_seedProgramAlreadyInStore_isSkippedAndLeftUntouched() throws {
        let context = try makeContext()
        let seed = try decodeSeed()
        let seedActive = try XCTUnwrap(seed.programs.programs.first(where: \.isActive))
        // Mesmo `uuid` do programa do seed, editado pelo usuário (ou restaurado de backup).
        let edited = ProgramModel(
            uuid: seedActive.id,
            name: "Editado pelo usuário",
            isActive: true,
            createdAt: now.addingTimeInterval(-86_400),
            goalRaw: ProgramGoal.strength.rawValue
        )
        context.insert(edited)
        try context.save()

        let report = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        XCTAssertEqual(report.insertedPrograms, seed.programs.programs.count - 1)
        XCTAssertEqual(report.skippedPrograms, 1)
        let programs = try context.fetch(FetchDescriptor<ProgramModel>())
        XCTAssertEqual(programs.count, seed.programs.programs.count)
        XCTAssertEqual(programs.filter { $0.uuid == seedActive.id }.count, 1)
        XCTAssertEqual(programs.filter(\.isActive).map(\.uuid), [seedActive.id])
        XCTAssertEqual(edited.name, "Editado pelo usuário")
        XCTAssertEqual(edited.goalRaw, "strength")
        XCTAssertEqual(edited.days.count, 0)
    }

    // MARK: - Erros

    func testLoadIfNeeded_bundleWithoutSeed_throwsResourceMissingAndWritesNothing() throws {
        let context = try makeContext()
        // O bundle de testes só tem os testes compilados: sem JSON (por isso os demais testes
        // usam `Bundle.main`, o bundle do app hospedeiro).
        let testBundle = Bundle(for: SeedLoaderTests.self)

        XCTAssertThrowsError(try SeedLoader.loadIfNeeded(context: context, bundle: testBundle, now: now)) { error in
            XCTAssertEqual(error as? SeedLoaderError, .resourceMissing("exercises.v2.json"))
        }
        // Ler e validar vem antes de gravar: nem o `UserSettingsModel` é criado.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserSettingsModel>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramModel>()), 0)
    }

    // MARK: - ProgramMapper.model(from:exercises:createdAt:)

    func testProgramMapper_model_buildsGraphThatRoundTripsToTemplate() throws {
        let context = try makeContext()
        let squat = insertExercise(slug: "agachamento", into: context)
        let bench = insertExercise(slug: "supino", into: context)
        try context.save()

        let template = ProgramTemplate(
            id: UUID(),
            name: "AB",
            days: [
                ProgramDayTemplate(
                    id: UUID(),
                    name: "Dia A",
                    order: 0,
                    exercises: [
                        ExerciseTarget(
                            id: UUID(),
                            exerciseID: squat.uuid,
                            order: 0,
                            sets: 4,
                            repMin: 5,
                            repMax: 8,
                            targetRIR: 1,
                            restSeconds: 180,
                            startingLoad: 60
                        ),
                        ExerciseTarget(
                            id: UUID(),
                            exerciseID: bench.uuid,
                            order: 1,
                            sets: 3,
                            repMin: 8,
                            repMax: 12,
                            targetRIR: 2,
                            restSeconds: 120,
                            startingLoad: nil
                        ),
                    ]
                ),
                ProgramDayTemplate(
                    id: UUID(),
                    name: "Dia B",
                    order: 1,
                    exercises: [
                        ExerciseTarget(
                            id: UUID(),
                            exerciseID: bench.uuid,
                            order: 0,
                            sets: 2,
                            repMin: 12,
                            repMax: 15,
                            targetRIR: 3,
                            restSeconds: 90,
                            startingLoad: 0
                        ),
                    ]
                ),
            ],
            isActive: true,
            goal: .strength,
            summary: "Dois dias, básicos pesados"
        )

        let model = try ProgramMapper.model(
            from: template,
            exercises: [squat.uuid: squat, bench.uuid: bench],
            createdAt: now
        )
        XCTAssertEqual(model.uuid, template.id)
        XCTAssertEqual(model.name, "AB")
        XCTAssertTrue(model.isActive)
        XCTAssertEqual(model.createdAt, now)
        XCTAssertEqual(model.goalRaw, "strength")
        XCTAssertEqual(model.summary, "Dois dias, básicos pesados")

        // Só a raiz é inserida; o SwiftData leva dias e exercícios do programa junto.
        context.insert(model)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramModel>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramDayModel>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), 3)
        // A relação `exercise` liga ao catálogo existente; não cria cópias.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), 2)

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<ProgramModel>()).first)
        XCTAssertEqual(try ProgramMapper.template(from: fetched), template)
    }

    func testProgramMapper_model_withoutGoal_storesHypertrophy() throws {
        _ = try makeContext()
        let template = ProgramTemplate(id: UUID(), name: "Sem objetivo", days: [], isActive: false)

        let model = try ProgramMapper.model(from: template, exercises: [:], createdAt: now)

        // SPEC §7.9: hipertrofia é o padrão; o sentido inverso devolve o objetivo explícito.
        XCTAssertEqual(model.goalRaw, "hypertrophy")
        XCTAssertNil(model.summary)
        XCTAssertEqual(try ProgramMapper.template(from: model).goal, .hypertrophy)
    }

    func testProgramMapper_model_unknownExerciseID_throwsMissingExerciseWithTargetID() throws {
        // Container criado só para garantir que o esquema está registrado no processo antes
        // de instanciar `@Model` fora de contexto.
        _ = try makeContext()
        let targetID = UUID()
        let template = ProgramTemplate(
            id: UUID(),
            name: "A",
            days: [
                ProgramDayTemplate(
                    id: UUID(),
                    name: "Dia A",
                    order: 0,
                    exercises: [ExerciseTarget(id: targetID, exerciseID: UUID(), order: 0)]
                ),
            ],
            isActive: true
        )

        XCTAssertThrowsError(try ProgramMapper.model(from: template, exercises: [:], createdAt: now)) { error in
            XCTAssertEqual(error as? MappingError, .missingExercise(programExerciseUUID: targetID))
        }
    }

    // MARK: - Fixtures

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainerFactory.make(.inMemory)
        containers.append(container)
        return container.mainContext
    }

    private func decodeSeed() throws -> SeedBundle {
        let catalogURL = try XCTUnwrap(
            appBundle.url(forResource: SeedLoader.catalogResourceName, withExtension: "json"),
            "\(SeedLoader.catalogResourceName).json não está na raiz do bundle do app"
        )
        let programURL = try XCTUnwrap(
            appBundle.url(forResource: SeedLoader.programResourceName, withExtension: "json"),
            "\(SeedLoader.programResourceName).json não está na raiz do bundle do app"
        )
        return try SeedBundle.decode(
            catalogData: Data(contentsOf: catalogURL),
            programData: Data(contentsOf: programURL)
        )
    }

    private func dayCount(in seed: SeedBundle) -> Int {
        seed.programs.programs.reduce(0) { $0 + $1.days.count }
    }

    private func targetCount(in seed: SeedBundle) -> Int {
        seed.programs.programs.reduce(0) { total, program in
            total + program.days.reduce(0) { $0 + $1.exercises.count }
        }
    }

    /// O que `ProgramMapper.template(from:)` devolve para um template do seed: dias e
    /// exercícios ordenados por `order` (to-many não guarda ordem) e o objetivo explícito
    /// (`goalRaw` nunca é vazio no store; `nil` no JSON vira hipertrofia).
    private func normalized(_ template: ProgramTemplate) -> ProgramTemplate {
        let days = template.days
            .sorted { $0.order < $1.order }
            .map { day in
                ProgramDayTemplate(
                    id: day.id,
                    name: day.name,
                    order: day.order,
                    exercises: day.exercises.sorted { $0.order < $1.order }
                )
            }
        return ProgramTemplate(
            id: template.id,
            name: template.name,
            days: days,
            isActive: template.isActive,
            goal: template.effectiveGoal,
            summary: template.summary
        )
    }

    private func fetchExercise(slug: String, in context: ModelContext) throws -> ExerciseModel? {
        try context.fetch(
            FetchDescriptor<ExerciseModel>(
                predicate: #Predicate<ExerciseModel> { $0.slug == slug }
            )
        ).first
    }

    private func insertExercise(slug: String, into context: ModelContext) -> ExerciseModel {
        let model = ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: slug,
            primaryMusclesRaw: CurrentSchema.encodeMuscleGroups([.quads]),
            secondaryMusclesRaw: "",
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

    /// Programa de um dia com um exercício, inserido antes de ligar as relações (o caminho
    /// mais previsível do SwiftData, como em `SchemaV1Tests`).
    private func insertProgram(
        name: String,
        isActive: Bool,
        createdAt: Date,
        exercise: ExerciseModel,
        into context: ModelContext
    ) -> ProgramModel {
        let program = ProgramModel(uuid: UUID(), name: name, isActive: isActive, createdAt: createdAt)
        context.insert(program)
        let day = ProgramDayModel(uuid: UUID(), name: "Dia A", order: 0)
        context.insert(day)
        program.days.append(day)
        let target = ProgramExerciseModel(
            uuid: UUID(),
            order: 0,
            sets: 3,
            repMin: 8,
            repMax: 12,
            targetRIR: 2,
            restSeconds: 120,
            startingLoad: nil
        )
        context.insert(target)
        target.exercise = exercise
        day.exercises.append(target)
        return program
    }
}
