import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T2.6, T2.12, T2.20, T2.21: ViewModels da aba Programa e do onboarding sobre doubles em memória
/// de `ProgramRepositoring` e `CatalogRepositoring` (o `ProgramRepository` real é de outra tarefa
/// e tem testes próprios). Nada aqui usa SwiftData. Tudo em `@MainActor` (ARCHITECTURE §10).
@MainActor
final class ProgramViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_758_600_000)

    // MARK: - ProgramListViewModel

    func testList_refresh_keepsRepositoryOrder_activeFirst() {
        let fixture = ProgramTestFixture()
        let model = makeListModel(fixture)

        XCTAssertTrue(model.programs.isEmpty, "Nada é lido no init: a view chama refresh()")
        model.refresh()

        XCTAssertEqual(model.programs.map(\.id), [fixture.fullBody.id, fixture.combat.id, fixture.lowerFocus.id, fixture.upperFocus.id])
        XCTAssertTrue(model.programs.first?.isActive ?? false)
        XCTAssertFalse(model.didFailToLoad)
        XCTAssertNil(model.errorMessage)
    }

    func testList_refreshFailure_setsMessage_andFlagSurvivesClosingAlert() {
        let fixture = ProgramTestFixture()
        fixture.repository.readError = ProgramTestError.boom
        let model = makeListModel(fixture)

        model.refresh()

        XCTAssertTrue(model.didFailToLoad)
        XCTAssertEqual(model.errorMessage, "Não foi possível carregar os programas.")
        model.isPresentingError = false
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.didFailToLoad, "Fechar o alerta não vira \"nenhum programa\"")

        fixture.repository.readError = nil
        model.refresh()
        XCTAssertFalse(model.didFailToLoad)
        XCTAssertEqual(model.programs.count, 4)
    }

    func testList_activate_writesAndRereads() {
        let fixture = ProgramTestFixture()
        let model = makeListModel(fixture)
        model.refresh()

        model.activate(fixture.combat.id)

        XCTAssertEqual(fixture.repository.calls, [.activate(fixture.combat.id)])
        XCTAssertEqual(model.programs.first?.id, fixture.combat.id, "Relido: o novo ativo sobe para o topo")
        XCTAssertEqual(model.programs.filter(\.isActive).count, 1)
    }

    func testList_duplicate_usesCopyName_andInjectedClock() {
        let fixture = ProgramTestFixture()
        let model = makeListModel(fixture)
        model.refresh()

        let copyID = model.duplicate(fixture.fullBody.id)

        XCTAssertEqual(fixture.repository.calls, [.duplicate(fixture.fullBody.id, "Hipertrofia — completo (cópia)", now)])
        XCTAssertNotNil(copyID)
        XCTAssertTrue(model.programs.contains { $0.id == copyID && !$0.isActive }, "A cópia entra inativa")
        XCTAssertNil(model.errorMessage)
    }

    func testList_requestDeletion_ofActive_isRefusedWithoutWrite() {
        let fixture = ProgramTestFixture()
        let model = makeListModel(fixture)
        model.refresh()

        model.requestDeletion(of: fixture.fullBody.id)

        XCTAssertNil(model.pendingDeletion)
        XCTAssertEqual(model.errorMessage, "O programa ativo não pode ser apagado. Ative outro programa antes.")
        XCTAssertTrue(fixture.repository.calls.isEmpty)
    }

    func testList_requestThenConfirmDeletion_deletesInactive() {
        let fixture = ProgramTestFixture()
        let model = makeListModel(fixture)
        model.refresh()

        model.requestDeletion(of: fixture.lowerFocus.id)
        XCTAssertEqual(model.pendingDeletion?.id, fixture.lowerFocus.id)
        XCTAssertTrue(model.isConfirmingDeletion)
        XCTAssertTrue(fixture.repository.calls.isEmpty, "Só apaga depois da confirmação")

        model.confirmDeletion()

        XCTAssertEqual(fixture.repository.calls, [.delete(fixture.lowerFocus.id)])
        XCTAssertNil(model.pendingDeletion)
        XCTAssertFalse(model.programs.contains { $0.id == fixture.lowerFocus.id })
    }

    func testList_cancelDeletion_clearsPending() {
        let fixture = ProgramTestFixture()
        let model = makeListModel(fixture)
        model.refresh()
        model.requestDeletion(of: fixture.lowerFocus.id)

        model.isConfirmingDeletion = false
        model.confirmDeletion()

        XCTAssertNil(model.pendingDeletion)
        XCTAssertTrue(fixture.repository.calls.isEmpty)
    }

    func testList_deleteError_isMappedToPortuguese() {
        let fixture = ProgramTestFixture()
        let model = makeListModel(fixture)
        model.refresh()
        model.requestDeletion(of: fixture.lowerFocus.id)
        fixture.repository.writeError = ProgramRepositoryError.cannotDeleteActive

        model.confirmDeletion()

        XCTAssertEqual(model.errorMessage, "O programa ativo não pode ser apagado. Ative outro programa antes.")
    }

    func testList_unknownError_usesFallback() {
        let fixture = ProgramTestFixture()
        let model = makeListModel(fixture)
        model.refresh()
        fixture.repository.writeError = ProgramTestError.boom

        model.activate(fixture.combat.id)

        XCTAssertEqual(model.errorMessage, "Não foi possível ativar o programa.")
    }

    func testList_texts() {
        XCTAssertEqual(ProgramListViewModel.copyName(for: "ABC"), "ABC (cópia)")
        XCTAssertEqual(ProgramListViewModel.dayCountText(1), "1 dia")
        XCTAssertEqual(ProgramListViewModel.dayCountText(3), "3 dias")
    }

    // MARK: - ProgramDetailViewModel: leitura, nome e objetivo

    func testDetail_refresh_loadsProgramNamesAndAvailableCatalog() {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)

        XCTAssertFalse(model.hasLoaded)
        model.refresh()

        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(model.program?.id, fixture.fullBody.id)
        XCTAssertEqual(model.goal, .hypertrophy, "Sem objetivo (v1) = hipertrofia")
        XCTAssertEqual(model.days.map(\.order), [0, 1], "Dias na ordem de `order` (S1)")
        XCTAssertEqual(model.exerciseName(for: fixture.dayATargets[0]), "Supino reto com barra")
        XCTAssertNotNil(model.exercisesByID[fixture.archivedChest.id], "Arquivados continuam com nome")
        XCTAssertFalse(model.availableExercises.contains { $0.id == fixture.archivedChest.id }, "Seletor sem arquivados")
    }

    func testDetail_missingProgram_isNotFoundWithoutError() {
        let fixture = ProgramTestFixture()
        let model = ProgramDetailViewModel(programID: UUID(), programs: fixture.repository, catalog: fixture.catalog)

        model.refresh()

        XCTAssertTrue(model.hasLoaded)
        XCTAssertNil(model.program)
        XCTAssertFalse(model.didFailToLoad)
        XCTAssertNil(model.errorMessage)
    }

    func testDetail_rename_trimsAndWrites() {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()

        model.rename(to: "  Meu ABC  ")

        XCTAssertEqual(fixture.repository.calls, [.rename(fixture.fullBody.id, "Meu ABC")])
        XCTAssertEqual(model.program?.name, "Meu ABC")
    }

    func testDetail_rename_emptyOrUnchanged_doesNotWrite() {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()

        model.rename(to: "   ")
        XCTAssertEqual(model.errorMessage, "O nome do programa não pode ficar vazio.")

        model.errorMessage = nil
        model.rename(to: fixture.fullBody.name)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(fixture.repository.calls.isEmpty)
    }

    func testDetail_setGoal_forwardsApplyDefaultsChoice() {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()

        model.setGoal(.strength, applyDefaults: true)
        model.setGoal(.endurance, applyDefaults: false)

        XCTAssertEqual(fixture.repository.calls, [
            .setGoal(fixture.fullBody.id, .strength, true),
            .setGoal(fixture.fullBody.id, .endurance, false),
        ])
        XCTAssertEqual(model.goal, .endurance)
    }

    // MARK: - ProgramDetailViewModel: dia (RF-33, RF-34)

    func testDetail_addExercise_appendsToDay() {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()

        model.addExercise(fixture.curl.id, toDay: fixture.dayA.id)

        XCTAssertEqual(fixture.repository.calls, [.add(fixture.curl.id, fixture.dayA.id)])
        XCTAssertEqual(model.targets(inDay: fixture.dayA.id).last?.exerciseID, fixture.curl.id)
        XCTAssertNil(model.dayErrorMessage)
    }

    func testDetail_RF33_addIsBlockedAtMaximum() {
        let fixture = ProgramTestFixture(dayATargetCount: ProgramLimits.maxExercisesPerDay)
        let model = makeDetailModel(fixture)
        model.refresh()

        XCTAssertFalse(model.canAddExercise(toDay: fixture.dayA.id))
        model.addExercise(fixture.curl.id, toDay: fixture.dayA.id)

        XCTAssertTrue(fixture.repository.calls.isEmpty)
        XCTAssertEqual(model.dayErrorMessage, "Cada dia pode ter no máximo 10 exercícios.")
        XCTAssertNil(model.errorMessage, "O aviso é do editor do dia, não da tela do programa")
    }

    func testDetail_RF33_removeKeepsMinimum_withAlert() {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()
        let dayB = fixture.dayB.id
        XCTAssertEqual(model.targets(inDay: dayB).count, 1)

        model.removeTargets(atOffsets: IndexSet(integer: 0), inDay: dayB)

        XCTAssertTrue(fixture.repository.calls.isEmpty)
        XCTAssertEqual(model.dayErrorMessage, "Cada dia precisa de pelo menos 1 exercício.")
        XCTAssertTrue(model.isPresentingDayError)
    }

    func testDetail_removeTargets_removesByOffsetInSortedOrder() {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()
        let second = fixture.dayATargets[1]

        model.removeTargets(atOffsets: IndexSet(integer: 1), inDay: fixture.dayA.id)

        XCTAssertEqual(fixture.repository.calls, [.remove(second.id)])
        XCTAssertFalse(model.targets(inDay: fixture.dayA.id).contains { $0.id == second.id })
        XCTAssertEqual(model.targets(inDay: fixture.dayA.id).map(\.order), [0, 1, 2], "Renumerado pelo repositório")
    }

    func testDetail_moveTargets_singleDrag_isOneWriteWithFinalIndex() {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()
        let ids = fixture.dayATargets.map(\.id)

        // `.onMove`: arrastar o 1º para antes do 4º (destino 3) → posição final 2.
        model.moveTargets(fromOffsets: IndexSet(integer: 0), toOffset: 3, inDay: fixture.dayA.id)

        XCTAssertEqual(fixture.repository.calls, [.move(ids[0], 2)])
        XCTAssertEqual(model.targets(inDay: fixture.dayA.id).map(\.id), [ids[1], ids[2], ids[0], ids[3]])
    }

    func testDetail_moveTargets_toEnd_andToTop() {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()
        let ids = fixture.dayATargets.map(\.id)

        model.moveTargets(fromOffsets: IndexSet(integer: 1), toOffset: 4, inDay: fixture.dayA.id)
        XCTAssertEqual(model.targets(inDay: fixture.dayA.id).map(\.id), [ids[0], ids[2], ids[3], ids[1]])

        model.moveTargets(fromOffsets: IndexSet(integer: 3), toOffset: 0, inDay: fixture.dayA.id)
        XCTAssertEqual(model.targets(inDay: fixture.dayA.id).map(\.id), [ids[1], ids[0], ids[2], ids[3]])
        XCTAssertEqual(fixture.repository.calls, [.move(ids[1], 3), .move(ids[1], 0)])
    }

    func testDetail_moveTargets_noOp_doesNotWrite() {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()

        model.moveTargets(fromOffsets: IndexSet(integer: 2), toOffset: 2, inDay: fixture.dayA.id)
        model.moveTargets(fromOffsets: IndexSet(integer: 2), toOffset: 3, inDay: fixture.dayA.id)

        XCTAssertTrue(fixture.repository.calls.isEmpty)
    }

    func testReordered_matchesOnMoveSemantics() {
        let items = ["a", "b", "c", "d", "e"]
        let cases: [(source: IndexSet, destination: Int, expected: [String])] = [
            (IndexSet(integer: 0), 3, ["b", "c", "a", "d", "e"]),
            (IndexSet(integer: 4), 0, ["e", "a", "b", "c", "d"]),
            (IndexSet(integer: 1), 5, ["a", "c", "d", "e", "b"]),
            (IndexSet(integer: 2), 2, ["a", "b", "c", "d", "e"]),
            (IndexSet([0, 2]), 5, ["b", "d", "e", "a", "c"]),
            (IndexSet([3, 4]), 1, ["a", "d", "e", "b", "c"]),
            (IndexSet(integer: 9), 0, ["a", "b", "c", "d", "e"]),
        ]
        for testCase in cases {
            XCTAssertEqual(
                ProgramDetailViewModel.reordered(items, moving: testCase.source, to: testCase.destination),
                testCase.expected,
                "source \(Array(testCase.source)) → \(testCase.destination)"
            )
        }
    }

    func testMoveSteps_generalCase_reachesDesiredOrder() {
        let ids = (0..<4).map { _ in UUID() }
        let desired = [ids[2], ids[3], ids[0], ids[1]]

        let steps = ProgramDetailViewModel.moveSteps(from: ids, to: desired)

        var simulated = ids
        for step in steps {
            guard let from = simulated.firstIndex(of: step.id) else {
                return XCTFail("Passo com id desconhecido")
            }
            simulated.remove(at: from)
            simulated.insert(step.id, at: step.index)
        }
        XCTAssertEqual(simulated, desired)
        XCTAssertLessThanOrEqual(steps.count, ids.count - 1)
        XCTAssertTrue(ProgramDetailViewModel.moveSteps(from: ids, to: [ids[0]]).isEmpty, "Conjuntos diferentes: nada a fazer")
    }

    func testDetail_RF34_replaceExercise_forwards() {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()
        let benchTarget = fixture.dayATargets[0]

        model.replaceExercise(targetID: benchTarget.id, with: fixture.dumbbellBench.id)

        XCTAssertEqual(fixture.repository.calls, [.replace(benchTarget.id, fixture.dumbbellBench.id)])
        XCTAssertEqual(model.targets(inDay: fixture.dayA.id).first?.exerciseID, fixture.dumbbellBench.id)
    }

    func testDetail_RF34_substitutes_skipArchivedAndExercisesAlreadyInDay() {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()
        let benchTarget = fixture.dayATargets[0]
        let dayExerciseIDs = Set(fixture.dayATargets.map(\.exerciseID))

        let substitutes = model.substitutes(forTargetID: benchTarget.id, inDay: fixture.dayA.id)

        XCTAssertLessThanOrEqual(substitutes.count, 20)
        XCTAssertFalse(substitutes.contains { dayExerciseIDs.contains($0.id) })
        XCTAssertFalse(substitutes.contains { $0.id == fixture.archivedChest.id })
        XCTAssertTrue(substitutes.contains { $0.id == fixture.dumbbellBench.id }, "Mesmo padrão e mesmo grupo primário")
        XCTAssertTrue(model.substitutes(forTargetID: UUID(), inDay: fixture.dayA.id).isEmpty)
    }

    func testDetail_makeDraft_thenUpdateTarget_forwardsValues() throws {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()
        let benchTarget = fixture.dayATargets[0]

        var draft = try XCTUnwrap(model.makeDraft(forTargetID: benchTarget.id, inDay: fixture.dayA.id))
        XCTAssertEqual(draft.loadIncrement, 2.5)
        XCTAssertEqual(draft.loadUnit, .kilograms)
        XCTAssertFalse(draft.isBodyweight)
        draft.sets = 4
        draft.repMax = 15
        draft.restSeconds = 135
        draft.startingLoad = 42.5

        model.updateTarget(id: benchTarget.id, with: draft)

        XCTAssertEqual(fixture.repository.calls, [.update(benchTarget.id, 4, 8, 15, 2, 135, 42.5)])
        XCTAssertEqual(model.targets(inDay: fixture.dayA.id).first?.startingLoad, 42.5)
        XCTAssertNil(model.dayErrorMessage)
    }

    func testDetail_updateTarget_invalidDraft_isRejectedWithoutWrite() throws {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()
        let benchTarget = fixture.dayATargets[0]
        var draft = try XCTUnwrap(model.makeDraft(forTargetID: benchTarget.id, inDay: fixture.dayA.id))
        draft.startingLoad = 41

        model.updateTarget(id: benchTarget.id, with: draft)

        XCTAssertTrue(fixture.repository.calls.isEmpty)
        XCTAssertEqual(model.dayErrorMessage, "A carga inicial deve ser múltipla do incremento do exercício.")
    }

    func testDetail_errorsGoToTheScreenThatCausedThem() {
        let fixture = ProgramTestFixture()
        let model = makeDetailModel(fixture)
        model.refresh()
        fixture.repository.writeError = ProgramRepositoryError.invalidParameters("repMax")

        model.rename(to: "Outro nome")
        XCTAssertEqual(model.errorMessage, "Valores inválidos: repMax")
        XCTAssertNil(model.dayErrorMessage)

        model.errorMessage = nil
        model.replaceExercise(targetID: fixture.dayATargets[0].id, with: fixture.dumbbellBench.id)
        XCTAssertEqual(model.dayErrorMessage, "Valores inválidos: repMax")
        XCTAssertNil(model.errorMessage)
    }

    func testDetail_repositoryErrorMessages_arePortuguese() {
        let fallback = "fallback"
        XCTAssertEqual(ProgramDetailViewModel.message(for: ProgramRepositoryError.tooManyExercises, fallback: fallback), "Cada dia pode ter no máximo 10 exercícios.")
        XCTAssertEqual(ProgramDetailViewModel.message(for: ProgramRepositoryError.tooFewExercises, fallback: fallback), "Cada dia precisa de pelo menos 1 exercício.")
        XCTAssertEqual(ProgramDetailViewModel.message(for: ProgramRepositoryError.exerciseNotFound(UUID()), fallback: fallback), "Exercício não encontrado no catálogo.")
        XCTAssertEqual(ProgramDetailViewModel.message(for: ProgramRepositoryError.invalidParameters(""), fallback: fallback), "Valores inválidos.")
        XCTAssertEqual(ProgramDetailViewModel.message(for: ProgramTestError.boom, fallback: fallback), fallback)
    }

    // MARK: - Formatação e rascunho

    func testTargetSummary_format() {
        let exerciseID = UUID()
        let plain = ExerciseTarget(exerciseID: exerciseID, order: 0, sets: 3, repMin: 8, repMax: 12, targetRIR: 2, restSeconds: 120)
        let withLoad = ExerciseTarget(exerciseID: exerciseID, order: 0, sets: 4, repMin: 6, repMax: 10, targetRIR: 1, restSeconds: 90, startingLoad: 62.5)
        let plates = ExerciseTarget(exerciseID: exerciseID, order: 0, sets: 3, repMin: 10, repMax: 15, targetRIR: 2, restSeconds: 45, startingLoad: 1)
        let level = ExerciseTarget(exerciseID: exerciseID, order: 0, sets: 2, repMin: 12, repMax: 20, targetRIR: 3, restSeconds: 60, startingLoad: 7)

        XCTAssertEqual(ProgramDetailViewModel.targetSummary(plain, unit: .kilograms), "3 × 8–12 · RIR 2 · 2 min")
        XCTAssertEqual(ProgramDetailViewModel.targetSummary(withLoad, unit: .kilograms), "4 × 6–10 · RIR 1 · 1 min 30 s · inicial 62,5 kg")
        XCTAssertEqual(ProgramDetailViewModel.targetSummary(plates, unit: .plates), "3 × 10–15 · RIR 2 · 45 s · inicial 1 placa")
        XCTAssertEqual(ProgramDetailViewModel.targetSummary(level, unit: .level), "2 × 12–20 · RIR 3 · 1 min · inicial nível 7")
        XCTAssertEqual(ProgramDetailViewModel.exerciseCountText(1), "1 exercício")
        XCTAssertEqual(ProgramDetailViewModel.exerciseCountText(5), "5 exercícios")
    }

    func testTargetDraft_normalizesOutOfRangeValues() {
        let exerciseID = UUID()
        let wild = ExerciseTarget(exerciseID: exerciseID, order: 0, sets: 12, repMin: 15, repMax: 60, targetRIR: 7, restSeconds: 100)
        let draft = ProgramDetailViewModel.TargetDraft(target: wild, loadUnit: .kilograms, loadIncrement: 2.5, isBodyweight: false)
        XCTAssertEqual(draft.sets, 10)
        XCTAssertEqual(draft.repMin, 15)
        XCTAssertEqual(draft.repMax, 50)
        XCTAssertEqual(draft.targetRIR, 5)
        XCTAssertEqual(draft.restSeconds, 105, "Arredondado ao passo de 15 s")
        XCTAssertNil(draft.validationMessage)

        let collapsed = ExerciseTarget(exerciseID: exerciseID, order: 0, sets: 0, repMin: 10, repMax: 10, targetRIR: -1, restSeconds: 5)
        let fixed = ProgramDetailViewModel.TargetDraft(target: collapsed, loadUnit: .kilograms, loadIncrement: 2.5, isBodyweight: false)
        XCTAssertEqual(fixed.sets, 1)
        XCTAssertEqual(fixed.repMin, 9, "repMin < repMax sempre")
        XCTAssertEqual(fixed.repMax, 10)
        XCTAssertEqual(fixed.targetRIR, 0)
        XCTAssertEqual(fixed.restSeconds, 15)
        XCTAssertEqual(fixed.repMinRange, 1...9)
        XCTAssertEqual(fixed.repMaxRange, 10...50)

        let tiny = ExerciseTarget(exerciseID: exerciseID, order: 0, repMin: 1, repMax: 1, restSeconds: 700)
        let tinyDraft = ProgramDetailViewModel.TargetDraft(target: tiny, loadUnit: .kilograms, loadIncrement: 2.5, isBodyweight: false)
        XCTAssertEqual(tinyDraft.repMin, 1)
        XCTAssertEqual(tinyDraft.repMax, 2)
        XCTAssertEqual(tinyDraft.restSeconds, 600)
    }

    func testTargetDraft_P8_startingLoadRules() {
        let target = ExerciseTarget(exerciseID: UUID(), order: 0)
        var draft = ProgramDetailViewModel.TargetDraft(target: target, loadUnit: .kilograms, loadIncrement: 2.5, isBodyweight: false)
        XCTAssertEqual(draft.minimumLoad, 2.5)
        XCTAssertEqual(draft.maximumLoad, 1000)
        XCTAssertEqual(draft.defaultStartingLoad, 2.5)

        draft.startingLoad = 62.5
        XCTAssertNil(draft.validationMessage)
        draft.startingLoad = 61
        XCTAssertEqual(draft.validationMessage, "A carga inicial deve ser múltipla do incremento do exercício.")
        draft.startingLoad = -2.5
        XCTAssertEqual(draft.validationMessage, "A carga inicial não pode ser negativa.")
        draft.startingLoad = nil
        XCTAssertNil(draft.validationMessage)

        var bodyweight = ProgramDetailViewModel.TargetDraft(target: target, loadUnit: .kilograms, loadIncrement: 2.5, isBodyweight: true)
        XCTAssertEqual(bodyweight.minimumLoad, 0, "SPEC P8: peso corporal puro aceita 0")
        bodyweight.startingLoad = 0
        XCTAssertNil(bodyweight.validationMessage)

        let odd = ProgramDetailViewModel.TargetDraft(target: target, loadUnit: .kilograms, loadIncrement: 3, isBodyweight: false)
        XCTAssertEqual(odd.maximumLoad, 999, "Teto é múltiplo do incremento")
    }

    func testTargetDraft_P8_legacyStartingLoad_snapsDownToIncrement() {
        let offGrid = ExerciseTarget(exerciseID: UUID(), order: 0, startingLoad: 41)
        let draft = ProgramDetailViewModel.TargetDraft(target: offGrid, loadUnit: .kilograms, loadIncrement: 2.5, isBodyweight: false)
        XCTAssertEqual(draft.startingLoad, 40)
        XCTAssertNil(draft.validationMessage)

        let onGrid = ExerciseTarget(exerciseID: UUID(), order: 0, startingLoad: 62.5)
        XCTAssertEqual(ProgramDetailViewModel.TargetDraft(target: onGrid, loadUnit: .kilograms, loadIncrement: 2.5, isBodyweight: false).startingLoad, 62.5)
        XCTAssertEqual(ProgramDetailViewModel.TargetDraft.snappedLoad(0.3, increment: 0.1) ?? -1, 0.3, accuracy: 1e-9, "Erro de ponto flutuante não derruba um passo")
        XCTAssertEqual(ProgramDetailViewModel.TargetDraft.snappedLoad(-5, increment: 2.5), 0)
        XCTAssertNil(ProgramDetailViewModel.TargetDraft.snappedLoad(nil, increment: 2.5))
    }

    func testRestText() {
        XCTAssertEqual(ProgramDetailViewModel.restText(seconds: 120), "2 min")
        XCTAssertEqual(ProgramDetailViewModel.restText(seconds: 90), "1 min 30 s")
        XCTAssertEqual(ProgramDetailViewModel.restText(seconds: 45), "45 s")
        XCTAssertEqual(ProgramDetailViewModel.restText(seconds: 0), "sem descanso")
    }

    func testGoalSummaries_existForEveryGoal() {
        for goal in ProgramGoal.allCases {
            XCTAssertFalse(GoalPickerView.summary(for: goal).isEmpty, "\(goal)")
        }
    }

    // MARK: - OnboardingViewModel (T2.21, RF-35)

    func testOnboarding_chooseGoal_filtersByEffectiveGoal_andPreselectsActive() {
        let fixture = ProgramTestFixture()
        let model = OnboardingViewModel(programs: fixture.repository)
        model.load()
        XCTAssertEqual(model.step, .goal)
        XCTAssertFalse(model.canStart)

        model.chooseGoal(.hypertrophy)

        XCTAssertEqual(model.step, .program)
        XCTAssertEqual(
            Set(model.candidates.map(\.id)),
            [fixture.fullBody.id, fixture.lowerFocus.id, fixture.upperFocus.id],
            "Programa sem objetivo conta como hipertrofia (effectiveGoal)"
        )
        XCTAssertEqual(model.selectedProgramID, fixture.fullBody.id, "O ativo vem pré-selecionado")
        XCTAssertTrue(model.canStart)
        XCTAssertFalse(model.showsCombatNotice)
    }

    func testOnboarding_goalWithoutActive_preselectsFirst_andShowsCombatNotice() {
        let fixture = ProgramTestFixture()
        let model = OnboardingViewModel(programs: fixture.repository)
        model.load()

        model.chooseGoal(.combat)

        XCTAssertEqual(model.candidates.map(\.id), [fixture.combat.id])
        XCTAssertEqual(model.selectedProgramID, fixture.combat.id)
        XCTAssertTrue(model.showsCombatNotice)
    }

    func testOnboarding_start_activatesChosenFormat() {
        let fixture = ProgramTestFixture()
        let model = OnboardingViewModel(programs: fixture.repository)
        model.load()
        model.chooseGoal(.hypertrophy)
        model.selectProgram(fixture.lowerFocus.id)

        XCTAssertTrue(model.start())

        XCTAssertEqual(fixture.repository.calls, [.activate(fixture.lowerFocus.id)])
        XCTAssertNil(model.errorMessage)
    }

    func testOnboarding_selectProgram_ignoresOtherGoals() {
        let fixture = ProgramTestFixture()
        let model = OnboardingViewModel(programs: fixture.repository)
        model.load()
        model.chooseGoal(.hypertrophy)

        model.selectProgram(fixture.combat.id)

        XCTAssertEqual(model.selectedProgramID, fixture.fullBody.id)
    }

    func testOnboarding_start_alreadyActive_doesNotWrite() {
        let fixture = ProgramTestFixture()
        let model = OnboardingViewModel(programs: fixture.repository)
        model.load()
        model.chooseGoal(.hypertrophy)

        XCTAssertTrue(model.start())

        XCTAssertTrue(fixture.repository.calls.isEmpty)
    }

    func testOnboarding_goalWithoutProgram_adaptsActiveProgram() {
        let fixture = ProgramTestFixture()
        let model = OnboardingViewModel(programs: fixture.repository)
        model.load()

        model.chooseGoal(.strength)

        XCTAssertTrue(model.candidates.isEmpty)
        XCTAssertEqual(model.adaptationBase?.id, fixture.fullBody.id)
        XCTAssertTrue(model.canStart)
        XCTAssertTrue(model.start())
        XCTAssertEqual(fixture.repository.calls, [.setGoal(fixture.fullBody.id, .strength, true)], "Já ativo: só troca o objetivo com os padrões")
    }

    func testOnboarding_goBack_returnsToGoalStep() {
        let fixture = ProgramTestFixture()
        let model = OnboardingViewModel(programs: fixture.repository)
        model.load()
        model.chooseGoal(.combat)

        model.goBack()

        XCTAssertEqual(model.step, .goal)
    }

    func testOnboarding_startFailure_keepsOnboardingOpen() {
        let fixture = ProgramTestFixture()
        let model = OnboardingViewModel(programs: fixture.repository)
        model.load()
        model.chooseGoal(.combat)
        fixture.repository.writeError = ProgramTestError.boom

        XCTAssertFalse(model.start())

        XCTAssertEqual(model.errorMessage, "Não foi possível ativar o programa. Tente de novo.")
        model.isPresentingError = false
        XCTAssertNil(model.errorMessage)
    }

    func testOnboarding_startWithoutGoal_isRefused() {
        let fixture = ProgramTestFixture()
        let model = OnboardingViewModel(programs: fixture.repository)
        model.load()

        XCTAssertFalse(model.start())
        XCTAssertEqual(model.errorMessage, "Escolha um objetivo.")
        XCTAssertTrue(fixture.repository.calls.isEmpty)
    }

    func testOnboarding_loadFailure_setsMessage() {
        let fixture = ProgramTestFixture()
        fixture.repository.readError = ProgramTestError.boom
        let model = OnboardingViewModel(programs: fixture.repository)

        model.load()

        XCTAssertTrue(model.didFailToLoad)
        XCTAssertEqual(model.errorMessage, "Não foi possível carregar os programas.")
    }

    // MARK: - Fábricas

    private func makeListModel(_ fixture: ProgramTestFixture) -> ProgramListViewModel {
        let fixedNow = now
        return ProgramListViewModel(programs: fixture.repository, now: { fixedNow })
    }

    private func makeDetailModel(_ fixture: ProgramTestFixture) -> ProgramDetailViewModel {
        ProgramDetailViewModel(programID: fixture.fullBody.id, programs: fixture.repository, catalog: fixture.catalog)
    }
}

// MARK: - Fixture

/// Catálogo com substitutos de supino (mesmo padrão e grupo), um arquivado, e quatro programas:
/// "completo" ativo e sem objetivo (v1 = hipertrofia), dois formatos de hipertrofia e combate.
@MainActor
private final class ProgramTestFixture {
    let bench: ExerciseDefinition
    let dumbbellBench: ExerciseDefinition
    let archivedChest: ExerciseDefinition
    let row: ExerciseDefinition
    let squat: ExerciseDefinition
    let lateral: ExerciseDefinition
    let curl: ExerciseDefinition
    let triceps: ExerciseDefinition

    let dayA: ProgramDayTemplate
    let dayB: ProgramDayTemplate
    let fullBody: ProgramTemplate
    let lowerFocus: ProgramTemplate
    let upperFocus: ProgramTemplate
    let combat: ProgramTemplate
    let repository: ProgramTestRepository
    let catalog: ProgramTestCatalog

    /// Alvos do dia A na ordem de `order`.
    var dayATargets: [ExerciseTarget] {
        dayA.exercises.sorted { $0.order < $1.order }
    }

    /// `dayATargetCount` ≥ 4: os quatro primeiros são supino, remada, elevação lateral e tríceps;
    /// o resto repete a rosca para chegar ao limite de RF-33.
    init(dayATargetCount: Int = 4) {
        // Locais primeiro: numa classe, `self` só pode ser lido depois de todas as propriedades
        // armazenadas terem valor.
        let bench = ExerciseDefinition(slug: "supino-reto-barra", name: "Supino reto com barra", primaryMuscles: [.chest], equipment: .barbell, loadUnit: .kilograms, loadIncrement: 2.5, movementPattern: .horizontalPush)
        let dumbbellBench = ExerciseDefinition(slug: "supino-halteres", name: "Supino com halteres", primaryMuscles: [.chest], equipment: .dumbbell, loadUnit: .kilograms, loadIncrement: 2, movementPattern: .horizontalPush)
        let archivedChest = ExerciseDefinition(slug: "supino-maquina-antiga", name: "Supino máquina antiga", primaryMuscles: [.chest], equipment: .machine, loadUnit: .kilograms, loadIncrement: 5, movementPattern: .horizontalPush)
        let row = ExerciseDefinition(slug: "remada-baixa", name: "Remada baixa", primaryMuscles: [.back], equipment: .cable, loadUnit: .kilograms, loadIncrement: 5, movementPattern: .horizontalPull)
        let squat = ExerciseDefinition(slug: "agachamento-livre", name: "Agachamento livre", primaryMuscles: [.quads], equipment: .barbell, loadUnit: .kilograms, loadIncrement: 2.5, movementPattern: .squat)
        let lateral = ExerciseDefinition(slug: "elevacao-lateral", name: "Elevação lateral", primaryMuscles: [.shoulders], equipment: .dumbbell, loadUnit: .kilograms, loadIncrement: 1, movementPattern: .shoulderIsolation)
        let curl = ExerciseDefinition(slug: "rosca-direta", name: "Rosca direta", primaryMuscles: [.biceps], equipment: .barbell, loadUnit: .kilograms, loadIncrement: 2, movementPattern: .elbowFlexion)
        let triceps = ExerciseDefinition(slug: "triceps-corda", name: "Tríceps na corda", primaryMuscles: [.triceps], equipment: .cable, loadUnit: .level, loadIncrement: 1, movementPattern: .elbowExtension)

        var dayAExercises = [bench.id, row.id, lateral.id, triceps.id]
        while dayAExercises.count < dayATargetCount {
            dayAExercises.append(curl.id)
        }
        let targets = dayAExercises.enumerated().map { index, exerciseID in
            ExerciseTarget(exerciseID: exerciseID, order: index, sets: 3, repMin: 8, repMax: 12, targetRIR: 2, restSeconds: 120)
        }
        // Gravados fora de ordem de propósito: o ViewModel ordena por `order`.
        let dayA = ProgramDayTemplate(name: "Dia A — Superior", order: 0, exercises: Array(targets.reversed()))
        let dayB = ProgramDayTemplate(
            name: "Dia B — Inferior",
            order: 1,
            exercises: [ExerciseTarget(exerciseID: squat.id, order: 0)]
        )
        let fullBody = ProgramTemplate(name: "Hipertrofia — completo", days: [dayB, dayA], isActive: true, goal: nil, summary: "Corpo inteiro")
        let lowerFocus = ProgramTemplate(
            name: "Hipertrofia — foco inferior",
            days: [ProgramDayTemplate(name: "Dia A", order: 0, exercises: [ExerciseTarget(exerciseID: squat.id, order: 0)])],
            goal: .hypertrophy,
            summary: "Pernas e glúteos com mais volume"
        )
        let upperFocus = ProgramTemplate(
            name: "Hipertrofia — foco superior",
            days: [ProgramDayTemplate(name: "Dia A", order: 0, exercises: [ExerciseTarget(exerciseID: bench.id, order: 0)])],
            goal: .hypertrophy,
            summary: "Superior com mais volume"
        )
        let combat = ProgramTemplate(
            name: "Combate",
            days: [ProgramDayTemplate(name: "Dia A", order: 0, exercises: [ExerciseTarget(exerciseID: squat.id, order: 0)])],
            goal: .combat
        )

        self.bench = bench
        self.dumbbellBench = dumbbellBench
        self.archivedChest = archivedChest
        self.row = row
        self.squat = squat
        self.lateral = lateral
        self.curl = curl
        self.triceps = triceps
        self.dayA = dayA
        self.dayB = dayB
        self.fullBody = fullBody
        self.lowerFocus = lowerFocus
        self.upperFocus = upperFocus
        self.combat = combat
        self.repository = ProgramTestRepository(programs: [upperFocus, combat, fullBody, lowerFocus])
        self.catalog = ProgramTestCatalog(
            exercises: [bench, dumbbellBench, archivedChest, row, squat, lateral, curl, triceps],
            archivedIDs: [archivedChest.id]
        )
    }
}

// MARK: - Doubles (privados ao arquivo, prefixo "Program" para não colidir com outras features)

private enum ProgramTestError: Error {
    case boom
}

/// Chamadas de escrita recebidas pelo repositório falso, na ordem.
private enum ProgramTestCall: Equatable {
    case activate(UUID)
    case rename(UUID, String)
    case setGoal(UUID, ProgramGoal, Bool)
    case duplicate(UUID, String, Date)
    case delete(UUID)
    case add(UUID, UUID)
    case remove(UUID)
    case move(UUID, Int)
    case replace(UUID, UUID)
    case update(UUID, Int, Int, Int, Int, Int, Double?)
}

/// Repositório em memória com o comportamento do contrato (ativo primeiro, renumeração de
/// `order`, limites de RF-33, recusa de apagar o ativo) e registro das escritas.
@MainActor
private final class ProgramTestRepository: ProgramRepositoring {
    private var programs: [ProgramTemplate]
    private(set) var calls: [ProgramTestCall] = []
    /// Lançado por `allPrograms()` e `program(id:)`.
    var readError: (any Error)?
    /// Lançado por qualquer escrita, depois de registrar a chamada.
    var writeError: (any Error)?

    init(programs: [ProgramTemplate]) {
        self.programs = programs
    }

    func allPrograms() throws -> [ProgramTemplate] {
        if let readError { throw readError }
        return programs.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func program(id: UUID) throws -> ProgramTemplate? {
        if let readError { throw readError }
        return programs.first { $0.id == id }
    }

    func activate(programID: UUID) throws {
        try record(.activate(programID))
        guard programs.contains(where: { $0.id == programID }) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        programs = programs.map { Self.rebuild($0, isActive: $0.id == programID) }
    }

    func rename(programID: UUID, to name: String) throws {
        try record(.rename(programID, name))
        try updateProgram(programID) { Self.rebuild($0, name: name) }
    }

    func setGoal(programID: UUID, goal: ProgramGoal, applyDefaults: Bool) throws {
        try record(.setGoal(programID, goal, applyDefaults))
        try updateProgram(programID) { Self.rebuild($0, goal: goal) }
    }

    func duplicate(programID: UUID, name: String, now: Date) throws -> UUID {
        try record(.duplicate(programID, name, now))
        guard let original = programs.first(where: { $0.id == programID }) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        let copy = ProgramTemplate(
            id: UUID(),
            name: name,
            days: original.days.map { day in
                ProgramDayTemplate(id: UUID(), name: day.name, order: day.order, exercises: day.exercises.map { Self.rebuild($0, id: UUID()) })
            },
            isActive: false,
            goal: original.goal,
            summary: original.summary
        )
        programs.append(copy)
        return copy.id
    }

    func delete(programID: UUID) throws {
        try record(.delete(programID))
        guard let program = programs.first(where: { $0.id == programID }) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        guard !program.isActive else {
            throw ProgramRepositoryError.cannotDeleteActive
        }
        programs.removeAll { $0.id == programID }
    }

    func addExercise(exerciseID: UUID, toDay dayID: UUID) throws -> UUID {
        try record(.add(exerciseID, dayID))
        let newID = UUID()
        try updateDay(dayID) { targets in
            guard targets.count < ProgramLimits.maxExercisesPerDay else {
                throw ProgramRepositoryError.tooManyExercises
            }
            return targets + [ExerciseTarget(id: newID, exerciseID: exerciseID, order: targets.count)]
        }
        return newID
    }

    func removeTarget(id: UUID) throws {
        try record(.remove(id))
        try updateDay(containingTarget: id) { targets in
            guard targets.count > ProgramLimits.minExercisesPerDay else {
                throw ProgramRepositoryError.tooFewExercises
            }
            return targets.filter { $0.id != id }
        }
    }

    func moveTarget(id: UUID, toIndex newIndex: Int) throws {
        try record(.move(id, newIndex))
        try updateDay(containingTarget: id) { targets in
            guard let from = targets.firstIndex(where: { $0.id == id }) else { return targets }
            var reordered = targets
            let moved = reordered.remove(at: from)
            reordered.insert(moved, at: min(max(newIndex, 0), reordered.count))
            return reordered
        }
    }

    func replaceExercise(targetID: UUID, with exerciseID: UUID) throws {
        try record(.replace(targetID, exerciseID))
        try updateDay(containingTarget: targetID) { targets in
            targets.map { $0.id == targetID ? Self.rebuild($0, exerciseID: exerciseID) : $0 }
        }
    }

    func updateTarget(id: UUID, sets: Int, repMin: Int, repMax: Int, targetRIR: Int, restSeconds: Int, startingLoad: Double?) throws {
        try record(.update(id, sets, repMin, repMax, targetRIR, restSeconds, startingLoad))
        try updateDay(containingTarget: id) { targets in
            targets.map { target in
                guard target.id == id else { return target }
                return ExerciseTarget(
                    id: target.id,
                    exerciseID: target.exerciseID,
                    order: target.order,
                    sets: sets,
                    repMin: repMin,
                    repMax: repMax,
                    targetRIR: targetRIR,
                    restSeconds: restSeconds,
                    startingLoad: startingLoad
                )
            }
        }
    }

    // MARK: - Apoio

    private func record(_ call: ProgramTestCall) throws {
        calls.append(call)
        if let writeError { throw writeError }
    }

    private func updateProgram(_ id: UUID, _ transform: (ProgramTemplate) -> ProgramTemplate) throws {
        guard let index = programs.firstIndex(where: { $0.id == id }) else {
            throw ProgramRepositoryError.programNotFound(id)
        }
        programs[index] = transform(programs[index])
    }

    private func updateDay(_ dayID: UUID, _ transform: ([ExerciseTarget]) throws -> [ExerciseTarget]) throws {
        for (programIndex, program) in programs.enumerated() {
            guard let dayIndex = program.days.firstIndex(where: { $0.id == dayID }) else { continue }
            try apply(transform, programIndex: programIndex, dayIndex: dayIndex)
            return
        }
        throw ProgramRepositoryError.dayNotFound(dayID)
    }

    private func updateDay(containingTarget targetID: UUID, _ transform: ([ExerciseTarget]) throws -> [ExerciseTarget]) throws {
        for (programIndex, program) in programs.enumerated() {
            for (dayIndex, day) in program.days.enumerated() where day.exercises.contains(where: { $0.id == targetID }) {
                try apply(transform, programIndex: programIndex, dayIndex: dayIndex)
                return
            }
        }
        throw ProgramRepositoryError.targetNotFound(targetID)
    }

    /// Aplica a transformação aos alvos ordenados e renumera `order` de 0 a n-1.
    private func apply(
        _ transform: ([ExerciseTarget]) throws -> [ExerciseTarget],
        programIndex: Int,
        dayIndex: Int
    ) throws {
        let program = programs[programIndex]
        let day = program.days[dayIndex]
        let sorted = day.exercises.sorted { $0.order < $1.order }
        let renumbered = try transform(sorted).enumerated().map { index, target in
            Self.rebuild(target, order: index)
        }
        var days = program.days
        days[dayIndex] = ProgramDayTemplate(id: day.id, name: day.name, order: day.order, exercises: renumbered)
        programs[programIndex] = Self.rebuild(program, days: days)
    }

    private static func rebuild(
        _ program: ProgramTemplate,
        name: String? = nil,
        days: [ProgramDayTemplate]? = nil,
        isActive: Bool? = nil,
        goal: ProgramGoal? = nil
    ) -> ProgramTemplate {
        ProgramTemplate(
            id: program.id,
            name: name ?? program.name,
            days: days ?? program.days,
            isActive: isActive ?? program.isActive,
            goal: goal ?? program.goal,
            summary: program.summary
        )
    }

    private static func rebuild(
        _ target: ExerciseTarget,
        id: UUID? = nil,
        exerciseID: UUID? = nil,
        order: Int? = nil
    ) -> ExerciseTarget {
        ExerciseTarget(
            id: id ?? target.id,
            exerciseID: exerciseID ?? target.exerciseID,
            order: order ?? target.order,
            sets: target.sets,
            repMin: target.repMin,
            repMax: target.repMax,
            targetRIR: target.targetRIR,
            restSeconds: target.restSeconds,
            startingLoad: target.startingLoad
        )
    }
}

@MainActor
private final class ProgramTestCatalog: CatalogRepositoring {
    private let exercises: [ExerciseDefinition]
    private var archivedIDs: Set<UUID>

    init(exercises: [ExerciseDefinition], archivedIDs: Set<UUID>) {
        self.exercises = exercises
        self.archivedIDs = archivedIDs
    }

    func allExercises(includeArchived: Bool) throws -> [ExerciseDefinition] {
        exercises
            .filter { includeArchived || !archivedIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func exercise(id: UUID) throws -> ExerciseDefinition? {
        exercises.first { $0.id == id }
    }

    func createExercise(_ draft: ExerciseDraft) throws -> UUID {
        UUID()
    }

    func updateExercise(id: UUID, with draft: ExerciseDraft) throws {}

    func setArchived(id: UUID, _ archived: Bool) throws {
        if archived {
            archivedIDs.insert(id)
        } else {
            archivedIDs.remove(id)
        }
    }
}
