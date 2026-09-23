import Foundation
import SwiftUI
import TrainerCore

// Doubles e fixtures só para os #Preview da feature Catalog (AGENTS R9: previews usam fakes).
// Tudo privado ao arquivo e prefixado por "Catalog" para não colidir com doubles de outras
// features; por isso os previews do catálogo vivem aqui, e não em cada arquivo de view.

// MARK: - Previews

#Preview("Catálogo") {
    NavigationStack {
        CatalogListView(catalog: CatalogPreviewRepository())
    }
}

#Preview("Catálogo — vazio") {
    NavigationStack {
        CatalogListView(catalog: CatalogPreviewRepository(exercises: [], archived: []))
    }
}

#Preview("Seletor — trocar exercício") {
    ExercisePickerView(
        exercises: CatalogPreviewFixture.activeExercises,
        title: "Trocar exercício",
        highlighted: CatalogPreviewFixture.benchSubstitutes,
        onPick: { _ in },
        onCancel: {}
    )
}

#Preview("Seletor — adicionar ao dia") {
    ExercisePickerView(
        exercises: CatalogPreviewFixture.activeExercises,
        title: "Adicionar exercício",
        onPick: { _ in },
        onCancel: {}
    )
}

#Preview("Editor — novo") {
    ExerciseEditorView(model: ExerciseEditorViewModel(catalog: CatalogPreviewRepository()))
}

#Preview("Editor — exercício do catálogo") {
    ExerciseEditorView(
        model: ExerciseEditorViewModel(
            catalog: CatalogPreviewRepository(),
            exercise: CatalogPreviewFixture.machineBench
        )
    )
}

#Preview("Editor — meu exercício") {
    ExerciseEditorView(
        model: ExerciseEditorViewModel(
            catalog: CatalogPreviewRepository(),
            exercise: CatalogPreviewFixture.customCurl
        )
    )
}

#Preview("Grupos musculares") {
    CatalogPreviewSelectorHost()
}

#Preview("Linha") {
    List {
        CatalogExerciseRow(exercise: CatalogPreviewFixture.barbellBench)
        CatalogExerciseRow(exercise: CatalogPreviewFixture.customCurl)
        CatalogExerciseRow(exercise: CatalogPreviewFixture.archivedFly, isArchived: true)
    }
}

// MARK: - Hosts

/// Estado local só para ver os chips alternando no canvas.
private struct CatalogPreviewSelectorHost: View {
    @State private var primary: [MuscleGroup] = [.chest]
    @State private var secondary: [MuscleGroup] = [.triceps, .shoulders]

    var body: some View {
        Form {
            Section("Grupos primários") {
                MuscleGroupSelector(selected: primary) { group in
                    if let index = primary.firstIndex(of: group) {
                        primary.remove(at: index)
                    } else {
                        primary.append(group)
                        secondary.removeAll { $0 == group }
                    }
                }
            }
            Section("Grupos secundários") {
                MuscleGroupSelector(selected: secondary, disabled: Set(primary)) { group in
                    if let index = secondary.firstIndex(of: group) {
                        secondary.remove(at: index)
                    } else {
                        secondary.append(group)
                    }
                }
            }
        }
    }
}

// MARK: - Fixtures

private enum CatalogPreviewFixture {
    static let barbellBench = ExerciseDefinition(
        slug: "supino-reto-barra",
        name: "Supino reto com barra",
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .shoulders],
        equipment: .barbell,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        movementPattern: .horizontalPush
    )
    static let dumbbellBench = ExerciseDefinition(
        slug: "supino-halteres",
        name: "Supino com halteres",
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .shoulders],
        equipment: .dumbbell,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        movementPattern: .horizontalPush
    )
    static let machineBench = ExerciseDefinition(
        slug: "supino-maquina",
        name: "Supino na máquina",
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps],
        equipment: .machine,
        loadUnit: .kilograms,
        loadIncrement: 5,
        machineNotes: "Assento na altura 3, pegada neutra.",
        movementPattern: .horizontalPush
    )
    static let pushUp = ExerciseDefinition(
        slug: "flexao",
        name: "Flexão de braço",
        primaryMuscles: [.chest],
        secondaryMuscles: [.triceps, .core],
        equipment: .bodyweight,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        movementPattern: .horizontalPush
    )
    static let latPulldown = ExerciseDefinition(
        slug: "puxada-frontal",
        name: "Puxada frontal",
        primaryMuscles: [.back],
        secondaryMuscles: [.biceps],
        equipment: .cable,
        loadUnit: .kilograms,
        loadIncrement: 5,
        movementPattern: .verticalPull
    )
    static let machineRow = ExerciseDefinition(
        slug: "remada-maquina",
        name: "Remada na máquina",
        primaryMuscles: [.back],
        secondaryMuscles: [.biceps],
        equipment: .machine,
        loadUnit: .level,
        loadIncrement: 1,
        machineNotes: "Pino no 7, peito apoiado.",
        movementPattern: .horizontalPull
    )
    static let legPress = ExerciseDefinition(
        slug: "leg-press-45",
        name: "Leg press 45°",
        primaryMuscles: [.quads, .glutes],
        secondaryMuscles: [.hamstrings],
        equipment: .machine,
        loadUnit: .kilograms,
        loadIncrement: 5,
        machineNotes: "Encosto no 2.",
        movementPattern: .squat
    )
    static let legExtension = ExerciseDefinition(
        slug: "cadeira-extensora",
        name: "Cadeira extensora",
        primaryMuscles: [.quads],
        equipment: .machine,
        loadUnit: .plates,
        loadIncrement: 1,
        movementPattern: .kneeExtension
    )
    static let hipThrust = ExerciseDefinition(
        slug: "elevacao-pelvica",
        name: "Elevação pélvica",
        primaryMuscles: [.glutes],
        secondaryMuscles: [.hamstrings],
        equipment: .barbell,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        movementPattern: .hipThrust
    )
    static let splitSquat = ExerciseDefinition(
        slug: "agachamento-bulgaro",
        name: "Agachamento búlgaro",
        primaryMuscles: [.quads, .glutes],
        equipment: .dumbbell,
        loadUnit: .kilograms,
        loadIncrement: 2.5,
        isUnilateral: true,
        movementPattern: .lunge
    )
    static let customCurl = ExerciseDefinition(
        slug: "rosca-banco-predio",
        name: "Rosca no banco do prédio",
        primaryMuscles: [.biceps],
        equipment: .dumbbell,
        loadUnit: .kilograms,
        loadIncrement: 1.25,
        movementPattern: .elbowFlexion,
        isCustom: true
    )
    static let archivedFly = ExerciseDefinition(
        slug: "voador",
        name: "Voador",
        primaryMuscles: [.chest],
        equipment: .machine,
        loadUnit: .kilograms,
        loadIncrement: 5,
        movementPattern: .chestFly
    )

    static let activeExercises: [ExerciseDefinition] = [
        barbellBench, dumbbellBench, machineBench, pushUp, latPulldown, machineRow,
        legPress, legExtension, hipThrust, splitSquat, customCurl,
    ]
    static let allExercises: [ExerciseDefinition] = activeExercises + [archivedFly]
    /// Substitutos do supino reto na ordem de semelhança que o planejador devolveria (RF-34).
    static let benchSubstitutes: [ExerciseDefinition] = [dumbbellBench, machineBench, pushUp]
}

// MARK: - Doubles

/// Catálogo em memória: cria, edita e arquiva sem SwiftData.
@MainActor
private final class CatalogPreviewRepository: CatalogRepositoring {
    private var exercises: [ExerciseDefinition]
    private var archived: Set<UUID>

    init(
        exercises: [ExerciseDefinition] = CatalogPreviewFixture.allExercises,
        archived: Set<UUID> = [CatalogPreviewFixture.archivedFly.id]
    ) {
        self.exercises = exercises
        self.archived = archived
    }

    func allExercises(includeArchived: Bool) throws -> [ExerciseDefinition] {
        exercises
            .filter { includeArchived || !archived.contains($0.id) }
            .sorted { $0.name < $1.name }
    }

    func exercise(id: UUID) throws -> ExerciseDefinition? {
        exercises.first { $0.id == id }
    }

    func createExercise(_ draft: ExerciseDraft) throws -> UUID {
        guard draft.isValid else { throw CatalogRepositoryError.invalidDraft }
        let created = Self.definition(
            from: draft,
            id: UUID(),
            slug: "meu-exercicio-\(exercises.count + 1)",
            isCustom: true
        )
        exercises.append(created)
        return created.id
    }

    func updateExercise(id: UUID, with draft: ExerciseDraft) throws {
        guard draft.isValid else { throw CatalogRepositoryError.invalidDraft }
        guard let index = exercises.firstIndex(where: { $0.id == id }) else {
            throw CatalogRepositoryError.exerciseNotFound(id)
        }
        let current = exercises[index]
        exercises[index] = Self.definition(from: draft, id: id, slug: current.slug, isCustom: current.isCustom)
    }

    func setArchived(id: UUID, _ archived: Bool) throws {
        if archived {
            self.archived.insert(id)
        } else {
            self.archived.remove(id)
        }
    }

    private static func definition(from draft: ExerciseDraft, id: UUID, slug: String, isCustom: Bool) -> ExerciseDefinition {
        ExerciseDefinition(
            id: id,
            slug: slug,
            name: draft.name,
            primaryMuscles: draft.primaryMuscles,
            secondaryMuscles: draft.secondaryMuscles,
            equipment: draft.equipment,
            loadUnit: draft.loadUnit,
            loadIncrement: draft.loadIncrement,
            isUnilateral: draft.isUnilateral,
            machineNotes: draft.machineNotes,
            movementPattern: draft.movementPattern,
            isCustom: isCustom
        )
    }
}
