import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T1.4: `HomeViewModel` sobre doubles de `SessionPlanning`/`SessionCoordinating` e a formatação
/// pt-BR de `PrescriptionRow` (CA1-1). Tudo em `@MainActor` (ARCHITECTURE §10); a única sessão
/// SwiftData vive num container in-memory.
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
        XCTAssertEqual(model.errorMessage, "Já existe um treino em andamento. Toque em Retomar treino.")
    }

    func testStartSession_coordinatorErrorSurfacesAsSessionInProgress() {
        let planner = HomeTestPlanner(planToReturn: makePlan())
        let inProgressID = UUID()
        planner.startError = SessionCoordinatorError.sessionAlreadyInProgress(inProgressID)
        let model = makeModel(planner: planner, coordinator: HomeTestCoordinator())
        model.refresh()

        XCTAssertNil(model.startSession())
        XCTAssertEqual(model.activeSessionID, inProgressID)
        XCTAssertEqual(model.errorMessage, "Já existe um treino em andamento. Toque em Retomar treino.")
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
        XCTAssertEqual(PrescriptionRow.noteText(.deload), "Deload")
    }

    // MARK: - Fixtures

    private func makeModel(planner: HomeTestPlanner, coordinator: HomeTestCoordinator) -> HomeViewModel {
        let fixedNow = now
        return HomeViewModel(planner: planner, coordinator: coordinator, now: { fixedNow })
    }

    /// Dia A com três exercícios: kg com carga, kg sem carga (P2) e nível de máquina.
    private func makePlan() -> SessionPlan {
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
            programDayID: UUID(),
            programDayName: "Dia A",
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
    private(set) var nextPlanCalls: [Date] = []
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
