import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Vários planos no `SessionPlanner` (SPEC §7.15 M1–M9, §7.3 S8, §7.16 W2; docs/V23-UI-CONTRACT.md §4.5), sobre
/// container em memória, no calendário UTC. A semana do teste vai de segunda 2026-09-28 a domingo 2026-10-04.
///
/// O Equilibrado do teste tem um exercício por dia (A peito, B quadríceps, C costas, D posteriores) e o Cardio
/// tem o do seed (A caminhada 1 × 30–45, B intervalos 4 × 3–4, C bicicleta 1 × 45–75). Com 2 por dia aceito e
/// de segunda a sábado, a semana ideal (conferida com a implementação de referência de `WeeklyFitTests`) é:
/// seg A + Cardio A, ter B, qua Cardio B, qui C, sex Cardio C, sáb D; domingo livre.
@MainActor
final class SessionPlannerMultiPlanTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private let twoPerDay = WeekPreferences(allowsTwoSessionsPerDay: true)

    // MARK: - M1 e M2

    func testM1_activePlans_principalFirst() throws {
        let fixture = try makeFixture()

        XCTAssertEqual(try fixture.planner.activeProgramGoals(), [.hypertrophy, .endurance])
        XCTAssertEqual(try fixture.planner.activeProgramGoal(), .hypertrophy)
        XCTAssertEqual(
            try fixture.planner.activeProgramDays().map(\.name),
            ["Dia A — Superior", "Dia B — Inferior", "Dia C — Superior", "Dia D — Inferior"]
        )
        XCTAssertEqual(
            try fixture.planner.days(ofProgramID: fixture.cardio.uuid).map(\.name),
            ["Dia A — Base contínua", "Dia B — Intervalos 4 × 4", "Dia C — Longo e leve"]
        )
        XCTAssertEqual(try fixture.planner.days(ofProgramID: UUID()), [])
    }

    func testS8_eachPlanKeepsItsRotation() throws {
        let fixture = try makeFixture()
        insertSession(.completed, day: fixture.hypertrophyDays[0], exercise: fixture.bench, startedAt: date(2026, 9, 21), into: fixture.context)
        insertSession(.completed, day: fixture.cardioDays[0], exercise: fixture.walk, startedAt: date(2026, 9, 22), into: fixture.context)
        insertSession(.completed, day: fixture.hypertrophyDays[1], exercise: fixture.squat, startedAt: date(2026, 9, 23), into: fixture.context)
        try fixture.context.save()
        let now = date(2026, 9, 28)

        // S2 de cada plano só com as sessões dos dias dele: a última sessão (Dia B da Hipertrofia) não
        // faz o Cardio recomeçar no Dia A.
        let hypertrophy = try XCTUnwrap(fixture.planner.nextPlan(forProgramID: fixture.hypertrophy.uuid, now: now))
        XCTAssertEqual(hypertrophy.programDayID, fixture.hypertrophyDays[2].uuid)
        XCTAssertEqual(hypertrophy.reason, .rotation)
        let cardio = try XCTUnwrap(fixture.planner.nextPlan(forProgramID: fixture.cardio.uuid, now: now))
        XCTAssertEqual(cardio.programDayID, fixture.cardioDays[1].uuid)
        XCTAssertNil(try fixture.planner.nextPlan(forProgramID: UUID(), now: now))

        // S4: o dia escolhido pode ser do segundo plano.
        let manual = try XCTUnwrap(fixture.planner.plan(forDayID: fixture.cardioDays[2].uuid, now: now))
        XCTAssertEqual(manual.programID, fixture.cardio.uuid)
        XCTAssertEqual(manual.programDayID, fixture.cardioDays[2].uuid)
        XCTAssertEqual(manual.reason, .manual)
        XCTAssertFalse(manual.isDeload)
    }

    func testM2_deloadAndReviewUsePrincipal() throws {
        let fixture = try makeFixture()
        let deloadStart = date(2026, 9, 21)
        insertSession(.completed, day: fixture.hypertrophyDays[0], exercise: fixture.bench, startedAt: deloadStart, isDeload: true, into: fixture.context)
        insertSession(.completed, day: fixture.cardioDays[0], exercise: fixture.walk, startedAt: date(2026, 9, 22), into: fixture.context)
        insertSession(.completed, day: fixture.hypertrophyDays[1], exercise: fixture.squat, startedAt: date(2026, 9, 23), isDeload: true, into: fixture.context)
        try fixture.context.save()
        let now = date(2026, 9, 28)

        // A semana leve é do principal e olha só os dias dele: o Cardio normal no meio não parte a
        // passagem em duas.
        XCTAssertEqual(try fixture.planner.deloadStatus(now: now), .active(start: deloadStart))
        XCTAssertEqual(try fixture.planner.nextPlan(forProgramID: fixture.hypertrophy.uuid, now: now)?.isDeload, true)
        XCTAssertEqual(try fixture.planner.nextPlan(forProgramID: fixture.cardio.uuid, now: now)?.isDeload, false)
        XCTAssertEqual(try fixture.planner.plan(forDayID: fixture.hypertrophyDays[3].uuid, now: now)?.isDeload, true)
        XCTAssertEqual(try fixture.planner.plan(forDayID: fixture.cardioDays[1].uuid, now: now)?.isDeload, false)

        let review = try XCTUnwrap(fixture.planner.reviewInput(now: now, recovery: .unknown))
        XCTAssertEqual(review.programID, fixture.hypertrophy.uuid)
        let hypertrophyDayIDs = Set(fixture.hypertrophyDays.map(\.uuid))
        XCTAssertEqual(review.sessions.count, 2)
        XCTAssertTrue(review.sessions.allSatisfy { hypertrophyDayIDs.contains($0.programDayID) })
    }

    // MARK: - M3 e M4

    func testM3_phaseFromWeekStart() throws {
        let fixture = try makeFixture(preferences: twoPerDay)
        insertSession(.completed, day: fixture.hypertrophyDays[0], exercise: fixture.bench, startedAt: date(2026, 9, 21), into: fixture.context)
        insertSession(.completed, day: fixture.hypertrophyDays[1], exercise: fixture.squat, startedAt: date(2026, 9, 22), into: fixture.context)
        insertSession(.completed, day: fixture.cardioDays[0], exercise: fixture.walk, startedAt: date(2026, 9, 23), into: fixture.context)
        // Depois de segunda 00:00: não muda a fase desta semana.
        insertSession(.completed, day: fixture.hypertrophyDays[2], exercise: fixture.row, startedAt: date(2026, 9, 28, hour: 8), into: fixture.context)
        try fixture.context.save()

        let schedule = try XCTUnwrap(fixture.planner.weekSchedule(now: date(2026, 9, 28)))

        let rows = schedule.slots.map { SlotRow(weekday: $0.weekday, dayName: $0.dayName) }
        XCTAssertEqual(rows, [
            SlotRow(weekday: .monday, dayName: "Dia C — Superior"),
            SlotRow(weekday: .tuesday, dayName: "Dia D — Inferior"),
            SlotRow(weekday: .tuesday, dayName: "Dia B — Intervalos 4 × 4"),
            SlotRow(weekday: .wednesday, dayName: "Dia C — Longo e leve"),
            SlotRow(weekday: .thursday, dayName: "Dia A — Superior"),
            SlotRow(weekday: .friday, dayName: "Dia A — Base contínua"),
            SlotRow(weekday: .saturday, dayName: "Dia B — Inferior"),
        ])
        XCTAssertEqual(schedule.slots.first?.programDayID, fixture.hypertrophyDays[2].uuid)
        XCTAssertEqual(schedule.slots(on: .tuesday).map(\.cardioIntensity), [nil, .vigorous])
        XCTAssertEqual(schedule.notes, [.strengthBeforeCardio(.tuesday)])
    }

    func testM4_fitCheckWithTheCandidateAndNoWeekWithOnePlan() throws {
        let fixture = try makeFixture(cardioIsActive: false)
        let now = date(2026, 9, 28)

        XCTAssertNil(try fixture.planner.weekSchedule(now: now), "Com um plano só, não há encaixe")
        let result = try fixture.planner.fitCheck(
            programIDs: [fixture.cardio.uuid, fixture.hypertrophy.uuid],
            preferences: twoPerDay,
            now: now
        )
        let schedule = try XCTUnwrap(result.schedule)
        XCTAssertEqual(schedule.slots.count, 7)
        XCTAssertEqual(schedule.slots(on: .monday).map(\.programID), [fixture.hypertrophy.uuid, fixture.cardio.uuid])
        XCTAssertEqual(schedule.restDays, [.sunday])

        let tooTight = try fixture.planner.fitCheck(
            programIDs: [fixture.hypertrophy.uuid, fixture.cardio.uuid],
            preferences: WeekPreferences(),
            now: now
        )
        XCTAssertEqual(tooTight.problems, [.notEnoughDays(needed: 7, available: 6)])
        XCTAssertEqual(tooTight.alternatives.first?.changes, [.addDays([.sunday])])

        // Com um plano só, a tela Hoje é a da 2.2.
        let overview = try fixture.planner.todayOverview(now: now)
        XCTAssertEqual(overview.sessions.map(\.id), [fixture.hypertrophy.uuid])
        XCTAssertEqual(overview.sessions.first?.isDoneToday, false)
        XCTAssertTrue(overview.otherSessions.isEmpty)
    }

    // MARK: - M6

    func testM6_todayOverview_twoPlans() throws {
        let fixture = try makeFixture(preferences: twoPerDay)

        let monday = try fixture.planner.todayOverview(now: date(2026, 9, 28))
        XCTAssertEqual(monday.sessions.map(\.plan.programDayID), [fixture.hypertrophyDays[0].uuid, fixture.cardioDays[0].uuid])
        XCTAssertEqual(monday.sessions.map(\.goal), [.hypertrophy, .endurance])
        XCTAssertEqual(monday.sessions.map(\.isDoneToday), [false, false])
        XCTAssertTrue(monday.otherSessions.isEmpty)
        XCTAssertFalse(monday.isRestDay)
        XCTAssertTrue(monday.fitsWeek)
        XCTAssertEqual(try fixture.planner.nextPlan(now: date(2026, 9, 28))?.programDayID, fixture.hypertrophyDays[0].uuid)

        // Quarta: só o Cardio tem lugar; a próxima da Hipertrofia fica para "Treinar mesmo assim".
        let wednesday = try fixture.planner.todayOverview(now: date(2026, 9, 30))
        XCTAssertEqual(wednesday.sessions.map(\.id), [fixture.cardio.uuid])
        XCTAssertEqual(wednesday.otherSessions.map(\.id), [fixture.hypertrophy.uuid])
        XCTAssertFalse(wednesday.isRestDay)
        XCTAssertEqual(try fixture.planner.nextPlan(now: date(2026, 9, 30))?.programID, fixture.cardio.uuid)
    }

    func testM6_todayOverview_restDay() throws {
        let fixture = try makeFixture(preferences: twoPerDay)
        let sunday = date(2026, 10, 4)

        let overview = try fixture.planner.todayOverview(now: sunday)

        XCTAssertTrue(overview.isRestDay)
        XCTAssertTrue(overview.sessions.isEmpty)
        XCTAssertEqual(overview.otherSessions.map(\.id), [fixture.hypertrophy.uuid, fixture.cardio.uuid])
        XCTAssertTrue(overview.fitsWeek)
        XCTAssertNil(overview.nextPending)
        XCTAssertEqual(try fixture.planner.nextPlan(now: sunday)?.programID, fixture.hypertrophy.uuid)
    }

    func testM6_todayOverview_doneToday() throws {
        let fixture = try makeFixture(preferences: twoPerDay)
        let now = date(2026, 9, 28)
        insertSession(.completed, day: fixture.hypertrophyDays[0], exercise: fixture.bench, startedAt: date(2026, 9, 28, hour: 8), into: fixture.context)
        try fixture.context.save()

        let overview = try fixture.planner.todayOverview(now: now)
        XCTAssertEqual(overview.sessions.map(\.id), [fixture.hypertrophy.uuid, fixture.cardio.uuid])
        XCTAssertEqual(overview.sessions.map(\.isDoneToday), [true, false])
        // A próxima da rotação do plano feito já é a seguinte (S8).
        XCTAssertEqual(overview.sessions.first?.plan.programDayID, fixture.hypertrophyDays[1].uuid)
        XCTAssertEqual(overview.nextPending?.id, fixture.cardio.uuid)
        XCTAssertEqual(try fixture.planner.nextPlan(now: now)?.programDayID, fixture.cardioDays[0].uuid)

        // Abandonada com série também conta como feita; com tudo feito, vale a próxima do principal.
        insertSession(.abandoned, day: fixture.cardioDays[0], exercise: fixture.walk, startedAt: date(2026, 9, 28, hour: 9), into: fixture.context)
        try fixture.context.save()
        let allDone = try fixture.planner.todayOverview(now: now)
        XCTAssertEqual(allDone.sessions.map(\.isDoneToday), [true, true])
        XCTAssertNil(allDone.nextPending)
        XCTAssertEqual(try fixture.planner.nextPlan(now: now)?.programDayID, fixture.hypertrophyDays[1].uuid)
    }

    func testM6_todayOverview_doesNotFitFallsBackToPrincipal() throws {
        // Sem 2 por dia: 7 sessões para 6 dias.
        let fixture = try makeFixture(preferences: WeekPreferences())
        let now = date(2026, 9, 30)

        let overview = try fixture.planner.todayOverview(now: now)

        XCTAssertFalse(overview.fitsWeek)
        XCTAssertFalse(overview.isRestDay)
        XCTAssertEqual(overview.sessions.map(\.id), [fixture.hypertrophy.uuid])
        XCTAssertEqual(overview.otherSessions.map(\.id), [fixture.cardio.uuid])
        XCTAssertNil(try fixture.planner.weekSchedule(now: now))
        XCTAssertEqual(try fixture.planner.nextPlan(now: now)?.programID, fixture.hypertrophy.uuid)
    }

    /// RF-49: com um plano só, o Início também sabe que a sessão de hoje já foi feita ("Tudo feito por
    /// hoje."). Ontem não conta, nem sessão sem série de trabalho, nem a de um plano inativo.
    func testRF49_todayOverview_singlePlanDoneToday() throws {
        let fixture = try makeFixture(cardioIsActive: false)
        let now = date(2026, 9, 28)
        insertSession(.completed, day: fixture.hypertrophyDays[0], exercise: fixture.bench, startedAt: date(2026, 9, 27), into: fixture.context)
        insertSession(.completed, day: fixture.hypertrophyDays[1], exercise: fixture.squat, startedAt: date(2026, 9, 28, hour: 7), workingSets: 0, into: fixture.context)
        insertSession(.completed, day: fixture.cardioDays[0], exercise: fixture.walk, startedAt: date(2026, 9, 28, hour: 8), into: fixture.context)
        try fixture.context.save()

        let notYet = try fixture.planner.todayOverview(now: now)
        XCTAssertEqual(notYet.sessions.map(\.id), [fixture.hypertrophy.uuid])
        XCTAssertEqual(notYet.sessions.map(\.isDoneToday), [false])

        insertSession(.completed, day: fixture.hypertrophyDays[1], exercise: fixture.squat, startedAt: date(2026, 9, 28, hour: 9), into: fixture.context)
        try fixture.context.save()

        let done = try fixture.planner.todayOverview(now: now)
        XCTAssertEqual(done.sessions.map(\.id), [fixture.hypertrophy.uuid])
        XCTAssertEqual(done.sessions.map(\.isDoneToday), [true])
        XCTAssertNil(done.nextPending)
        XCTAssertTrue(done.otherSessions.isEmpty)
        XCTAssertFalse(done.isRestDay)
    }

    // MARK: - M9

    func testM9_weekPreferencesRoundTrip() throws {
        let suiteName = "SessionPlannerMultiPlanTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let fixture = try makeFixture(defaults: defaults)

        XCTAssertEqual(fixture.planner.weekPreferences(), .default, "Ausente vale o padrão")
        defaults.set(Data("isto não é JSON".utf8), forKey: PlannerSettings.weekPreferencesKey)
        XCTAssertEqual(fixture.planner.weekPreferences(), .default, "Ilegível vale o padrão")

        let stranger = UUID()
        let chosen = WeekPreferences(
            availableDays: [.monday, .wednesday, .friday, .sunday],
            allowsTwoSessionsPerDay: true,
            allowsLightCardioAfterStrength: true,
            sessionsPerWeek: [fixture.cardio.uuid: 2, stranger: 1]
        )
        try fixture.planner.saveWeekPreferences(chosen)

        // Gravado como veio (o fluxo de adicionar grava antes de ativar); lido sem os planos que não estão ativos.
        XCTAssertEqual(PlannerSettings.loadWeekPreferences(from: defaults), chosen)
        let read = fixture.planner.weekPreferences()
        XCTAssertEqual(read.availableDays, chosen.availableDays)
        XCTAssertTrue(read.allowsTwoSessionsPerDay)
        XCTAssertTrue(read.allowsLightCardioAfterStrength)
        XCTAssertEqual(read.sessionsPerWeek, [fixture.cardio.uuid: 2])
    }

    // MARK: - W2

    func testW2_planWeekProgress_twoPlans() throws {
        let fixture = try makeFixture()
        // "Menos sessões" no Cardio: 2 por semana (M3).
        let planner = makePlanner(fixture, preferences: WeekPreferences(sessionsPerWeek: [fixture.cardio.uuid: 2]))
        insertSession(.completed, day: fixture.hypertrophyDays[0], exercise: fixture.bench, startedAt: date(2026, 9, 28), into: fixture.context)
        insertSession(.abandoned, day: fixture.hypertrophyDays[1], exercise: fixture.squat, startedAt: date(2026, 9, 29), into: fixture.context)
        insertSession(.completed, day: fixture.hypertrophyDays[2], exercise: fixture.row, startedAt: date(2026, 9, 30), workingSets: 0, warmups: 1, into: fixture.context)
        insertSession(.completed, day: fixture.cardioDays[0], exercise: fixture.walk, startedAt: date(2026, 9, 29), into: fixture.context)
        // Domingo da semana anterior: fora.
        insertSession(.completed, day: fixture.cardioDays[1], exercise: fixture.intervals, startedAt: date(2026, 9, 27), into: fixture.context)
        try fixture.context.save()

        let progress = try planner.planWeekProgress(now: date(2026, 10, 1))

        XCTAssertEqual(progress, [
            PlanWeekProgress(programID: fixture.hypertrophy.uuid, goal: .hypertrophy, completed: 1, perWeek: 4),
            PlanWeekProgress(programID: fixture.cardio.uuid, goal: .endurance, completed: 1, perWeek: 2),
        ])
    }

    func testW2_weeklyFrequencyUsesSettingsTargets() throws {
        let fixture = try makeFixture()
        let settings = UserSettingsModel(
            uuid: UUID(),
            weekStartsOnMonday: false,
            weeklyTargetsRaw: "{\"chest\":3}",
            healthKitEnabled: false,
            defaultRestSeconds: 120,
            schemaSeedVersion: 4
        )
        fixture.context.insert(settings)
        // Semana começando no domingo 2026-09-27: as duas sessões contam, uma de cada plano.
        insertSession(.completed, day: fixture.hypertrophyDays[0], exercise: fixture.bench, startedAt: date(2026, 9, 27, hour: 10), into: fixture.context)
        insertSession(.completed, day: fixture.cardioDays[0], exercise: fixture.walk, startedAt: date(2026, 9, 29), into: fixture.context)
        insertSession(.completed, day: fixture.hypertrophyDays[1], exercise: fixture.squat, startedAt: date(2026, 9, 26), into: fixture.context)
        try fixture.context.save()

        let report = try fixture.planner.weeklyFrequency(now: date(2026, 10, 1))

        XCTAssertEqual(report.weekStart, date(2026, 9, 27, hour: 0))
        let chest = try XCTUnwrap(report.entries.first { $0.muscle == .chest })
        XCTAssertEqual(chest.completed, 1)
        XCTAssertEqual(chest.target, 3)
        let quads = try XCTUnwrap(report.entries.first { $0.muscle == .quads })
        XCTAssertEqual(quads.completed, 1, "O aeróbico do Cardio conta para as pernas; o sábado anterior fica fora")
        XCTAssertEqual(quads.target, 2)
    }

    // MARK: - Fixture

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let planner: SessionPlanner
        let deloads: FakeDeloadDecisionsStore
        let hypertrophy: ProgramModel
        /// A (peito), B (quadríceps), C (costas), D (posteriores).
        let hypertrophyDays: [ProgramDayModel]
        let cardio: ProgramModel
        /// A (caminhada), B (intervalos de corrida), C (bicicleta).
        let cardioDays: [ProgramDayModel]
        let bench: ExerciseModel
        let squat: ExerciseModel
        let row: ExerciseModel
        let legCurl: ExerciseModel
        let walk: ExerciseModel
        let intervals: ExerciseModel
        let bike: ExerciseModel
    }

    private struct SlotRow: Equatable {
        let weekday: PlanWeekday
        let dayName: String
    }

    private func makeFixture(
        preferences: WeekPreferences = WeekPreferences(),
        cardioIsActive: Bool = true,
        defaults: UserDefaults? = nil
    ) throws -> Fixture {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext

        let bench = insertExercise(slug: "supino", name: "Supino", primary: [.chest], pattern: .horizontalPush, into: context)
        let squat = insertExercise(slug: "agachamento", name: "Agachamento", primary: [.quads], pattern: .squat, into: context)
        let row = insertExercise(slug: "remada", name: "Remada", primary: [.back], pattern: .horizontalPull, into: context)
        let legCurl = insertExercise(slug: "flexora", name: "Mesa flexora", primary: [.hamstrings], pattern: .kneeFlexion, into: context)
        let walk = insertExercise(slug: "brisk-walk", name: "Caminhada rápida", primary: [.quads, .glutes], pattern: .cardio, into: context)
        let intervals = insertExercise(slug: "run-intervals", name: "Intervalos de corrida", primary: [.quads, .glutes], pattern: .cardio, into: context)
        let bike = insertExercise(slug: "stationary-bike", name: "Bicicleta ergométrica", primary: [.quads, .glutes], pattern: .cardio, into: context)

        let hypertrophy = ProgramModel(
            uuid: UUID(),
            name: "Hipertrofia — Equilibrado",
            isActive: true,
            createdAt: date(2026, 8, 1),
            goalRaw: ProgramGoal.hypertrophy.rawValue
        )
        context.insert(hypertrophy)
        let hypertrophyDays = [
            insertDay("Dia A — Superior", order: 0, exercise: bench, sets: 3, repMin: 8, repMax: 12, rest: 90, program: hypertrophy, into: context),
            insertDay("Dia B — Inferior", order: 1, exercise: squat, sets: 3, repMin: 8, repMax: 12, rest: 90, program: hypertrophy, into: context),
            insertDay("Dia C — Superior", order: 2, exercise: row, sets: 3, repMin: 8, repMax: 12, rest: 90, program: hypertrophy, into: context),
            insertDay("Dia D — Inferior", order: 3, exercise: legCurl, sets: 3, repMin: 8, repMax: 12, rest: 90, program: hypertrophy, into: context),
        ]

        // O Cardio é o mais antigo: o principal sai do objetivo, não da data (M1).
        let cardio = ProgramModel(
            uuid: UUID(),
            name: "Cardio",
            isActive: cardioIsActive,
            createdAt: date(2026, 7, 1),
            goalRaw: ProgramGoal.endurance.rawValue
        )
        context.insert(cardio)
        let cardioDays = [
            insertDay("Dia A — Base contínua", order: 0, exercise: walk, sets: 1, repMin: 30, repMax: 45, rest: 60, program: cardio, into: context),
            insertDay("Dia B — Intervalos 4 × 4", order: 1, exercise: intervals, sets: 4, repMin: 3, repMax: 4, rest: 180, program: cardio, into: context),
            insertDay("Dia C — Longo e leve", order: 2, exercise: bike, sets: 1, repMin: 45, repMax: 75, rest: 60, program: cardio, into: context),
        ]
        try context.save()

        let deloads = FakeDeloadDecisionsStore()
        let planner: SessionPlanner
        if let defaults {
            planner = SessionPlanner(
                modelContext: context,
                coordinator: MultiPlanTestCoordinator(),
                deloadDecisions: deloads,
                settings: { PlannerSettings.load(from: defaults) },
                calendar: calendar,
                saveWeekPreferences: { preferences in
                    try PlannerSettings.saveWeekPreferences(preferences, to: defaults)
                }
            )
        } else {
            planner = SessionPlanner(
                modelContext: context,
                coordinator: MultiPlanTestCoordinator(),
                deloadDecisions: deloads,
                settings: { PlannerSettings(weekPreferences: preferences) },
                calendar: calendar,
                saveWeekPreferences: { _ in }
            )
        }
        return Fixture(
            container: container,
            context: context,
            planner: planner,
            deloads: deloads,
            hypertrophy: hypertrophy,
            hypertrophyDays: hypertrophyDays,
            cardio: cardio,
            cardioDays: cardioDays,
            bench: bench,
            squat: squat,
            row: row,
            legCurl: legCurl,
            walk: walk,
            intervals: intervals,
            bike: bike
        )
    }

    /// Outro planejador sobre o mesmo store, com outras escolhas da semana.
    private func makePlanner(_ fixture: Fixture, preferences: WeekPreferences) -> SessionPlanner {
        SessionPlanner(
            modelContext: fixture.context,
            coordinator: MultiPlanTestCoordinator(),
            deloadDecisions: fixture.deloads,
            settings: { PlannerSettings(weekPreferences: preferences) },
            calendar: calendar,
            saveWeekPreferences: { _ in }
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date(timeIntervalSince1970: 0)
    }

    private func insertExercise(
        slug: String,
        name: String,
        primary: [MuscleGroup],
        pattern: MovementPattern,
        into context: ModelContext
    ) -> ExerciseModel {
        let model = ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: name,
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups(primary),
            secondaryMusclesRaw: "",
            equipmentRaw: Equipment.bodyweight.rawValue,
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

    /// Um dia com um exercício só.
    private func insertDay(
        _ name: String,
        order: Int,
        exercise: ExerciseModel,
        sets: Int,
        repMin: Int,
        repMax: Int,
        rest: Int,
        program: ProgramModel,
        into context: ModelContext
    ) -> ProgramDayModel {
        let day = ProgramDayModel(uuid: UUID(), name: name, order: order)
        context.insert(day)
        program.days.append(day)
        let target = ProgramExerciseModel(
            uuid: UUID(),
            order: 0,
            sets: sets,
            repMin: repMin,
            repMax: repMax,
            targetRIR: 2,
            restSeconds: rest,
            startingLoad: nil
        )
        context.insert(target)
        target.exercise = exercise
        day.exercises.append(target)
        return day
    }

    /// Uma sessão de um dia com `workingSets` séries de trabalho e `warmups` aquecimentos.
    @discardableResult
    private func insertSession(
        _ status: SessionStatus,
        day: ProgramDayModel,
        exercise: ExerciseModel,
        startedAt: Date,
        isDeload: Bool = false,
        workingSets: Int = 1,
        warmups: Int = 0,
        into context: ModelContext
    ) -> WorkoutSessionModel {
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: day.uuid,
            programDayName: day.name,
            statusRaw: status.rawValue,
            startedAt: startedAt,
            endedAt: status == .inProgress ? nil : startedAt.addingTimeInterval(3_600),
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: isDeload,
            sourceRaw: DeviceSource.iphone.rawValue
        )
        context.insert(session)
        let entry = SessionExerciseModel(
            uuid: UUID(),
            order: 0,
            exerciseUUID: exercise.uuid,
            exerciseName: exercise.name,
            prescribedLoad: nil,
            prescribedSets: 3,
            prescribedRepMin: 8,
            prescribedRepMax: 12,
            prescribedRIR: 2,
            restSeconds: 90,
            noteRaw: PrescriptionNote.calibrate.rawValue,
            wasSkipped: false,
            substitutedFromUUID: nil
        )
        context.insert(entry)
        entry.exercise = exercise
        session.exercises.append(entry)
        let total = max(0, warmups) + max(0, workingSets)
        for index in 0..<total {
            let set = SetLogModel(
                uuid: UUID(),
                index: index,
                load: 0,
                reps: 10,
                rir: nil,
                isWarmup: index < warmups,
                completedAt: startedAt.addingTimeInterval(Double(index + 1) * 120),
                sourceRaw: DeviceSource.iphone.rawValue,
                updatedAt: startedAt
            )
            context.insert(set)
            entry.sets.append(set)
        }
        return session
    }
}

// MARK: - Double do coordinator

/// Nunca toca o `ModelContext`: o planejador só lê.
@MainActor
private final class MultiPlanTestCoordinator: SessionCoordinating {
    var activeSession: WorkoutSessionModel?

    func session(withID id: UUID) -> WorkoutSessionModel? {
        nil
    }

    func startSession(plan: SessionPlan, now: Date, source: DeviceSource) throws -> UUID {
        UUID()
    }

    func apply(_ event: SessionEvent) throws {}

    var eventsApplied: AsyncStream<SessionEvent> {
        AsyncStream<SessionEvent> { continuation in
            continuation.finish()
        }
    }
}
