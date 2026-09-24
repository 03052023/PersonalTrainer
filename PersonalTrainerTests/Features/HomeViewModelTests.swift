import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T1.4 / T2.14 / T2.7: `HomeViewModel` sobre doubles de `SessionPlanning`/`SessionCoordinating`
/// (plano, dias, objetivo, escolha manual do dia — SPEC S4), a formatação pt-BR de
/// `PrescriptionRow` (CA1-1), o painel semanal `WeeklyFrequencyCard` (SPEC §7.4, CA2-6), a faixa
/// do motivo do plano (`PlanBanner`, CA4-5) e a releitura depois de uma resposta ao diálogo.
/// Tudo em `@MainActor` (ARCHITECTURE §10); dados SwiftData vivem em containers in-memory.
@MainActor
final class HomeViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - refresh()

    func testRefresh_loadsPlanWithInjectedClock_andNoActiveSession() throws {
        let plan = makePlan()
        let planner = HomeTestPlanner(planToReturn: plan)
        let coordinator = HomeTestCoordinator()
        let model = makeModel(planner: planner, coordinator: coordinator)

        XCTAssertNil(model.plan, "Nada é lido no init: a view chama refresh()")
        model.refresh()

        XCTAssertEqual(model.plan, plan)
        XCTAssertNil(model.activeSessionID)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isPresentingError)
        XCTAssertFalse(model.didFailToLoad)
        XCTAssertEqual(planner.nextPlanCalls, [now], "SPEC P11: o relógio injetado vai para o planejador")
    }

    func testRefresh_withInProgressSession_exposesItsID() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let session = try insertInProgressSession(into: container.mainContext)
        let planner = HomeTestPlanner(planToReturn: makePlan())
        let coordinator = HomeTestCoordinator(activeSession: session)
        let model = makeModel(planner: planner, coordinator: coordinator)

        model.refresh()

        XCTAssertEqual(model.activeSessionID, session.uuid)
        XCTAssertNotNil(model.plan)
        // O container precisa viver até aqui: a sessão lida acima pertence ao seu mainContext.
        withExtendedLifetime(container) {}
    }

    func testRefresh_plannerReturnsNil_isEmptyStateWithoutError() {
        let planner = HomeTestPlanner(planToReturn: nil)
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())

        model.refresh()

        XCTAssertNil(model.plan)
        XCTAssertNil(model.errorMessage)
    }

    func testRefresh_plannerThrows_setsPortugueseMessageAndDropsPlan() {
        let planner = HomeTestPlanner(planToReturn: makePlan())
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()
        XCTAssertNotNil(model.plan)

        planner.nextPlanError = PlanningError.programHasNoDays
        model.refresh()

        XCTAssertNil(model.plan, "Plano antigo não pode sobreviver a uma leitura falha")
        XCTAssertEqual(model.errorMessage, "O programa ativo não tem dias de treino.")
        XCTAssertTrue(model.isPresentingError)
        XCTAssertTrue(model.didFailToLoad)
    }

    func testDidFailToLoad_survivesClosingTheAlert_andClearsOnSuccessfulRefresh() {
        let planner = HomeTestPlanner(planToReturn: makePlan())
        planner.nextPlanError = HomeTestError.boom
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())

        model.refresh()
        XCTAssertTrue(model.didFailToLoad)

        // Fechar o alerta zera a mensagem, mas a tela continua em "não foi possível carregar",
        // não em "nenhum programa ativo".
        model.isPresentingError = false
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.didFailToLoad)

        planner.nextPlanError = nil
        model.refresh()
        XCTAssertFalse(model.didFailToLoad)
        XCTAssertNotNil(model.plan)
    }

    func testRefresh_unknownError_usesFallbackMessage() {
        let planner = HomeTestPlanner(planToReturn: nil)
        planner.nextPlanError = HomeTestError.boom
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())

        model.refresh()

        XCTAssertEqual(model.errorMessage, "Não foi possível carregar o próximo treino.")
    }

    // MARK: - startSession()

    func testStartSession_withPlan_startsThroughPlannerAndStoresID() {
        let plan = makePlan()
        let planner = HomeTestPlanner(planToReturn: plan)
        let expectedID = UUID()
        planner.sessionIDToReturn = expectedID
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()

        let returned = model.startSession()

        XCTAssertEqual(returned, expectedID)
        XCTAssertEqual(model.activeSessionID, expectedID)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(planner.startedPlans.count, 1)
        XCTAssertEqual(planner.startedPlans.first?.plan, plan)
        XCTAssertEqual(planner.startedPlans.first?.now, now)
    }

    func testStartSession_withActiveSession_resumesWithoutStartingAnother() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let session = try insertInProgressSession(into: container.mainContext)
        let planner = HomeTestPlanner(planToReturn: makePlan())
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator(activeSession: session))
        model.refresh()

        let returned = model.startSession()

        XCTAssertEqual(returned, session.uuid, "RF-02: só uma sessão em andamento; o botão retoma")
        XCTAssertTrue(planner.startedPlans.isEmpty)
        XCTAssertNil(model.errorMessage)
        withExtendedLifetime(container) {}
    }

    func testStartSession_withoutPlan_returnsNilAndExplains() {
        let model = makeModel(planner: HomeTestPlanner(planToReturn: nil), coordinator: HomeTestCoordinator())
        model.refresh()

        let returned = model.startSession()

        XCTAssertNil(returned)
        XCTAssertEqual(model.errorMessage, "Nenhum programa ativo para iniciar.")
    }

    func testStartSession_plannerReportsSessionInProgress_switchesToResume() {
        let planner = HomeTestPlanner(planToReturn: makePlan())
        let inProgressID = UUID()
        planner.startError = PlanningError.sessionAlreadyInProgress(inProgressID)
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()

        let returned = model.startSession()

        XCTAssertNil(returned)
        XCTAssertEqual(model.activeSessionID, inProgressID, "Depois do alerta a Home oferece Retomar")
        XCTAssertEqual(model.errorMessage, "Já existe uma sessão em andamento. Toque em Retomar.")
    }

    func testStartSession_coordinatorErrorSurfacesAsSessionInProgress() {
        let planner = HomeTestPlanner(planToReturn: makePlan())
        let inProgressID = UUID()
        planner.startError = SessionCoordinatorError.sessionAlreadyInProgress(inProgressID)
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()

        XCTAssertNil(model.startSession())
        XCTAssertEqual(model.activeSessionID, inProgressID)
        XCTAssertEqual(model.errorMessage, "Já existe uma sessão em andamento. Toque em Retomar.")
    }

    func testStartSession_unknownError_usesFallbackMessage() {
        let planner = HomeTestPlanner(planToReturn: makePlan())
        planner.startError = HomeTestError.boom
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()

        XCTAssertNil(model.startSession())
        XCTAssertNil(model.activeSessionID)
        XCTAssertEqual(model.errorMessage, "Não foi possível iniciar o treino.")
    }

    // MARK: - isPresentingError

    func testIsPresentingError_settingFalseClearsMessage() {
        let planner = HomeTestPlanner(planToReturn: nil)
        planner.nextPlanError = HomeTestError.boom
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()
        XCTAssertTrue(model.isPresentingError)

        model.isPresentingError = true
        XCTAssertNotNil(model.errorMessage, "Atribuir true não inventa mensagem nem apaga a atual")

        model.isPresentingError = false
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isPresentingError)
    }

    // MARK: - Dias e objetivo (T2.14, SPEC §7.9)

    func testRefresh_loadsDaysSortedByOrder_andGoal() {
        let planner = HomeTestPlanner(planToReturn: makePlan())
        let dayA = ProgramDayTemplate(name: "Dia A — Superior empurrar", order: 0)
        let dayB = ProgramDayTemplate(name: "Dia B — Inferior", order: 1)
        let dayC = ProgramDayTemplate(name: "Dia C — Superior puxar", order: 2)
        planner.daysToReturn = [dayC, dayA, dayB]
        planner.goalToReturn = .strength
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())

        XCTAssertTrue(model.days.isEmpty, "Nada é lido no init")
        XCTAssertNil(model.goal)
        model.refresh()

        XCTAssertEqual(model.days.map(\.id), [dayA.id, dayB.id, dayC.id], "SPEC S1: ordem do programa")
        XCTAssertEqual(model.goal, .strength)
        XCTAssertNil(model.selectedDayID, "Sem escolha manual, a Home segue a rotação")
    }

    func testRefresh_daysAndGoalFailures_doNotHideThePlan() {
        let planner = HomeTestPlanner(planToReturn: makePlan())
        planner.daysToReturn = [ProgramDayTemplate(name: "Dia A", order: 0)]
        planner.goalToReturn = .hypertrophy
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()
        XCTAssertEqual(model.days.count, 1)
        XCTAssertEqual(model.goal, .hypertrophy)

        planner.daysError = HomeTestError.boom
        planner.goalError = HomeTestError.boom
        model.refresh()

        XCTAssertTrue(model.days.isEmpty)
        XCTAssertNil(model.goal)
        XCTAssertNotNil(model.plan, "O plano não depende do menu de dias nem do selo do objetivo")
        XCTAssertFalse(model.didFailToLoad)
        XCTAssertNil(model.errorMessage)
    }

    // MARK: - selectDay / selectAutomaticDay (T2.14, SPEC S4)

    func testSelectDay_S4_showsPlanForChosenDay_withInjectedClock() {
        let rotationPlan = makePlan(dayName: "Dia A")
        let dayC = UUID()
        let manualPlan = makePlan(dayID: dayC, dayName: "Dia C")
        let planner = HomeTestPlanner(planToReturn: rotationPlan)
        planner.plansByDayID = [dayC: manualPlan]
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()
        XCTAssertEqual(model.plan, rotationPlan)

        model.selectDay(dayC)

        XCTAssertEqual(model.plan, manualPlan)
        XCTAssertEqual(model.selectedDayID, dayC)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(planner.planForDayCalls.map { $0.dayID }, [dayC])
        XCTAssertEqual(planner.planForDayCalls.map { $0.now }, [now], "SPEC P11: o relógio injetado vai para o planejador")
    }

    func testSelectDay_S4_overrideSurvivesRefresh() {
        let rotationPlan = makePlan(dayName: "Dia A")
        let dayC = UUID()
        let manualPlan = makePlan(dayID: dayC, dayName: "Dia C")
        let planner = HomeTestPlanner(planToReturn: rotationPlan)
        planner.plansByDayID = [dayC: manualPlan]
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()
        model.selectDay(dayC)

        // Trocar de aba chama onAppear → refresh(): a escolha não pode sumir sem o usuário ver.
        model.refresh()

        XCTAssertEqual(model.plan, manualPlan)
        XCTAssertEqual(model.selectedDayID, dayC)
        XCTAssertEqual(planner.nextPlanCalls.count, 1, "Com escolha manual, a rotação não é consultada")
        XCTAssertEqual(planner.planForDayCalls.count, 2, "O dia escolhido é replanejado com o relógio atual")
    }

    func testSelectAutomaticDay_S2_clearsOverrideAndReturnsToRotation() {
        let rotationPlan = makePlan(dayName: "Dia A")
        let dayC = UUID()
        let planner = HomeTestPlanner(planToReturn: rotationPlan)
        planner.plansByDayID = [dayC: makePlan(dayID: dayC, dayName: "Dia C")]
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()
        model.selectDay(dayC)

        model.selectAutomaticDay()

        XCTAssertNil(model.selectedDayID)
        XCTAssertEqual(model.plan, rotationPlan)
        XCTAssertEqual(planner.nextPlanCalls.count, 2)
    }

    func testStartSession_S4_afterSelectDay_startsChosenPlanAndClearsOverride() {
        let rotationPlan = makePlan(dayName: "Dia A")
        let dayC = UUID()
        let manualPlan = makePlan(dayID: dayC, dayName: "Dia C")
        let planner = HomeTestPlanner(planToReturn: rotationPlan)
        planner.plansByDayID = [dayC: manualPlan]
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()
        model.selectDay(dayC)

        let returned = model.startSession()

        XCTAssertEqual(returned, planner.sessionIDToReturn)
        XCTAssertEqual(planner.startedPlans.map { $0.plan }, [manualPlan], "A sessão é do dia escolhido")
        XCTAssertNil(model.selectedDayID, "A escolha é consumida ao iniciar; a rotação segue dela (S4)")
    }

    func testRefresh_whenChosenDayLeftTheProgram_fallsBackToRotation() {
        let rotationPlan = makePlan(dayName: "Dia A")
        let dayC = UUID()
        let planner = HomeTestPlanner(planToReturn: rotationPlan)
        planner.plansByDayID = [dayC: makePlan(dayID: dayC, dayName: "Dia C")]
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()
        model.selectDay(dayC)

        // Programa editado ou trocado: o planejador não conhece mais o dia.
        planner.plansByDayID = [:]
        model.refresh()

        XCTAssertNil(model.selectedDayID)
        XCTAssertEqual(model.plan, rotationPlan)
        XCTAssertNil(model.errorMessage)
    }

    func testSelectDay_unknownDay_keepsCurrentPlanAndExplains() {
        let rotationPlan = makePlan()
        let planner = HomeTestPlanner(planToReturn: rotationPlan)
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()

        model.selectDay(UUID())

        XCTAssertEqual(model.plan, rotationPlan)
        XCTAssertNil(model.selectedDayID)
        XCTAssertEqual(model.errorMessage, "Este dia não existe mais no programa ativo.")
    }

    func testSelectDay_plannerThrows_keepsCurrentPlanAndExplains() {
        let rotationPlan = makePlan()
        let planner = HomeTestPlanner(planToReturn: rotationPlan)
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()

        planner.planForDayError = HomeTestError.boom
        model.selectDay(UUID())

        XCTAssertEqual(model.plan, rotationPlan, "Falha ao escolher não apaga o plano que estava na tela")
        XCTAssertNil(model.selectedDayID)
        XCTAssertFalse(model.didFailToLoad)
        XCTAssertEqual(model.errorMessage, "Não foi possível carregar o dia escolhido.")

        model.isPresentingError = false
        planner.planForDayError = PlanningError.exerciseNotFound(UUID())
        model.selectDay(UUID())
        XCTAssertEqual(model.errorMessage, "Um exercício do programa não foi encontrado no catálogo.")
    }

    func testSelectDay_withActiveSession_isRejected() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let session = try insertInProgressSession(into: container.mainContext)
        let dayC = UUID()
        let planner = HomeTestPlanner(planToReturn: makePlan())
        planner.plansByDayID = [dayC: makePlan(dayID: dayC, dayName: "Dia C")]
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator(activeSession: session))
        model.refresh()

        model.selectDay(dayC)

        XCTAssertNil(model.selectedDayID)
        XCTAssertTrue(planner.planForDayCalls.isEmpty, "RF-02: com treino em andamento só existe Retomar")
        XCTAssertEqual(model.errorMessage, "Já existe uma sessão em andamento. Toque em Retomar.")
        withExtendedLifetime(container) {}
    }

    func testRefresh_whenSessionStartedElsewhere_clearsOverride() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let session = try insertInProgressSession(into: container.mainContext)
        let rotationPlan = makePlan(dayName: "Dia A")
        let dayC = UUID()
        let planner = HomeTestPlanner(planToReturn: rotationPlan)
        planner.plansByDayID = [dayC: makePlan(dayID: dayC, dayName: "Dia C")]
        let coordinator = HomeTestCoordinator()
        let model = makeModel(planner: planner, coordinator: coordinator)
        model.refresh()
        model.selectDay(dayC)

        // Ex.: sessão iniciada pelo relógio (M3); ao terminar, a rotação já segue do dia feito.
        coordinator.activeSession = session
        model.refresh()

        XCTAssertNil(model.selectedDayID)
        XCTAssertEqual(model.activeSessionID, session.uuid)
        XCTAssertEqual(model.plan, rotationPlan)
        withExtendedLifetime(container) {}
    }

    func testDayPickerMenu_sortsByProgramOrder() {
        let dayB = ProgramDayTemplate(name: "Dia B", order: 1)
        let dayA = ProgramDayTemplate(name: "Dia A", order: 0)
        let dayC = ProgramDayTemplate(name: "Dia C", order: 2)

        XCTAssertEqual(DayPickerMenu.sorted([dayC, dayA, dayB]).map(\.name), ["Dia A", "Dia B", "Dia C"])
    }

    // MARK: - WeeklyFrequencyCard (T2.7, SPEC §7.4, CA2-6)

    func testWeeklyFrequency_CA2_6_chestShowsOneOfTwoAfterADayAInTheWeek() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let bench = insertExercise(slug: "supino-reto", name: "Supino reto", primary: [.chest], secondary: [.triceps], into: context)
        // `now` = terça 2023-11-14 22:13:20 UTC → semana [segunda 13/11 00:00, segunda 20/11 00:00).
        insertSession(status: .completed, startedAt: now.addingTimeInterval(-3_600), exercise: bench, isWarmup: false, into: context)
        // Não contam (SPEC §7.4): semana anterior, abandonada e só aquecimento.
        insertSession(status: .completed, startedAt: now.addingTimeInterval(-8 * 86_400), exercise: bench, isWarmup: false, into: context)
        insertSession(status: .abandoned, startedAt: now.addingTimeInterval(-7_200), exercise: bench, isWarmup: false, into: context)
        insertSession(status: .completed, startedAt: now.addingTimeInterval(-10_800), exercise: bench, isWarmup: true, into: context)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<WorkoutSessionModel>())
        let report = WeeklyFrequencyCard.report(sessions: sessions, now: now, calendar: utcCalendar())
        let entries = WeeklyFrequencyCard.visibleEntries(report)
        let chest = try XCTUnwrap(entries.first { $0.muscle == .chest })
        let triceps = try XCTUnwrap(entries.first { $0.muscle == .triceps })

        XCTAssertEqual(WeeklyFrequencyCard.chipText(chest), "Peito 1/2")
        XCTAssertEqual(WeeklyFrequencyCard.chipText(triceps), "Tríceps 0/2", "Secundário não conta (SPEC §7.4 v1)")
        XCTAssertEqual(entries.map(\.muscle), MuscleGroup.allCases, "Meta padrão 2× em todos os grupos, na ordem fixa")
        XCTAssertEqual(report.weekStart, Date(timeIntervalSince1970: 1_699_833_600), "Semana começa segunda 00:00")
        withExtendedLifetime(container) {}
    }

    func testWeeklyFrequency_usesConfiguredTargetsAndWeekStart() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let bench = insertExercise(slug: "supino-reto", name: "Supino reto", primary: [.chest], secondary: [.triceps], into: context)
        // Domingo 2023-11-12 12:00 UTC: na semana que começa no domingo (12/11), mas não na que
        // começa na segunda (13/11).
        insertSession(status: .completed, startedAt: Date(timeIntervalSince1970: 1_699_790_400), exercise: bench, isWarmup: false, into: context)
        try context.save()
        let sessions = try context.fetch(FetchDescriptor<WorkoutSessionModel>())

        // Metas gravadas em `UserSettingsModel.weeklyTargets`: peito 3, panturrilhas 0 (escondido);
        // os outros grupos ficam no padrão 2 (SPEC §7.4).
        let report = WeeklyFrequencyCard.report(
            sessions: sessions,
            now: now,
            calendar: utcCalendar(),
            targets: [.chest: 3, .calves: 0],
            weekStartsOnMonday: false
        )
        let entries = WeeklyFrequencyCard.visibleEntries(report)

        XCTAssertEqual(report.weekStart, Date(timeIntervalSince1970: 1_699_747_200), "Semana começa domingo 00:00")
        let chest = try XCTUnwrap(entries.first { $0.muscle == .chest })
        XCTAssertEqual(WeeklyFrequencyCard.chipText(chest), "Peito 1/3")
        XCTAssertNil(entries.first { $0.muscle == .calves }, "Meta 0 esconde o grupo")
        XCTAssertEqual(entries.first { $0.muscle == .back }?.target, WeeklyFrequency.defaultTarget)

        let mondayReport = WeeklyFrequencyCard.report(sessions: sessions, now: now, calendar: utcCalendar())
        XCTAssertEqual(mondayReport.entries.first { $0.muscle == .chest }?.completed, 0, "Domingo fica na semana anterior")
        withExtendedLifetime(container) {}
    }

    func testWeeklyFrequency_visibleEntries_hideGroupsWithoutTarget() {
        let report = WeeklyFrequencyReport(
            weekStart: now,
            weekEnd: now.addingTimeInterval(7 * 86_400),
            entries: [
                WeeklyFrequencyEntry(muscle: .chest, completed: 1, target: 2),
                WeeklyFrequencyEntry(muscle: .calves, completed: 0, target: 0),
                WeeklyFrequencyEntry(muscle: .core, completed: 3, target: 1),
            ]
        )

        XCTAssertEqual(WeeklyFrequencyCard.visibleEntries(report).map(\.muscle), [.chest, .core])
    }

    func testWeeklyFrequency_textsArePortuguese() {
        XCTAssertEqual(
            MuscleGroup.allCases.map { WeeklyFrequencyCard.muscleName($0) },
            ["Peito", "Costas", "Ombros", "Bíceps", "Tríceps", "Quadríceps", "Posteriores", "Glúteos", "Panturrilhas", "Core"]
        )
        XCTAssertEqual(
            WeeklyFrequencyCard.accessibilityText(WeeklyFrequencyEntry(muscle: .chest, completed: 1, target: 2)),
            "Peito: 1 de 2 sessões"
        )
        XCTAssertEqual(
            WeeklyFrequencyCard.accessibilityText(WeeklyFrequencyEntry(muscle: .core, completed: 0, target: 1)),
            "Core: 0 de 1 sessão"
        )
    }

    // MARK: - PrescriptionRow (CA1-1)

    func testPrescriptionRow_summary_matchesSpecFormat() {
        let plan = makePlan()
        let squat = plan.exercises[0]
        let bench = plan.exercises[1]
        let row = plan.exercises[2]

        XCTAssertEqual(PrescriptionRow.summary(for: squat), "3 × 8–12 · 60 kg · RIR 2 · 2 min")
        XCTAssertEqual(PrescriptionRow.summary(for: bench), "3 × 8–12 · — · RIR 3 · 1 min 30 s")
        XCTAssertEqual(PrescriptionRow.summary(for: row), "4 × 10–15 · nível 7 · RIR 2 · 45 s")
    }

    func testPrescriptionRow_loadText_perUnit() {
        XCTAssertEqual(PrescriptionRow.loadText(nil, unit: .kilograms), "—")
        XCTAssertEqual(PrescriptionRow.loadText(62.5, unit: .kilograms), "62,5 kg")
        XCTAssertEqual(PrescriptionRow.loadText(1, unit: .plates), "1 placa")
        XCTAssertEqual(PrescriptionRow.loadText(4, unit: .plates), "4 placas")
        XCTAssertEqual(PrescriptionRow.loadText(7, unit: .level), "nível 7")
    }

    func testPrescriptionRow_restText() {
        XCTAssertEqual(PrescriptionRow.restText(seconds: 120), "2 min")
        XCTAssertEqual(PrescriptionRow.restText(seconds: 90), "1 min 30 s")
        XCTAssertEqual(PrescriptionRow.restText(seconds: 45), "45 s")
        XCTAssertEqual(PrescriptionRow.restText(seconds: 0), "sem descanso")
    }

    func testPrescriptionRow_noteText_isPortuguese() {
        XCTAssertEqual(PrescriptionRow.noteText(.calibrate), "Calibrar")
        XCTAssertEqual(PrescriptionRow.noteText(.increase), "Subir")
        XCTAssertEqual(PrescriptionRow.noteText(.hold), "Manter")
        XCTAssertEqual(PrescriptionRow.noteText(.retry), "Repetir")
        XCTAssertEqual(PrescriptionRow.noteText(.decrease), "Reduzir")
        XCTAssertEqual(PrescriptionRow.noteText(.returning), "Retorno")
        XCTAssertEqual(PrescriptionRow.noteText(.deload), "Semana leve", "DESIGN §6: semana leve, nunca deload")
    }

    func testPlanCard_exerciseCountText() {
        XCTAssertEqual(PlanCard.exerciseCountText(1), "1 exercício")
        XCTAssertEqual(PlanCard.exerciseCountText(5), "5 exercícios")
    }

    // MARK: - PlanBanner (CA4-5)

    func testCA4_5_frequencyReason_namesGroupAndWeeklyCount() {
        let banner = PlanBanner.make(reason: .frequency(muscle: .quads, done: 0, target: 2), isDeload: false)

        XCTAssertEqual(banner?.text, "Quadríceps: abaixo da meta semanal (0 de 2)")
        XCTAssertEqual(
            PlanBanner.make(reason: .frequency(muscle: .chest, done: 1, target: 3), isDeload: false)?.text,
            "Peito: abaixo da meta semanal (1 de 3)"
        )
    }

    func testCA4_5_deloadReasonOrDeloadPlan_showsLightWeek() {
        XCTAssertEqual(PlanBanner.make(reason: .deload(.manyDecreases), isDeload: true)?.text, "Semana leve")
        XCTAssertEqual(PlanBanner.make(reason: .deload(nil), isDeload: true)?.text, "Semana leve", "Passagem em andamento: sem gatilho")
        XCTAssertEqual(
            PlanBanner.make(reason: .manual, isDeload: true)?.text,
            "Semana leve",
            "Dia escolhido à mão em semana leve: `plan(forDayID:)` devolve .manual com isDeload"
        )
        XCTAssertEqual(PlanBanner.make(reason: .deload(.scheduled), isDeload: false), PlanBanner.deload)
    }

    func testCA4_5_rotationManualAndMissingReason_haveNoBanner() {
        XCTAssertNil(PlanBanner.make(reason: .rotation, isDeload: false))
        XCTAssertNil(PlanBanner.make(reason: .manual, isDeload: false))
        XCTAssertNil(PlanBanner.make(reason: nil, isDeload: false))
    }

    func testCA4_5_bannerReadsThePlan() {
        let base = makePlan()
        let plan = SessionPlan(
            programID: base.programID,
            programName: base.programName,
            programDayID: base.programDayID,
            programDayName: base.programDayName,
            exercises: base.exercises,
            generatedAt: base.generatedAt,
            isDeload: false,
            reason: .frequency(muscle: .back, done: 0, target: 2)
        )

        XCTAssertEqual(PlanBanner.make(for: plan)?.text, "Costas: abaixo da meta semanal (0 de 2)")
        XCTAssertNil(PlanBanner.make(for: base), "Plano montado fora do planejador (reason nil): sem faixa")
    }

    // MARK: - Respostas ao diálogo (SPEC §7.11)

    func testDidHandleCoachAction_applyAndKeepNormal_reloadThePlan() {
        let planner = HomeTestPlanner(planToReturn: makePlan())
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()
        XCTAssertEqual(planner.nextPlanCalls.count, 1)

        let deloadPlan = makePlan(dayName: "Dia B")
        planner.planToReturn = deloadPlan
        model.didHandleCoachAction(.apply)
        XCTAssertEqual(planner.nextPlanCalls.count, 2, "C2 Aplicar muda o programa: o plano é relido")
        XCTAssertEqual(model.plan, deloadPlan)

        model.didHandleCoachAction(.keepNormal)
        XCTAssertEqual(planner.nextPlanCalls.count, 3, "C1 Seguir normal desfaz a semana leve: o plano é relido")
    }

    func testDidHandleCoachAction_otherAnswers_keepThePlanAsIs() {
        let planner = HomeTestPlanner(planToReturn: makePlan())
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()

        let untouched: [CoachAction] = [.ok, .notNow, .neverAgain, .understood, .remindTomorrow, .howToRenew, .start, .seeProgress, .backupNow, .later, .done, .skip]
        for action in untouched {
            model.didHandleCoachAction(action)
        }

        XCTAssertEqual(planner.nextPlanCalls.count, 1, "Só Aplicar e Seguir normal mudam o plano")
    }

    // MARK: - Fixtures

    private func makeModel(planner: HomeTestPlanner, coordinator: HomeTestCoordinator) -> HomeViewModel {
        let fixedNow = now
        return HomeViewModel(planner: planner, coordinator: coordinator, now: { fixedNow })
    }

    /// Calendário gregoriano em UTC: a semana do painel não depende do fuso do runner.
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        return calendar
    }

    /// Dia com três exercícios: kg com carga, kg sem carga (P2) e nível de máquina.
    private func makePlan(dayID: UUID = UUID(), dayName: String = "Dia A") -> SessionPlan {
        let squat = ExerciseDefinition(
            slug: "agachamento-livre",
            name: "Agachamento livre",
            primaryMuscles: [.quads],
            equipment: .barbell,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )
        let bench = ExerciseDefinition(
            slug: "supino-reto",
            name: "Supino reto",
            primaryMuscles: [.chest],
            equipment: .barbell,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )
        let row = ExerciseDefinition(
            slug: "remada-maquina",
            name: "Remada na máquina",
            primaryMuscles: [.back],
            equipment: .machine,
            loadUnit: .level,
            loadIncrement: 1
        )
        return SessionPlan(
            programID: UUID(),
            programName: "Programa ABC",
            programDayID: dayID,
            programDayName: dayName,
            exercises: [
                PlannedExercise(
                    id: UUID(),
                    exercise: squat,
                    target: ExerciseTarget(exerciseID: squat.id, order: 0, startingLoad: 60),
                    prescription: ExercisePrescription(exerciseID: squat.id, load: 60, sets: 3, repMin: 8, repMax: 12, targetReps: 8, targetRIR: 2, restSeconds: 120, note: .calibrate)
                ),
                PlannedExercise(
                    id: UUID(),
                    exercise: bench,
                    target: ExerciseTarget(exerciseID: bench.id, order: 1),
                    prescription: ExercisePrescription(exerciseID: bench.id, load: nil, sets: 3, repMin: 8, repMax: 12, targetReps: 8, targetRIR: 3, restSeconds: 90, note: .calibrate)
                ),
                PlannedExercise(
                    id: UUID(),
                    exercise: row,
                    target: ExerciseTarget(exerciseID: row.id, order: 2, sets: 4, repMin: 10, repMax: 15, restSeconds: 45, startingLoad: 7),
                    prescription: ExercisePrescription(exerciseID: row.id, load: 7, sets: 4, repMin: 10, repMax: 15, targetReps: 12, targetRIR: 2, restSeconds: 45, note: .hold)
                ),
            ],
            generatedAt: now
        )
    }

    @discardableResult
    private func insertExercise(
        slug: String,
        name: String,
        primary: [MuscleGroup],
        secondary: [MuscleGroup],
        into context: ModelContext
    ) -> ExerciseModel {
        let exercise = ExerciseModel(
            uuid: UUID(),
            slug: slug,
            name: name,
            primaryMusclesRaw: SchemaV1.encodeMuscleGroups(primary),
            secondaryMusclesRaw: SchemaV1.encodeMuscleGroups(secondary),
            equipmentRaw: Equipment.barbell.rawValue,
            loadUnitRaw: LoadUnit.kilograms.rawValue,
            loadIncrement: 2.5,
            isUnilateral: false,
            machineNotes: nil,
            isArchived: false
        )
        context.insert(exercise)
        return exercise
    }

    /// Sessão com um exercício e uma série (de trabalho ou aquecimento), ligada ao catálogo.
    private func insertSession(
        status: SessionStatus,
        startedAt: Date,
        exercise: ExerciseModel,
        isWarmup: Bool,
        into context: ModelContext
    ) {
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: status.rawValue,
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
        context.insert(sessionExercise)
        sessionExercise.exercise = exercise
        session.exercises.append(sessionExercise)

        let completedAt = startedAt.addingTimeInterval(180)
        let set = SetLogModel(
            uuid: UUID(),
            index: 0,
            load: 60,
            reps: 10,
            rir: 2,
            isWarmup: isWarmup,
            completedAt: completedAt,
            sourceRaw: DeviceSource.iphone.rawValue,
            updatedAt: completedAt
        )
        context.insert(set)
        sessionExercise.sets.append(set)
    }

    private func insertInProgressSession(into context: ModelContext) throws -> WorkoutSessionModel {
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
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
        context.insert(session)
        try context.save()
        return session
    }
}

// MARK: - Doubles (privados ao arquivo, prefixo "Home" para não colidir com outras features)

private enum HomeTestError: Error {
    case boom
}

@MainActor
private final class HomeTestPlanner: SessionPlanning {
    var planToReturn: SessionPlan?
    var nextPlanError: (any Error)?
    var startError: (any Error)?
    var sessionIDToReturn = UUID()
    /// Planos por dia para `plan(forDayID:now:)` (SPEC S4); `planToReturn` também responde pelo
    /// próprio dia.
    var plansByDayID: [UUID: SessionPlan] = [:]
    var planForDayError: (any Error)?
    var daysToReturn: [ProgramDayTemplate] = []
    var daysError: (any Error)?
    var goalToReturn: ProgramGoal?
    var goalError: (any Error)?
    private(set) var nextPlanCalls: [Date] = []
    private(set) var planForDayCalls: [(dayID: UUID, now: Date)] = []
    private(set) var startedPlans: [(plan: SessionPlan, now: Date)] = []

    init(planToReturn: SessionPlan?) {
        self.planToReturn = planToReturn
    }

    func nextPlan(now: Date) throws -> SessionPlan? {
        nextPlanCalls.append(now)
        if let nextPlanError {
            throw nextPlanError
        }
        return planToReturn
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        planForDayCalls.append((dayID: dayID, now: now))
        if let planForDayError {
            throw planForDayError
        }
        if let plan = plansByDayID[dayID] {
            return plan
        }
        guard let planToReturn, planToReturn.programDayID == dayID else { return nil }
        return planToReturn
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        startedPlans.append((plan: plan, now: now))
        if let startError {
            throw startError
        }
        return sessionIDToReturn
    }

    func activeProgramDays() throws -> [ProgramDayTemplate] {
        if let daysError {
            throw daysError
        }
        return daysToReturn
    }

    func activeProgramGoal() throws -> ProgramGoal? {
        if let goalError {
            throw goalError
        }
        return goalToReturn
    }
}

@MainActor
private final class HomeTestCoordinator: SessionCoordinating {
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
