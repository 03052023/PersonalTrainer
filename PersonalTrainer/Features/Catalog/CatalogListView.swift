import SwiftUI
import TrainerCore

/// Catálogo de exercícios (SPEC RF-15; TASKS T2.5): busca, filtro por grupo, arquivados sob
/// demanda, edição por toque, "+" para criar exercício próprio e deslize para arquivar/restaurar.
///
/// Não tem `NavigationStack` própria: a aba Programa empilha esta tela na pilha dela. Lê e grava
/// só pelo ViewModel, que usa o `CatalogRepositoring` (AGENTS R4).
struct CatalogListView: View {
    @State private var model: CatalogListViewModel

    init(catalog: any CatalogRepositoring) {
        // `State(initialValue:)` guarda só a primeira instância: re-inits da view pelo pai não
        // recriam o ViewModel (e o init dele não lê nada).
        _model = State(initialValue: CatalogListViewModel(catalog: catalog))
    }

    var body: some View {
        List {
            if model.hasActiveFilter {
                filterSummarySection
            }
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.exercises, id: \.id) { exercise in
                        row(for: exercise)
                    }
                } header: {
                    Text(section.title)
                }
            }
        }
        .overlay {
            emptyState
        }
        .searchable(text: $model.searchText, prompt: "Buscar exercício")
        .navigationTitle("Exercícios")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                filterMenu
                Button {
                    model.startCreating()
                } label: {
                    Label("Novo exercício", systemImage: "plus")
                }
            }
        }
        .onAppear {
            model.load()
        }
        .sheet(isPresented: $model.isEditorPresented, onDismiss: {
            model.editorDismissed()
        }) {
            if let editor = model.editor {
                ExerciseEditorView(model: editor)
            }
        }
        .alert("Não foi possível continuar", isPresented: $model.isPresentingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Linhas

    private func row(for exercise: ExerciseDefinition) -> some View {
        let archived = model.isArchived(exercise)
        return Button {
            model.startEditing(exercise)
        } label: {
            CatalogExerciseRow(exercise: exercise, isArchived: archived)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                model.toggleArchived(exercise)
            } label: {
                if archived {
                    Label("Restaurar", systemImage: "arrow.uturn.backward")
                } else {
                    Label("Arquivar", systemImage: "archivebox")
                }
            }
            .tint(archived ? Color.green : Color.orange)
        }
    }

    private var filterSummarySection: some View {
        Section {
            HStack {
                Label(model.filterSummary, systemImage: "line.3.horizontal.decrease.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Limpar") {
                    model.clearFilters()
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Toolbar

    private var filterMenu: some View {
        Menu {
            Picker("Grupo muscular", selection: $model.muscleFilter) {
                Text("Todos os grupos").tag(MuscleGroup?.none)
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    Text(group.displayName).tag(MuscleGroup?.some(group))
                }
            }
            Toggle("Mostrar arquivados", isOn: $model.showArchived)
        } label: {
            Label(
                "Filtrar",
                systemImage: model.hasActiveFilter
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle"
            )
        }
    }

    // MARK: - Estados vazios

    /// "Não carregou", "catálogo vazio" e "nada bate com a busca/filtro" são estados distintos.
    @ViewBuilder
    private var emptyState: some View {
        // Antes da primeira leitura não há o que dizer (evita piscar "Catálogo vazio").
        if model.hasLoaded && model.visibleExercises.isEmpty {
            if model.exercises.isEmpty && model.didFailToLoad {
                ContentUnavailableView(
                    "Não foi possível carregar o catálogo",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Volte a esta tela para tentar de novo.")
                )
            } else if model.exercises.isEmpty {
                ContentUnavailableView(
                    "Catálogo vazio",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("Toque em + para criar um exercício.")
                )
            } else {
                ContentUnavailableView(
                    "Nenhum exercício encontrado",
                    systemImage: "magnifyingglass",
                    description: Text("Mude a busca ou o filtro.")
                )
            }
        }
    }
}
