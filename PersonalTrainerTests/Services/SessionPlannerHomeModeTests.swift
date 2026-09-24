import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// v2.1 B1 (docs/V21-CONTRACT.md): modo casa no planejador (SPEC RF-42, §7.13 H1–H4), "Trocar" em
/// casa, duração estimada (B7) e a chave `homeModeEnabled`. Container in-memory e coordinator real;
/// o catálogo de marcas é montado no teste, e nada aqui lê o bundle, `UserDefaults.standard` ou o
/// disco.
///
/// Catálogo dos testes (todos em kg, bilaterais):
/// - academia: supino reto (barra) e supino inclinado (halteres), ambos empurrar horizontal/peito;
///   cadeira extensora (extensão de joelho/quadríceps); panturrilha na máquina (panturrilha);
///   remada baixa (polia, puxar horizontal/costas);
/// - casa: flexão e flexão de joelhos (peso do corpo, empurrar horizontal/peito), agachamento com o
///   peso do corpo (agachar/quadríceps), remada com mochila (objeto de casa, puxar horizontal/costas)
///   e prancha (peso do corpo, estabilidade/core, medida em segundos).
@MainActor
final class SessionPlannerHomeModeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let day: TimeInterval = 86_400

    // MARK: - H2: mesmo padrão de movimento, alvo do original (H4)

    func testH2_H4_gymExercise_becomesHomeEquivalent_withTargetFromOriginal() throws {
        let fixture = try makeFixture(homeMode: true)
        let catalog = insertCatalog(into: fixture.context)
        let program = try insertProgram(
            exercises: [ProgramEntry(exercise: catalog.bench, startingLoad: 40)],
            into: fixture.context
        )

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))

        XCTAssertTrue(plan.isHomeMode)
        XCTAssertEqual(plan.homeNotices, [])
        XCTAssertEqual(plan.programDayID, program.dayA.uuid, "O dia continua sendo o do programa")
        XCTAssertEqual(plan.exercises.count, 1)
        let planned = try XCTUnwrap(plan.exercises.first)
        XCTAssertEqual(planned.exercise.id, catalog.pushUp.uuid, "Supino com barra → flexão (RF-34: nome desempata)")
        // H4: séries, faixa, RIR, descanso, ordem e id do alvo vêm do supino.
        XCTAssertEqual(planned.target.id, program.targets[0].uuid)
        XCTAssertEqual(planned.target.exerciseID, catalog.pushUp.uuid)
        XCTAssertEqual(planned.target.sets, 4)
        XCTAssertEqual(planned.target.repMin, 6)
        XCTAssertEqual(planned.target.repMax, 10)
        XCTAssertEqual(planned.target.targetRIR, 1)
        XCTAssertEqual(planned.target.restSeconds, 150)
        XCTAssertNil(planned.target.startingLoad, "A carga inicial do supino não vale para a flexão")
        // H4: sem histórico da flexão, calibrar (P2).
        XCTAssertEqual(planned.prescription.exerciseID, catalog.pushUp.uuid)
        XCTAssertEqual(planned.prescription.note, .calibrate)
        XCTAssertEqual(planned.prescription.sets, 4)
        XCTAssertEqual(planned.prescription.restSeconds, 150)
    }

    func testRF42_homeModeOff_keepsProgramExercises() throws {
        let fixture = try makeFixture(homeMode: false)
        let catalog = insertCatalog(into: fixture.context)
        _ = try insertProgram(exercises: [ProgramEntry(exercise: catalog.bench, startingLoad: 40)], into: fixture.context)

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))

        XCTAssertFalse(plan.isHomeMode)
        XCTAssertEqual(plan.homeNotices, [])
        XCTAssertEqual(plan.exercises.map { $0.exercise.id }, [catalog.bench.uuid])
        XCTAssertEqual(plan.exercises.first?.target.startingLoad, 40)
    }

    func testRF42_turningHomeModeOff_bringsBackGymExercises_programUntouched() throws {
        let fixture = try makeFixture(homeMode: true)
        let catalog = insertCatalog(into: fixture.context)
        let program = try insertProgram(exercises: [ProgramEntry(exercise: catalog.bench, startingLoad: 40)], into: fixture.context)

        let home = try XCTUnwrap(try fixture.planner.nextPlan(now: now))
        XCTAssertEqual(home.exercises.map { $0.exercise.id }, [catalog.pushUp.uuid])
        XCTAssertEqual(program.targets[0].exercise?.uuid, catalog.bench.uuid, "O programa não muda (RF-42)")

        fixture.settings.value = PlannerSettings(homeModeEnabled: false)
        let gym = try XCTUnwrap(try fixture.planner.nextPlan(now: now))
        XCTAssertEqual(gym.exercises.map { $0.exercise.id }, [catalog.bench.uuid])
        XCTAssertFalse(gym.isHomeMode)
    }

    // MARK: - H1: exercício de casa fica

    func testH1_homeExerciseInProgram_staysWithProgramTarget() throws {
        let fixture = try makeFixture(homeMode: true)
        let catalog = insertCatalog(into: fixture.context)
        let program = try insertProgram(
            exercises: [ProgramEntry(exercise: catalog.pushUp, startingLoad: 5)],
            into: fixture.context
        )

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))

        let planned = try XCTUnwrap(plan.exercises.first)
        XCTAssertEqual(planned.exercise.id, catalog.pushUp.uuid)
        XCTAssertEqual(planned.target.id, program.targets[0].uuid)
        XCTAssertEqual(planned.target.startingLoad, 5, "Já era de casa: o alvo do programa fica inteiro")
        XCTAssertEqual(plan.homeNotices, [])
    }

    // MARK: - H2: sem o mesmo padrão, vale o mesmo grupo primário

    func testH2_withoutSamePattern_fallsBackToSamePrimaryGroup() throws {
        let fixture = try makeFixture(homeMode: true)
        let catalog = insertCatalog(into: fixture.context)
        _ = try insertProgram(exercises: [ProgramEntry(exercise: catalog.legExtension, startingLoad: nil)], into: fixture.context)

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))

        XCTAssertEqual(plan.exercises.map { $0.exercise.id }, [catalog.bodyweightSquat.uuid], "Sem extensão de joelho em casa: agachamento (quadríceps)")
        XCTAssertEqual(plan.homeNotices, [])
    }

    // MARK: - H2: sem nenhum equivalente, sai com aviso

    func testH2_withoutAnyHomeOption_leavesSessionWithNotice() throws {
        let fixture = try makeFixture(homeMode: true)
        let catalog = insertCatalog(into: fixture.context)
        _ = try insertProgram(
            exercises: [
                ProgramEntry(exercise: catalog.calfMachine, startingLoad: nil),
                ProgramEntry(exercise: catalog.bench, startingLoad: 40),
            ],
            into: fixture.context
        )

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))

        XCTAssertEqual(plan.exercises.map { $0.exercise.id }, [catalog.pushUp.uuid])
        XCTAssertEqual(plan.homeNotices, ["Sem opção em casa para Panturrilha na máquina: fica fora desta sessão."])
        XCTAssertEqual(
            SessionPlanner.noHomeOptionNotice(exerciseName: "Panturrilha na máquina"),
            "Sem opção em casa para Panturrilha na máquina: fica fora desta sessão."
        )
    }

    func testH2_dayWithNoHomeOptionAtAll_isEmptyPlanWithNotices() throws {
        let fixture = try makeFixture(homeMode: true)
        let catalog = insertCatalog(into: fixture.context)
        _ = try insertProgram(exercises: [ProgramEntry(exercise: catalog.calfMachine, startingLoad: nil)], into: fixture.context)

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))

        XCTAssertTrue(plan.exercises.isEmpty)
        XCTAssertEqual(plan.homeNotices.count, 1)
        XCTAssertEqual(plan.estimatedMinutes, 0)
        XCTAssertEqual(
            HomeViewModel.emptyDayMessage(for: plan),
            "Nenhum exercício deste dia tem opção em casa. Desligue Em casa ou escolha outro dia."
        )
    }

    // MARK: - H3: sem repetição no mesmo dia

    func testH3_twoGymExercisesWithSameBestHomeEquivalent_getDifferentOnes() throws {
        let fixture = try makeFixture(homeMode: true)
        let catalog = insertCatalog(into: fixture.context)
        _ = try insertProgram(
            exercises: [
                ProgramEntry(exercise: catalog.bench, startingLoad: 40),
                ProgramEntry(exercise: catalog.incline, startingLoad: 14),
            ],
            into: fixture.context
        )

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))

        XCTAssertEqual(
            plan.exercises.map { $0.exercise.id },
            [catalog.pushUp.uuid, catalog.kneePushUp.uuid],
            "O segundo recebe o próximo candidato (H3)"
        )
        XCTAssertEqual(plan.exercises.map { $0.target.order }, [0, 1])
    }

    func testH3_homeExerciseLaterInTheDay_isReservedBeforeSwaps() throws {
        let fixture = try makeFixture(homeMode: true)
        let catalog = insertCatalog(into: fixture.context)
        _ = try insertProgram(
            exercises: [
                ProgramEntry(exercise: catalog.bench, startingLoad: 40),
                ProgramEntry(exercise: catalog.pushUp, startingLoad: nil),
            ],
            into: fixture.context
        )

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))

        XCTAssertEqual(plan.exercises.map { $0.exercise.id }, [catalog.kneePushUp.uuid, catalog.pushUp.uuid])
    }

    // MARK: - H4: carga e nota do histórico do exercício de casa

    func testH4_prescriptionComesFromHomeExerciseHistory() throws {
        let fixture = try makeFixture(homeMode: true)
        let catalog = insertCatalog(into: fixture.context)
        let program = try insertProgram(
            exercises: [ProgramEntry(exercise: catalog.cableRow, startingLoad: 50, sets: 3, repMin: 8, repMax: 12, targetRIR: 2, restSeconds: 90)],
            into: fixture.context
        )
        // Remada com mochila: 3 × 10 a 10 kg há dois dias (dentro da faixa 8–12 → manter, P5).
        insertCompletedSession(
            day: program.dayA,
            exercise: catalog.backpackRow,
            load: 10,
            reps: 10,
            startedAt: now.addingTimeInterval(-2 * day),
            into: fixture.context
        )
        try fixture.context.save()

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))

        let planned = try XCTUnwrap(plan.exercises.first)
        XCTAssertEqual(planned.exercise.id, catalog.backpackRow.uuid)
        XCTAssertEqual(planned.prescription.note, .hold)
        XCTAssertEqual(planned.prescription.load, 10, "Carga do histórico da mochila, não os 50 kg da polia")
        XCTAssertEqual(planned.prescription.sets, 3)
        XCTAssertEqual(planned.prescription.repMin, 8)
        XCTAssertEqual(planned.prescription.repMax, 12)
    }

    func testRF42_lightWeek_appliesToHomeExercise() throws {
        let fixture = try makeFixture(homeMode: true)
        let catalog = insertCatalog(into: fixture.context)
        _ = try insertProgram(exercises: [ProgramEntry(exercise: catalog.bench, startingLoad: 40)], into: fixture.context)
        try fixture.planner.requestDeload(now: now)

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))

        XCTAssertTrue(plan.isDeload)
        XCTAssertTrue(plan.isHomeMode)
        XCTAssertEqual(plan.reason, .deload(.manual))
        let planned = try XCTUnwrap(plan.exercises.first)
        XCTAssertEqual(planned.exercise.id, catalog.pushUp.uuid)
        XCTAssertEqual(planned.prescription.note, .deload)
        XCTAssertEqual(planned.prescription.exerciseID, catalog.pushUp.uuid)
    }

    func testS4_planForDayID_alsoAppliesHomeMode() throws {
        let fixture = try makeFixture(homeMode: true)
        let catalog = insertCatalog(into: fixture.context)
        let program = try insertProgram(exercises: [ProgramEntry(exercise: catalog.legExtension, startingLoad: nil)], into: fixture.context)

        let plan = try XCTUnwrap(try fixture.planner.plan(forDayID: program.dayA.uuid, now: now))

        XCTAssertEqual(plan.reason, .manual)
        XCTAssertTrue(plan.isHomeMode)
        XCTAssertEqual(plan.exercises.map { $0.exercise.id }, [catalog.bodyweightSquat.uuid])
    }

    func testRF42_startedHomeSession_recordsHomeExercise() throws {
        let fixture = try makeFixture(homeMode: true)
        let catalog = insertCatalog(into: fixture.context)
        _ = try insertProgram(exercises: [ProgramEntry(exercise: catalog.bench, startingLoad: 40)], into: fixture.context)
        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))

        _ = try fixture.planner.startSession(from: plan, now: now)

        let recorded = try fixture.context.fetch(FetchDescriptor<SessionExerciseModel>())
        XCTAssertEqual(recorded.map { $0.exerciseUUID }, [catalog.pushUp.uuid], "O histórico da flexão é separado (P3)")
        XCTAssertEqual(recorded.first?.prescribedSets, 4)
    }

    // MARK: - Trocar (RF-34 / §7.13 H2)

    func testH2_substitutes_withHomeMode_offersOnlyHomeCandidates() throws {
        let fixture = try makeFixture(homeMode: true)
        let catalog = insertCatalog(into: fixture.context)
        try fixture.context.save()

        let home = try fixture.planner.substitutes(for: catalog.bench.uuid, limit: 10)
        XCTAssertEqual(home.map { $0.id }, [catalog.pushUp.uuid, catalog.kneePushUp.uuid])

        // Trocar no programa ignora o modo casa: o supino com halteres vem primeiro (RF-34).
        let program = try fixture.planner.programSubstitutes(for: catalog.bench.uuid, limit: 10)
        XCTAssertEqual(program.first?.id, catalog.incline.uuid)
        XCTAssertEqual(Set(program.map { $0.id }), [catalog.incline.uuid, catalog.pushUp.uuid, catalog.kneePushUp.uuid])

        fixture.settings.value = PlannerSettings(homeModeEnabled: false)
        let gym = try fixture.planner.substitutes(for: catalog.bench.uuid, limit: 10)
        XCTAssertEqual(gym.map { $0.id }, program.map { $0.id }, "Fora do modo casa, o Trocar volta ao RF-34")
    }

    // MARK: - B7: duração estimada

    func testB7_planEstimate_usesMeasureFromTraits() throws {
        let fixture = try makeFixture(homeMode: false)
        let catalog = insertCatalog(into: fixture.context)
        // Prancha (segundos): 3 × 20–40 s com 90 s de descanso → 3 × (30 + 90) + 120 = 480 s.
        _ = try insertProgram(
            exercises: [ProgramEntry(exercise: catalog.plank, startingLoad: nil, sets: 3, repMin: 20, repMax: 40, targetRIR: 2, restSeconds: 90)],
            into: fixture.context
        )

        let plan = try XCTUnwrap(try fixture.planner.nextPlan(now: now))

        XCTAssertEqual(plan.estimatedMinutes, 8)
    }

    func testB7_estimate_formulaPerMeasure() {
        let reps = makePlanned(sets: 3, repMin: 8, repMax: 12, rest: 90)
        let seconds = makePlanned(sets: 3, repMin: 20, repMax: 40, rest: 60)
        let steps = makePlanned(sets: 2, repMin: 20, repMax: 40, rest: 60)

        // Repetições: 3 × (10 × 3 s + 90 s) + 120 s = 480 s.
        XCTAssertEqual(SessionDurationEstimate.seconds(for: reps, measure: .reps), 480, accuracy: 0.001)
        // Segundos: 3 × (30 s + 60 s) + 120 s = 390 s.
        XCTAssertEqual(SessionDurationEstimate.seconds(for: seconds, measure: .seconds), 390, accuracy: 0.001)
        // Passos: 2 × (30 × 1 s + 60 s) + 120 s = 300 s.
        XCTAssertEqual(SessionDurationEstimate.seconds(for: steps, measure: .steps), 300, accuracy: 0.001)

        let traits = ExerciseTraitsCatalog(traitsBySlug: [
            seconds.exercise.slug: ExerciseTraits(measure: .seconds),
            steps.exercise.slug: ExerciseTraits(measure: .steps),
        ])
        // 480 + 390 + 300 = 1170 s = 19,5 min → 20.
        XCTAssertEqual(SessionDurationEstimate.seconds(for: [reps, seconds, steps], traits: traits), 1_170, accuracy: 0.001)
        XCTAssertEqual(SessionDurationEstimate.minutes(for: [reps, seconds, steps], traits: traits), 20)
        XCTAssertEqual(SessionDurationEstimate.minutes(for: [reps], traits: .empty), 8)
        XCTAssertEqual(SessionDurationEstimate.minutes(for: [], traits: traits), 0, "Sem exercícios, sem estimativa")
    }

    func testB7_handBuiltPlan_estimatesWithRepsByDefault() {
        let reps = makePlanned(sets: 3, repMin: 8, repMax: 12, rest: 90)
        let plan = SessionPlan(
            programID: UUID(),
            programName: "Programa",
            programDayID: UUID(),
            programDayName: "Dia A",
            exercises: [reps],
            generatedAt: now
        )
        XCTAssertEqual(plan.estimatedMinutes, 8)
        XCTAssertFalse(plan.isHomeMode)
        XCTAssertEqual(plan.homeNotices, [])

        let explicit = SessionPlan(
            programID: UUID(),
            programName: "Programa",
            programDayID: UUID(),
            programDayName: "Dia A",
            exercises: [reps],
            generatedAt: now,
            estimatedMinutes: 42
        )
        XCTAssertEqual(explicit.estimatedMinutes, 42)
    }

    // MARK: - Chave (RF-42)

    func testRF42_plannerSettings_readsHomeModeKey() throws {
        let suiteName = "SessionPlannerHomeModeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(PlannerSettings.load(from: defaults).homeModeEnabled, "Padrão: desligado")
        defaults.set(true, forKey: "homeModeEnabled")
        XCTAssertTrue(PlannerSettings.load(from: defaults).homeModeEnabled)
        XCTAssertEqual(PlannerSettings.homeModeKey, "homeModeEnabled")
        XCTAssertEqual(
            PlannerSettings.load(from: defaults),
            PlannerSettings(frequencySelector: .auto, deloadWeeks: 6, homeModeEnabled: true)
        )
    }

    // MARK: - Fixtures

    /// Ajustes mutáveis dentro de um teste; a closure do planejador lê o valor atual.
    private final class SettingsBox {
        var value: PlannerSettings

        init(_ value: PlannerSettings) {
            self.value = value
        }
    }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let coordinator: SessionCoordinator
        let settings: SettingsBox
        let planner: SessionPlanner
    }

    private func makeFixture(homeMode: Bool) throws -> Fixture {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let coordinator = SessionCoordinator(modelContext: context, appliedEvents: AppliedEventStore.inMemory())
        let box = SettingsBox(PlannerSettings(homeModeEnabled: homeMode))
        let planner = SessionPlanner(
            modelContext: context,
            coordinator: coordinator,
            deloadDecisions: FakeDeloadDecisionsStore(),
            settings: { box.value },
            traits: Self.traits
        )
        return Fixture(container: container, context: context, coordinator: coordinator, settings: box, planner: planner)
    }

    /// H1 pelo slug, como o catálogo do seed faz.
    private static let traits = ExerciseTraitsCatalog(traitsBySlug: [
        "flexao": ExerciseTraits(atHome: true),
        "flexao-joelhos": ExerciseTraits(atHome: true),
        "agachamento-peso-corpo": ExerciseTraits(atHome: true),
        "remada-mochila": ExerciseTraits(atHome: true),
        "prancha": ExerciseTraits(measure: .seconds, atHome: true),
    ])

    private struct Catalog {
        let bench: ExerciseModel
        let incline: ExerciseModel
        let legExtension: ExerciseModel
        let calfMachine: ExerciseModel
        let cableRow: ExerciseModel
        let pushUp: ExerciseModel
        let kneePushUp: ExerciseModel
        let bodyweightSquat: ExerciseModel
        let backpackRow: ExerciseModel
        let plank: ExerciseModel
    }

    private func insertCatalog(into context: ModelContext) -> Catalog {
        Catalog(
            bench: insertExercise(slug: "supino-reto", name: "Supino reto", primary: [.chest], equipment: .barbell, pattern: .horizontalPush, into: context),
            incline: insertExercise(slug: "supino-inclinado-halteres", name: "Supino inclinado", primary: [.chest], equipment: .dumbbell, pattern: .horizontalPush, into: context),
            legExtension: insertExercise(slug: "cadeira-extensora", name: "Cadeira extensora", primary: [.quads], equipment: .machine, pattern: .kneeExtension, into: context),
            calfMachine: insertExercise(slug: "panturrilha-maquina", name: "Panturrilha na máquina", primary: [.calves], equipment: .machine, pattern: .calfRaise, into: context),
            cableRow: insertExercise(slug: "remada-baixa", name: "Remada baixa", primary: [.back], equipment: .cable, pattern: .horizontalPull, into: context),
            pushUp: insertExercise(slug: "flexao", name: "Flexão", primary: [.chest], equipment: .bodyweight, pattern: .horizontalPush, into: context),
            kneePushUp: insertExercise(slug: "flexao-joelhos", name: "Flexão de joelhos", primary: [.chest], equipment: .bodyweight, pattern: .horizontalPush, into: context),
            bodyweightSquat: insertExercise(slug: "agachamento-peso-corpo", name: "Agachamento com o peso do corpo", primary: [.quads], equipment: .bodyweight, pattern: .squat, into: context),
            backpackRow: insertExercise(slug: "remada-mochila", name: "Remada com mochila", primary: [.back], equipment: .household, pattern: .horizontalPull, into: context),
            plank: insertExercise(slug: "prancha", name: "Prancha", primary: [.core], equipment: .bodyweight, pattern: .coreStability, into: context)
        )
    }

    private func insertExercise(
        slug: String,
        name: String,
        primary: [MuscleGroup],
        equipment: Equipment,
        pattern: MovementPattern,
        into context: ModelContext
    ) -> ExerciseModel {
        let model = ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: name,
            primaryMusclesRaw: CurrentSchema.encodeMuscleGroups(primary),
            secondaryMusclesRaw: "",
            equipmentRaw: equipment.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 2.5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false,
            movementPatternRaw: pattern.rawValue,
            isCustom: false
        )
        context.insert(model)
        return model
    }

    /// Um exercício do dia com o alvo gravado no programa. O padrão (4 × 6–10, RIR 1, 150 s) foge
    /// do padrão de `ExerciseTarget` para o teste enxergar de onde veio cada número.
    private struct ProgramEntry {
        let exercise: ExerciseModel
        let startingLoad: Double?
        var sets = 4
        var repMin = 6
        var repMax = 10
        var targetRIR = 1
        var restSeconds = 150
    }

    private struct InsertedProgram {
        let program: ProgramModel
        let dayA: ProgramDayModel
        /// Na ordem de `exercises`.
        let targets: [ProgramExerciseModel]
    }

    /// Programa ativo de um dia só ("Dia A") com os exercícios na ordem dada.
    private func insertProgram(exercises: [ProgramEntry], into context: ModelContext) throws -> InsertedProgram {
        let program = ProgramModel(uuid: UUID(), name: "Casa", isActive: true, createdAt: now.addingTimeInterval(-60 * day))
        context.insert(program)
        let dayA = ProgramDayModel(uuid: UUID(), name: "Dia A", order: 0)
        context.insert(dayA)
        program.days.append(dayA)
        var targets: [ProgramExerciseModel] = []
        for (order, entry) in exercises.enumerated() {
            let target = ProgramExerciseModel(
                uuid: UUID(),
                order: order,
                sets: entry.sets,
                repMin: entry.repMin,
                repMax: entry.repMax,
                targetRIR: entry.targetRIR,
                restSeconds: entry.restSeconds,
                startingLoad: entry.startingLoad
            )
            context.insert(target)
            target.exercise = entry.exercise
            dayA.exercises.append(target)
            targets.append(target)
        }
        try context.save()
        return InsertedProgram(program: program, dayA: dayA, targets: targets)
    }

    /// Sessão concluída com 3 séries de trabalho do exercício (RIR 2).
    private func insertCompletedSession(
        day: ProgramDayModel,
        exercise: ExerciseModel,
        load: Double,
        reps: Int,
        startedAt: Date,
        into context: ModelContext
    ) {
        let session = WorkoutSessionModel(
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
            sourceRaw: DeviceSource.iphone.rawValue
        )
        context.insert(session)
        let sessionExercise = SessionExerciseModel(
            uuid: UUID(),
            order: 0,
            exerciseUUID: exercise.uuid,
            exerciseName: exercise.name,
            prescribedLoad: load,
            prescribedSets: 3,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: 2,
            restSeconds: 90,
            noteRaw: PrescriptionNote.hold.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(sessionExercise)
        sessionExercise.exercise = exercise
        session.exercises.append(sessionExercise)
        for index in 0..<3 {
            let completedAt = startedAt.addingTimeInterval(Double(index + 1) * 120)
            let setLog = SetLogModel(
                uuid: UUID(),
                index: index,
                load: load,
                reps: reps,
                rir: 2,
                isWarmup: false,
                completedAt: completedAt,
                sourceRaw: DeviceSource.iphone.rawValue,
                updatedAt: completedAt
            )
            context.insert(setLog)
            sessionExercise.sets.append(setLog)
        }
    }

    /// Exercício de plano montado à mão, para as contas da estimativa.
    private func makePlanned(sets: Int, repMin: Int, repMax: Int, rest: Int) -> PlannedExercise {
        let exercise = ExerciseDefinition(
            slug: "exercicio-\(UUID().uuidString)",
            name: "Exercício",
            primaryMuscles: [.chest],
            equipment: .dumbbell,
            loadUnit: .kilograms,
            loadIncrement: 2
        )
        return PlannedExercise(
            id: UUID(),
            exercise: exercise,
            target: ExerciseTarget(exerciseID: exercise.id, order: 0, sets: sets, repMin: repMin, repMax: repMax, restSeconds: rest),
            prescription: ExercisePrescription(
                exerciseID: exercise.id,
                load: 10,
                sets: sets,
                repMin: repMin,
                repMax: repMax,
                targetReps: repMin,
                targetRIR: 2,
                restSeconds: rest,
                note: .hold
            )
        )
    }
}
