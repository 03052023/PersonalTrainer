import Foundation
import SwiftUI
import TrainerCore

// Doubles e fixtures só para os #Preview da feature Plano (AGENTS R9: previews usam fakes).
// Tudo privado ao arquivo e prefixado por "Program" para não colidir com doubles de outras
// features; por isso os previews da aba Plano vivem aqui, e não em cada arquivo de view.

// MARK: - Previews

#Preview("Plano") {
    ProgramTabView(
        programs: ProgramPreviewRepository.make(),
        catalog: ProgramPreviewCatalog(),
        references: ProgramPreviewFixture.references,
        now: { ProgramPreviewFixture.referenceDate },
        planner: ProgramPreviewPlanner(nextDayID: ProgramPreviewFixture.balancedDayBID)
    )
}

#Preview("Plano — dois planos") {
    ProgramTabView(
        programs: ProgramPreviewRepository(programs: ProgramPreviewFixture.makePrograms(
            activeIDs: [ProgramPreviewFixture.balancedID, ProgramPreviewFixture.enduranceID]
        )),
        catalog: ProgramPreviewCatalog(),
        references: ProgramPreviewFixture.references,
        now: { ProgramPreviewFixture.referenceDate },
        planner: ProgramPreviewPlanner(nextDayID: ProgramPreviewFixture.balancedDayBID)
    )
}

#Preview("Adicionar um plano") {
    GoalSheet(
        programs: ProgramPreviewRepository.make(),
        catalog: ProgramPreviewCatalog(),
        references: ProgramPreviewFixture.references,
        mode: .add,
        planner: ProgramPreviewPlanner(nextDayID: ProgramPreviewFixture.balancedDayBID),
        now: { ProgramPreviewFixture.referenceDate },
        onFinish: { _ in }
    )
}

#Preview("Sua semana — não cabe") {
    NavigationStack {
        PlanFitFlowView(
            model: ProgramPreviewFixture.makeNotFittingFlow(),
            references: ProgramPreviewFixture.references,
            onCancel: {},
            onDone: {}
        )
    }
}

#Preview("Plano — sem objetivo ativo") {
    ProgramTabView(
        programs: ProgramPreviewRepository(programs: ProgramPreviewFixture.makePrograms(activeID: nil)),
        catalog: ProgramPreviewCatalog(),
        references: ProgramPreviewFixture.references,
        now: { ProgramPreviewFixture.referenceDate }
    )
}

#Preview("Ajustar exercícios") {
    NavigationStack {
        ProgramDetailView(
            programID: ProgramPreviewFixture.balancedID,
            programs: ProgramPreviewRepository.make(),
            catalog: ProgramPreviewCatalog(),
            references: ProgramPreviewFixture.references
        )
    }
}

#Preview("Ajustar exercícios — dia") {
    NavigationStack {
        DayEditorView(
            model: ProgramPreviewFixture.makeDetailModel(),
            dayID: ProgramPreviewFixture.balancedDayAID
        )
    }
}

#Preview("Editar exercício") {
    TargetEditorSheet(
        exerciseName: "Supino reto com barra",
        draft: ProgramDetailViewModel.TargetDraft(
            target: ExerciseTarget(
                exerciseID: ProgramPreviewFixture.benchID,
                order: 0,
                sets: 3,
                repMin: 6,
                repMax: 12,
                targetRIR: 2,
                restSeconds: 150,
                startingLoad: 40
            ),
            loadUnit: .kilograms,
            loadIncrement: 2.5,
            isBodyweight: false
        ),
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Editar exercício — segundos") {
    TargetEditorSheet(
        exerciseName: "Prancha",
        draft: ProgramDetailViewModel.TargetDraft(
            target: ExerciseTarget(
                exerciseID: ProgramPreviewFixture.benchID,
                order: 0,
                sets: 3,
                repMin: 20,
                repMax: 40,
                targetRIR: 2,
                restSeconds: 60
            ),
            loadUnit: .kilograms,
            loadIncrement: 2.5,
            isBodyweight: true,
            measure: .seconds
        ),
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Seu objetivo") {
    GoalSheet(
        programs: ProgramPreviewRepository(programs: ProgramPreviewFixture.makePrograms(activeID: ProgramPreviewFixture.combatID)),
        catalog: ProgramPreviewCatalog(),
        references: ProgramPreviewFixture.references,
        onFinish: { _ in }
    )
}

#Preview("Seu objetivo — sessão em andamento") {
    GoalSheet(
        programs: ProgramPreviewRepository.make(),
        catalog: ProgramPreviewCatalog(),
        references: ProgramPreviewFixture.references,
        mode: .change,
        isSessionInProgress: true,
        onFinish: { _ in }
    )
}

#Preview("Primeiro uso") {
    OnboardingView(
        programs: ProgramPreviewRepository.make(),
        references: ProgramPreviewFixture.references,
        catalog: ProgramPreviewCatalog(),
        onDone: {}
    )
}

// MARK: - Fixtures

/// Só valores `Sendable`, sem isolamento; o que cria objetos `@MainActor` é marcado à parte.
/// Os programas usam os ids do seed para o `GoalPlanCatalog` reconhecer os formatos.
private enum ProgramPreviewFixture {
    /// Data fixa (SPEC P11): previews determinísticos.
    static let referenceDate = Date(timeIntervalSince1970: 1_758_600_000)

    static let balancedID = GoalPlanCatalog.hypertrophyBalancedID
    static let lowerFocusID = GoalPlanCatalog.hypertrophyLowerFocusID
    static let upperFocusID = GoalPlanCatalog.hypertrophyUpperFocusID
    static let strengthID = GoalPlanCatalog.strengthID
    static let enduranceID = GoalPlanCatalog.enduranceCardioID
    static let longevityID = GoalPlanCatalog.longevityID
    static let combatID = GoalPlanCatalog.combatID
    static let balancedDayAID = UUID(uuidString: "00000000-0000-0000-0000-00000000D001") ?? UUID()
    static let balancedDayBID = UUID(uuidString: "00000000-0000-0000-0000-00000000D002") ?? UUID()

    static let benchID = UUID(uuidString: "00000000-0000-0000-0000-00000000E001") ?? UUID()

    static let exercises: [ExerciseDefinition] = [
        ExerciseDefinition(id: benchID, slug: "supino-reto-barra", name: "Supino reto com barra", primaryMuscles: [.chest], secondaryMuscles: [.triceps, .shoulders], equipment: .barbell, loadUnit: .kilograms, loadIncrement: 2.5, movementPattern: .horizontalPush),
        ExerciseDefinition(slug: "supino-halteres", name: "Supino com halteres", primaryMuscles: [.chest], secondaryMuscles: [.triceps], equipment: .dumbbell, loadUnit: .kilograms, loadIncrement: 2, movementPattern: .horizontalPush),
        ExerciseDefinition(slug: "chest-press", name: "Chest press", primaryMuscles: [.chest], equipment: .machine, loadUnit: .plates, loadIncrement: 1, movementPattern: .horizontalPush),
        ExerciseDefinition(slug: "flexao", name: "Flexão de braço", primaryMuscles: [.chest], equipment: .bodyweight, loadUnit: .kilograms, loadIncrement: 2.5, movementPattern: .horizontalPush),
        ExerciseDefinition(slug: "remada-baixa", name: "Remada baixa", primaryMuscles: [.back], secondaryMuscles: [.biceps], equipment: .cable, loadUnit: .kilograms, loadIncrement: 5, movementPattern: .horizontalPull),
        ExerciseDefinition(slug: "puxada-frente", name: "Puxada na frente", primaryMuscles: [.back], equipment: .cable, loadUnit: .kilograms, loadIncrement: 5, movementPattern: .verticalPull),
        ExerciseDefinition(slug: "agachamento-livre", name: "Agachamento livre", primaryMuscles: [.quads, .glutes], equipment: .barbell, loadUnit: .kilograms, loadIncrement: 2.5, movementPattern: .squat),
        ExerciseDefinition(slug: "leg-press-45", name: "Leg press 45°", primaryMuscles: [.quads, .glutes], equipment: .machine, loadUnit: .kilograms, loadIncrement: 5, movementPattern: .squat),
        ExerciseDefinition(slug: "stiff", name: "Stiff", primaryMuscles: [.hamstrings], secondaryMuscles: [.glutes], equipment: .barbell, loadUnit: .kilograms, loadIncrement: 2.5, movementPattern: .hinge),
        ExerciseDefinition(slug: "elevacao-lateral", name: "Elevação lateral", primaryMuscles: [.shoulders], equipment: .dumbbell, loadUnit: .kilograms, loadIncrement: 1, movementPattern: .shoulderIsolation),
        ExerciseDefinition(slug: "rosca-direta", name: "Rosca direta", primaryMuscles: [.biceps], equipment: .barbell, loadUnit: .kilograms, loadIncrement: 2, movementPattern: .elbowFlexion),
        ExerciseDefinition(slug: "triceps-corda", name: "Tríceps na corda", primaryMuscles: [.triceps], equipment: .cable, loadUnit: .level, loadIncrement: 1, movementPattern: .elbowExtension),
        ExerciseDefinition(slug: "farmer-walk", name: "Caminhada do fazendeiro com halteres", primaryMuscles: [.core], equipment: .dumbbell, loadUnit: .kilograms, loadIncrement: 2, movementPattern: .carry),
        ExerciseDefinition(slug: "caminhada-rapida", name: "Caminhada rápida", primaryMuscles: [.quads, .glutes], equipment: .bodyweight, loadUnit: .kilograms, loadIncrement: 2.5, movementPattern: .cardio),
        ExerciseDefinition(slug: "bicicleta", name: "Bicicleta ergométrica", primaryMuscles: [.quads, .glutes], equipment: .machine, loadUnit: .level, loadIncrement: 1, movementPattern: .cardio),
        ExerciseDefinition(slug: "run-intervals", name: "Intervalos de corrida", primaryMuscles: [.quads, .glutes], equipment: .bodyweight, loadUnit: .kilograms, loadIncrement: 2.5, movementPattern: .cardio),
    ]

    static func exerciseID(_ slug: String) -> UUID {
        exercises.first { $0.slug == slug }?.id ?? benchID
    }

    /// Os programas do app, com o Equilibrado ativo.
    static var programs: [ProgramTemplate] {
        makePrograms(activeID: balancedID)
    }

    /// Mesmos programas com `activeID` ativo (`nil`: nenhum ativo).
    static func makePrograms(activeID: UUID?) -> [ProgramTemplate] {
        makePrograms(activeIDs: activeID.map { Set([$0]) } ?? Set<UUID>())
    }

    /// Mesmos programas com vários ativos (SPEC §7.15 M1).
    static func makePrograms(activeIDs: Set<UUID>) -> [ProgramTemplate] {
        [
            ProgramTemplate(
                id: balancedID,
                name: "Hipertrofia — Equilibrado",
                days: [
                    day(id: balancedDayAID, "Dia A — Superior", order: 0, slugs: ["supino-reto-barra", "remada-baixa", "elevacao-lateral", "rosca-direta", "triceps-corda"], startingLoads: [40, nil, nil, nil, 6]),
                    day(id: balancedDayBID, "Dia B — Inferior", order: 1, slugs: ["agachamento-livre", "stiff", "leg-press-45"]),
                    day("Dia C — Superior", order: 2, slugs: ["supino-halteres", "puxada-frente", "elevacao-lateral", "rosca-direta", "triceps-corda"]),
                    day("Dia D — Inferior", order: 3, slugs: ["leg-press-45", "stiff", "farmer-walk"]),
                ],
                isActive: activeIDs.contains(balancedID),
                goal: .hypertrophy,
                summary: "Quatro dias que alternam superior e inferior, com cada grupo duas vezes por semana."
            ),
            ProgramTemplate(
                id: lowerFocusID,
                name: "Hipertrofia — Foco inferior",
                days: [
                    day("Dia A — Inferior (quadríceps e glúteos)", order: 0, slugs: ["agachamento-livre", "leg-press-45", "stiff"]),
                    day("Dia B — Superior (manutenção)", order: 1, slugs: ["supino-reto-barra", "remada-baixa"]),
                    day("Dia C — Inferior (posteriores e glúteos)", order: 2, slugs: ["stiff", "leg-press-45"]),
                    day("Dia D — Superior (manutenção)", order: 3, slugs: ["supino-halteres", "puxada-frente"]),
                ],
                isActive: activeIDs.contains(lowerFocusID),
                goal: .hypertrophy,
                summary: "Glúteos e pernas com mais volume; superior em manutenção."
            ),
            ProgramTemplate(
                id: upperFocusID,
                name: "Hipertrofia — Foco superior",
                days: [
                    day("Dia A — Superior", order: 0, slugs: ["supino-reto-barra", "remada-baixa", "puxada-frente"]),
                    day("Dia B — Inferior (manutenção)", order: 1, slugs: ["agachamento-livre", "stiff"]),
                    day("Dia C — Superior", order: 2, slugs: ["supino-halteres", "remada-baixa", "rosca-direta"]),
                    day("Dia D — Inferior (manutenção)", order: 3, slugs: ["leg-press-45", "stiff"]),
                ],
                isActive: activeIDs.contains(upperFocusID),
                goal: .hypertrophy,
                summary: "Peito, ombros, braços e costas com mais volume; inferior em manutenção."
            ),
            ProgramTemplate(
                id: strengthID,
                name: "Força",
                days: [
                    day("Dia A — Agachamento e supino", order: 0, slugs: ["agachamento-livre", "supino-reto-barra", "remada-baixa"]),
                    day("Dia B — Levantamento terra", order: 1, slugs: ["stiff", "puxada-frente"]),
                    day("Dia C — Agachamento e supino", order: 2, slugs: ["agachamento-livre", "supino-halteres"]),
                ],
                isActive: activeIDs.contains(strengthID),
                goal: .strength
            ),
            // SPEC RF-48 (2.3): o Cardio focado no VO2máx, um aeróbico por dia.
            ProgramTemplate(
                id: enduranceID,
                name: "Cardio",
                days: [
                    day("Dia A — Base contínua", order: 0, slugs: ["caminhada-rapida"]),
                    day("Dia B — Intervalos 4 × 4", order: 1, slugs: ["run-intervals"]),
                    day("Dia C — Longo e leve", order: 2, slugs: ["bicicleta"]),
                ],
                isActive: activeIDs.contains(enduranceID),
                goal: .endurance
            ),
            ProgramTemplate(
                id: longevityID,
                name: "Longevidade",
                days: [
                    day("Dia A — Corpo inteiro", order: 0, slugs: ["leg-press-45", "chest-press", "farmer-walk"]),
                    day("Dia B — Corpo inteiro", order: 1, slugs: ["agachamento-livre", "remada-baixa"]),
                    day("Dia C — Corpo inteiro", order: 2, slugs: ["stiff", "puxada-frente"]),
                ],
                isActive: activeIDs.contains(longevityID),
                goal: .longevity
            ),
            ProgramTemplate(
                id: combatID,
                name: "Combate",
                days: [
                    day("Dia A — Potência, agachamento e pegada", order: 0, slugs: ["agachamento-livre", "remada-baixa", "farmer-walk"]),
                    day("Dia B — Salto, terra e supino", order: 1, slugs: ["stiff", "supino-reto-barra"]),
                    day("Dia C — Potência rotacional e ombros", order: 2, slugs: ["elevacao-lateral", "farmer-walk"]),
                ],
                isActive: activeIDs.contains(combatID),
                goal: .combat,
                summary: "Força máxima, potência, pegada e tronco."
            ),
        ]
    }

    private static func day(
        id: UUID = UUID(),
        _ name: String,
        order: Int,
        slugs: [String],
        startingLoads: [Double?] = []
    ) -> ProgramDayTemplate {
        let targets = slugs.enumerated().map { index, slug in
            ExerciseTarget(
                exerciseID: exerciseID(slug),
                order: index,
                sets: 3,
                repMin: 8,
                repMax: 12,
                targetRIR: 2,
                restSeconds: 120,
                startingLoad: index < startingLoads.count ? startingLoads[index] : nil
            )
        }
        return ProgramDayTemplate(id: id, name: name, order: order, exercises: targets)
    }

    /// Catálogo mínimo para o "Por quê?" aparecer em todos os objetivos.
    static let references: ReferenceCatalog = {
        let reference = ScientificReference(
            id: "schoenfeld-2017-volume",
            authors: "Schoenfeld BJ, Ogborn D, Krieger JW",
            year: 2017,
            title: "Dose-response relationship between weekly resistance training volume and increases in muscle mass",
            source: "Journal of Sports Sciences",
            doi: "10.1080/02640414.2016.1210197",
            level: .metaAnalysis,
            summary: "Mais séries semanais por grupo muscular trazem mais hipertrofia."
        )
        var topics: [String: [String]] = [:]
        var explanations: [String: String] = [:]
        for goal in ProgramGoal.allCases {
            topics[goal.referenceTopic] = [reference.id]
            explanations[goal.referenceTopic] = "Exemplo de explicação para \(goal.displayName)."
        }
        return ReferenceCatalog(version: 1, references: [reference], topics: topics, explanations: explanations)
    }()

    /// ViewModel já lido, para o preview do editor de dia (quem chama `refresh()` no app é a
    /// tela "Ajustar exercícios").
    @MainActor
    static func makeDetailModel() -> ProgramDetailViewModel {
        let model = ProgramDetailViewModel(
            programID: balancedID,
            programs: ProgramPreviewRepository.make(),
            catalog: ProgramPreviewCatalog()
        )
        model.refresh()
        return model
    }

    /// "Sua semana" de Hipertrofia + Cardio que não cabe, com duas saídas (SPEC §7.15 M5).
    @MainActor
    static func makeNotFittingFlow() -> PlanFitFlowModel {
        let planner = ProgramPreviewPlanner(nextDayID: balancedDayBID)
        planner.fitsWeek = false
        let repository = ProgramPreviewRepository.make()
        let all = programs
        let current = all.first { $0.id == balancedID } ?? ProgramTemplate(name: "Hipertrofia", goal: .hypertrophy)
        let candidate = all.first { $0.id == enduranceID } ?? ProgramTemplate(name: "Cardio", goal: .endurance)
        let date = referenceDate
        let flow = PlanFitFlowModel(
            purpose: .addPlan(current: current, candidate: candidate),
            programs: repository,
            planner: planner,
            now: { date }
        )
        flow.next()
        flow.next()
        return flow
    }

    /// Uma semana de Hipertrofia + Cardio (SPEC §7.15 M4), com os nomes dos dias.
    static let week = WeekSchedule(
        slots: [
            PlannedSlot(weekday: .monday, programID: balancedID, indexInWeek: 0, kind: .strength, orderInDay: 0, dayName: "Dia A — Superior"),
            PlannedSlot(weekday: .tuesday, programID: enduranceID, indexInWeek: 0, kind: .cardio, orderInDay: 0, dayName: "Dia A — Base contínua", cardioIntensity: .moderate),
            PlannedSlot(weekday: .wednesday, programID: balancedID, indexInWeek: 1, kind: .strength, orderInDay: 0, dayName: "Dia B — Inferior"),
            PlannedSlot(weekday: .thursday, programID: balancedID, indexInWeek: 2, kind: .strength, orderInDay: 0, dayName: "Dia C — Superior"),
            PlannedSlot(weekday: .thursday, programID: enduranceID, indexInWeek: 1, kind: .cardio, orderInDay: 1, dayName: "Dia B — Intervalos 4 × 4", cardioIntensity: .vigorous),
            PlannedSlot(weekday: .saturday, programID: balancedID, indexInWeek: 3, kind: .strength, orderInDay: 0, dayName: "Dia D — Inferior"),
            PlannedSlot(weekday: .sunday, programID: enduranceID, indexInWeek: 2, kind: .cardio, orderInDay: 0, dayName: "Dia C — Longo e leve", cardioIntensity: .light),
        ],
        notes: [.strengthBeforeCardio(.thursday)]
    )
}

// MARK: - Doubles

/// Repositório em memória com o comportamento do contrato de `ProgramRepositoring`, o bastante
/// para interagir nos previews (ativar, duplicar, reordenar, trocar, editar).
@MainActor
private final class ProgramPreviewRepository: ProgramRepositoring {
    private var programs: [ProgramTemplate]

    init(programs: [ProgramTemplate]) {
        self.programs = programs
    }

    static func make() -> ProgramPreviewRepository {
        ProgramPreviewRepository(programs: ProgramPreviewFixture.programs)
    }

    func allPrograms() throws -> [ProgramTemplate] {
        programs.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive {
                return lhs.isActive
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func program(id: UUID) throws -> ProgramTemplate? {
        programs.first { $0.id == id }
    }

    func activate(programID: UUID) throws {
        guard programs.contains(where: { $0.id == programID }) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        programs = programs.map { Self.rebuild($0, isActive: $0.id == programID) }
    }

    /// SPEC §7.15 M1: até dois ativos, de objetivos diferentes.
    func addActivePlan(programID: UUID) throws {
        guard let program = programs.first(where: { $0.id == programID }) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        guard !program.isActive else { return }
        let actives = programs.filter(\.isActive)
        guard
            actives.count < ActivePlanOrder.maxActivePlans,
            !actives.contains(where: { $0.effectiveGoal == program.effectiveGoal })
        else {
            throw ProgramRepositoryError.invalidParameters("Só dá para ter dois planos, de objetivos diferentes.")
        }
        try updateProgram(programID) { Self.rebuild($0, isActive: true) }
    }

    /// SPEC §7.15 M8: nunca tira o último.
    func removeActivePlan(programID: UUID) throws {
        guard let program = programs.first(where: { $0.id == programID }) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        guard program.isActive else { return }
        guard programs.filter(\.isActive).count > 1 else {
            throw ProgramRepositoryError.invalidParameters("Sempre fica um plano ativo.")
        }
        try updateProgram(programID) { Self.rebuild($0, isActive: false) }
    }

    func rename(programID: UUID, to name: String) throws {
        try updateProgram(programID) { Self.rebuild($0, name: name) }
    }

    func setGoal(programID: UUID, goal: ProgramGoal, applyDefaults: Bool) throws {
        try updateProgram(programID) { Self.rebuild($0, goal: goal) }
    }

    func duplicate(programID: UUID, name: String, now: Date) throws -> UUID {
        guard let original = programs.first(where: { $0.id == programID }) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        let copy = ProgramTemplate(
            id: UUID(),
            name: name,
            days: original.days.map { day in
                ProgramDayTemplate(
                    id: UUID(),
                    name: day.name,
                    order: day.order,
                    exercises: day.exercises.map { Self.rebuild($0, id: UUID()) }
                )
            },
            isActive: false,
            goal: original.goal,
            summary: original.summary
        )
        programs.append(copy)
        return copy.id
    }

    func delete(programID: UUID) throws {
        guard let program = programs.first(where: { $0.id == programID }) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        guard !program.isActive else {
            throw ProgramRepositoryError.cannotDeleteActive
        }
        programs.removeAll { $0.id == programID }
    }

    func addExercise(exerciseID: UUID, toDay dayID: UUID) throws -> UUID {
        let newID = UUID()
        try updateDay(dayID) { targets in
            guard targets.count < ProgramLimits.maxExercisesPerDay else {
                throw ProgramRepositoryError.tooManyExercises
            }
            return targets + [ExerciseTarget(id: newID, exerciseID: exerciseID, order: targets.count)]
        }
        return newID
    }

    func removeTarget(id: UUID) throws {
        try updateDay(containingTarget: id) { targets in
            guard targets.count > ProgramLimits.minExercisesPerDay else {
                throw ProgramRepositoryError.tooFewExercises
            }
            return targets.filter { $0.id != id }
        }
    }

    func moveTarget(id: UUID, toIndex newIndex: Int) throws {
        try updateDay(containingTarget: id) { targets in
            guard let from = targets.firstIndex(where: { $0.id == id }) else { return targets }
            var reordered = targets
            let moved = reordered.remove(at: from)
            reordered.insert(moved, at: min(max(newIndex, 0), reordered.count))
            return reordered
        }
    }

    func replaceExercise(targetID: UUID, with exerciseID: UUID) throws {
        try updateDay(containingTarget: targetID) { targets in
            targets.map { $0.id == targetID ? Self.rebuild($0, exerciseID: exerciseID) : $0 }
        }
    }

    func updateTarget(id: UUID, sets: Int, repMin: Int, repMax: Int, targetRIR: Int, restSeconds: Int, startingLoad: Double?) throws {
        try updateDay(containingTarget: id) { targets in
            targets.map { target in
                guard target.id == id else { return target }
                return ExerciseTarget(
                    id: target.id,
                    exerciseID: target.exerciseID,
                    order: target.order,
                    sets: sets,
                    repMin: repMin,
                    repMax: repMax,
                    targetRIR: targetRIR,
                    restSeconds: restSeconds,
                    startingLoad: startingLoad
                )
            }
        }
    }

    // MARK: - Dias do programa (T2.22, RF-36)

    func addDay(programID: UUID, name: String?) throws -> UUID {
        guard let programIndex = programs.firstIndex(where: { $0.id == programID }) else {
            throw ProgramRepositoryError.programNotFound(programID)
        }
        guard programs[programIndex].days.count < ProgramLimits.maxDays else {
            throw ProgramRepositoryError.tooManyDays
        }

        let dayName: String
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw ProgramRepositoryError.invalidParameters("O nome não pode ficar vazio.")
            }
            dayName = trimmed
        } else {
            dayName = Self.nextDayLabel(existingNames: programs[programIndex].days.map { $0.name })
        }

        let newID = UUID()
        let order = (programs[programIndex].days.map { $0.order }.max() ?? -1) + 1
        var days = programs[programIndex].days
        days.append(ProgramDayTemplate(id: newID, name: dayName, order: order))
        programs[programIndex] = Self.rebuild(programs[programIndex], days: days)
        return newID
    }

    func removeDay(id: UUID) throws {
        guard let programIndex = programs.firstIndex(where: { $0.days.contains { $0.id == id } }) else {
            throw ProgramRepositoryError.dayNotFound(id)
        }
        let remaining = programs[programIndex].days.filter { $0.id != id }
        guard remaining.count >= ProgramLimits.minDays else {
            throw ProgramRepositoryError.tooFewDays
        }
        programs[programIndex] = Self.rebuild(programs[programIndex], days: Self.renumberedDays(remaining))
    }

    func renameDay(id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ProgramRepositoryError.invalidParameters("O nome não pode ficar vazio.")
        }
        guard let programIndex = programs.firstIndex(where: { $0.days.contains { $0.id == id } }) else {
            throw ProgramRepositoryError.dayNotFound(id)
        }
        let days = programs[programIndex].days.map { day in
            day.id == id ? ProgramDayTemplate(id: day.id, name: trimmed, order: day.order, exercises: day.exercises) : day
        }
        programs[programIndex] = Self.rebuild(programs[programIndex], days: days)
    }

    func moveDay(id: UUID, toIndex newIndex: Int) throws {
        guard let programIndex = programs.firstIndex(where: { $0.days.contains { $0.id == id } }) else {
            throw ProgramRepositoryError.dayNotFound(id)
        }
        var ordered = programs[programIndex].days.sorted { $0.order < $1.order }
        guard newIndex >= 0, newIndex < ordered.count else {
            throw ProgramRepositoryError.invalidParameters("Posição fora da lista de dias.")
        }
        guard let currentIndex = ordered.firstIndex(where: { $0.id == id }) else {
            throw ProgramRepositoryError.dayNotFound(id)
        }
        let moving = ordered.remove(at: currentIndex)
        ordered.insert(moving, at: min(max(newIndex, 0), ordered.count))
        programs[programIndex] = Self.rebuild(programs[programIndex], days: Self.renumberedDays(ordered))
    }

    /// Reatribui `order` 0…n-1 na ordem atual, sem buracos (mesmo papel do `ProgramRepository`).
    private static func renumberedDays(_ days: [ProgramDayTemplate]) -> [ProgramDayTemplate] {
        days.sorted { $0.order < $1.order }.enumerated().map { index, day in
            ProgramDayTemplate(id: day.id, name: day.name, order: index, exercises: day.exercises)
        }
    }

    /// "Dia " + a primeira letra livre (mesma regra de `ProgramRepository.nextDayLabel`).
    private static func nextDayLabel(existingNames: [String]) -> String {
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            let candidate = "Dia \(letter)"
            let isUsed = existingNames.contains { name in
                name == candidate || name.hasPrefix(candidate + " ")
            }
            if !isUsed {
                return candidate
            }
        }
        return "Dia \(existingNames.count + 1)"
    }

    // MARK: - Reconstrução (os DTOs são imutáveis)

    private func updateProgram(_ id: UUID, _ transform: (ProgramTemplate) -> ProgramTemplate) throws {
        guard let index = programs.firstIndex(where: { $0.id == id }) else {
            throw ProgramRepositoryError.programNotFound(id)
        }
        programs[index] = transform(programs[index])
    }

    private func updateDay(_ dayID: UUID, _ transform: ([ExerciseTarget]) throws -> [ExerciseTarget]) throws {
        for (programIndex, program) in programs.enumerated() {
            guard let dayIndex = program.days.firstIndex(where: { $0.id == dayID }) else { continue }
            try apply(transform, programIndex: programIndex, dayIndex: dayIndex)
            return
        }
        throw ProgramRepositoryError.dayNotFound(dayID)
    }

    private func updateDay(containingTarget targetID: UUID, _ transform: ([ExerciseTarget]) throws -> [ExerciseTarget]) throws {
        for (programIndex, program) in programs.enumerated() {
            for (dayIndex, day) in program.days.enumerated() where day.exercises.contains(where: { $0.id == targetID }) {
                try apply(transform, programIndex: programIndex, dayIndex: dayIndex)
                return
            }
        }
        throw ProgramRepositoryError.targetNotFound(targetID)
    }

    /// Aplica a transformação aos alvos ordenados e renumera `order` de 0 a n-1.
    private func apply(
        _ transform: ([ExerciseTarget]) throws -> [ExerciseTarget],
        programIndex: Int,
        dayIndex: Int
    ) throws {
        let program = programs[programIndex]
        let day = program.days[dayIndex]
        let sorted = day.exercises.sorted { $0.order < $1.order }
        let renumbered = try transform(sorted).enumerated().map { index, target in
            Self.rebuild(target, order: index)
        }
        var days = program.days
        days[dayIndex] = ProgramDayTemplate(id: day.id, name: day.name, order: day.order, exercises: renumbered)
        programs[programIndex] = Self.rebuild(program, days: days)
    }

    private static func rebuild(
        _ program: ProgramTemplate,
        name: String? = nil,
        days: [ProgramDayTemplate]? = nil,
        isActive: Bool? = nil,
        goal: ProgramGoal? = nil
    ) -> ProgramTemplate {
        ProgramTemplate(
            id: program.id,
            name: name ?? program.name,
            days: days ?? program.days,
            isActive: isActive ?? program.isActive,
            goal: goal ?? program.goal,
            summary: program.summary
        )
    }

    private static func rebuild(
        _ target: ExerciseTarget,
        id: UUID? = nil,
        exerciseID: UUID? = nil,
        order: Int? = nil
    ) -> ExerciseTarget {
        ExerciseTarget(
            id: id ?? target.id,
            exerciseID: exerciseID ?? target.exerciseID,
            order: order ?? target.order,
            sets: target.sets,
            repMin: target.repMin,
            repMax: target.repMax,
            targetRIR: target.targetRIR,
            restSeconds: target.restSeconds,
            startingLoad: target.startingLoad
        )
    }
}

/// Planejador mínimo: `nextPlan` devolve o dia `nextDayID` do Equilibrado (a marca "próxima").
@MainActor
private final class ProgramPreviewPlanner: SessionPlanning {
    private let nextDayID: UUID
    /// Falso: a conferência da semana não cabe e mostra as saídas (SPEC §7.15 M5).
    var fitsWeek = true
    private var preferences = WeekPreferences.default

    init(nextDayID: UUID) {
        self.nextDayID = nextDayID
    }

    func nextPlan(now: Date) throws -> SessionPlan? {
        SessionPlan(
            programID: ProgramPreviewFixture.balancedID,
            programName: "Hipertrofia — Equilibrado",
            programDayID: nextDayID,
            programDayName: "Dia B — Inferior",
            exercises: [],
            generatedAt: now
        )
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        nil
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        UUID()
    }

    /// Só o Equilibrado marca o próximo dia; o Cardio fica sem marca no preview.
    func nextPlan(forProgramID programID: UUID, now: Date) throws -> SessionPlan? {
        guard programID == ProgramPreviewFixture.balancedID else { return nil }
        return try nextPlan(now: now)
    }

    func weekSchedule(now: Date) throws -> WeekSchedule? {
        ProgramPreviewFixture.week
    }

    func weekPreferences() -> WeekPreferences {
        preferences
    }

    func saveWeekPreferences(_ preferences: WeekPreferences) throws {
        self.preferences = preferences
    }

    func fitCheck(programIDs: [UUID], preferences: WeekPreferences, now: Date) throws -> FitResult {
        let week = ProgramPreviewFixture.week
        guard !fitsWeek else {
            return FitResult(schedule: week)
        }
        var everyDay = preferences
        everyDay.availableDays = Set(PlanWeekday.allCases)
        let fewerChange = FitChange.fewerSessions(programID: ProgramPreviewFixture.enduranceID, perWeek: 2)
        return FitResult(
            schedule: nil,
            problems: [.notEnoughDays(needed: 7, available: 6)],
            alternatives: [
                FitAlternative(changes: [.addDays([.sunday])], preferences: everyDay, schedule: week),
                FitAlternative(
                    changes: [fewerChange],
                    preferences: fewerChange.applied(to: preferences),
                    schedule: WeekSchedule(slots: week.slots.filter { $0.weekday != .sunday })
                ),
            ]
        )
    }
}

@MainActor
private final class ProgramPreviewCatalog: CatalogRepositoring {
    private var exercises: [ExerciseDefinition]

    init() {
        self.exercises = ProgramPreviewFixture.exercises
    }

    func allExercises(includeArchived: Bool) throws -> [ExerciseDefinition] {
        exercises.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func exercise(id: UUID) throws -> ExerciseDefinition? {
        exercises.first { $0.id == id }
    }

    func createExercise(_ draft: ExerciseDraft) throws -> UUID {
        let definition = ExerciseDefinition(
            slug: "custom-\(exercises.count)",
            name: draft.name,
            primaryMuscles: draft.primaryMuscles,
            secondaryMuscles: draft.secondaryMuscles,
            equipment: draft.equipment,
            loadUnit: draft.loadUnit,
            loadIncrement: draft.loadIncrement,
            isUnilateral: draft.isUnilateral,
            machineNotes: draft.machineNotes,
            movementPattern: draft.movementPattern,
            isCustom: true
        )
        exercises.append(definition)
        return definition.id
    }

    func updateExercise(id: UUID, with draft: ExerciseDraft) throws {}

    func setArchived(id: UUID, _ archived: Bool) throws {}
}
