import SwiftUI
import TrainerCore

/// Seletor de exercício compartilhado (contrato M2 §5; TASKS T2.5): usado para trocar exercício na
/// sessão (RF-11, RF-34) e para adicionar/trocar exercício na edição de programa (RF-16, RF-33).
///
/// Tem `NavigationStack` própria (é apresentado em sheet): busca por nome, seção "Sugeridos" com os
/// `highlighted` (ex.: substitutos do mesmo padrão de movimento) e seções pelo primeiro grupo
/// primário. Não filtra arquivados nem fecha a si mesmo: mostra exatamente `exercises` e quem
/// apresenta fecha a sheet em `onPick`/`onCancel`.
struct ExercisePickerView: View {
    private let exercises: [ExerciseDefinition]
    private let title: String
    private let highlighted: [ExerciseDefinition]
    private let onPick: (ExerciseDefinition) -> Void
    private let onCancel: () -> Void

    @State private var searchText = ""

    init(
        exercises: [ExerciseDefinition],
        title: String,
        highlighted: [ExerciseDefinition] = [],
        onPick: @escaping (ExerciseDefinition) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.exercises = exercises
        self.title = title
        self.highlighted = highlighted
        self.onPick = onPick
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            List {
                if !suggestedExercises.isEmpty {
                    Section {
                        ForEach(suggestedExercises, id: \.id) { exercise in
                            row(for: exercise)
                        }
                    } header: {
                        Text("Sugeridos")
                    }
                }
                ForEach(sections) { section in
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
                if suggestedExercises.isEmpty && sections.isEmpty {
                    ContentUnavailableView(
                        "Nenhum exercício encontrado",
                        systemImage: "magnifyingglass",
                        description: Text(searchText.isEmpty ? "O catálogo não tem exercícios disponíveis." : "Tente outro nome.")
                    )
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Buscar exercício"
            )
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        onCancel()
                    }
                }
            }
        }
    }

    // MARK: - Conteúdo

    /// Sugeridos na ordem recebida (o chamador já ordena por semelhança, RF-34), filtrados pela busca.
    private var suggestedExercises: [ExerciseDefinition] {
        highlighted.filter { ExerciseListing.matches($0, query: searchText) }
    }

    private var sections: [ExerciseListing.MuscleSection] {
        ExerciseListing.sections(exercises.filter { ExerciseListing.matches($0, query: searchText) })
    }

    private func row(for exercise: ExerciseDefinition) -> some View {
        Button {
            onPick(exercise)
        } label: {
            CatalogExerciseRow(exercise: exercise)
        }
    }
}
