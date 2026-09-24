import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T2.5 (RF-15): `CatalogListViewModel`, `ExerciseEditorViewModel` e os helpers puros do catálogo
/// (busca, seções, textos pt-BR) sobre um double de `CatalogRepositoring`. Nada aqui toca SwiftData:
/// os ViewModels só conhecem o protocolo (AGENTS R4).
@MainActor
final class CatalogViewModelTests: XCTestCase {
    // MARK: - CatalogListViewModel · leitura

    func testLoad_readsCatalog_andDerivesArchivedIDsFromBothReads() {
        let repository = CatalogTestRepository(archived: [CatalogTestFixture.fly.id])
        let model = CatalogListViewModel(catalog: repository)

        XCTAssertTrue(model.exercises.isEmpty, "Nada é lido no init: a view chama load()")
        XCTAssertFalse(model.hasLoaded)
        model.load()

        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(Set(model.exercises.map(\.id)), Set(CatalogTestFixture.all.map(\.id)))
        XCTAssertEqual(model.archivedIDs, [CatalogTestFixture.fly.id])
        XCTAssertTrue(model.isArchived(CatalogTestFixture.fly))
        XCTAssertFalse(model.isArchived(CatalogTestFixture.bench))
        XCTAssertFalse(model.didFailToLoad)
        XCTAssertNil(model.errorMessage)
    }

    func testVisibleExercises_hidesArchived_untilShowArchived() {
        let repository = CatalogTestRepository(archived: [CatalogTestFixture.fly.id])
        let model = CatalogListViewModel(catalog: repository)
        model.load()

        XCTAssertFalse(model.visibleExercises.contains(CatalogTestFixture.fly))
        XCTAssertEqual(model.visibleExercises.count, CatalogTestFixture.all.count - 1)

        model.showArchived = true
        XCTAssertTrue(model.visibleExercises.contains(CatalogTestFixture.fly))
        XCTAssertEqual(model.visibleExercises.count, CatalogTestFixture.all.count)
    }

    func testSearch_ignoresCaseAndAccents_andRequiresEveryWord() {
        let model = CatalogListViewModel(catalog: CatalogTestRepository())
        model.load()

        model.searchText = "SUPINO"
        XCTAssertEqual(model.visibleExercises.map(\.name), ["Supino com halteres", "Supino reto com barra"])

        model.searchText = "supino halter"
        XCTAssertEqual(model.visibleExercises.map(\.name), ["Supino com halteres"])

        model.searchText = "pelvica"
        XCTAssertEqual(model.visibleExercises.map(\.name), ["Elevação pélvica"], "Sem acento acha com acento")

        model.searchText = "   "
        XCTAssertEqual(model.visibleExercises.count, CatalogTestFixture.all.count, "Só espaços = sem busca")

        model.searchText = "inexistente"
        XCTAssertTrue(model.visibleExercises.isEmpty)
    }

    func testMuscleFilter_matchesPrimaryGroupsOnly() {
        let model = CatalogListViewModel(catalog: CatalogTestRepository())
        model.load()

        model.muscleFilter = .glutes
        // Leg press tem glúteo como 2º primário (entra); agachamento só como secundário (não entra).
        XCTAssertEqual(model.visibleExercises.map(\.name), ["Elevação pélvica", "Leg press 45°"])

        model.muscleFilter = .triceps
        XCTAssertTrue(model.visibleExercises.isEmpty, "Tríceps só aparece como secundário do supino")
    }

    func testSections_followFirstPrimaryGroup_inMuscleOrder_sortedByName() {
        let model = CatalogListViewModel(catalog: CatalogTestRepository())
        model.load()

        let sections = model.sections
        XCTAssertEqual(sections.map(\.group), [.chest, .back, .biceps, .quads, .glutes])
        XCTAssertEqual(sections.map(\.title), ["Peito", "Costas", "Bíceps", "Quadríceps", "Glúteos"])
        XCTAssertEqual(
            sections.first?.exercises.map(\.name),
            ["Crucifixo na máquina", "Supino com halteres", "Supino reto com barra"]
        )
        XCTAssertEqual(
            sections.first { $0.group == .quads }?.exercises.map(\.name),
            ["Agachamento livre", "Leg press 45°"],
            "Leg press (quadríceps, glúteos) fica na seção do primeiro primário"
        )
    }

    func testLoad_failure_keepsLastGoodList_andReportsInPortuguese() {
        let repository = CatalogTestRepository()
        let model = CatalogListViewModel(catalog: repository)
        model.load()
        let before = model.exercises

        repository.readError = CatalogTestError.boom
        model.load()

        XCTAssertEqual(model.exercises, before, "Uma leitura falha não esvazia a tela")
        XCTAssertTrue(model.didFailToLoad)
        XCTAssertEqual(model.errorMessage, "Não foi possível carregar o catálogo de exercícios.")
        XCTAssertTrue(model.isPresentingError)

        model.isPresentingError = false
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.didFailToLoad, "Fechar o alerta não apaga o estado de falha")

        repository.readError = nil
        model.load()
        XCTAssertFalse(model.didFailToLoad)
    }

    // MARK: - CatalogListViewModel · arquivar

    func testToggleArchived_archivesThenRestores_throughRepository() {
        let repository = CatalogTestRepository()
        let model = CatalogListViewModel(catalog: repository)
        model.load()

        model.toggleArchived(CatalogTestFixture.bench)
        XCTAssertEqual(repository.archiveCalls.last?.id, CatalogTestFixture.bench.id)
        XCTAssertEqual(repository.archiveCalls.last?.archived, true)
        XCTAssertTrue(model.isArchived(CatalogTestFixture.bench), "A lista é relida depois de arquivar")
        XCTAssertFalse(model.visibleExercises.contains(CatalogTestFixture.bench))

        model.showArchived = true
        model.toggleArchived(CatalogTestFixture.bench)
        XCTAssertEqual(repository.archiveCalls.last?.archived, false)
        XCTAssertFalse(model.isArchived(CatalogTestFixture.bench))
        XCTAssertEqual(repository.archiveCalls.count, 2)
    }

    func testToggleArchived_failure_setsMessage_andKeepsState() {
        let repository = CatalogTestRepository(archived: [CatalogTestFixture.fly.id])
        let model = CatalogListViewModel(catalog: repository)
        model.load()
        repository.writeError = CatalogTestError.boom

        model.toggleArchived(CatalogTestFixture.bench)
        XCTAssertEqual(model.errorMessage, "Não foi possível arquivar o exercício.")
        XCTAssertFalse(model.isArchived(CatalogTestFixture.bench))

        model.isPresentingError = false
        model.toggleArchived(CatalogTestFixture.fly)
        XCTAssertEqual(model.errorMessage, "Não foi possível restaurar o exercício.")
        XCTAssertTrue(model.isArchived(CatalogTestFixture.fly))
    }

    // MARK: - CatalogListViewModel · editor e filtros

    func testStartCreating_andStartEditing_openEditor_dismissClearsAndReloads() {
        let repository = CatalogTestRepository()
        let model = CatalogListViewModel(catalog: repository)
        model.load()
        let readsAfterLoad = repository.readCount

        model.startCreating()
        XCTAssertTrue(model.isEditorPresented)
        XCTAssertEqual(model.editor?.mode, .create)

        model.editorDismissed()
        XCTAssertFalse(model.isEditorPresented)
        XCTAssertNil(model.editor)
        XCTAssertGreaterThan(repository.readCount, readsAfterLoad, "Fechar o editor relê o catálogo")

        model.startEditing(CatalogTestFixture.bench)
        XCTAssertTrue(model.isEditorPresented)
        XCTAssertEqual(model.editor?.mode, .edit(CatalogTestFixture.bench.id))
        XCTAssertEqual(model.editor?.draft.name, "Supino reto com barra")
    }

    func testFilterSummary_andClearFilters() {
        let model = CatalogListViewModel(catalog: CatalogTestRepository())
        XCTAssertFalse(model.hasActiveFilter)
        XCTAssertEqual(model.filterSummary, "")

        model.muscleFilter = .chest
        model.showArchived = true
        model.searchText = "supino"
        XCTAssertTrue(model.hasActiveFilter)
        XCTAssertEqual(model.filterSummary, "Peito · com arquivados")

        model.clearFilters()
        XCTAssertFalse(model.hasActiveFilter)
        XCTAssertNil(model.muscleFilter)
        XCTAssertFalse(model.showArchived)
        XCTAssertEqual(model.searchText, "supino", "A busca é da barra de busca, não do filtro")
    }

    // MARK: - ExerciseEditorViewModel · estado inicial

    func testEditor_createMode_startsFromDraftDefaults() {
        let model = ExerciseEditorViewModel(catalog: CatalogTestRepository())

        XCTAssertEqual(model.mode, .create)
        XCTAssertEqual(model.title, "Novo exercício")
        XCTAssertEqual(model.draft, ExerciseDraft())
        XCTAssertEqual(model.incrementChoice, .five, "ExerciseDraft começa em 5 (máquina de placas)")
        XCTAssertFalse(model.isSeedExercise)
        XCTAssertFalse(model.canSave, "Sem nome e sem grupo primário")
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testEditor_editMode_mapsExerciseAndIncrementChoice() {
        let bench = ExerciseEditorViewModel(catalog: CatalogTestRepository(), exercise: CatalogTestFixture.bench)
        XCTAssertEqual(bench.mode, .edit(CatalogTestFixture.bench.id))
        XCTAssertEqual(bench.title, "Editar exercício")
        XCTAssertEqual(bench.draft, ExerciseDraft(from: CatalogTestFixture.bench))
        XCTAssertEqual(bench.incrementChoice, .twoAndHalf)
        XCTAssertEqual(bench.customIncrementText, "")
        XCTAssertTrue(bench.isSeedExercise)
        XCTAssertTrue(bench.canSave)

        let curl = ExerciseEditorViewModel(catalog: CatalogTestRepository(), exercise: CatalogTestFixture.customCurl)
        XCTAssertEqual(curl.incrementChoice, .custom, "1,25 não é opção fixa")
        XCTAssertEqual(curl.customIncrementText, "1,25")
        XCTAssertEqual(curl.draft.loadIncrement, 1.25)
        XCTAssertFalse(curl.isSeedExercise, "Exercício do usuário não recebe o aviso do seed")
    }

    // MARK: - ExerciseEditorViewModel · validação

    func testEditor_canSave_requiresNamePrimaryGroupAndPositiveIncrement() {
        let model = ExerciseEditorViewModel(catalog: CatalogTestRepository())

        model.draft.name = "   "
        model.togglePrimary(.chest)
        XCTAssertFalse(model.canSave, "Nome só com espaços não vale")

        model.draft.name = "Crucifixo com halteres"
        XCTAssertTrue(model.canSave)

        model.togglePrimary(.chest)
        XCTAssertFalse(model.canSave, "Sem grupo primário")

        model.togglePrimary(.chest)
        model.incrementChoice = .custom
        model.customIncrementText = "0"
        XCTAssertFalse(model.canSave, "Incremento zero não vale (P8)")
    }

    func testEditor_increment_fixedChoicesAndCustomText() {
        let model = ExerciseEditorViewModel(catalog: CatalogTestRepository())

        model.incrementChoice = .twoAndHalf
        XCTAssertEqual(model.draft.loadIncrement, 2.5)
        model.incrementChoice = .one
        XCTAssertEqual(model.draft.loadIncrement, 1)

        model.incrementChoice = .custom
        XCTAssertEqual(model.customIncrementText, "1", "O campo abre com o valor atual")
        XCTAssertEqual(model.draft.loadIncrement, 1)

        model.customIncrementText = "1,25"
        XCTAssertEqual(model.draft.loadIncrement, 1.25)
        model.customIncrementText = "0.5"
        XCTAssertEqual(model.draft.loadIncrement, 0.5)
        model.customIncrementText = "abc"
        XCTAssertEqual(model.draft.loadIncrement, 0, "Texto inválido zera e desabilita o Salvar")

        model.incrementChoice = .five
        XCTAssertEqual(model.draft.loadIncrement, 5, "Voltar a uma opção fixa ignora o texto")
    }

    // MARK: - ExerciseEditorViewModel · grupos musculares

    func testEditor_togglePrimary_keepsTapOrder_andPullsFromSecondary() {
        let model = ExerciseEditorViewModel(catalog: CatalogTestRepository())

        model.toggleSecondary(.glutes)
        model.togglePrimary(.quads)
        model.togglePrimary(.glutes)
        XCTAssertEqual(model.draft.primaryMuscles, [.quads, .glutes], "O primeiro marcado define a seção")
        XCTAssertEqual(model.draft.secondaryMuscles, [], "Marcar como primário tira dos secundários")
        XCTAssertTrue(model.mainGroupText.hasPrefix("Principal: Quadríceps."))

        model.togglePrimary(.quads)
        XCTAssertEqual(model.draft.primaryMuscles, [.glutes])
    }

    func testEditor_toggleSecondary_ignoresGroupsAlreadyPrimary() {
        let model = ExerciseEditorViewModel(catalog: CatalogTestRepository())
        model.togglePrimary(.chest)

        model.toggleSecondary(.chest)
        XCTAssertEqual(model.draft.secondaryMuscles, [])

        model.toggleSecondary(.triceps)
        model.toggleSecondary(.shoulders)
        XCTAssertEqual(model.draft.secondaryMuscles, [.triceps, .shoulders])
        model.toggleSecondary(.triceps)
        XCTAssertEqual(model.draft.secondaryMuscles, [.shoulders])
    }

    func testEditor_mainGroupText_withoutPrimary_asksForOne() {
        let model = ExerciseEditorViewModel(catalog: CatalogTestRepository())
        XCTAssertEqual(model.mainGroupText, "Marque ao menos um grupo primário.")
    }

    // MARK: - ExerciseEditorViewModel · salvar

    func testEditor_saveCreate_normalizesDraft_andCallsCreate() {
        let repository = CatalogTestRepository()
        let newID = UUID()
        repository.idToCreate = newID
        let model = ExerciseEditorViewModel(catalog: repository)
        model.draft.name = "  Rosca no banco do prédio  "
        model.togglePrimary(.biceps)
        model.draft.equipment = .dumbbell
        model.draft.movementPattern = .elbowFlexion
        model.machineNotesText = "   "
        XCTAssertTrue(model.hasUnsavedChanges)

        XCTAssertTrue(model.saveExercise())

        XCTAssertEqual(repository.created.count, 1)
        XCTAssertEqual(repository.created.first?.name, "Rosca no banco do prédio")
        XCTAssertNil(repository.created.first?.machineNotes, "Notas só com espaços viram nil")
        XCTAssertEqual(repository.created.first?.primaryMuscles, [.biceps])
        XCTAssertEqual(repository.created.first?.equipment, .dumbbell)
        XCTAssertEqual(repository.created.first?.movementPattern, .elbowFlexion)
        XCTAssertTrue(repository.updated.isEmpty)
        XCTAssertEqual(model.savedExerciseID, newID)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.hasUnsavedChanges, "Depois de gravar não há edição pendente")
    }

    func testEditor_saveCreateTwice_updatesInsteadOfDuplicating() {
        let repository = CatalogTestRepository()
        let newID = UUID()
        repository.idToCreate = newID
        let model = ExerciseEditorViewModel(catalog: repository)
        model.draft.name = "Remada unilateral"
        model.togglePrimary(.back)

        XCTAssertTrue(model.saveExercise())
        XCTAssertTrue(model.saveExercise())

        XCTAssertEqual(repository.created.count, 1)
        XCTAssertEqual(repository.updated.map { $0.id }, [newID])
        XCTAssertEqual(model.savedExerciseID, newID)
    }

    func testEditor_saveEdit_callsUpdateWithSameID() {
        let repository = CatalogTestRepository()
        let model = ExerciseEditorViewModel(catalog: repository, exercise: CatalogTestFixture.bench)
        model.machineNotesText = " Banco no 4, pino no 7 "
        model.incrementChoice = .five

        XCTAssertTrue(model.saveExercise())

        XCTAssertTrue(repository.created.isEmpty)
        XCTAssertEqual(repository.updated.count, 1)
        XCTAssertEqual(repository.updated.first?.id, CatalogTestFixture.bench.id)
        XCTAssertEqual(repository.updated.first?.draft.machineNotes, "Banco no 4, pino no 7")
        XCTAssertEqual(repository.updated.first?.draft.loadIncrement, 5)
        XCTAssertEqual(repository.updated.first?.draft.name, "Supino reto com barra")
        XCTAssertEqual(model.savedExerciseID, CatalogTestFixture.bench.id)
    }

    func testEditor_saveInvalid_doesNotTouchRepository() {
        let repository = CatalogTestRepository()
        let model = ExerciseEditorViewModel(catalog: repository)
        model.draft.name = "Sem grupo"

        XCTAssertFalse(model.saveExercise())

        XCTAssertTrue(repository.created.isEmpty)
        XCTAssertNil(model.savedExerciseID)
        XCTAssertEqual(
            model.errorMessage,
            "Preencha o nome, marque ao menos um grupo primário e informe um incremento maior que zero."
        )
    }

    func testEditor_saveFailure_setsMessage_andKeepsDraft() {
        let repository = CatalogTestRepository()
        repository.writeError = CatalogRepositoryError.exerciseNotFound(CatalogTestFixture.bench.id)
        let model = ExerciseEditorViewModel(catalog: repository, exercise: CatalogTestFixture.bench)
        model.draft.name = "Supino reto"

        XCTAssertFalse(model.saveExercise())

        XCTAssertEqual(model.errorMessage, "Este exercício não foi encontrado no catálogo.")
        XCTAssertEqual(model.draft.name, "Supino reto", "O rascunho fica para o usuário corrigir")
        XCTAssertNil(model.savedExerciseID)
        XCTAssertTrue(model.hasUnsavedChanges)

        repository.writeError = CatalogTestError.boom
        XCTAssertFalse(model.saveExercise())
        XCTAssertEqual(model.errorMessage, "Não foi possível salvar o exercício.")
    }

    func testEditor_machineNotesText_emptyStringBecomesNil() {
        let model = ExerciseEditorViewModel(catalog: CatalogTestRepository(), exercise: CatalogTestFixture.bench)
        model.machineNotesText = "Banco no 3"
        XCTAssertEqual(model.draft.machineNotes, "Banco no 3")
        model.machineNotesText = ""
        XCTAssertNil(model.draft.machineNotes)
        XCTAssertEqual(model.machineNotesText, "")
    }

    // MARK: - Helpers puros

    func testIncrementHelpers_parseFormatAndChoice() {
        XCTAssertEqual(ExerciseEditorViewModel.parseIncrement("1,25"), 1.25)
        XCTAssertEqual(ExerciseEditorViewModel.parseIncrement(" 2.5 "), 2.5)
        XCTAssertNil(ExerciseEditorViewModel.parseIncrement(""))
        XCTAssertNil(ExerciseEditorViewModel.parseIncrement("0"))
        XCTAssertNil(ExerciseEditorViewModel.parseIncrement("-1"))
        XCTAssertNil(ExerciseEditorViewModel.parseIncrement("inf"))
        XCTAssertNil(ExerciseEditorViewModel.parseIncrement("nan"))

        XCTAssertEqual(ExerciseEditorViewModel.incrementText(1.25), "1,25")
        XCTAssertEqual(ExerciseEditorViewModel.incrementText(2), "2")
        XCTAssertEqual(ExerciseEditorViewModel.incrementText(0), "")

        XCTAssertEqual(ExerciseEditorViewModel.choice(for: 2.5), .twoAndHalf)
        XCTAssertEqual(ExerciseEditorViewModel.choice(for: 5), .five)
        XCTAssertEqual(ExerciseEditorViewModel.choice(for: 1), .one)
        XCTAssertEqual(ExerciseEditorViewModel.choice(for: 1.25), .custom)
    }

    func testCatalogExerciseRow_detailText() {
        XCTAssertEqual(CatalogExerciseRow.detailText(for: CatalogTestFixture.bench), "Barra · Empurrar (horizontal)")
        XCTAssertEqual(CatalogExerciseRow.detailText(for: CatalogTestFixture.legPress), "Máquina · Agachar")
        XCTAssertEqual(
            CatalogExerciseRow.detailText(for: CatalogTestFixture.noPattern),
            "Polia · unilateral",
            "Sem padrão de movimento (catálogo v1) mostra só o equipamento"
        )
    }

    func testExerciseListing_sections_putExercisesWithoutPrimaryInOthers() {
        let sections = ExerciseListing.sections([CatalogTestFixture.noPrimary, CatalogTestFixture.bench])
        XCTAssertEqual(sections.map(\.title), ["Peito", "Outros"])
        XCTAssertEqual(sections.map(\.id), ["chest", "other"])
        XCTAssertTrue(ExerciseListing.sections([]).isEmpty)
    }

    func testDisplayNames_areUniquePortuguese_andPickersCoverEveryCase() {
        let muscleNames = MuscleGroup.allCases.map(\.displayName)
        XCTAssertEqual(Set(muscleNames).count, MuscleGroup.allCases.count)
        XCTAssertEqual(MuscleGroup.hamstrings.displayName, "Posteriores")

        // `Equipment` e `LoadUnit` não são CaseIterable: a lista de raw values abaixo é a do domínio.
        let equipmentRaw: Set<String> = [
            "barbell", "dumbbell", "machine", "cable", "bodyweight", "smith", "kettlebell", "household",
        ]
        XCTAssertEqual(Set(Equipment.pickerOrder.map(\.rawValue)), equipmentRaw)
        XCTAssertEqual(Equipment.pickerOrder.count, equipmentRaw.count, "Sem repetição no Picker")
        XCTAssertEqual(Set(Equipment.pickerOrder.map(\.displayName)).count, equipmentRaw.count)

        let unitRaw: Set<String> = ["kilograms", "plates", "level"]
        XCTAssertEqual(Set(LoadUnit.pickerOrder.map(\.rawValue)), unitRaw)
        XCTAssertEqual(LoadUnit.pickerOrder.count, unitRaw.count)
        XCTAssertEqual(Set(LoadUnit.pickerOrder.map(\.displayName)).count, unitRaw.count)
    }
}

// MARK: - Fixtures

private enum CatalogTestFixture {
    static let bench = ExerciseDefinition(
        slug: "supino-reto-barra",
        name: "Supino reto com barra",
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .shoulders],
        equipment: .barbell,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        movementPattern: .horizontalPush
    )
    static let dumbbellBench = ExerciseDefinition(
        slug: "supino-halteres",
        name: "Supino com halteres",
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps],
        equipment: .dumbbell,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        movementPattern: .horizontalPush
    )
    static let fly = ExerciseDefinition(
        slug: "crucifixo-maquina",
        name: "Crucifixo na máquina",
        primaryMuscles: [.chest],
        equipment: .machine,
        loadUnit: .kilograms,
        loadIncrement: 5,
        movementPattern: .chestFly
    )
    static let row = ExerciseDefinition(
        slug: "remada-maquina",
        name: "Remada na máquina",
        primaryMuscles: [.back],
        secondaryMuscles: [.biceps],
        equipment: .machine,
        loadUnit: .level,
        loadIncrement: 1,
        movementPattern: .horizontalPull
    )
    static let squat = ExerciseDefinition(
        slug: "agachamento-livre",
        name: "Agachamento livre",
        primaryMuscles: [.quads],
        secondaryMuscles: [.glutes],
        equipment: .barbell,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        movementPattern: .squat
    )
    static let legPress = ExerciseDefinition(
        slug: "leg-press-45",
        name: "Leg press 45°",
        primaryMuscles: [.quads, .glutes],
        equipment: .machine,
        loadUnit: .kilograms,
        loadIncrement: 5,
        movementPattern: .squat
    )
    static let hipThrust = ExerciseDefinition(
        slug: "elevacao-pelvica",
        name: "Elevação pélvica",
        primaryMuscles: [.glutes],
        equipment: .barbell,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        movementPattern: .hipThrust
    )
    static let customCurl = ExerciseDefinition(
        slug: "rosca-banco-predio",
        name: "Rosca no banco do prédio",
        primaryMuscles: [.biceps],
        equipment: .dumbbell,
        loadUnit: .kilograms,
        loadIncrement: 1.25,
        movementPattern: .elbowFlexion,
        isCustom: true
    )

    /// Catálogo do double (fora de ordem de propósito: a lista ordena).
    static let all: [ExerciseDefinition] = [legPress, bench, row, hipThrust, fly, squat, customCurl, dumbbellBench]

    /// Fora do catálogo do double: casos de borda dos helpers.
    static let noPattern = ExerciseDefinition(
        slug: "cabo-unilateral",
        name: "Cabo unilateral",
        primaryMuscles: [.shoulders],
        equipment: .cable,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        isUnilateral: true
    )
    static let noPrimary = ExerciseDefinition(
        slug: "sem-grupo",
        name: "Sem grupo",
        primaryMuscles: [],
        equipment: .bodyweight,
        loadUnit: .kilograms,
        loadIncrement: 2.5
    )
}

// MARK: - Doubles (privados ao arquivo, prefixo "Catalog" para não colidir com outras features)

private enum CatalogTestError: Error {
    case boom
}

@MainActor
private final class CatalogTestRepository: CatalogRepositoring {
    var exercises: [ExerciseDefinition]
    var archived: Set<UUID>
    var readError: (any Error)?
    var writeError: (any Error)?
    var idToCreate = UUID()
    private(set) var readCount = 0
    private(set) var created: [ExerciseDraft] = []
    private(set) var updated: [(id: UUID, draft: ExerciseDraft)] = []
    private(set) var archiveCalls: [(id: UUID, archived: Bool)] = []

    init(exercises: [ExerciseDefinition] = CatalogTestFixture.all, archived: Set<UUID> = []) {
        self.exercises = exercises
        self.archived = archived
    }

    func allExercises(includeArchived: Bool) throws -> [ExerciseDefinition] {
        readCount += 1
        if let readError {
            throw readError
        }
        return exercises.filter { includeArchived || !archived.contains($0.id) }
    }

    func exercise(id: UUID) throws -> ExerciseDefinition? {
        if let readError {
            throw readError
        }
        return exercises.first { $0.id == id }
    }

    func createExercise(_ draft: ExerciseDraft) throws -> UUID {
        if let writeError {
            throw writeError
        }
        created.append(draft)
        return idToCreate
    }

    func updateExercise(id: UUID, with draft: ExerciseDraft) throws {
        if let writeError {
            throw writeError
        }
        updated.append((id: id, draft: draft))
    }

    func setArchived(id: UUID, _ archived: Bool) throws {
        if let writeError {
            throw writeError
        }
        archiveCalls.append((id: id, archived: archived))
        if archived {
            self.archived.insert(id)
        } else {
            self.archived.remove(id)
        }
    }
}
