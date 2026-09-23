import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T1.10: `SeedLoader` grava o seed em container in-memory e
/// `ProgramMapper.model(from:exercises:createdAt:)` monta o grafo do programa.
/// Tudo em `@MainActor` (ARCHITECTURE §10).
///
/// Os JSON do seed são recursos do target do APP, copiados para a raiz do bundle do app
/// (ARCHITECTURE §11). O bundle de testes (`Bundle(for: SeedLoaderTests.self)`) não os
/// contém. Como os testes são hospedados pelo app (TEST_HOST definido pelo XcodeGen a partir
/// da dependência no `project.yml`), `Bundle.main` é o bundle do app e é por ele que o seed
/// é lido aqui — exatamente como o app fará.
@MainActor
final class SeedLoaderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private var appBundle: Bundle { Bundle.main }
    /// Mantém os containers vivos até o fim de cada teste, independentemente de o
    /// `ModelContext` reter o seu.
    private var containers: [ModelContainer] = []

    // MARK: - Primeiro launch

    func testLoadIfNeeded_firstRun_insertsCatalogAndActiveProgram() throws {
        let context = try makeContext()

        let report = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        XCTAssertEqual(
            report,
            SeedLoadReport(insertedExercises: 45, updatedExercises: 0, insertedPrograms: 1, skipped: false)
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), 45)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramModel>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramDayModel>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), 15)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserSettingsModel>()), 1)
    }

    func testLoadIfNeeded_catalogMatchesSeedDefinitions() throws {
        let context = try makeContext()
        let seed = try decodeSeed()

        _ = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        // Ida e volta pelo mapper: cada modelo inserido reproduz a definição do JSON.
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
    }

    func testLoadIfNeeded_activeProgramHasThreeDaysOfSixLinkedExercises() throws {
        let context = try makeContext()

        _ = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        let programs = try context.fetch(FetchDescriptor<ProgramModel>())
        XCTAssertEqual(programs.count, 1)
        let program = try XCTUnwrap(programs.first)
        XCTAssertTrue(program.isActive)
        XCTAssertEqual(program.createdAt, now)

        // To-many não garante ordem; `order` é a ordem de verdade.
        let days = program.days.sorted { $0.order < $1.order }
        XCTAssertEqual(days.map(\.order), [0, 1, 2])
        for day in days {
            XCTAssertEqual(day.exercises.count, 5, day.name)
            XCTAssertEqual(day.program?.uuid, program.uuid, day.name)
            for programExercise in day.exercises {
                XCTAssertNotNil(programExercise.exercise, "\(day.name) · order \(programExercise.order)")
                XCTAssertEqual(programExercise.day?.uuid, day.uuid, "\(day.name) · order \(programExercise.order)")
            }
        }

        // O grafo gravado volta exatamente ao template do JSON (ids, ordem, parâmetros).
        let seed = try decodeSeed()
        let expected = try XCTUnwrap(seed.programs.programs.first)
        XCTAssertEqual(try ProgramMapper.template(from: program), expected)
    }

    func testLoadIfNeeded_createsSingleUserSettingsRowAtCurrentSeedVersion() throws {
        let context = try makeContext()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserSettingsModel>()), 0)

        _ = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        let rows = try context.fetch(FetchDescriptor<UserSettingsModel>())
        XCTAssertEqual(rows.count, 1)
        let settings = try XCTUnwrap(rows.first)
        XCTAssertEqual(settings.schemaSeedVersion, 1)
        XCTAssertEqual(settings.schemaSeedVersion, SeedLoader.currentSeedVersion)
        XCTAssertTrue(settings.weekStartsOnMonday)
        XCTAssertFalse(settings.healthKitEnabled)
        XCTAssertEqual(settings.defaultRestSeconds, 120)
        XCTAssertEqual(settings.weeklyTargets, [:])
    }

    // MARK: - Idempotência

    func testLoadIfNeeded_secondRun_isSkippedAndKeepsCounts() throws {
        let context = try makeContext()
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
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), 45)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramModel>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramDayModel>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), 15)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<UserSettingsModel>()), 1)
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

        // Edições do usuário (M2 permitirá isso pela UI) + campos de catálogo alterados à mão,
        // para provar que o seed sobrescreve só os de catálogo.
        let edited = try XCTUnwrap(fetchExercise(slug: definition.slug, in: context))
        edited.machineNotes = "Banco 3, pino 7"
        edited.isArchived = true
        edited.name = "Nome editado pelo usuário"
        edited.loadIncrement = 100
        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettingsModel>()).first)
        settings.schemaSeedVersion = 0
        try context.save()

        let report = try SeedLoader.loadIfNeeded(
            context: context,
            bundle: appBundle,
            now: now.addingTimeInterval(86_400)
        )

        XCTAssertEqual(
            report,
            SeedLoadReport(insertedExercises: 0, updatedExercises: 45, insertedPrograms: 0, skipped: false)
        )
        // Upsert por slug: nenhum segundo modelo com o mesmo uuid/slug.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ExerciseModel>()), 45)

        let reloaded = try XCTUnwrap(fetchExercise(slug: definition.slug, in: context))
        XCTAssertEqual(reloaded.uuid, definition.id)
        XCTAssertEqual(reloaded.machineNotes, "Banco 3, pino 7")
        XCTAssertTrue(reloaded.isArchived)
        XCTAssertEqual(reloaded.name, definition.name)
        XCTAssertEqual(reloaded.loadIncrement, definition.loadIncrement)
        XCTAssertEqual(settings.schemaSeedVersion, SeedLoader.currentSeedVersion)

        // O programa já existia: o seed não o reinstala nem duplica.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramModel>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramDayModel>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), 15)
    }

    func testLoadIfNeeded_existingProgram_isLeftUntouched() throws {
        let context = try makeContext()
        let custom = ProgramModel(uuid: UUID(), name: "Meu programa", isActive: true, createdAt: now)
        context.insert(custom)
        try context.save()

        let report = try SeedLoader.loadIfNeeded(context: context, bundle: appBundle, now: now)

        XCTAssertFalse(report.skipped)
        XCTAssertEqual(report.insertedExercises, 45)
        XCTAssertEqual(report.insertedPrograms, 0)
        let programs = try context.fetch(FetchDescriptor<ProgramModel>())
        XCTAssertEqual(programs.map(\.name), ["Meu programa"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramDayModel>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), 0)
    }

    // MARK: - Erros

    func testLoadIfNeeded_bundleWithoutSeed_throwsResourceMissingAndWritesNothing() throws {
        let context = try makeContext()
        // O bundle de testes só tem os testes compilados: sem JSON (por isso os demais testes
        // usam `Bundle.main`, o bundle do app hospedeiro).
        let testBundle = Bundle(for: SeedLoaderTests.self)

        XCTAssertThrowsError(try SeedLoader.loadIfNeeded(context: context, bundle: testBundle, now: now)) { error in
            XCTAssertEqual(error as? SeedLoaderError, .resourceMissing("exercises.v1.json"))
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
            isActive: true
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
            "exercises.v1.json não está na raiz do bundle do app"
        )
        let programURL = try XCTUnwrap(
            appBundle.url(forResource: SeedLoader.programResourceName, withExtension: "json"),
            "program-default.v1.json não está na raiz do bundle do app"
        )
        return try SeedBundle.decode(
            catalogData: Data(contentsOf: catalogURL),
            programData: Data(contentsOf: programURL)
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
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups([.quads]),
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
}
