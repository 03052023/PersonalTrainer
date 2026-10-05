import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// O planejador com os dados novos da 2.4 (docs/V24-CONTRACT.md §4.3), sobre container em memória e
/// coordinator real, no calendário UTC:
/// - lê as atividades fora do app (SPEC §7.17 X4, X5; RF-53);
/// - passa `isCardio` à semana leve (§7.5, F5), a medida à revisão (R8) e os números do C1.
///
/// No branch da `data`, os corpos do motor e do encaixe ainda são os do andaime (o S6 não lê as cargas, o
/// encaixe ignora as fixas, a semana leve ignora `isCardio`, `triggerDetail` devolve `nil`). Por isso estes
/// testes conferem o que vale nos dois mundos: que o planejador lê o store e entrega ao motor o que a SPEC
/// manda. O efeito no S6, no encaixe, nos minutos e nos números do C1 fica para os testes cruzados da
/// integração (§5).
@MainActor
final class SessionPlannerActivitiesTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    /// Segunda-feira, 2026-09-28, 12:00 UTC.
    private var now: Date { date(2026, 9, 28) }

    // MARK: - RF-53: o planejador lê as atividades

    func testRF53_plannerReadsActivitiesStore() throws {
        // S6 (X5): com o seletor por frequência ligado, o próximo plano lê os registros.
        let single = try makeFixture(settings: PlannerSettings(frequencySelector: .on))
        _ = try insertStrengthProgram(into: single.context)
        let beforePlan = single.activities.loadCount
        XCTAssertNotNil(try single.planner.nextPlan(now: now))
        XCTAssertGreaterThan(single.activities.loadCount, beforePlan, "S6 com as cargas das atividades (X5)")
        XCTAssertEqual(single.activities.saveCount, 0, "O planejador nunca grava as atividades")

        // X4: com dois planos, a semana da aba Plano, a conferência do encaixe e a tela Hoje leem as fixas.
        let twoPlans = try makeFixture(settings: PlannerSettings(weekPreferences: WeekPreferences(allowsTwoSessionsPerDay: true)))
        let strength = try insertStrengthProgram(into: twoPlans.context)
        let cardio = try insertCardioProgram(into: twoPlans.context)

        let beforeWeek = twoPlans.activities.loadCount
        _ = try twoPlans.planner.weekSchedule(now: now)
        XCTAssertGreaterThan(twoPlans.activities.loadCount, beforeWeek, "weekSchedule passa as fixas ao encaixe")

        let beforeCheck = twoPlans.activities.loadCount
        _ = try twoPlans.planner.fitCheck(
            programIDs: [strength.program.uuid, cardio.program.uuid],
            preferences: WeekPreferences(allowsTwoSessionsPerDay: true),
            now: now
        )
        XCTAssertGreaterThan(twoPlans.activities.loadCount, beforeCheck, "fitCheck passa as fixas ao encaixe")

        let beforeToday = twoPlans.activities.loadCount
        _ = try twoPlans.planner.todayOverview(now: now)
        XCTAssertGreaterThan(twoPlans.activities.loadCount, beforeToday, "A tela Hoje usa a mesma semana da aba Plano")
        XCTAssertEqual(twoPlans.activities.saveCount, 0)
    }

    func testRF53_activitiesNeverChangeThePrescription() throws {
        // X7: nenhum registro muda a prescrição. O mesmo programa, com e sem atividades, dá o mesmo plano
        // (o S6 só muda o dia escolhido, e com um dia só não há o que escolher).
        let plain = try makeFixture(settings: PlannerSettings(frequencySelector: .on))
        let program = try insertStrengthProgram(into: plain.context)
        let withoutActivities = try XCTUnwrap(try plain.planner.nextPlan(now: now))

        let log = OutsideActivityLog(
            entries: [
                OutsideActivityEntry(kind: .cross, start: now.addingTimeInterval(-20 * 3_600), minutes: 60, intensity: .vigorous),
                OutsideActivityEntry(kind: .spinning, start: now.addingTimeInterval(-10 * 3_600), minutes: 45, intensity: .vigorous),
            ],
            fixed: [
                FixedOutsideActivity(kind: .pilates, weekday: .monday, startMinuteOfDay: 19 * 60, minutes: 50, intensity: .light),
            ]
        )
        let busy = SessionPlanner(
            modelContext: plain.context,
            coordinator: plain.coordinator,
            deloadDecisions: plain.decisions,
            settings: { PlannerSettings(frequencySelector: .on) },
            calendar: calendar,
            saveWeekPreferences: { _ in },
            activities: FakeOutsideActivityStore(log: log)
        )
        let withActivities = try XCTUnwrap(try busy.nextPlan(now: now))

        XCTAssertEqual(withActivities.programDayID, program.day.uuid)
        XCTAssertEqual(
            withActivities.exercises.map(\.prescription),
            withoutActivities.exercises.map(\.prescription)
        )
        XCTAssertEqual(withActivities.isDeload, withoutActivities.isDeload)
    }

    // MARK: - F5: semana leve no aeróbico

    func testF5_deloadPassesCardioFlag() throws {
        let fixture = try makeFixture()
        let program = try insertMixedProgram(into: fixture.context)
        let normal = try XCTUnwrap(try fixture.planner.nextPlan(now: now))
        XCTAssertFalse(normal.isDeload)

        try fixture.planner.requestDeload(now: now)
        let light = try XCTUnwrap(try fixture.planner.nextPlan(now: now))
        XCTAssertTrue(light.isDeload)
        XCTAssertEqual(light.exercises.map(\.exercise.id), [program.bench.uuid, program.walk.uuid])

        // Cada prescrição leve é a do `DeloadPolicy` sobre a normal, com `isCardio` só no aeróbico (SPEC §7.5,
        // F5): o aeróbico encurta os minutos, a força segue como antes.
        for (planned, before) in zip(light.exercises, normal.exercises) {
            let exercise = planned.exercise
            let expected = DeloadPolicy.deloadPrescription(
                from: before.prescription,
                loadIncrement: exercise.loadIncrement,
                isBodyweight: exercise.equipment == .bodyweight,
                isCardio: exercise.movementPattern == .cardio
            )
            XCTAssertEqual(planned.prescription, expected, exercise.name)
        }
        let walkNormal = try XCTUnwrap(normal.exercises.last)
        XCTAssertEqual(walkNormal.exercise.movementPattern, .cardio)
        XCTAssertEqual(
            SessionPlanner.deloadPrescription(from: walkNormal.prescription, exercise: walkNormal.exercise),
            DeloadPolicy.deloadPrescription(
                from: walkNormal.prescription,
                loadIncrement: 2.5,
                isBodyweight: true,
                isCardio: true
            )
        )

        // A revisão recebe as mesmas prescrições leves.
        let review = try XCTUnwrap(try fixture.planner.reviewInput(now: now, recovery: .unknown))
        XCTAssertEqual(review.currentPrescriptions, light.exercises.map(\.prescription))
    }

    // MARK: - R8: a medida vai à revisão

    func testR8_reviewInputPassesMeasure() throws {
        let traits = ExerciseTraitsCatalog(traitsBySlug: [
            "prancha": ExerciseTraits(measure: .seconds, atHome: true),
            "carregada": ExerciseTraits(measure: .steps),
            "brisk-walk": ExerciseTraits(measure: .minutes),
        ])
        let fixture = try makeFixture(traits: traits)
        let context = fixture.context
        let bench = insertExercise(slug: "supino", name: "Supino", primary: [.chest], pattern: .horizontalPush, equipment: .barbell, into: context)
        let plank = insertExercise(slug: "prancha", name: "Prancha", primary: [.core], pattern: .coreStability, equipment: .bodyweight, into: context)
        let carry = insertExercise(slug: "carregada", name: "Carregada", primary: [.core], pattern: .carry, equipment: .dumbbell, into: context)
        let walk = insertExercise(slug: "brisk-walk", name: "Caminhada rápida", primary: [.quads], pattern: .cardio, equipment: .bodyweight, into: context)
        let program = insertProgram(name: "Medidas", goal: .longevity, into: context)
        let day = insertDay("Dia A", order: 0, program: program, into: context)
        insertTarget(order: 0, exercise: bench, sets: 3, repMin: 8, repMax: 12, startingLoad: nil, day: day, into: context)
        insertTarget(order: 1, exercise: plank, sets: 3, repMin: 20, repMax: 40, startingLoad: nil, day: day, into: context)
        insertTarget(order: 2, exercise: carry, sets: 3, repMin: 20, repMax: 30, startingLoad: nil, day: day, into: context)
        insertTarget(order: 3, exercise: walk, sets: 1, repMin: 30, repMax: 45, startingLoad: nil, day: day, into: context)
        try context.save()

        let input = try XCTUnwrap(try fixture.planner.reviewInput(now: now, recovery: .unknown))

        let measures = Dictionary(uniqueKeysWithValues: input.exercises.map { ($0.exercise.slug, $0.measure) })
        XCTAssertEqual(measures, [
            "supino": .reps,
            "prancha": .seconds,
            "carregada": .steps,
            "brisk-walk": .minutes,
        ])
    }

    // MARK: - C1: os números da semana leve

    func testC1_deloadTriggerDetailFollowsStatus() throws {
        // Padrão do protocolo, para doubles e previews: sem números.
        XCTAssertNil(try MinimalPlanner().deloadTriggerDetail(now: now))

        // Sem programa ativo: nada.
        let empty = try makeFixture()
        XCTAssertNil(try empty.planner.deloadTriggerDetail(now: now))

        // Sem semana leve: nada.
        let fixture = try makeFixture(settings: PlannerSettings(deloadWeeks: 1))
        let program = try insertStrengthProgram(into: fixture.context)
        XCTAssertEqual(try fixture.planner.deloadStatus(now: now), .inactive)
        XCTAssertNil(try fixture.planner.deloadTriggerDetail(now: now))

        // §7.5 (b) com N = 1: 8 dias desde a primeira sessão. Os números, quando o motor os dá, são do
        // gatilho do status (o corpo do `triggerDetail` é da tarefa `engine`; no andaime, `nil`).
        insertCompletedSession(day: program.day, exercise: program.bench, startedAt: now.addingTimeInterval(-8 * 86_400), into: fixture.context)
        try fixture.context.save()
        XCTAssertEqual(try fixture.planner.deloadStatus(now: now), .pending(trigger: .scheduled))
        if let detail = try fixture.planner.deloadTriggerDetail(now: now) {
            XCTAssertEqual(detail.trigger, .scheduled)
            XCTAssertEqual(detail.weeksBetweenDeloads, 1)
            XCTAssertFalse(detail.anchorIsLastDeload)
        }

        // O pedido manual não tem números.
        let manual = try makeFixture()
        _ = try insertStrengthProgram(into: manual.context)
        try manual.planner.requestDeload(now: now)
        XCTAssertEqual(try manual.planner.deloadStatus(now: now), .pending(trigger: .manual))
        XCTAssertNil(try manual.planner.deloadTriggerDetail(now: now))
    }

    // MARK: - Fixture

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let coordinator: SessionCoordinator
        let decisions: FakeDeloadDecisionsStore
        let activities: FakeOutsideActivityStore
        let planner: SessionPlanner
    }

    private func makeFixture(
        settings: PlannerSettings = PlannerSettings(),
        traits: ExerciseTraitsCatalog = .empty,
        activities: FakeOutsideActivityStore = FakeOutsideActivityStore()
    ) throws -> Fixture {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let coordinator = SessionCoordinator(modelContext: context, appliedEvents: AppliedEventStore.inMemory())
        let decisions = FakeDeloadDecisionsStore()
        let planner = SessionPlanner(
            modelContext: context,
            coordinator: coordinator,
            deloadDecisions: decisions,
            settings: { settings },
            calendar: calendar,
            traits: traits,
            saveWeekPreferences: { _ in },
            activities: activities
        )
        return Fixture(
            container: container,
            context: context,
            coordinator: coordinator,
            decisions: decisions,
            activities: activities,
            planner: planner
        )
    }

    /// Hipertrofia de um dia: supino (barra, incremento 2,5, carga inicial 40, 3 × 8–12).
    private struct StrengthProgram {
        let program: ProgramModel
        let day: ProgramDayModel
        let bench: ExerciseModel
    }

    private func insertStrengthProgram(into context: ModelContext) throws -> StrengthProgram {
        let bench = insertExercise(slug: "supino", name: "Supino", primary: [.chest], pattern: .horizontalPush, equipment: .barbell, into: context)
        let program = insertProgram(name: "Hipertrofia", goal: .hypertrophy, into: context)
        let day = insertDay("Dia A", order: 0, program: program, into: context)
        insertTarget(order: 0, exercise: bench, sets: 3, repMin: 8, repMax: 12, startingLoad: 40, day: day, into: context)
        try context.save()
        return StrengthProgram(program: program, day: day, bench: bench)
    }

    /// Cardio de dois dias: caminhada 1 × 30–45 min e intervalos 4 × 3–4 min.
    private struct CardioProgram {
        let program: ProgramModel
    }

    private func insertCardioProgram(into context: ModelContext) throws -> CardioProgram {
        let walk = insertExercise(slug: "brisk-walk", name: "Caminhada rápida", primary: [.quads, .glutes], pattern: .cardio, equipment: .bodyweight, into: context)
        let intervals = insertExercise(slug: "run-intervals", name: "Intervalos de corrida", primary: [.quads, .glutes], pattern: .cardio, equipment: .bodyweight, into: context)
        let program = insertProgram(name: "Cardio", goal: .endurance, into: context)
        let dayA = insertDay("Dia A", order: 0, program: program, into: context)
        insertTarget(order: 0, exercise: walk, sets: 1, repMin: 30, repMax: 45, startingLoad: nil, day: dayA, into: context)
        let dayB = insertDay("Dia B", order: 1, program: program, into: context)
        insertTarget(order: 0, exercise: intervals, sets: 4, repMin: 3, repMax: 4, startingLoad: nil, day: dayB, into: context)
        try context.save()
        return CardioProgram(program: program)
    }

    /// Um dia com força e aeróbico: supino (carga inicial 40) e caminhada 1 × 30–45 min.
    private struct MixedProgram {
        let program: ProgramModel
        let bench: ExerciseModel
        let walk: ExerciseModel
    }

    private func insertMixedProgram(into context: ModelContext) throws -> MixedProgram {
        let bench = insertExercise(slug: "supino", name: "Supino", primary: [.chest], pattern: .horizontalPush, equipment: .barbell, into: context)
        let walk = insertExercise(slug: "brisk-walk", name: "Caminhada rápida", primary: [.quads, .glutes], pattern: .cardio, equipment: .bodyweight, into: context)
        let program = insertProgram(name: "Misto", goal: .longevity, into: context)
        let day = insertDay("Dia A", order: 0, program: program, into: context)
        insertTarget(order: 0, exercise: bench, sets: 3, repMin: 8, repMax: 12, startingLoad: 40, day: day, into: context)
        insertTarget(order: 1, exercise: walk, sets: 1, repMin: 30, repMax: 45, startingLoad: nil, day: day, into: context)
        try context.save()
        return MixedProgram(program: program, bench: bench, walk: walk)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date(timeIntervalSince1970: 0)
    }

    private func insertExercise(
        slug: String,
        name: String,
        primary: [MuscleGroup],
        pattern: MovementPattern,
        equipment: Equipment,
        into context: ModelContext
    ) -> ExerciseModel {
        let model = ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: name,
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups(primary),
            secondaryMusclesRaw: "",
            equipmentRaw: equipment.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 2.5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        model.movementPatternRaw = pattern.rawValue
        context.insert(model)
        return model
    }

    private func insertProgram(name: String, goal: ProgramGoal, into context: ModelContext) -> ProgramModel {
        let model = ProgramModel(
            uuid: UUID(),
            name: name,
            isActive: true,
            createdAt: date(2026, 8, 1),
            goalRaw: goal.rawValue
        )
        context.insert(model)
        return model
    }

    private func insertDay(_ name: String, order: Int, program: ProgramModel, into context: ModelContext) -> ProgramDayModel {
        let model = ProgramDayModel(uuid: UUID(), name: name, order: order)
        context.insert(model)
        program.days.append(model)
        return model
    }

    private func insertTarget(
        order: Int,
        exercise: ExerciseModel,
        sets: Int,
        repMin: Int,
        repMax: Int,
        startingLoad: Double?,
        day: ProgramDayModel,
        into context: ModelContext
    ) {
        let model = ProgramExerciseModel(
            uuid: UUID(),
            order: order,
            sets: sets,
            repMin: repMin,
            repMax: repMax,
            targetRIR: 2,
            restSeconds: 90,
            startingLoad: startingLoad
        )
        context.insert(model)
        model.exercise = exercise
        day.exercises.append(model)
    }

    /// Sessão concluída com 3 × 10 a 40 kg, ligada ao catálogo.
    private func insertCompletedSession(
        day: ProgramDayModel,
        exercise: ExerciseModel,
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
        let entry = SessionExerciseModel(
            uuid: UUID(),
            order: 0,
            exerciseUUID: exercise.uuid,
            exerciseName: exercise.name,
            prescribedLoad: 40,
            prescribedSets: 3,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: 2,
            restSeconds: 90,
            noteRaw: PrescriptionNote.hold.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(entry)
        entry.exercise = exercise
        session.exercises.append(entry)
        for index in 0..<3 {
            let completedAt = startedAt.addingTimeInterval(Double(index + 1) * 120)
            let set = SetLogModel(
                uuid: UUID(),
                index: index,
                load: 40,
                reps: 10,
                rir: 2,
                isWarmup: false,
                completedAt: completedAt,
                sourceRaw: DeviceSource.iphone.rawValue,
                updatedAt: completedAt
            )
            context.insert(set)
            entry.sets.append(set)
        }
    }
}

/// `SessionPlanning` só com o obrigatório, para conferir os padrões do protocolo.
@MainActor
private final class MinimalPlanner: SessionPlanning {
    func nextPlan(now: Date) throws -> SessionPlan? {
        nil
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        nil
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        UUID()
    }
}
