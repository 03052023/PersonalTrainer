import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// v2.1 B1 (docs/V21-CONTRACT.md) na Home: interruptor "Em casa" (SPEC RF-42), faixa com os avisos
/// (§7.13 H2) e duração estimada no cartão (B7, DESIGN §9.2). Cada teste usa uma suite própria de
/// `UserDefaults`; o planner é um double que só conta as leituras.
@MainActor
final class HomeModeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_175_600)

    // MARK: - Interruptor "Em casa" (RF-42)

    func testRF42_setHomeMode_writesPlannerKey_andReloadsPlan() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let planner = HomeModeTestPlanner(planToReturn: makePlan())
        let model = makeModel(planner: planner, defaults: defaults)
        model.refresh()
        XCTAssertFalse(model.isHomeMode, "Padrão: desligado")
        XCTAssertEqual(planner.nextPlanCalls, 1)

        planner.planToReturn = makePlan(isHomeMode: true)
        model.setHomeMode(true)

        XCTAssertTrue(model.isHomeMode)
        XCTAssertTrue(defaults.bool(forKey: "homeModeEnabled"))
        XCTAssertTrue(PlannerSettings.load(from: defaults).homeModeEnabled, "O planner lê o que a Home gravou")
        XCTAssertEqual(planner.nextPlanCalls, 2, "O plano é relido com os exercícios de casa")
        XCTAssertEqual(model.plan?.isHomeMode, true)

        model.setHomeMode(false)
        XCTAssertFalse(model.isHomeMode)
        XCTAssertFalse(defaults.bool(forKey: "homeModeEnabled"))
        XCTAssertEqual(planner.nextPlanCalls, 3)
    }

    func testRF42_refresh_picksUpKeyWrittenBySettings() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(planner: HomeModeTestPlanner(planToReturn: makePlan()), defaults: defaults)
        model.refresh()
        XCTAssertFalse(model.isHomeMode)

        defaults.set(true, forKey: PlannerSettings.homeModeKey)
        model.refresh()

        XCTAssertTrue(model.isHomeMode)
    }

    func testRF42_setHomeMode_keepsManuallyChosenDay() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let dayB = UUID()
        let planner = HomeModeTestPlanner(planToReturn: makePlan())
        planner.plansByDayID[dayB] = makePlan(dayID: dayB, dayName: "Dia B")
        let model = makeModel(planner: planner, defaults: defaults)
        model.refresh()
        model.selectDay(dayB)

        model.setHomeMode(true)

        XCTAssertEqual(model.selectedDayID, dayB, "Ligar o modo casa não desfaz a escolha do dia (S4)")
        XCTAssertEqual(model.plan?.programDayName, "Dia B")
    }

    // MARK: - Dia vazio no modo casa (§7.13 H2)

    func testH2_emptyHomeDay_explainsAndDoesNotStart() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let empty = makePlan(
            exercises: [],
            isHomeMode: true,
            notices: ["Sem opção em casa para Leg press: fica fora desta sessão."]
        )
        let planner = HomeModeTestPlanner(planToReturn: empty)
        let model = makeModel(planner: planner, defaults: defaults)
        model.refresh()

        XCTAssertNil(model.startSession())
        XCTAssertEqual(model.errorMessage, "Nenhum exercício deste dia tem opção em casa. Desligue Em casa ou escolha outro dia.")
        XCTAssertTrue(planner.startedPlans.isEmpty)
    }

    func testRF33_emptyDayOutsideHomeMode_keepsProgramMessage() {
        let empty = makePlan(exercises: [])
        XCTAssertEqual(
            HomeViewModel.emptyDayMessage(for: empty),
            "Este dia ainda não tem exercícios. Escolha os exercícios dele na aba Programa."
        )
        // Modo casa sem nenhum exercício que saiu: o dia já era vazio no programa.
        let emptyHome = makePlan(exercises: [], isHomeMode: true)
        XCTAssertEqual(HomeViewModel.emptyDayMessage(for: emptyHome), HomeViewModel.emptyDayMessage(for: empty))
    }

    // MARK: - Cartão: duração estimada (B7) e textos

    func testB7_planCardDetail_showsEstimatedDuration() {
        let plan = makePlan(estimatedMinutes: 45)
        XCTAssertEqual(PlanCard.detailText(for: plan), "Programa ABC · 1 exercício · ≈ 45 min")
        XCTAssertEqual(PlanCard.detailAccessibilityText(for: plan), "Programa ABC, 1 exercício, cerca de 45 minutos")

        let noEstimate = makePlan(exercises: [], estimatedMinutes: 0)
        XCTAssertEqual(PlanCard.detailText(for: noEstimate), "Programa ABC · 0 exercícios")
        XCTAssertEqual(PlanCard.detailAccessibilityText(for: noEstimate), "Programa ABC, 0 exercícios")

        XCTAssertEqual(PlanCard.durationText(minutes: 1), "≈ 1 min")
        XCTAssertNil(PlanCard.durationText(minutes: 0))
        XCTAssertEqual(PlanCard.detailAccessibilityText(for: makePlan(estimatedMinutes: 1)), "Programa ABC, 1 exercício, cerca de 1 minuto")
    }

    func testRF42_homeBandSummary_isCalmPortuguese() {
        XCTAssertEqual(PlanCard.homeModeSummary, "Exercícios com o peso do corpo ou objetos de casa. O programa continua o mesmo.")
    }

    // MARK: - Fixtures

    private func makeModel(planner: HomeModeTestPlanner, defaults: UserDefaults) -> HomeViewModel {
        let fixedNow = now
        return HomeViewModel(
            planner: planner,
            coordinator: HomeModeTestCoordinator(),
            now: { fixedNow },
            defaults: defaults
        )
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "HomeModeTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    /// Um dia com uma flexão (3 × 8–12), salvo quando `exercises` é passado.
    private func makePlan(
        dayID: UUID = UUID(),
        dayName: String = "Dia A",
        exercises: [PlannedExercise]? = nil,
        isHomeMode: Bool = false,
        notices: [String] = [],
        estimatedMinutes: Int? = nil
    ) -> SessionPlan {
        let pushUp = ExerciseDefinition(
            slug: "flexao",
            name: "Flexão",
            primaryMuscles: [.chest],
            equipment: .bodyweight,
            loadUnit: .kilograms,
            loadIncrement: 2.5,
            movementPattern: .horizontalPush
        )
        let defaultExercises = [
            PlannedExercise(
                id: UUID(),
                exercise: pushUp,
                target: ExerciseTarget(exerciseID: pushUp.id, order: 0),
                prescription: ExercisePrescription(
                    exerciseID: pushUp.id,
                    load: nil,
                    sets: 3,
                    repMin: 8,
                    repMax: 12,
                    targetReps: 8,
                    targetRIR: 3,
                    restSeconds: 90,
                    note: .calibrate
                )
            ),
        ]
        return SessionPlan(
            programID: UUID(),
            programName: "Programa ABC",
            programDayID: dayID,
            programDayName: dayName,
            exercises: exercises ?? defaultExercises,
            generatedAt: now,
            isHomeMode: isHomeMode,
            homeNotices: notices,
            estimatedMinutes: estimatedMinutes
        )
    }
}

// MARK: - Doubles (privados ao arquivo, prefixo "HomeMode")

@MainActor
private final class HomeModeTestPlanner: SessionPlanning {
    var planToReturn: SessionPlan?
    var plansByDayID: [UUID: SessionPlan] = [:]
    private(set) var nextPlanCalls = 0
    private(set) var startedPlans: [SessionPlan] = []

    init(planToReturn: SessionPlan?) {
        self.planToReturn = planToReturn
    }

    func nextPlan(now: Date) throws -> SessionPlan? {
        nextPlanCalls += 1
        return planToReturn
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        plansByDayID[dayID]
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        startedPlans.append(plan)
        return UUID()
    }
}

@MainActor
private final class HomeModeTestCoordinator: SessionCoordinating {
    var activeSession: WorkoutSessionModel?

    func session(withID id: UUID) -> WorkoutSessionModel? {
        nil
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
