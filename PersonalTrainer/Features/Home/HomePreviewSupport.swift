import Foundation
import SwiftUI
import TrainerCore

// Doubles e fixtures só para os #Preview da feature Home (AGENTS R9: previews usam fakes).
// Tudo privado ao arquivo e prefixado por "Home" para não colidir com doubles de outras
// features; por isso os previews da Home vivem aqui, e não em cada arquivo de view.

// MARK: - Previews

#Preview("Home — próximo treino") {
    HomeView(
        model: HomeViewModel(
            planner: HomePreviewPlanner(fixedPlan: HomePreviewFixture.plan),
            coordinator: HomePreviewCoordinator(),
            now: { HomePreviewFixture.referenceDate }
        ),
        onOpenSession: { _ in }
    )
}

#Preview("Home — retomar") {
    HomeView(
        model: HomeViewModel(
            planner: HomePreviewPlanner(fixedPlan: HomePreviewFixture.plan),
            coordinator: HomePreviewCoordinator(activeSession: HomePreviewFixture.makeInProgressSession()),
            now: { HomePreviewFixture.referenceDate }
        ),
        onOpenSession: { _ in }
    )
}

#Preview("Home — sem programa") {
    HomeView(
        model: HomeViewModel(
            planner: HomePreviewPlanner(fixedPlan: nil),
            coordinator: HomePreviewCoordinator(),
            now: { HomePreviewFixture.referenceDate }
        ),
        onOpenSession: { _ in }
    )
}

#Preview("PlanCard") {
    ScrollView {
        PlanCard(plan: HomePreviewFixture.plan)
            .padding()
    }
}

#Preview("PrescriptionRow") {
    List {
        ForEach(HomePreviewFixture.plan.exercises) { exercise in
            PrescriptionRow(exercise: exercise)
        }
    }
}

// MARK: - Fixtures

private enum HomePreviewFixture {
    /// Data fixa (SPEC P11): previews determinísticos.
    static let referenceDate = Date(timeIntervalSince1970: 1_758_600_000)

    /// Dia A com três exercícios cobrindo carga em kg, carga vazia (P2) e nível de máquina.
    static let plan: SessionPlan = makePlan()

    private static func makePlan() -> SessionPlan {
        let squat = ExerciseDefinition(
            slug: "agachamento-livre",
            name: "Agachamento livre",
            primaryMuscles: [.quads, .glutes],
            secondaryMuscles: [.hamstrings],
            equipment: .barbell,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )
        let bench = ExerciseDefinition(
            slug: "supino-reto",
            name: "Supino reto",
            primaryMuscles: [.chest],
            secondaryMuscles: [.triceps, .shoulders],
            equipment: .barbell,
            loadUnit: .kilograms,
            loadIncrement: 2.5
        )
        let row = ExerciseDefinition(
            slug: "remada-maquina",
            name: "Remada na máquina",
            primaryMuscles: [.back],
            secondaryMuscles: [.biceps],
            equipment: .machine,
            loadUnit: .level,
            loadIncrement: 1
        )

        let squatTarget = ExerciseTarget(exerciseID: squat.id, order: 0, sets: 3, repMin: 6, repMax: 10, targetRIR: 2, restSeconds: 180, startingLoad: 60)
        let benchTarget = ExerciseTarget(exerciseID: bench.id, order: 1, sets: 3, repMin: 8, repMax: 12, targetRIR: 2, restSeconds: 120, startingLoad: nil)
        let rowTarget = ExerciseTarget(exerciseID: row.id, order: 2, sets: 3, repMin: 10, repMax: 15, targetRIR: 2, restSeconds: 90, startingLoad: 7)

        return SessionPlan(
            programID: UUID(),
            programName: "Programa ABC",
            programDayID: UUID(),
            programDayName: "Dia A — Inferior",
            exercises: [
                PlannedExercise(
                    id: UUID(),
                    exercise: squat,
                    target: squatTarget,
                    prescription: ExercisePrescription(
                        exerciseID: squat.id,
                        load: 62.5,
                        sets: 3,
                        repMin: 6,
                        repMax: 10,
                        targetReps: 6,
                        targetRIR: 2,
                        restSeconds: 180,
                        note: .increase
                    )
                ),
                PlannedExercise(
                    id: UUID(),
                    exercise: bench,
                    target: benchTarget,
                    prescription: ExercisePrescription(
                        exerciseID: bench.id,
                        load: nil,
                        sets: 3,
                        repMin: 8,
                        repMax: 12,
                        targetReps: 8,
                        targetRIR: 3,
                        restSeconds: 120,
                        note: .calibrate
                    )
                ),
                PlannedExercise(
                    id: UUID(),
                    exercise: row,
                    target: rowTarget,
                    prescription: ExercisePrescription(
                        exerciseID: row.id,
                        load: 7,
                        sets: 3,
                        repMin: 10,
                        repMax: 15,
                        targetReps: 12,
                        targetRIR: 2,
                        restSeconds: 90,
                        note: .hold
                    )
                ),
            ],
            generatedAt: referenceDate
        )
    }

    /// Sessão `inProgress` fora de qualquer container: o preview só lê `uuid`.
    static func makeInProgressSession() -> WorkoutSessionModel {
        WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: plan.programDayID,
            programDayName: plan.programDayName,
            statusRaw: SessionStatus.inProgress.rawValue,
            startedAt: referenceDate.addingTimeInterval(-900),
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: DeviceSource.iphone.rawValue
        )
    }
}

// MARK: - Doubles

@MainActor
private final class HomePreviewPlanner: SessionPlanning {
    private let fixedPlan: SessionPlan?

    init(fixedPlan: SessionPlan?) {
        self.fixedPlan = fixedPlan
    }

    func nextPlan(now: Date) throws -> SessionPlan? {
        fixedPlan
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        guard let fixedPlan, fixedPlan.programDayID == dayID else { return nil }
        return fixedPlan
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        UUID()
    }
}

@MainActor
private final class HomePreviewCoordinator: SessionCoordinating {
    let activeSession: WorkoutSessionModel?

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

    /// Stream vazio: nenhum observador de preview espera eventos.
    var eventsApplied: AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
