import Foundation
import SwiftData
import SwiftUI
import TrainerCore

// Doubles e fixtures só para os #Preview da feature Home (AGENTS R9: previews usam fakes).
// Tudo privado ao arquivo e prefixado por "Home" para não colidir com doubles de outras
// features; por isso os previews da Home vivem aqui, e não em cada arquivo de view.
// O `WeeklyFrequencyCard` usa `@Query`: os previews da Home recebem um container in-memory
// vazio (painel zerado); nada aqui insere modelos no app real (R4). Diálogo e Saúde usam os
// fakes (`FakeCoachLogStore`, `FakeNotificationScheduler`, `FakeHealthDataReader`) e suites
// próprias de `UserDefaults`.

// MARK: - Previews

#Preview("Home — próximo treino") {
    if let container = HomePreviewFixture.makeContainer() {
        HomePreviewFixture.makeHome(
            planner: HomePreviewPlanner(fixedPlan: HomePreviewFixture.plan),
            coordinator: HomePreviewCoordinator(),
            references: HomePreviewFixture.references,
            container: container
        )
        .modelContainer(container)
    } else {
        Text("Não foi possível montar os dados de preview")
    }
}

#Preview("Home — retomar") {
    if let container = HomePreviewFixture.makeContainer() {
        HomePreviewFixture.makeHome(
            planner: HomePreviewPlanner(fixedPlan: HomePreviewFixture.plan),
            coordinator: HomePreviewCoordinator(activeSession: HomePreviewFixture.makeInProgressSession()),
            references: HomePreviewFixture.references,
            container: container
        )
        .modelContainer(container)
    } else {
        Text("Não foi possível montar os dados de preview")
    }
}

#Preview("Home — sem programa") {
    if let container = HomePreviewFixture.makeContainer() {
        HomePreviewFixture.makeHome(
            planner: HomePreviewPlanner(fixedPlan: nil),
            coordinator: HomePreviewCoordinator(),
            references: .empty,
            container: container
        )
        .modelContainer(container)
    } else {
        Text("Não foi possível montar os dados de preview")
    }
}

#Preview("PlanCard") {
    ScrollView {
        PlanCard(
            plan: HomePreviewFixture.plan,
            days: HomePreviewFixture.days,
            selectedDayID: nil,
            goal: .hypertrophy,
            references: HomePreviewFixture.references,
            onSelectDay: { _ in },
            onSelectAutomatic: {}
        )
        .padding()
    }
}

#Preview("PlanCard — frequência") {
    ScrollView {
        PlanCard(
            plan: HomePreviewFixture.makePlan(reason: .frequency(muscle: .quads, done: 0, target: 2)),
            days: HomePreviewFixture.days,
            selectedDayID: nil,
            goal: .strength,
            references: HomePreviewFixture.references,
            onSelectDay: { _ in },
            onSelectAutomatic: {}
        )
        .padding()
    }
}

#Preview("PlanCard — semana leve") {
    ScrollView {
        PlanCard(
            plan: HomePreviewFixture.makePlan(isDeload: true, reason: .deload(.scheduled)),
            days: HomePreviewFixture.days,
            selectedDayID: nil,
            goal: .longevity,
            references: HomePreviewFixture.references,
            onSelectDay: { _ in },
            onSelectAutomatic: {}
        )
        .padding()
    }
}

#Preview("Topo — objetivo") {
    VStack(alignment: .leading, spacing: 24) {
        GoalHeaderView(goal: .strength)
        GoalHeaderView(goal: nil)
    }
    .padding()
}

#Preview("PrescriptionRow") {
    VStack(spacing: 16) {
        ForEach(HomePreviewFixture.plan.exercises) { exercise in
            PrescriptionRow(exercise: exercise, references: HomePreviewFixture.references)
        }
    }
    .padding()
}

#Preview("DayPickerMenu") {
    DayPickerMenu(
        dayName: HomePreviewFixture.plan.programDayName,
        days: HomePreviewFixture.days,
        selectedDayID: HomePreviewFixture.days.last?.id,
        onSelectDay: { _ in },
        onSelectAutomatic: {}
    )
    .padding()
}

#Preview("WeeklyFrequencyCard") {
    if let container = HomePreviewFixture.makeContainer() {
        WeeklyFrequencyCard(references: HomePreviewFixture.references)
            .padding()
            .modelContainer(container)
    } else {
        Text("Não foi possível montar os dados de preview")
    }
}

// MARK: - Fixtures

private enum HomePreviewFixture {
    /// Data fixa (SPEC P11): previews determinísticos.
    static let referenceDate = Date(timeIntervalSince1970: 1_758_600_000)

    /// Id do Dia A, compartilhado entre o plano e a lista de dias do menu.
    static let dayAID = UUID()

    /// Dia A com três exercícios cobrindo carga em kg, carga vazia (P2) e nível de máquina.
    static let plan: SessionPlan = makePlan()

    /// Três dias no formato do seed ("Dia A — ...").
    static let days: [ProgramDayTemplate] = [
        ProgramDayTemplate(id: dayAID, name: "Dia A — Inferior", order: 0),
        ProgramDayTemplate(id: UUID(), name: "Dia B — Superior empurrar", order: 1),
        ProgramDayTemplate(id: UUID(), name: "Dia C — Superior puxar", order: 2),
    ]

    /// Catálogo mínimo para o botão "Por quê?" aparecer nos previews (o do app vem de
    /// `references.v1.json`). Referências reais, citadas como no catálogo.
    static let references = ReferenceCatalog(
        version: 1,
        references: [
            ScientificReference(
                id: "schoenfeld-2017-volume",
                authors: "Schoenfeld BJ, Ogborn D, Krieger JW",
                year: 2017,
                title: "Dose-response relationship between weekly resistance training volume and increases in muscle mass: A systematic review and meta-analysis",
                source: "Journal of Sports Sciences",
                doi: "10.1080/02640414.2016.1210197",
                level: .metaAnalysis,
                summary: "Mais séries semanais por grupo muscular se associam a mais hipertrofia."
            ),
            ScientificReference(
                id: "schoenfeld-2016-frequency",
                authors: "Schoenfeld BJ, Ogborn D, Krieger JW",
                year: 2016,
                title: "Effects of Resistance Training Frequency on Measures of Muscle Hypertrophy: A Systematic Review and Meta-Analysis",
                source: "Sports Medicine",
                doi: "10.1007/s40279-016-0543-8",
                level: .metaAnalysis,
                summary: "Treinar cada grupo muscular pelo menos 2 vezes por semana favorece a hipertrofia."
            ),
        ],
        topics: [
            "goal.hypertrophy": ["schoenfeld-2017-volume"],
            "note.increase": ["schoenfeld-2017-volume"],
            "note.calibrate": ["schoenfeld-2017-volume"],
            "note.hold": ["schoenfeld-2017-volume"],
            "topic.frequency": ["schoenfeld-2016-frequency"],
        ],
        explanations: [
            "goal.hypertrophy": "Hipertrofia: faixas moderadas de repetições, perto da falha, com volume semanal suficiente.",
            "topic.frequency": "Cada grupo muscular rende mais quando é treinado ao menos duas vezes por semana.",
        ]
    )

    @MainActor
    static func makeContainer() -> ModelContainer? {
        try? ModelContainerFactory.make(.inMemory)
    }

    /// Home completa com diálogo e Saúde de mentira: o diálogo sobre o planner do preview e um
    /// repositório real do container em memória (vazio), o Saúde com os dados de exemplo do
    /// `FakeHealthDataReader` e a conexão já marcada numa suite própria.
    @MainActor
    static func makeHome(
        planner: any SessionPlanning,
        coordinator: any SessionCoordinating,
        references: ReferenceCatalog,
        container: ModelContainer
    ) -> HomeView {
        let fixedNow = referenceDate
        // Um log em memória para o diálogo e o Saúde, como no app (A4/B8; AGENTS R9).
        let logStore = FakeCoachLogStore()
        let coach = CoachService(
            planner: planner,
            programs: ProgramRepository(modelContext: container.mainContext),
            log: logStore,
            expiry: .unavailable,
            notifications: FakeNotificationScheduler(),
            now: { fixedNow },
            calendar: .current,
            defaults: UserDefaults(suiteName: "HomePreview.coach") ?? .standard
        )
        let healthDefaults = UserDefaults(suiteName: "HomePreview.health") ?? .standard
        healthDefaults.set(true, forKey: HealthViewModel.Keys.readAuthorized)
        let health = HealthViewModel(
            reader: FakeHealthDataReader(),
            sessionsProvider: { [] },
            now: { fixedNow },
            defaults: healthDefaults,
            logStore: logStore
        )
        return HomeView(
            model: HomeViewModel(planner: planner, coordinator: coordinator, now: { fixedNow }),
            coach: coach,
            health: health,
            references: references,
            onOpenSession: { _ in }
        )
    }

    /// Mesmo Dia A com outro motivo, para ver a faixa do cartão (CA4-5).
    static func makePlan(isDeload: Bool, reason: PlanReason?) -> SessionPlan {
        let base = plan
        return SessionPlan(
            programID: base.programID,
            programName: base.programName,
            programDayID: base.programDayID,
            programDayName: base.programDayName,
            exercises: base.exercises,
            generatedAt: base.generatedAt,
            isDeload: isDeload,
            reason: reason
        )
    }

    static func makePlan(reason: PlanReason?) -> SessionPlan {
        makePlan(isDeload: false, reason: reason)
    }

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
            programDayID: dayAID,
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

    /// O preview só tem o plano do Dia A; os outros dias reaproveitam os mesmos exercícios com
    /// o nome do dia escolhido, o bastante para ver o menu funcionando.
    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        guard let fixedPlan, let day = HomePreviewFixture.days.first(where: { $0.id == dayID }) else {
            return nil
        }
        return SessionPlan(
            programID: fixedPlan.programID,
            programName: fixedPlan.programName,
            programDayID: day.id,
            programDayName: day.name,
            exercises: fixedPlan.exercises,
            generatedAt: now
        )
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        UUID()
    }

    func activeProgramDays() throws -> [ProgramDayTemplate] {
        fixedPlan == nil ? [] : HomePreviewFixture.days
    }

    func activeProgramGoal() throws -> ProgramGoal? {
        fixedPlan == nil ? nil : .hypertrophy
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
