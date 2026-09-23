import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T2.5 (RF-15): `CatalogRepository` é o único caminho de escrita do catálogo (AGENTS R4). Cobre
/// leitura ordenada em pt-BR com e sem arquivados, criação de exercício do usuário (slug único,
/// `isCustom`), edição, arquivamento e cada erro de `CatalogRepositoryError`. Tudo em `@MainActor`
/// com container in-memory (ARCHITECTURE §10).
@MainActor
final class CatalogRepositoryTests: XCTestCase {
    // MARK: - Leitura

    func testAllExercises_excludesArchivedByDefault_sortedByNamePtBR() throws {
        let fixture = try makeFixture()
        insertExercise(slug: "remada", name: "Remada baixa", into: fixture.context)
        insertExercise(slug: "abdominal", name: "abdominal", into: fixture.context)
        insertExercise(slug: "agil", name: "Ágil step", into: fixture.context)
        insertExercise(slug: "elevacao", name: "Elevação pélvica", into: fixture.context)
        insertExercise(slug: "velho", name: "Aaa arquivado", archived: true, into: fixture.context)
        try fixture.context.save()

        let names = try fixture.repository.allExercises(includeArchived: false).map { $0.name }

        // pt-BR sem diferenciar maiúsculas: "Á" fica entre os "a", não depois do "z".
        XCTAssertEqual(names, ["abdominal", "Ágil step", "Elevação pélvica", "Remada baixa"])
    }

    func testAllExercises_includeArchived_returnsEverything() throws {
        let fixture = try makeFixture()
        insertExercise(slug: "remada", name: "Remada baixa", into: fixture.context)
        insertExercise(slug: "velho", name: "Aaa arquivado", archived: true, into: fixture.context)
        try fixture.context.save()

        let names = try fixture.repository.allExercises(includeArchived: true).map { $0.name }

        XCTAssertEqual(names, ["Aaa arquivado", "Remada baixa"])
    }

    func testExercise_mapsPatternAndOrigin_includesArchived() throws {
        let fixture = try makeFixture()
        let model = insertExercise(slug: "supino-reto", name: "Supino reto", archived: true, into: fixture.context)
        model.movementPatternRaw = MovementPattern.horizontalPush.rawValue
        try fixture.context.save()

        let definition = try XCTUnwrap(fixture.repository.exercise(id: model.uuid))

        XCTAssertEqual(definition.id, model.uuid)
        XCTAssertEqual(definition.slug, "supino-reto")
        XCTAssertEqual(definition.movementPattern, .horizontalPush)
        XCTAssertFalse(definition.isCustom)
    }

    func testExercise_unknownID_returnsNil() throws {
        let fixture = try makeFixture()

        XCTAssertNil(try fixture.repository.exercise(id: UUID()))
    }

    // MARK: - createExercise

    func testCreateExercise_storesCustomExerciseWithGeneratedSlug() throws {
        let fixture = try makeFixture()
        let draft = ExerciseDraft(
            name: "  Supino Inclinado c/ Halteres ",
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .shoulders],
            equipment: .dumbbell,
            loadUnit: .kilograms,
            loadIncrement: 2,
            isUnilateral: true,
            machineNotes: "  Banco no 3º furo ",
            movementPattern: .horizontalPush
        )

        let id = try fixture.repository.createExercise(draft)

        let definition = try XCTUnwrap(fixture.repository.exercise(id: id))
        let shortID = String(id.uuidString.lowercased().prefix(8))
        XCTAssertEqual(definition.slug, "custom-supino-inclinado-c-halteres-\(shortID)")
        XCTAssertEqual(definition.name, "Supino Inclinado c/ Halteres")
        XCTAssertEqual(definition.primaryMuscles, [.chest])
        XCTAssertEqual(definition.secondaryMuscles, [.triceps, .shoulders])
        XCTAssertEqual(definition.equipment, .dumbbell)
        XCTAssertEqual(definition.loadUnit, .kilograms)
        XCTAssertEqual(definition.loadIncrement, 2)
        XCTAssertTrue(definition.isUnilateral)
        XCTAssertEqual(definition.machineNotes, "Banco no 3º furo")
        XCTAssertEqual(definition.movementPattern, .horizontalPush)
        XCTAssertTrue(definition.isCustom)

        // Campos do SchemaV2 gravados no modelo (o seed nunca sobrescreve `isCustom == true`).
        let model = try fetchModel(id, in: fixture.context)
        XCTAssertTrue(model.isCustom)
        XCTAssertFalse(model.isArchived)
        XCTAssertEqual(model.movementPatternRaw, MovementPattern.horizontalPush.rawValue)
    }

    func testCreateExercise_persistsBeyondTheContext() throws {
        let fixture = try makeFixture()

        let id = try fixture.repository.createExercise(validDraft(name: "Remada curvada"))

        // Outro contexto do mesmo container só enxerga o que foi salvo.
        let otherContext = ModelContext(fixture.container)
        XCTAssertEqual(try fetchModel(id, in: otherContext).name, "Remada curvada")
    }

    func testCreateExercise_sameNameTwice_getsDistinctSlugs() throws {
        let fixture = try makeFixture()

        let first = try fixture.repository.createExercise(validDraft(name: "Rosca Scott"))
        let second = try fixture.repository.createExercise(validDraft(name: "Rosca Scott"))

        let slugs = try [first, second].map { try XCTUnwrap(fixture.repository.exercise(id: $0)?.slug) }
        XCTAssertNotEqual(slugs[0], slugs[1])
        XCTAssertTrue(slugs.allSatisfy { $0.hasPrefix("custom-rosca-scott-") })
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ExerciseModel>()), 2)
    }

    func testCreateExercise_nameWithoutLettersOrDigits_slugIsPrefixAndShortID() throws {
        let fixture = try makeFixture()

        let id = try fixture.repository.createExercise(validDraft(name: "!!! ???"))

        let shortID = String(id.uuidString.lowercased().prefix(8))
        XCTAssertEqual(try fixture.repository.exercise(id: id)?.slug, "custom-\(shortID)")
    }

    func testCreateExercise_blankNotes_becomeNil() throws {
        let fixture = try makeFixture()
        var draft = validDraft(name: "Voador")
        draft.machineNotes = "   "

        let id = try fixture.repository.createExercise(draft)

        XCTAssertNil(try fixture.repository.exercise(id: id)?.machineNotes)
    }

    func testCreateExercise_invalidDrafts_throwInvalidDraft() throws {
        let fixture = try makeFixture()
        var blankName = validDraft(name: "   ")
        blankName.primaryMuscles = [.chest]
        var noPrimary = validDraft(name: "Supino")
        noPrimary.primaryMuscles = []
        var zeroIncrement = validDraft(name: "Supino")
        zeroIncrement.loadIncrement = 0
        var negativeIncrement = validDraft(name: "Supino")
        negativeIncrement.loadIncrement = -2.5
        var infiniteIncrement = validDraft(name: "Supino")
        infiniteIncrement.loadIncrement = .infinity
        var nanIncrement = validDraft(name: "Supino")
        nanIncrement.loadIncrement = .nan

        for draft in [blankName, noPrimary, zeroIncrement, negativeIncrement, infiniteIncrement, nanIncrement] {
            assertThrows(try fixture.repository.createExercise(draft), .invalidDraft)
        }
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ExerciseModel>()), 0)
    }

    // MARK: - Slug

    func testKebabCase_foldsAccentsAndCollapsesSeparators() {
        let cases: [(input: String, expected: String)] = [
            ("Supino Inclinado c/ Halteres", "supino-inclinado-c-halteres"),
            ("  Elevação   Pélvica!! ", "elevacao-pelvica"),
            ("Leg press 45°", "leg-press-45"),
            ("Crucifixo — máquina", "crucifixo-maquina"),
            ("Açúcar & Café", "acucar-cafe"),
            ("!!!", ""),
            // 40 caracteres terminariam em hífen: o hífen final sai.
            ("aaaaaaaaa bbbbbbbbb ccccccccc ddddddddd eeeee", "aaaaaaaaa-bbbbbbbbb-ccccccccc-ddddddddd"),
        ]

        for testCase in cases {
            XCTAssertEqual(CatalogRepository.kebabCase(testCase.input), testCase.expected, testCase.input)
        }
    }

    // MARK: - updateExercise

    func testUpdateExercise_rewritesEditableFields_keepsIdentityAndFlags() throws {
        let fixture = try makeFixture()
        // Exercício do seed: a edição vale para ele também e `isCustom` continua `false`.
        let model = insertExercise(slug: "leg-press-45", name: "Leg press 45°", into: fixture.context)
        try fixture.context.save()
        let draft = ExerciseDraft(
            name: " Leg press horizontal ",
            primaryMuscles: [.quads, .glutes],
            secondaryMuscles: [.hamstrings],
            equipment: .machine,
            loadUnit: .plates,
            loadIncrement: 1,
            isUnilateral: true,
            machineNotes: "Encosto no 4",
            movementPattern: .squat
        )

        try fixture.repository.updateExercise(id: model.uuid, with: draft)

        let definition = try XCTUnwrap(fixture.repository.exercise(id: model.uuid))
        XCTAssertEqual(definition.slug, "leg-press-45")
        XCTAssertEqual(definition.name, "Leg press horizontal")
        XCTAssertEqual(definition.primaryMuscles, [.quads, .glutes])
        XCTAssertEqual(definition.secondaryMuscles, [.hamstrings])
        XCTAssertEqual(definition.equipment, .machine)
        XCTAssertEqual(definition.loadUnit, .plates)
        XCTAssertEqual(definition.loadIncrement, 1)
        XCTAssertTrue(definition.isUnilateral)
        XCTAssertEqual(definition.machineNotes, "Encosto no 4")
        XCTAssertEqual(definition.movementPattern, .squat)
        XCTAssertFalse(definition.isCustom)
        XCTAssertFalse(model.isArchived)
    }

    func testUpdateExercise_clearingPatternAndNotes_storesNil() throws {
        let fixture = try makeFixture()
        let id = try fixture.repository.createExercise(validDraft(name: "Supino"))
        var draft = try XCTUnwrap(fixture.repository.exercise(id: id).map { ExerciseDraft(from: $0) })
        draft.movementPattern = nil
        draft.machineNotes = ""

        try fixture.repository.updateExercise(id: id, with: draft)

        let definition = try XCTUnwrap(fixture.repository.exercise(id: id))
        XCTAssertNil(definition.movementPattern)
        XCTAssertNil(definition.machineNotes)
        XCTAssertTrue(definition.isCustom)
    }

    func testUpdateExercise_invalidDraft_throwsAndLeavesExerciseUnchanged() throws {
        let fixture = try makeFixture()
        let model = insertExercise(slug: "supino-reto", name: "Supino reto", into: fixture.context)
        try fixture.context.save()
        var draft = validDraft(name: "Novo nome")
        draft.primaryMuscles = []

        assertThrows(try fixture.repository.updateExercise(id: model.uuid, with: draft), .invalidDraft)
        XCTAssertEqual(try fixture.repository.exercise(id: model.uuid)?.name, "Supino reto")
    }

    func testUpdateExercise_unknownID_throwsExerciseNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(
            try fixture.repository.updateExercise(id: unknown, with: validDraft(name: "Supino")),
            .exerciseNotFound(unknown)
        )
    }

    // MARK: - setArchived

    func testSetArchived_hidesFromListAndBack() throws {
        let fixture = try makeFixture()
        let model = insertExercise(slug: "supino-reto", name: "Supino reto", into: fixture.context)
        try fixture.context.save()

        try fixture.repository.setArchived(id: model.uuid, true)

        XCTAssertTrue(model.isArchived)
        XCTAssertTrue(try fixture.repository.allExercises(includeArchived: false).isEmpty)
        XCTAssertEqual(try fixture.repository.allExercises(includeArchived: true).map { $0.id }, [model.uuid])
        // Arquivar nunca apaga: o histórico aponta para ele (ARCHITECTURE §5).
        XCTAssertNotNil(try fixture.repository.exercise(id: model.uuid))

        try fixture.repository.setArchived(id: model.uuid, false)

        XCTAssertFalse(model.isArchived)
        XCTAssertEqual(try fixture.repository.allExercises(includeArchived: false).map { $0.id }, [model.uuid])
    }

    func testSetArchived_unknownID_throwsExerciseNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(try fixture.repository.setArchived(id: unknown, true), .exerciseNotFound(unknown))
    }

    // MARK: - Fixture

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let repository: CatalogRepository
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        return Fixture(
            container: container,
            context: context,
            repository: CatalogRepository(modelContext: context)
        )
    }

    private func validDraft(name: String) -> ExerciseDraft {
        ExerciseDraft(
            name: name,
            primaryMuscles: [.chest],
            equipment: .machine,
            loadUnit: .kilograms,
            loadIncrement: 5,
            machineNotes: "Nota",
            movementPattern: .horizontalPush
        )
    }

    @discardableResult
    private func insertExercise(
        slug: String,
        name: String,
        archived: Bool = false,
        into context: ModelContext
    ) -> ExerciseModel {
        let model = ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: name,
            primaryMusclesRaw: MuscleGroup.quads.rawValue,
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.machine.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: archived
        )
        context.insert(model)
        return model
    }

    private func fetchModel(_ id: UUID, in context: ModelContext) throws -> ExerciseModel {
        let descriptor = FetchDescriptor<ExerciseModel>(predicate: #Predicate<ExerciseModel> { $0.uuid == id })
        return try XCTUnwrap(context.fetch(descriptor).first)
    }

    private func assertThrows<T>(
        _ expression: @autoclosure () throws -> T,
        _ expected: CatalogRepositoryError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? CatalogRepositoryError, expected, file: file, line: line)
        }
    }
}
