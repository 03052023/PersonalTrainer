import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T9.6, SPEC RF-01 e §7.15 M6: a tela Hoje com dois planos. Um cartão por sessão de `todayOverview`, a
/// força antes do aeróbico, "Começar" na primeira pendente, "Feito hoje" com "A seguir", o dia de
/// descanso com "Treinar mesmo assim" e a faixa de quando os planos não cabem. Com um plano só, tudo
/// como na 2.2. O planejador de teste devolve `TodayOverview` prontos.
@MainActor
final class HomeMultiPlanTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let hypertrophyID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001") ?? UUID()
    private let cardioID = UUID(uuidString: "00000000-0000-0000-0000-00000000B002") ?? UUID()

    // MARK: - Duas sessões hoje

    func testM6_today_twoSessions_orderAndPrimaryButton() {
        let strength = makeStrengthPlan(dayName: "Dia A — Superior")
        let cardio = makeCardioPlan()
        let planner = MultiPlanTestPlanner(overview: TodayOverview(sessions: [
            TodaySession(plan: strength, goal: .hypertrophy, isDoneToday: false),
            TodaySession(plan: cardio, goal: .endurance, isDoneToday: false),
        ]))
        let model = makeModel(planner)

        model.refresh()

        XCTAssertTrue(model.isMultiPlan)
        XCTAssertEqual(model.headerGoals, [.hypertrophy, .endurance])
        XCTAssertEqual(model.todayCards.map(\.id), [hypertrophyID, cardioID], "A força antes do aeróbico")
        XCTAssertEqual(model.primaryCard?.id, hypertrophyID, "Começar abre a primeira pendente")
        XCTAssertEqual(model.todayCards.map(\.isPrimary), [true, false])
        XCTAssertEqual(model.todayCards.map(\.isStartable), [true, true], "O segundo tem \"Começar esta\"")
        XCTAssertEqual(model.todayLine, "Hoje: Superior + Cardio moderado 30 min")
        XCTAssertEqual(model.spokenTodayLine, "Hoje: Superior e Cardio moderado, 30 minutos")
        XCTAssertEqual(TodayPlansText.detailText(for: cardio), "30 min", "No cardio, os minutos")
        XCTAssertFalse(model.isRestDay)
        XCTAssertFalse(model.showsTrainAnyway)
        XCTAssertFalse(model.showsNotFitBanner)
        XCTAssertEqual(model.plan, strength, "O \"Começar\" do diálogo (C5) começa a mesma")
        XCTAssertEqual(planner.nextPlanCalls, 0, "Com dois planos, a tela lê o dia de hoje (M6)")
        XCTAssertEqual(planner.overviewDates, [now], "Relógio injetado (SPEC P11)")

        XCTAssertEqual(model.startSession(), planner.sessionIDToReturn)
        XCTAssertEqual(planner.startedPlans, [strength])
    }

    func testM6_today_startThis_startsTheSecondPlan() {
        let strength = makeStrengthPlan(dayName: "Dia A — Superior")
        let cardio = makeCardioPlan()
        let planner = MultiPlanTestPlanner(overview: TodayOverview(sessions: [
            TodaySession(plan: strength, goal: .hypertrophy, isDoneToday: false),
            TodaySession(plan: cardio, goal: .endurance, isDoneToday: false),
        ]))
        let model = makeModel(planner)
        model.refresh()

        XCTAssertEqual(model.startSession(programID: cardioID), planner.sessionIDToReturn)
        XCTAssertEqual(planner.startedPlans, [cardio], "\"Começar esta\" começa o cartão tocado")
    }

    func testC5_startPrincipalSession_startsWhatTheMessageNames() {
        let strength = makeStrengthPlan(dayName: "Dia C — Superior")
        let cardio = makeCardioPlan()
        // A semana ideal põe hoje só o Cardio; a próxima do principal fica em `otherSessions`.
        let planner = MultiPlanTestPlanner(overview: TodayOverview(
            sessions: [TodaySession(plan: cardio, goal: .endurance, isDoneToday: false)],
            otherSessions: [TodaySession(plan: strength, goal: .hypertrophy, isDoneToday: false)]
        ))
        let model = makeModel(planner)
        model.refresh()

        XCTAssertEqual(model.primaryCard?.id, cardioID, "o \"Começar\" da tela abre a de hoje")
        XCTAssertEqual(model.startPrincipalSession(), planner.sessionIDToReturn)
        XCTAssertEqual(planner.startedPlans, [strength], "o C5 nomeia a próxima do principal e começa ela")
    }

    func testM6_today_doneTodayMovesToNext() {
        let nextStrength = makeStrengthPlan(dayName: "Dia B — Inferior")
        let cardio = makeCardioPlan()
        let planner = MultiPlanTestPlanner(overview: TodayOverview(sessions: [
            TodaySession(plan: nextStrength, goal: .hypertrophy, isDoneToday: true),
            TodaySession(plan: cardio, goal: .endurance, isDoneToday: false),
        ]))
        let model = makeModel(planner)

        model.refresh()

        let cards = model.todayCards
        XCTAssertEqual(cards.map(\.isDoneToday), [true, false])
        XCTAssertEqual(cards.map(\.isStartable), [false, true], "Feito hoje não começa de novo")
        XCTAssertEqual(model.primaryCard?.id, cardioID, "O botão principal passa para a seguinte")
        XCTAssertEqual(cards.first.map { TodayPlansText.upNext($0.plan) }, "A seguir: Dia B — Inferior")
        XCTAssertEqual(TodayPlansText.doneToday, "✓ Feito hoje")
        XCTAssertFalse(model.isAllDoneToday)
        XCTAssertFalse(model.showsTrainAnyway)

        XCTAssertEqual(model.startSession(), planner.sessionIDToReturn)
        XCTAssertEqual(planner.startedPlans, [cardio])
    }

    func testM6_today_allDone_trainAnyway() {
        let nextStrength = makeStrengthPlan(dayName: "Dia B — Inferior")
        let nextCardio = makeCardioPlan()
        let planner = MultiPlanTestPlanner(overview: TodayOverview(sessions: [
            TodaySession(plan: nextStrength, goal: .hypertrophy, isDoneToday: true),
            TodaySession(plan: nextCardio, goal: .endurance, isDoneToday: true),
        ]))
        let model = makeModel(planner)
        model.refresh()

        XCTAssertTrue(model.isAllDoneToday)
        XCTAssertNil(model.primaryCard, "Sem \"Começar\" com tudo feito")
        XCTAssertTrue(model.showsTrainAnyway)

        model.trainAnyway()

        XCTAssertFalse(model.showsTrainAnyway)
        XCTAssertEqual(model.todayCards.map(\.isStartable), [true, true])
        XCTAssertEqual(model.primaryCard?.id, hypertrophyID)
        XCTAssertEqual(model.startSession(), planner.sessionIDToReturn)
        XCTAssertEqual(planner.startedPlans, [nextStrength])
        XCTAssertFalse(model.isTrainingAnyway, "Vale até começar uma sessão")
    }

    // MARK: - Dia de descanso

    func testM6_today_restDay_trainAnyway() {
        let strength = makeStrengthPlan(dayName: "Dia A — Superior")
        let cardio = makeCardioPlan()
        let planner = MultiPlanTestPlanner(overview: TodayOverview(
            sessions: [],
            otherSessions: [
                TodaySession(plan: strength, goal: .hypertrophy, isDoneToday: false),
                TodaySession(plan: cardio, goal: .endurance, isDoneToday: false),
            ],
            isRestDay: true
        ))
        let model = makeModel(planner)

        model.refresh()

        XCTAssertTrue(model.isRestDay)
        XCTAssertEqual(TodayPlansText.restDay, "Hoje é dia de descanso.", "Sem frase depois (item 16)")
        XCTAssertTrue(model.todayCards.isEmpty)
        XCTAssertNil(model.primaryCard)
        XCTAssertNil(model.todayLine)
        XCTAssertTrue(model.showsTrainAnyway)
        XCTAssertEqual(TodayPlansText.trainAnyway, "Treinar mesmo assim")
        XCTAssertEqual(model.plan, strength, "O diálogo (C5) começa a próxima do principal")

        model.trainAnyway()

        XCTAssertEqual(model.todayCards.map(\.id), [hypertrophyID, cardioID])
        XCTAssertEqual(model.primaryCard?.id, hypertrophyID)
        XCTAssertFalse(model.showsTrainAnyway)
        XCTAssertEqual(model.startSession(programID: cardioID), planner.sessionIDToReturn)
        XCTAssertEqual(planner.startedPlans, [cardio])
    }

    // MARK: - Planos que não cabem

    func testM6_today_notFitBanner() {
        let strength = makeStrengthPlan(dayName: "Dia A — Superior")
        let cardio = makeCardioPlan()
        let planner = MultiPlanTestPlanner(overview: TodayOverview(
            sessions: [TodaySession(plan: strength, goal: .hypertrophy, isDoneToday: false)],
            otherSessions: [TodaySession(plan: cardio, goal: .endurance, isDoneToday: false)],
            fitsWeek: false
        ))
        let model = makeModel(planner)

        model.refresh()

        XCTAssertTrue(model.showsNotFitBanner)
        XCTAssertEqual(TodayPlansText.notFitBanner, "Seus planos não cabem nos dias escolhidos. Ajuste em Plano › Seus dias.")
        XCTAssertEqual(model.todayCards.map(\.id), [hypertrophyID], "A sessão do principal")
        XCTAssertEqual(model.primaryCard?.id, hypertrophyID)
        XCTAssertEqual(model.todayLine, "Hoje: Superior")
        XCTAssertTrue(model.showsTrainAnyway, "A do outro fica em \"Treinar mesmo assim\"")

        model.trainAnyway()

        XCTAssertEqual(model.todayCards.map(\.id), [hypertrophyID, cardioID])
        XCTAssertEqual(model.primaryCard?.id, hypertrophyID)
    }

    // MARK: - Um plano só

    func testM6_singlePlanUnchanged() {
        let strength = makeStrengthPlan(dayName: "Dia A — Superior")
        let planner = MultiPlanTestPlanner(overview: TodayOverview(sessions: [
            TodaySession(plan: makeCardioPlan(), goal: .endurance, isDoneToday: false),
        ]))
        planner.goals = [.hypertrophy]
        planner.nextPlanToReturn = strength
        let model = makeModel(planner)

        model.refresh()

        XCTAssertFalse(model.isMultiPlan)
        XCTAssertEqual(model.headerGoals, [.hypertrophy])
        XCTAssertEqual(model.plan, strength, "O próximo da rotação, como na 2.2")
        XCTAssertTrue(model.todayCards.isEmpty)
        XCTAssertNil(model.overview)
        XCTAssertNil(model.todayLine)
        XCTAssertFalse(model.isRestDay)
        XCTAssertFalse(model.showsTrainAnyway)
        XCTAssertFalse(model.showsNotFitBanner)
        XCTAssertEqual(planner.nextPlanCalls, 1)
        XCTAssertTrue(planner.overviewDates.isEmpty, "Com um plano, a tela não lê o dia de dois planos")
    }

    // MARK: - Dia escolhido à mão e sessão em andamento

    func testM6_chosenDayStaysOnItsCard() {
        let strength = makeStrengthPlan(dayName: "Dia A — Superior")
        let cardio = makeCardioPlan()
        let chosenDayID = UUID()
        let chosen = makeCardioPlan(dayID: chosenDayID, dayName: "Dia C — Longo e leve", minutes: 45)
        let planner = MultiPlanTestPlanner(overview: TodayOverview(sessions: [
            TodaySession(plan: strength, goal: .hypertrophy, isDoneToday: false),
            TodaySession(plan: cardio, goal: .endurance, isDoneToday: false),
        ]))
        planner.plansByDayID = [chosenDayID: chosen]
        let model = makeModel(planner)
        model.refresh()

        model.selectDay(chosenDayID)

        XCTAssertEqual(model.todayCards.last?.plan, chosen)
        XCTAssertEqual(model.todayCards.last?.selectedDayID, chosenDayID)
        XCTAssertEqual(model.todayCards.first?.plan, strength, "O outro cartão não muda")
        XCTAssertEqual(model.todayCards.last?.days.map(\.name), ["Dia A — Base contínua", "Dia B — Intervalos 4 × 4", "Dia C — Longo e leve"])

        // Trocar de aba (refresh) mantém a escolha; "Automático" desfaz.
        model.refresh()
        XCTAssertEqual(model.todayCards.last?.plan, chosen)
        model.selectAutomaticDay(forProgramID: cardioID)
        XCTAssertEqual(model.todayCards.last?.plan, cardio)
        XCTAssertNil(model.todayCards.last?.selectedDayID)
    }

    func testM6_sessionInProgress_resumes() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A — Superior",
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
        container.mainContext.insert(session)
        let planner = MultiPlanTestPlanner(overview: TodayOverview(sessions: [
            TodaySession(plan: makeStrengthPlan(dayName: "Dia A — Superior"), goal: .hypertrophy, isDoneToday: false),
            TodaySession(plan: makeCardioPlan(), goal: .endurance, isDoneToday: false),
        ]))
        let model = HomeViewModel(
            planner: planner,
            coordinator: MultiPlanTestCoordinator(activeSession: session),
            now: { [now = self.now] in now }
        )

        model.refresh()

        XCTAssertEqual(model.activeSessionID, session.uuid)
        XCTAssertNil(model.primaryCard, "Com sessão em andamento, só Retomar")
        XCTAssertEqual(model.todayCards.map(\.isStartable), [false, false])
        XCTAssertEqual(model.startSession(), session.uuid)
        XCTAssertEqual(model.startSession(programID: cardioID), session.uuid)
        XCTAssertTrue(planner.startedPlans.isEmpty)
        withExtendedLifetime(container) {}
    }

    // MARK: - Textos do cardio (SPEC §7.14 F1, §7.15 M3)

    func testM6_cardioTexts() {
        let intervals = makeCardioPlan(slug: "run-intervals", sets: 4, minutes: 3, repMax: 4, restSeconds: 180)
        let long = makeCardioPlan(slug: "stationary-bike", sets: 1, minutes: 45, repMax: 75, restSeconds: 60)

        XCTAssertEqual(TodayPlansText.cardioMinutes(intervals), 21, "4 × 3 min com 3 min de recuperação")
        XCTAssertEqual(TodayPlansText.cardioIntensity(intervals), .vigorous)
        XCTAssertEqual(TodayPlansText.sessionLabel(intervals), "Cardio forte 21 min")
        XCTAssertEqual(TodayPlansText.cardioIntensity(long), .light, "Faixa que chega a 60 min é leve")
        XCTAssertEqual(TodayPlansText.sessionLabel(long), "Cardio leve 45 min")
        XCTAssertEqual(TodayPlansText.detailSpokenText(for: long), "45 minutos")
        XCTAssertEqual(TodayPlansText.shortDayTitle("Dia A — Superior"), "Superior")
        XCTAssertEqual(TodayPlansText.shortDayTitle("Dia A"), "Dia A")
        XCTAssertEqual(TodayPlansText.sessionLabel(makeStrengthPlan(dayName: "Dia B — Inferior")), "Inferior")
        XCTAssertFalse(TodayPlansText.isCardioOnly(makeStrengthPlan(dayName: "Dia A")))
        XCTAssertEqual(TodayPlansText.detailText(for: makeStrengthPlan(dayName: "Dia A")), PlanCard.detailText(for: makeStrengthPlan(dayName: "Dia A")))
    }

    // MARK: - Fixtures

    private func makeModel(_ planner: MultiPlanTestPlanner) -> HomeViewModel {
        let fixedNow = now
        return HomeViewModel(planner: planner, coordinator: MultiPlanTestCoordinator(), now: { fixedNow })
    }

    private func makeStrengthPlan(dayName: String) -> SessionPlan {
        let bench = ExerciseDefinition(
            slug: "supino-reto",
            name: "Supino reto",
            primaryMuscles: [.chest],
            equipment: .barbell,
            loadUnit: .kilograms,
            loadIncrement: 2.5,
            movementPattern: .horizontalPush
        )
        return SessionPlan(
            programID: hypertrophyID,
            programName: "Hipertrofia — Equilibrado",
            programDayID: UUID(),
            programDayName: dayName,
            exercises: [
                PlannedExercise(
                    id: UUID(),
                    exercise: bench,
                    target: ExerciseTarget(exerciseID: bench.id, order: 0),
                    prescription: ExercisePrescription(exerciseID: bench.id, load: 40, sets: 3, repMin: 8, repMax: 12, targetReps: 8, targetRIR: 2, restSeconds: 120, note: .hold)
                ),
            ],
            generatedAt: now,
            estimatedMinutes: 20
        )
    }

    private func makeCardioPlan(
        dayID: UUID = UUID(),
        dayName: String = "Dia A — Base contínua",
        slug: String = "brisk-walk",
        sets: Int = 1,
        minutes: Int = 30,
        repMax: Int = 45,
        restSeconds: Int = 60
    ) -> SessionPlan {
        let exercise = ExerciseDefinition(
            slug: slug,
            name: "Caminhada rápida",
            primaryMuscles: [.quads],
            equipment: .bodyweight,
            loadUnit: .level,
            loadIncrement: 1,
            movementPattern: .cardio
        )
        return SessionPlan(
            programID: cardioID,
            programName: "Cardio",
            programDayID: dayID,
            programDayName: dayName,
            exercises: [
                PlannedExercise(
                    id: UUID(),
                    exercise: exercise,
                    target: ExerciseTarget(exerciseID: exercise.id, order: 0, sets: sets, repMin: minutes, repMax: repMax, restSeconds: restSeconds),
                    prescription: ExercisePrescription(exerciseID: exercise.id, load: nil, sets: sets, repMin: minutes, repMax: repMax, targetReps: minutes, targetRIR: 3, restSeconds: restSeconds, note: .hold)
                ),
            ],
            generatedAt: now,
            estimatedMinutes: minutes + 3
        )
    }
}

// MARK: - Doubles (privados ao arquivo, prefixo "MultiPlan")

/// Dois planos ativos por padrão; `todayOverview` devolve o dia pronto. As assinaturas são exatamente as
/// do protocolo (senão valeria o padrão em silêncio).
@MainActor
private final class MultiPlanTestPlanner: SessionPlanning {
    var overview: TodayOverview
    var goals: [ProgramGoal] = [.hypertrophy, .endurance]
    var nextPlanToReturn: SessionPlan?
    var plansByDayID: [UUID: SessionPlan] = [:]
    var sessionIDToReturn = UUID()
    private(set) var nextPlanCalls = 0
    private(set) var overviewDates: [Date] = []
    private(set) var startedPlans: [SessionPlan] = []

    /// Os dias do Cardio, para o menu do cartão dele.
    let cardioDays: [ProgramDayTemplate] = [
        ProgramDayTemplate(name: "Dia C — Longo e leve", order: 2),
        ProgramDayTemplate(name: "Dia A — Base contínua", order: 0),
        ProgramDayTemplate(name: "Dia B — Intervalos 4 × 4", order: 1),
    ]

    init(overview: TodayOverview) {
        self.overview = overview
    }

    func nextPlan(now: Date) throws -> SessionPlan? {
        nextPlanCalls += 1
        return nextPlanToReturn
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        plansByDayID[dayID]
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        startedPlans.append(plan)
        return sessionIDToReturn
    }

    func activeProgramGoal() throws -> ProgramGoal? {
        goals.first
    }

    func activeProgramGoals() throws -> [ProgramGoal] {
        goals
    }

    func todayOverview(now: Date) throws -> TodayOverview {
        overviewDates.append(now)
        return overview
    }

    func days(ofProgramID programID: UUID) throws -> [ProgramDayTemplate] {
        programID == overview.sessions.last?.id ? cardioDays : []
    }
}

@MainActor
private final class MultiPlanTestCoordinator: SessionCoordinating {
    var activeSession: WorkoutSessionModel?

    init(activeSession: WorkoutSessionModel? = nil) {
        self.activeSession = activeSession
    }

    func session(withID id: UUID) -> WorkoutSessionModel? {
        guard let activeSession, activeSession.uuid == id else { return nil }
        return activeSession
    }

    func startSession(plan: SessionPlan, now: Date, source: DeviceSource) throws -> UUID {
        UUID()
    }

    func apply(_ event: SessionEvent) throws {}

    var eventsApplied: AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
