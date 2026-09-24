import Foundation
import SwiftUI
import TrainerCore

// Doubles e fixtures só para os #Preview da feature Programa (AGENTS R9: previews usam fakes).
// Tudo privado ao arquivo e prefixado por "Program" para não colidir com doubles de outras
// features; por isso os previews da aba Programa vivem aqui, e não em cada arquivo de view.

// MARK: - Previews

#Preview("Programa — lista") {
    ProgramTabView(
        programs: ProgramPreviewRepository.make(),
        catalog: ProgramPreviewCatalog(),
        references: ProgramPreviewFixture.references,
        now: { ProgramPreviewFixture.referenceDate }
    )
}

#Preview("Programa — detalhe") {
    NavigationStack {
        ProgramDetailView(
            programID: ProgramPreviewFixture.fullBodyID,
            programs: ProgramPreviewRepository.make(),
            catalog: ProgramPreviewCatalog(),
            references: ProgramPreviewFixture.references
        )
    }
}

#Preview("Programa — dia") {
    NavigationStack {
        DayEditorView(
            model: ProgramPreviewFixture.makeDetailModel(),
            dayID: ProgramPreviewFixture.fullBodyDayAID
        )
    }
}

#Preview("Programa — editar exercício") {
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

#Preview("Programa — objetivo") {
    NavigationStack {
        GoalPickerView(
            selected: .hypertrophy,
            references: ProgramPreviewFixture.references,
            onChoose: { _, _ in }
        )
    }
}

#Preview("Onboarding") {
    OnboardingView(
        programs: ProgramPreviewRepository.make(),
        references: ProgramPreviewFixture.references,
        onDone: {}
    )
}

// MARK: - Fixtures

/// Só valores `Sendable`, sem isolamento; o que cria objetos `@MainActor` é marcado à parte.
private enum ProgramPreviewFixture {
    /// Data fixa (SPEC P11): previews determinísticos.
    static let referenceDate = Date(timeIntervalSince1970: 1_758_600_000)

    static let fullBodyID = UUID(uuidString: "00000000-0000-0000-0000-00000000A001") ?? UUID()
    static let lowerFocusID = UUID(uuidString: "00000000-0000-0000-0000-00000000A002") ?? UUID()
    static let upperFocusID = UUID(uuidString: "00000000-0000-0000-0000-00000000A003") ?? UUID()
    static let combatID = UUID(uuidString: "00000000-0000-0000-0000-00000000A004") ?? UUID()
    static let fullBodyDayAID = UUID(uuidString: "00000000-0000-0000-0000-00000000D001") ?? UUID()

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
        ExerciseDefinition(slug: "farmer-walk", name: "Farmer's walk", primaryMuscles: [.core], equipment: .dumbbell, loadUnit: .kilograms, loadIncrement: 2, movementPattern: .carry),
    ]

    static func exerciseID(_ slug: String) -> UUID {
        exercises.first { $0.slug == slug }?.id ?? benchID
    }

    static var programs: [ProgramTemplate] {
        [
            ProgramTemplate(
                id: fullBodyID,
                name: "Hipertrofia — completo",
                days: [
                    day(id: fullBodyDayAID, "Dia A — Superior", order: 0, slugs: ["supino-reto-barra", "remada-baixa", "elevacao-lateral", "rosca-direta", "triceps-corda"], startingLoads: [40, nil, nil, nil, 6]),
                    day("Dia B — Inferior", order: 1, slugs: ["agachamento-livre", "leg-press-45", "stiff"]),
                    day("Dia C — Superior", order: 2, slugs: ["supino-halteres", "puxada-frente", "elevacao-lateral"]),
                ],
                isActive: true,
                goal: .hypertrophy,
                summary: "Corpo inteiro equilibrado em três dias (ABC)."
            ),
            ProgramTemplate(
                id: lowerFocusID,
                name: "Hipertrofia — foco inferior",
                days: [
                    day("Dia A — Pernas e glúteos", order: 0, slugs: ["agachamento-livre", "leg-press-45", "stiff"]),
                    day("Dia B — Superior (manutenção)", order: 1, slugs: ["supino-reto-barra", "remada-baixa"]),
                ],
                goal: .hypertrophy,
                summary: "Glúteos e pernas com mais volume; superior em manutenção."
            ),
            ProgramTemplate(
                id: upperFocusID,
                name: "Hipertrofia — foco superior",
                days: [
                    day("Dia A — Peito e costas", order: 0, slugs: ["supino-reto-barra", "remada-baixa", "puxada-frente"]),
                    day("Dia B — Inferior (manutenção)", order: 1, slugs: ["agachamento-livre", "stiff"]),
                ],
                goal: .hypertrophy,
                summary: "Peito, ombros, braços e costas com mais volume; inferior em manutenção."
            ),
            ProgramTemplate(
                id: combatID,
                name: "Combate",
                days: [
                    day("Dia A — Força e pegada", order: 0, slugs: ["agachamento-livre", "remada-baixa", "farmer-walk"]),
                ],
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
    /// tela do programa).
    @MainActor
    static func makeDetailModel() -> ProgramDetailViewModel {
        let model = ProgramDetailViewModel(
            programID: fullBodyID,
            programs: ProgramPreviewRepository.make(),
            catalog: ProgramPreviewCatalog()
        )
        model.refresh()
        return model
    }
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
