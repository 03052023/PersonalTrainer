import Foundation
import Observation
import os
import TrainerCore

/// Estado da lista do catálogo (SPEC RF-15; TASKS T2.5): busca por nome, filtro por grupo primário,
/// arquivados sob demanda e abertura do editor. Lê e escreve só pelo `CatalogRepositoring`
/// (AGENTS R4): nenhum `@Query` nem `ModelContext` aqui.
@Observable
@MainActor
final class CatalogListViewModel {
    /// Catálogo inteiro, inclusive arquivados, na ordem do repositório.
    private(set) var exercises: [ExerciseDefinition] = []
    /// Ids arquivados. `ExerciseDefinition` não carrega `isArchived`; sai da diferença entre as
    /// leituras com e sem arquivados.
    private(set) var archivedIDs: Set<UUID> = []
    var searchText = ""
    /// `nil` = todos os grupos. Filtra pelo grupo **primário** (mesma regra da frequência, §7.4).
    var muscleFilter: MuscleGroup?
    var showArchived = false
    /// Mensagem pt-BR para o `.alert` da view; a view zera ao fechar o alerta.
    var errorMessage: String?
    /// Verdadeiro enquanto a última leitura tiver falhado (sobrevive ao fechamento do alerta).
    private(set) var didFailToLoad = false
    /// Verdadeiro depois da primeira tentativa de leitura, com sucesso ou não.
    private(set) var hasLoaded = false
    /// Editor aberto na sheet. Vive aqui (e não na view) para sobreviver a re-renderizações da lista.
    private(set) var editor: ExerciseEditorViewModel?
    /// Ligado à sheet do editor; `editorDismissed()` limpa o editor quando ela termina de fechar.
    var isEditorPresented = false

    private let catalog: any CatalogRepositoring

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "Catalog"
    )

    /// Nada é lido no init: a view chama `load()` ao aparecer.
    init(catalog: any CatalogRepositoring) {
        self.catalog = catalog
    }

    /// Ponte para `.alert(isPresented:)`: verdadeiro enquanto há mensagem; atribuir `false` limpa.
    var isPresentingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
            }
        }
    }

    // MARK: - Leitura

    /// Relê o catálogo. Em falha mantém a última lista boa (arquivar não pode esvaziar a tela) e
    /// avisa por `errorMessage`.
    func load() {
        defer { hasLoaded = true }
        do {
            let all = try catalog.allExercises(includeArchived: true)
            let active = try catalog.allExercises(includeArchived: false)
            let activeIDs = Set(active.map(\.id))
            exercises = all
            archivedIDs = Set(all.map(\.id)).subtracting(activeIDs)
            didFailToLoad = false
        } catch {
            Self.logger.error("Falha ao carregar o catálogo: \(String(describing: error), privacy: .public)")
            didFailToLoad = true
            errorMessage = "Não foi possível carregar o catálogo de exercícios."
        }
    }

    func isArchived(_ exercise: ExerciseDefinition) -> Bool {
        archivedIDs.contains(exercise.id)
    }

    /// Exercícios depois de arquivados, grupo e busca, em ordem alfabética.
    var visibleExercises: [ExerciseDefinition] {
        let filtered = exercises.filter { exercise in
            (showArchived || !archivedIDs.contains(exercise.id))
                && (muscleFilter.map { exercise.primaryMuscles.contains($0) } ?? true)
                && ExerciseListing.matches(exercise, query: searchText)
        }
        return ExerciseListing.sorted(filtered)
    }

    /// `visibleExercises` em seções pelo primeiro grupo primário.
    var sections: [ExerciseListing.MuscleSection] {
        ExerciseListing.sections(visibleExercises)
    }

    /// Filtro de grupo ou arquivados ligado (a view destaca o ícone do menu e mostra o resumo).
    var hasActiveFilter: Bool {
        muscleFilter != nil || showArchived
    }

    /// "Peito · com arquivados"; vazio sem filtro.
    var filterSummary: String {
        var parts: [String] = []
        if let muscleFilter {
            parts.append(muscleFilter.displayName)
        }
        if showArchived {
            parts.append("com arquivados")
        }
        return parts.joined(separator: " · ")
    }

    /// Desliga grupo e arquivados; a busca por nome fica (é controlada pela barra de busca).
    func clearFilters() {
        muscleFilter = nil
        showArchived = false
    }

    // MARK: - Arquivar

    /// Arquiva ou restaura (RF-15; o exercício nunca é apagado: o histórico aponta para ele).
    func toggleArchived(_ exercise: ExerciseDefinition) {
        let archive = !isArchived(exercise)
        do {
            try catalog.setArchived(id: exercise.id, archive)
        } catch {
            Self.logger.error("Falha ao arquivar exercício: \(String(describing: error), privacy: .public)")
            errorMessage = archive
                ? "Não foi possível arquivar o exercício."
                : "Não foi possível restaurar o exercício."
            return
        }
        load()
    }

    // MARK: - Editor

    func startCreating() {
        editor = ExerciseEditorViewModel(catalog: catalog)
        isEditorPresented = true
    }

    func startEditing(_ exercise: ExerciseDefinition) {
        editor = ExerciseEditorViewModel(catalog: catalog, exercise: exercise)
        isEditorPresented = true
    }

    /// Chamado quando a sheet termina de fechar (salvando ou não): solta o editor e relê a lista.
    func editorDismissed() {
        isEditorPresented = false
        editor = nil
        load()
    }
}
