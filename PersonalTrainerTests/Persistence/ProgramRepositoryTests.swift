import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T2.6, T2.20, T2.12: `ProgramRepository` é o único caminho de escrita de programa (AGENTS R4).
/// Cobre cada operação de `ProgramRepositoring`, cada erro de `ProgramRepositoryError`, os limites
/// de RF-33 e os padrões por objetivo de SPEC §7.9. Tudo em `@MainActor` com container in-memory
/// (ARCHITECTURE §10). Expectativas de padrão vêm de `ProgramGoal.defaults`, não de números
/// copiados, para o teste acompanhar a tabela da SPEC.
@MainActor
final class ProgramRepositoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Leitura

    func testAllPrograms_activeFirstThenByNamePtBR() throws {
        let fixture = try makeFixture()
        insertProgram(name: "alfa", isActive: false, exercise: fixture.squat, into: fixture.context)
        insertProgram(name: "Ábaco", isActive: false, exercise: fixture.squat, into: fixture.context)
        try fixture.context.save()

        let names = try fixture.repository.allPrograms().map { $0.name }

        // Ativo primeiro; depois pt-BR sem diferenciar maiúsculas, com "Á" entre os "a".
        XCTAssertEqual(names, ["ABC", "Ábaco", "alfa", "Força"])
    }

    func testProgram_mapsDaysTargetsGoalAndSummary() throws {
        let fixture = try makeFixture()
        fixture.program.goalRaw = ProgramGoal.strength.rawValue
        fixture.program.summary = "Três dias, corpo inteiro."
        try fixture.context.save()

        let template = try XCTUnwrap(fixture.repository.program(id: fixture.program.uuid))

        XCTAssertEqual(template.id, fixture.program.uuid)
        XCTAssertEqual(template.name, "ABC")
        XCTAssertTrue(template.isActive)
        XCTAssertEqual(template.goal, .strength)
        XCTAssertEqual(template.summary, "Três dias, corpo inteiro.")
        XCTAssertEqual(template.days.map { $0.id }, [fixture.dayA.uuid, fixture.dayB.uuid])
        XCTAssertEqual(
            template.days[0].exercises.map { $0.exerciseID },
            [fixture.squat.uuid, fixture.legExtension.uuid, fixture.plank.uuid]
        )
        XCTAssertEqual(template.days[0].exercises.map { $0.order }, [0, 1, 2])
    }

    func testProgram_unknownID_returnsNil() throws {
        let fixture = try makeFixture()

        XCTAssertNil(try fixture.repository.program(id: UUID()))
    }

    // MARK: - activate

    func testActivate_leavesExactlyOneActive() throws {
        let fixture = try makeFixture()
        // Store inconsistente de propósito: dois ativos. `activate` deixa só o pedido.
        let extra = insertProgram(name: "Extra", isActive: true, exercise: fixture.squat, into: fixture.context)
        try fixture.context.save()

        try fixture.repository.activate(programID: fixture.strengthProgram.uuid)

        XCTAssertTrue(fixture.strengthProgram.isActive)
        XCTAssertFalse(fixture.program.isActive)
        XCTAssertFalse(extra.isActive)
        let active = try fixture.repository.allPrograms().filter { $0.isActive }
        XCTAssertEqual(active.map { $0.id }, [fixture.strengthProgram.uuid])
    }

    func testActivate_unknownProgram_throwsProgramNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(try fixture.repository.activate(programID: unknown), .programNotFound(unknown))
        XCTAssertTrue(fixture.program.isActive)
    }

    // MARK: - rename

    func testRename_trimsAndPersists() throws {
        let fixture = try makeFixture()

        try fixture.repository.rename(programID: fixture.program.uuid, to: "  Meu ABC  ")

        // Outro contexto do mesmo container só enxerga o que foi salvo.
        let otherContext = ModelContext(fixture.container)
        let programID = fixture.program.uuid
        let stored = try otherContext.fetch(
            FetchDescriptor<ProgramModel>(predicate: #Predicate<ProgramModel> { $0.uuid == programID })
        )
        XCTAssertEqual(stored.first?.name, "Meu ABC")
    }

    func testRename_blankName_throwsInvalidParameters() throws {
        let fixture = try makeFixture()

        assertInvalidParameters(try fixture.repository.rename(programID: fixture.program.uuid, to: "   "))
        XCTAssertEqual(fixture.program.name, "ABC")
    }

    func testRename_unknownProgram_throwsProgramNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(try fixture.repository.rename(programID: unknown, to: "X"), .programNotFound(unknown))
    }

    // MARK: - setGoal (T2.12, SPEC §7.9)

    func testSetGoal_withoutDefaults_changesGoalOnly() throws {
        let fixture = try makeFixture()
        let before = try targetsOfDayA(fixture)

        try fixture.repository.setGoal(programID: fixture.program.uuid, goal: .endurance, applyDefaults: false)

        XCTAssertEqual(fixture.program.goalRaw, ProgramGoal.endurance.rawValue)
        XCTAssertEqual(try fixture.repository.program(id: fixture.program.uuid)?.goal, .endurance)
        XCTAssertEqual(try targetsOfDayA(fixture), before)
    }

    func testSetGoal_withDefaults_rewritesRepsRIRAndRestByMovementPattern() throws {
        let fixture = try makeFixture()
        fixture.squatTarget.startingLoad = 60
        try fixture.context.save()
        let defaults = ProgramGoal.strength.defaults

        try fixture.repository.setGoal(programID: fixture.program.uuid, goal: .strength, applyDefaults: true)

        let targets = try targetsOfDayA(fixture)
        XCTAssertEqual(targets.count, 3)

        // Agachamento: padrão `squat` é composto.
        let squat = targets[0]
        XCTAssertEqual(squat.repMin, defaults.compoundRepRange.lowerBound)
        XCTAssertEqual(squat.repMax, defaults.compoundRepRange.upperBound)
        XCTAssertEqual(squat.targetRIR, defaults.targetRIR)
        XCTAssertEqual(squat.restSeconds, defaults.compoundRestSeconds)
        // Séries e carga inicial não fazem parte de `setGoal`.
        XCTAssertEqual(squat.sets, 3)
        XCTAssertEqual(squat.startingLoad, 60)

        // Cadeira extensora: `kneeExtension` é isolado. Prancha sem padrão conta como isolado.
        for isolated in targets[1...] {
            XCTAssertEqual(isolated.repMin, defaults.isolationRepRange.lowerBound)
            XCTAssertEqual(isolated.repMax, defaults.isolationRepRange.upperBound)
            XCTAssertEqual(isolated.targetRIR, defaults.targetRIR)
            XCTAssertEqual(isolated.restSeconds, defaults.isolationRestSeconds)
            XCTAssertEqual(isolated.sets, 3)
        }

        // O dia B também é reescrito.
        let dayB = try XCTUnwrap(fixture.repository.program(id: fixture.program.uuid)?.days.last)
        XCTAssertEqual(dayB.exercises.first?.repMin, defaults.compoundRepRange.lowerBound)
        XCTAssertEqual(fixture.program.goalRaw, ProgramGoal.strength.rawValue)
    }

    func testSetGoal_withDefaults_keepsStepsAndSecondsOfCarriesAndNeckButUpdatesRIR() throws {
        let fixture = try makeFixture()
        let carry = insertExercise(slug: "caminhada-fazendeiro", name: "Caminhada do fazendeiro", pattern: .carry, increment: 2.5, into: fixture.context)
        let neck = insertExercise(slug: "isometria-pescoco", name: "Isometria de pescoço", pattern: .neck, increment: 1, into: fixture.context)
        let carryTarget = insertTarget(order: 3, exercise: carry, into: fixture.context, day: fixture.dayA)
        carryTarget.repMin = 20
        carryTarget.repMax = 40
        carryTarget.restSeconds = 120
        let neckTarget = insertTarget(order: 4, exercise: neck, into: fixture.context, day: fixture.dayA)
        neckTarget.repMin = 10
        neckTarget.repMax = 20
        neckTarget.restSeconds = 60
        try fixture.context.save()
        let defaults = ProgramGoal.strength.defaults

        try fixture.repository.setGoal(programID: fixture.program.uuid, goal: .strength, applyDefaults: true)

        let targets = try targetsOfDayA(fixture)
        let storedCarry = try XCTUnwrap(targets.first { $0.id == carryTarget.uuid })
        XCTAssertEqual(storedCarry.repMin, 20, "Passos, não repetições de força")
        XCTAssertEqual(storedCarry.repMax, 40)
        XCTAssertEqual(storedCarry.restSeconds, 120)
        XCTAssertEqual(storedCarry.targetRIR, defaults.targetRIR)
        let storedNeck = try XCTUnwrap(targets.first { $0.id == neckTarget.uuid })
        XCTAssertEqual(storedNeck.repMin, 10, "Segundos de isometria")
        XCTAssertEqual(storedNeck.repMax, 20)
        XCTAssertEqual(storedNeck.restSeconds, 60)
        XCTAssertEqual(storedNeck.targetRIR, defaults.targetRIR)
        // Os demais seguem a tabela do objetivo.
        XCTAssertEqual(targets.first?.repMin, defaults.compoundRepRange.lowerBound)
    }

    func testSetGoal_unknownProgram_throwsProgramNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(
            try fixture.repository.setGoal(programID: unknown, goal: .strength, applyDefaults: true),
            .programNotFound(unknown)
        )
    }

    // MARK: - duplicate

    func testDuplicate_copiesWithNewIDsInactiveAndCreatedAtNow() throws {
        let fixture = try makeFixture()
        fixture.program.goalRaw = ProgramGoal.longevity.rawValue
        fixture.program.summary = "Resumo"
        fixture.squatTarget.startingLoad = 40
        try fixture.context.save()
        let later = now.addingTimeInterval(86_400)
        let original = try XCTUnwrap(fixture.repository.program(id: fixture.program.uuid))

        let copyID = try fixture.repository.duplicate(programID: fixture.program.uuid, name: " Cópia ", now: later)

        let copy = try XCTUnwrap(fixture.repository.program(id: copyID))
        XCTAssertNotEqual(copyID, original.id)
        XCTAssertEqual(copy.name, "Cópia")
        XCTAssertFalse(copy.isActive)
        XCTAssertEqual(copy.goal, .longevity)
        XCTAssertEqual(copy.summary, "Resumo")
        XCTAssertEqual(try fetchProgramModel(copyID, in: fixture.context).createdAt, later)

        // Mesma estrutura e mesmos parâmetros, ids novos em dias e alvos.
        XCTAssertEqual(copy.days.map { $0.name }, original.days.map { $0.name })
        XCTAssertEqual(copy.days.map { $0.order }, original.days.map { $0.order })
        XCTAssertTrue(Set(copy.days.map { $0.id }).isDisjoint(with: original.days.map { $0.id }))
        let originalTargets = original.days.flatMap { $0.exercises }
        let copiedTargets = copy.days.flatMap { $0.exercises }
        XCTAssertTrue(Set(copiedTargets.map { $0.id }).isDisjoint(with: originalTargets.map { $0.id }))
        XCTAssertEqual(copiedTargets.map { $0.exerciseID }, originalTargets.map { $0.exerciseID })
        XCTAssertEqual(copiedTargets.map { $0.order }, originalTargets.map { $0.order })
        XCTAssertEqual(copiedTargets.map { $0.sets }, originalTargets.map { $0.sets })
        XCTAssertEqual(copiedTargets.map { $0.repMin }, originalTargets.map { $0.repMin })
        XCTAssertEqual(copiedTargets.map { $0.repMax }, originalTargets.map { $0.repMax })
        XCTAssertEqual(copiedTargets.map { $0.targetRIR }, originalTargets.map { $0.targetRIR })
        XCTAssertEqual(copiedTargets.map { $0.restSeconds }, originalTargets.map { $0.restSeconds })
        XCTAssertEqual(copiedTargets.map { $0.startingLoad }, originalTargets.map { $0.startingLoad })

        // Original intacto e ainda ativo; catálogo não duplicado.
        XCTAssertEqual(try fixture.repository.program(id: fixture.program.uuid), original)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProgramModel>()), 3)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ExerciseModel>()), 3)
    }

    func testDuplicate_editingCopyLeavesOriginalUntouched() throws {
        let fixture = try makeFixture()
        let copyID = try fixture.repository.duplicate(programID: fixture.program.uuid, name: "Cópia", now: now)
        let copy = try XCTUnwrap(fixture.repository.program(id: copyID))
        let copiedSquat = try XCTUnwrap(copy.days.first?.exercises.first)

        try fixture.repository.updateTarget(
            id: copiedSquat.id, sets: 5, repMin: 3, repMax: 5, targetRIR: 1, restSeconds: 240, startingLoad: nil
        )

        XCTAssertEqual(fixture.squatTarget.sets, 3)
        XCTAssertEqual(fixture.squatTarget.repMax, 12)
    }

    func testDuplicate_blankName_throwsInvalidParameters() throws {
        let fixture = try makeFixture()

        assertInvalidParameters(try fixture.repository.duplicate(programID: fixture.program.uuid, name: "", now: now))
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProgramModel>()), 2)
    }

    func testDuplicate_unknownProgram_throwsProgramNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(
            try fixture.repository.duplicate(programID: unknown, name: "Cópia", now: now),
            .programNotFound(unknown)
        )
    }

    // MARK: - delete

    func testDelete_inactiveProgram_cascadesAndKeepsCatalog() throws {
        let fixture = try makeFixture()
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProgramDayModel>()), 3)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), 5)

        try fixture.repository.delete(programID: fixture.strengthProgram.uuid)

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProgramModel>()), 1)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProgramDayModel>()), 2)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), 4)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ExerciseModel>()), 3)
        XCTAssertEqual(try fixture.repository.allPrograms().map { $0.id }, [fixture.program.uuid])
    }

    func testDelete_activeProgram_throwsCannotDeleteActive() throws {
        let fixture = try makeFixture()

        assertThrows(try fixture.repository.delete(programID: fixture.program.uuid), .cannotDeleteActive)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProgramModel>()), 2)
    }

    func testDelete_unknownProgram_throwsProgramNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(try fixture.repository.delete(programID: unknown), .programNotFound(unknown))
    }

    // MARK: - addExercise (RF-33)

    func testAddExercise_compound_appendsWithGoalDefaults() throws {
        let fixture = try makeFixture()
        fixture.program.goalRaw = ProgramGoal.strength.rawValue
        try fixture.context.save()
        let defaults = ProgramGoal.strength.defaults

        let targetID = try fixture.repository.addExercise(exerciseID: fixture.squat.uuid, toDay: fixture.dayA.uuid)

        let targets = try targetsOfDayA(fixture)
        XCTAssertEqual(targets.count, 4)
        let added = try XCTUnwrap(targets.last)
        XCTAssertEqual(added.id, targetID)
        XCTAssertEqual(added.exerciseID, fixture.squat.uuid)
        XCTAssertEqual(added.order, 3)
        XCTAssertEqual(added.sets, defaults.setsPerExercise)
        XCTAssertEqual(added.repMin, defaults.compoundRepRange.lowerBound)
        XCTAssertEqual(added.repMax, defaults.compoundRepRange.upperBound)
        XCTAssertEqual(added.targetRIR, defaults.targetRIR)
        XCTAssertEqual(added.restSeconds, defaults.compoundRestSeconds)
        XCTAssertNil(added.startingLoad, "Sem carga inicial: o motor calibra (SPEC P2)")
    }

    func testAddExercise_isolationOrNoPattern_usesIsolationDefaultsOfHypertrophy() throws {
        let fixture = try makeFixture()
        let defaults = ProgramGoal.hypertrophy.defaults

        let extensionID = try fixture.repository.addExercise(exerciseID: fixture.legExtension.uuid, toDay: fixture.dayB.uuid)
        let plankID = try fixture.repository.addExercise(exerciseID: fixture.plank.uuid, toDay: fixture.dayB.uuid)

        let dayB = try XCTUnwrap(fixture.repository.program(id: fixture.program.uuid)?.days.last)
        XCTAssertEqual(Array(dayB.exercises.map { $0.id }.suffix(2)), [extensionID, plankID])
        XCTAssertEqual(dayB.exercises.map { $0.order }, [0, 1, 2])
        for added in dayB.exercises.suffix(2) {
            XCTAssertEqual(added.sets, defaults.setsPerExercise)
            XCTAssertEqual(added.repMin, defaults.isolationRepRange.lowerBound)
            XCTAssertEqual(added.repMax, defaults.isolationRepRange.upperBound)
            XCTAssertEqual(added.targetRIR, defaults.targetRIR)
            XCTAssertEqual(added.restSeconds, defaults.isolationRestSeconds)
        }
    }

    func testAddExercise_carryAndNeck_startInStepsAndSeconds() throws {
        let fixture = try makeFixture()
        fixture.program.goalRaw = ProgramGoal.combat.rawValue
        let carry = insertExercise(slug: "caminhada-fazendeiro", name: "Caminhada do fazendeiro", pattern: .carry, increment: 2.5, into: fixture.context)
        let neck = insertExercise(slug: "isometria-pescoco", name: "Isometria de pescoço", pattern: .neck, increment: 1, into: fixture.context)
        try fixture.context.save()
        let defaults = ProgramGoal.combat.defaults

        let carryID = try fixture.repository.addExercise(exerciseID: carry.uuid, toDay: fixture.dayB.uuid)
        let neckID = try fixture.repository.addExercise(exerciseID: neck.uuid, toDay: fixture.dayB.uuid)

        let dayB = try XCTUnwrap(fixture.repository.program(id: fixture.program.uuid)?.days.last)
        let addedCarry = try XCTUnwrap(dayB.exercises.first { $0.id == carryID })
        XCTAssertEqual(addedCarry.repMin, 20)
        XCTAssertEqual(addedCarry.repMax, 40)
        XCTAssertEqual(addedCarry.restSeconds, defaults.isolationRestSeconds)
        XCTAssertEqual(addedCarry.targetRIR, defaults.targetRIR)
        XCTAssertEqual(addedCarry.sets, defaults.setsPerExercise)
        let addedNeck = try XCTUnwrap(dayB.exercises.first { $0.id == neckID })
        XCTAssertEqual(addedNeck.repMin, 10)
        XCTAssertEqual(addedNeck.repMax, 20)
        XCTAssertEqual(addedNeck.restSeconds, defaults.isolationRestSeconds)
    }

    func testAddExercise_dayAtMaximum_throwsTooManyExercises() throws {
        let fixture = try makeFixture()
        for _ in 3..<ProgramLimits.maxExercisesPerDay {
            _ = try fixture.repository.addExercise(exerciseID: fixture.plank.uuid, toDay: fixture.dayA.uuid)
        }
        XCTAssertEqual(try targetsOfDayA(fixture).count, ProgramLimits.maxExercisesPerDay)

        assertThrows(
            try fixture.repository.addExercise(exerciseID: fixture.squat.uuid, toDay: fixture.dayA.uuid),
            .tooManyExercises
        )
        XCTAssertEqual(try targetsOfDayA(fixture).count, ProgramLimits.maxExercisesPerDay)
    }

    func testAddExercise_unknownDay_throwsDayNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(
            try fixture.repository.addExercise(exerciseID: fixture.squat.uuid, toDay: unknown),
            .dayNotFound(unknown)
        )
    }

    func testAddExercise_unknownExercise_throwsExerciseNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(
            try fixture.repository.addExercise(exerciseID: unknown, toDay: fixture.dayA.uuid),
            .exerciseNotFound(unknown)
        )
        XCTAssertEqual(try targetsOfDayA(fixture).count, 3)
    }

    // MARK: - removeTarget (RF-33)

    func testRemoveTarget_deletesAndRenumbers() throws {
        let fixture = try makeFixture()

        try fixture.repository.removeTarget(id: fixture.legExtensionTarget.uuid)

        let targets = try targetsOfDayA(fixture)
        XCTAssertEqual(targets.map { $0.exerciseID }, [fixture.squat.uuid, fixture.plank.uuid])
        XCTAssertEqual(targets.map { $0.order }, [0, 1])
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), 4)
        // O catálogo nunca sai junto (ARCHITECTURE §5).
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ExerciseModel>()), 3)
    }

    func testRemoveTarget_lastExerciseOfDay_throwsTooFewExercises() throws {
        let fixture = try makeFixture()

        assertThrows(try fixture.repository.removeTarget(id: fixture.dayBTarget.uuid), .tooFewExercises)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), 5)
    }

    func testRemoveTarget_unknownTarget_throwsTargetNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(try fixture.repository.removeTarget(id: unknown), .targetNotFound(unknown))
    }

    // MARK: - moveTarget

    func testMoveTarget_firstToLast_renumbers() throws {
        let fixture = try makeFixture()

        try fixture.repository.moveTarget(id: fixture.squatTarget.uuid, toIndex: 2)

        let targets = try targetsOfDayA(fixture)
        XCTAssertEqual(targets.map { $0.exerciseID }, [fixture.legExtension.uuid, fixture.plank.uuid, fixture.squat.uuid])
        XCTAssertEqual(targets.map { $0.order }, [0, 1, 2])
    }

    func testMoveTarget_lastToFirst_renumbers() throws {
        let fixture = try makeFixture()

        try fixture.repository.moveTarget(id: fixture.plankTarget.uuid, toIndex: 0)

        let targets = try targetsOfDayA(fixture)
        XCTAssertEqual(targets.map { $0.exerciseID }, [fixture.plank.uuid, fixture.squat.uuid, fixture.legExtension.uuid])
        XCTAssertEqual(targets.map { $0.order }, [0, 1, 2])
    }

    func testMoveTarget_indexOutOfRange_throwsInvalidParameters() throws {
        let fixture = try makeFixture()

        assertInvalidParameters(try fixture.repository.moveTarget(id: fixture.squatTarget.uuid, toIndex: -1))
        assertInvalidParameters(try fixture.repository.moveTarget(id: fixture.squatTarget.uuid, toIndex: 3))
        XCTAssertEqual(try targetsOfDayA(fixture).map { $0.exerciseID }.first, fixture.squat.uuid)
    }

    func testMoveTarget_unknownTarget_throwsTargetNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(try fixture.repository.moveTarget(id: unknown, toIndex: 0), .targetNotFound(unknown))
    }

    // MARK: - replaceExercise (RF-34, na edição)

    func testReplaceExercise_keepsParametersAndClearsStartingLoad() throws {
        let fixture = try makeFixture()
        try fixture.repository.updateTarget(
            id: fixture.squatTarget.uuid, sets: 4, repMin: 6, repMax: 10, targetRIR: 1, restSeconds: 150, startingLoad: 60
        )

        try fixture.repository.replaceExercise(targetID: fixture.squatTarget.uuid, with: fixture.legExtension.uuid)

        let replaced = try XCTUnwrap(try targetsOfDayA(fixture).first)
        XCTAssertEqual(replaced.id, fixture.squatTarget.uuid)
        XCTAssertEqual(replaced.exerciseID, fixture.legExtension.uuid)
        XCTAssertEqual(replaced.order, 0)
        XCTAssertEqual(replaced.sets, 4)
        XCTAssertEqual(replaced.repMin, 6)
        XCTAssertEqual(replaced.repMax, 10)
        XCTAssertEqual(replaced.targetRIR, 1)
        XCTAssertEqual(replaced.restSeconds, 150)
        XCTAssertNil(replaced.startingLoad, "A carga era do exercício antigo; o substituto calibra (SPEC P2)")
    }

    func testReplaceExercise_unknownTarget_throwsTargetNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(
            try fixture.repository.replaceExercise(targetID: unknown, with: fixture.squat.uuid),
            .targetNotFound(unknown)
        )
    }

    func testReplaceExercise_unknownExercise_throwsExerciseNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(
            try fixture.repository.replaceExercise(targetID: fixture.squatTarget.uuid, with: unknown),
            .exerciseNotFound(unknown)
        )
        XCTAssertEqual(fixture.squatTarget.exercise?.uuid, fixture.squat.uuid)
    }

    // MARK: - updateTarget (RF-16, CA2-4)

    func testUpdateTarget_validParameters_persistAndLeaveSessionSnapshotsAlone() throws {
        let fixture = try makeFixture()
        let snapshot = insertSessionSnapshot(for: fixture.squat, into: fixture.context)
        try fixture.context.save()

        try fixture.repository.updateTarget(
            id: fixture.squatTarget.uuid, sets: 4, repMin: 6, repMax: 15, targetRIR: 1, restSeconds: 180, startingLoad: 62.5
        )

        let updated = try XCTUnwrap(try targetsOfDayA(fixture).first)
        XCTAssertEqual(updated.sets, 4)
        XCTAssertEqual(updated.repMin, 6)
        XCTAssertEqual(updated.repMax, 15)
        XCTAssertEqual(updated.targetRIR, 1)
        XCTAssertEqual(updated.restSeconds, 180)
        XCTAssertEqual(updated.startingLoad, 62.5)
        // CA2-4: a sessão antiga mantém o snapshot da prescrição.
        XCTAssertEqual(snapshot.prescribedRepMax, 12)
        XCTAssertEqual(snapshot.prescribedSets, 3)
    }

    func testUpdateTarget_boundaryValues_areAccepted() throws {
        let fixture = try makeFixture()
        let id = fixture.squatTarget.uuid

        try fixture.repository.updateTarget(id: id, sets: 1, repMin: 1, repMax: 2, targetRIR: 0, restSeconds: 15, startingLoad: 0)
        try fixture.repository.updateTarget(id: id, sets: 10, repMin: 49, repMax: 50, targetRIR: 5, restSeconds: 600, startingLoad: nil)

        let updated = try XCTUnwrap(try targetsOfDayA(fixture).first)
        XCTAssertEqual(updated.sets, 10)
        XCTAssertEqual(updated.repMin, 49)
        XCTAssertEqual(updated.repMax, 50)
        XCTAssertEqual(updated.targetRIR, 5)
        XCTAssertEqual(updated.restSeconds, 600)
        XCTAssertNil(updated.startingLoad)
    }

    func testUpdateTarget_invalidParameters_throwAndLeaveTargetUnchanged() throws {
        let fixture = try makeFixture()
        let before = try targetsOfDayA(fixture)

        struct Case {
            let label: String
            let sets: Int
            let repMin: Int
            let repMax: Int
            let rir: Int
            let rest: Int
            let load: Double?
        }
        // Agachamento tem incremento 2,5 (P8).
        let cases = [
            Case(label: "séries 0", sets: 0, repMin: 8, repMax: 12, rir: 2, rest: 120, load: nil),
            Case(label: "séries 11", sets: 11, repMin: 8, repMax: 12, rir: 2, rest: 120, load: nil),
            Case(label: "repMin 0", sets: 3, repMin: 0, repMax: 12, rir: 2, rest: 120, load: nil),
            Case(label: "repMin = repMax", sets: 3, repMin: 10, repMax: 10, rir: 2, rest: 120, load: nil),
            Case(label: "repMin > repMax", sets: 3, repMin: 12, repMax: 8, rir: 2, rest: 120, load: nil),
            Case(label: "repMax 51", sets: 3, repMin: 8, repMax: 51, rir: 2, rest: 120, load: nil),
            Case(label: "RIR -1", sets: 3, repMin: 8, repMax: 12, rir: -1, rest: 120, load: nil),
            Case(label: "RIR 6", sets: 3, repMin: 8, repMax: 12, rir: 6, rest: 120, load: nil),
            Case(label: "descanso 14", sets: 3, repMin: 8, repMax: 12, rir: 2, rest: 14, load: nil),
            Case(label: "descanso 601", sets: 3, repMin: 8, repMax: 12, rir: 2, rest: 601, load: nil),
            Case(label: "carga negativa", sets: 3, repMin: 8, repMax: 12, rir: 2, rest: 120, load: -2.5),
            Case(label: "carga fora do incremento", sets: 3, repMin: 8, repMax: 12, rir: 2, rest: 120, load: 61),
            Case(label: "carga infinita", sets: 3, repMin: 8, repMax: 12, rir: 2, rest: 120, load: .infinity),
            Case(label: "carga NaN", sets: 3, repMin: 8, repMax: 12, rir: 2, rest: 120, load: .nan),
        ]

        for testCase in cases {
            XCTAssertThrowsError(
                try fixture.repository.updateTarget(
                    id: fixture.squatTarget.uuid,
                    sets: testCase.sets,
                    repMin: testCase.repMin,
                    repMax: testCase.repMax,
                    targetRIR: testCase.rir,
                    restSeconds: testCase.rest,
                    startingLoad: testCase.load
                ),
                testCase.label
            ) { error in
                guard case .invalidParameters = error as? ProgramRepositoryError else {
                    XCTFail("\(testCase.label): esperado invalidParameters, veio \(error)")
                    return
                }
            }
        }
        XCTAssertEqual(try targetsOfDayA(fixture), before)
    }

    func testUpdateTarget_unknownTarget_throwsTargetNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(
            try fixture.repository.updateTarget(
                id: unknown, sets: 3, repMin: 8, repMax: 12, targetRIR: 2, restSeconds: 120, startingLoad: nil
            ),
            .targetNotFound(unknown)
        )
    }

    // MARK: - addDay (T2.22, RF-36)

    func testAddDay_defaultName_usesNextFreeLetterAndAppendsAtEnd() throws {
        let fixture = try makeFixture()

        let newID = try fixture.repository.addDay(programID: fixture.program.uuid, name: nil)

        let days = try XCTUnwrap(fixture.repository.program(id: fixture.program.uuid)).days
        XCTAssertEqual(days.map { $0.name }, ["Dia A", "Dia B", "Dia C"])
        XCTAssertEqual(days.map { $0.order }, [0, 1, 2])
        XCTAssertEqual(days.last?.id, newID)
        XCTAssertEqual(days.last?.exercises.count, 0)
    }

    func testAddDay_explicitName_trimsAndUsesIt() throws {
        let fixture = try makeFixture()

        let newID = try fixture.repository.addDay(programID: fixture.program.uuid, name: "  Cardio leve  ")

        let days = try XCTUnwrap(fixture.repository.program(id: fixture.program.uuid)).days
        let added = try XCTUnwrap(days.first { $0.id == newID })
        XCTAssertEqual(added.name, "Cardio leve")
    }

    func testAddDay_blankExplicitName_throwsInvalidParameters() throws {
        let fixture = try makeFixture()

        assertInvalidParameters(try fixture.repository.addDay(programID: fixture.program.uuid, name: "   "))
        XCTAssertEqual(try fixture.repository.program(id: fixture.program.uuid)?.days.count, 2)
    }

    func testAddDay_atMaximum_throwsTooManyDays() throws {
        let fixture = try makeFixture()
        for _ in 2..<ProgramLimits.maxDays {
            _ = try fixture.repository.addDay(programID: fixture.program.uuid, name: nil)
        }
        XCTAssertEqual(try fixture.repository.program(id: fixture.program.uuid)?.days.count, ProgramLimits.maxDays)

        assertThrows(try fixture.repository.addDay(programID: fixture.program.uuid, name: nil), .tooManyDays)
        XCTAssertEqual(try fixture.repository.program(id: fixture.program.uuid)?.days.count, ProgramLimits.maxDays)
    }

    func testAddDay_unknownProgram_throwsProgramNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(try fixture.repository.addDay(programID: unknown, name: nil), .programNotFound(unknown))
    }

    // MARK: - removeDay (T2.22, RF-36)

    func testRemoveDay_deletesCascadesAndRenumbersRemaining() throws {
        let fixture = try makeFixture()

        try fixture.repository.removeDay(id: fixture.dayA.uuid)

        let days = try XCTUnwrap(fixture.repository.program(id: fixture.program.uuid)).days
        XCTAssertEqual(days.map { $0.id }, [fixture.dayB.uuid])
        XCTAssertEqual(days.map { $0.order }, [0])
        // Dia A tinha 3 alvos; só sobram os 2 dias restantes do fixture (Dia B e o da Força).
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProgramDayModel>()), 2)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProgramExerciseModel>()), 2)
        // O catálogo nunca sai junto (ARCHITECTURE §5).
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ExerciseModel>()), 3)
    }

    func testRemoveDay_keepsSessionHistoryUntouched() throws {
        let fixture = try makeFixture()
        _ = insertSessionSnapshot(for: fixture.squat, into: fixture.context)
        try fixture.context.save()

        try fixture.repository.removeDay(id: fixture.dayA.uuid)

        // O histórico é por sessão/exercício, sem relação com `ProgramDayModel` (ARCHITECTURE §5,
        // decisão 3): a sessão antiga continua intacta, com o nome do dia gravado na hora.
        let sessions = try fixture.context.fetch(FetchDescriptor<WorkoutSessionModel>())
        XCTAssertEqual(sessions.map { $0.programDayName }, ["Dia A"])
    }

    func testRemoveDay_lastDayOfProgram_throwsTooFewDays() throws {
        let fixture = try makeFixture()
        let onlyDay = try XCTUnwrap(fixture.strengthProgram.days.first)

        assertThrows(try fixture.repository.removeDay(id: onlyDay.uuid), .tooFewDays)
        XCTAssertEqual(try fixture.repository.program(id: fixture.strengthProgram.uuid)?.days.count, 1)
    }

    func testRemoveDay_unknownDay_throwsDayNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(try fixture.repository.removeDay(id: unknown), .dayNotFound(unknown))
    }

    // MARK: - renameDay (T2.22, RF-36)

    func testRenameDay_trimsAndPersists() throws {
        let fixture = try makeFixture()

        try fixture.repository.renameDay(id: fixture.dayA.uuid, to: "  Dia A — Superior  ")

        let day = try XCTUnwrap(fixture.repository.program(id: fixture.program.uuid)?.days.first)
        XCTAssertEqual(day.name, "Dia A — Superior")
    }

    func testRenameDay_blankName_throwsInvalidParameters() throws {
        let fixture = try makeFixture()

        assertInvalidParameters(try fixture.repository.renameDay(id: fixture.dayA.uuid, to: "   "))
        XCTAssertEqual(fixture.dayA.name, "Dia A")
    }

    func testRenameDay_unknownDay_throwsDayNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(try fixture.repository.renameDay(id: unknown, to: "X"), .dayNotFound(unknown))
    }

    // MARK: - moveDay (T2.22, RF-36)

    func testMoveDay_firstToLast_renumbers() throws {
        let fixture = try makeFixture()
        let dayCID = try fixture.repository.addDay(programID: fixture.program.uuid, name: nil)

        try fixture.repository.moveDay(id: fixture.dayA.uuid, toIndex: 2)

        let days = try XCTUnwrap(fixture.repository.program(id: fixture.program.uuid)).days
        XCTAssertEqual(days.map { $0.id }, [fixture.dayB.uuid, dayCID, fixture.dayA.uuid])
        XCTAssertEqual(days.map { $0.order }, [0, 1, 2])
    }

    func testMoveDay_lastToFirst_renumbers() throws {
        let fixture = try makeFixture()

        try fixture.repository.moveDay(id: fixture.dayB.uuid, toIndex: 0)

        let days = try XCTUnwrap(fixture.repository.program(id: fixture.program.uuid)).days
        XCTAssertEqual(days.map { $0.id }, [fixture.dayB.uuid, fixture.dayA.uuid])
        XCTAssertEqual(days.map { $0.order }, [0, 1])
    }

    func testMoveDay_indexOutOfRange_throwsInvalidParameters() throws {
        let fixture = try makeFixture()

        assertInvalidParameters(try fixture.repository.moveDay(id: fixture.dayA.uuid, toIndex: -1))
        assertInvalidParameters(try fixture.repository.moveDay(id: fixture.dayA.uuid, toIndex: 2))
        XCTAssertEqual(try fixture.repository.program(id: fixture.program.uuid)?.days.first?.id, fixture.dayA.uuid)
    }

    func testMoveDay_unknownDay_throwsDayNotFound() throws {
        let fixture = try makeFixture()
        let unknown = UUID()

        assertThrows(try fixture.repository.moveDay(id: unknown, toIndex: 0), .dayNotFound(unknown))
    }

    // MARK: - Fixture

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let repository: ProgramRepository
        /// Composto (`squat`), incremento 2,5.
        let squat: ExerciseModel
        /// Isolado (`kneeExtension`), incremento 5.
        let legExtension: ExerciseModel
        /// Sem padrão de movimento: conta como isolado.
        let plank: ExerciseModel
        /// "ABC", ativo, hipertrofia. Dia A: agachamento, extensora, prancha. Dia B: agachamento.
        let program: ProgramModel
        let dayA: ProgramDayModel
        let dayB: ProgramDayModel
        let squatTarget: ProgramExerciseModel
        let legExtensionTarget: ProgramExerciseModel
        let plankTarget: ProgramExerciseModel
        let dayBTarget: ProgramExerciseModel
        /// "Força", inativo, um dia com um alvo.
        let strengthProgram: ProgramModel
    }

    private func makeFixture() throws -> Fixture {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext

        let squat = insertExercise(slug: "agachamento-livre", name: "Agachamento livre", pattern: .squat, increment: 2.5, into: context)
        let legExtension = insertExercise(slug: "cadeira-extensora", name: "Cadeira extensora", pattern: .kneeExtension, increment: 5, into: context)
        let plank = insertExercise(slug: "prancha", name: "Prancha", pattern: nil, increment: 1, into: context)

        let program = ProgramModel(uuid: UUID(), name: "ABC", isActive: true, createdAt: now)
        context.insert(program)
        let dayA = insertDay(name: "Dia A", order: 0, into: context, program: program)
        let squatTarget = insertTarget(order: 0, exercise: squat, into: context, day: dayA)
        let legExtensionTarget = insertTarget(order: 1, exercise: legExtension, into: context, day: dayA)
        let plankTarget = insertTarget(order: 2, exercise: plank, into: context, day: dayA)
        let dayB = insertDay(name: "Dia B", order: 1, into: context, program: program)
        let dayBTarget = insertTarget(order: 0, exercise: squat, into: context, day: dayB)

        let strengthProgram = insertProgram(name: "Força", isActive: false, exercise: squat, into: context)
        try context.save()

        return Fixture(
            container: container,
            context: context,
            repository: ProgramRepository(modelContext: context),
            squat: squat,
            legExtension: legExtension,
            plank: plank,
            program: program,
            dayA: dayA,
            dayB: dayB,
            squatTarget: squatTarget,
            legExtensionTarget: legExtensionTarget,
            plankTarget: plankTarget,
            dayBTarget: dayBTarget,
            strengthProgram: strengthProgram
        )
    }

    /// Alvos do dia A pelo DTO, na ordem de `order`.
    private func targetsOfDayA(_ fixture: Fixture) throws -> [ExerciseTarget] {
        let template = try XCTUnwrap(fixture.repository.program(id: fixture.program.uuid))
        let dayA = try XCTUnwrap(template.days.first { $0.id == fixture.dayA.uuid })
        return dayA.exercises
    }

    private func fetchProgramModel(_ id: UUID, in context: ModelContext) throws -> ProgramModel {
        let descriptor = FetchDescriptor<ProgramModel>(predicate: #Predicate<ProgramModel> { $0.uuid == id })
        return try XCTUnwrap(context.fetch(descriptor).first)
    }

    private func insertExercise(
        slug: String,
        name: String,
        pattern: MovementPattern?,
        increment: Double,
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
            loadIncrement: increment,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        model.movementPatternRaw = pattern?.rawValue
        context.insert(model)
        return model
    }

    @discardableResult
    private func insertProgram(
        name: String,
        isActive: Bool,
        exercise: ExerciseModel,
        into context: ModelContext
    ) -> ProgramModel {
        let program = ProgramModel(uuid: UUID(), name: name, isActive: isActive, createdAt: now)
        context.insert(program)
        let day = insertDay(name: "Dia A", order: 0, into: context, program: program)
        insertTarget(order: 0, exercise: exercise, into: context, day: day)
        return program
    }

    private func insertDay(name: String, order: Int, into context: ModelContext, program: ProgramModel) -> ProgramDayModel {
        let day = ProgramDayModel(uuid: UUID(), name: name, order: order)
        context.insert(day)
        program.days.append(day)
        return day
    }

    @discardableResult
    private func insertTarget(
        order: Int,
        exercise: ExerciseModel,
        into context: ModelContext,
        day: ProgramDayModel
    ) -> ProgramExerciseModel {
        let target = ProgramExerciseModel(
            uuid: UUID(),
            order: order,
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
        return target
    }

    /// Sessão concluída com o snapshot 3 × 8–12 do agachamento (ARCHITECTURE §5, decisão 3).
    private func insertSessionSnapshot(for exercise: ExerciseModel, into context: ModelContext) -> SessionExerciseModel {
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: SessionStatus.completed.rawValue,
            startedAt: now,
            endedAt: now.addingTimeInterval(3_600),
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: DeviceSource.iphone.rawValue
        )
        context.insert(session)
        let snapshot = SessionExerciseModel(
            uuid: UUID(),
            order: 0,
            exerciseUUID: exercise.uuid,
            exerciseName: exercise.name,
            prescribedLoad: 60,
            prescribedSets: 3,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: 2,
            restSeconds: 120,
            noteRaw: PrescriptionNote.hold.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(snapshot)
        snapshot.exercise = exercise
        session.exercises.append(snapshot)
        return snapshot
    }

    // MARK: - Asserções

    private func assertThrows<T>(
        _ expression: @autoclosure () throws -> T,
        _ expected: ProgramRepositoryError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            XCTAssertEqual(error as? ProgramRepositoryError, expected, file: file, line: line)
        }
    }

    private func assertInvalidParameters<T>(
        _ expression: @autoclosure () throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard case .invalidParameters = error as? ProgramRepositoryError else {
                XCTFail("Esperado invalidParameters, veio \(error)", file: file, line: line)
                return
            }
        }
    }
}
