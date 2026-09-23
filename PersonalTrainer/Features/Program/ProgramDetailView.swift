import SwiftUI
import TrainerCore

/// Tela de um programa (T2.6, T2.12): nome (renomear), objetivo com "Por quê?" e lista de dias.
/// Tocar num dia abre o `DayEditorView`, que compartilha este ViewModel.
///
/// Monta o próprio `ProgramDetailViewModel` a partir dos repositórios recebidos e o guarda em
/// `@State`; toda escrita vai pelo ViewModel (AGENTS R4).
struct ProgramDetailView: View {
    @State private var model: ProgramDetailViewModel
    private let references: ReferenceCatalog

    @State private var isRenaming = false
    @State private var nameDraft = ""

    init(
        programID: UUID,
        programs: any ProgramRepositoring,
        catalog: any CatalogRepositoring,
        references: ReferenceCatalog
    ) {
        self.references = references
        self._model = State(initialValue: ProgramDetailViewModel(
            programID: programID,
            programs: programs,
            catalog: catalog
        ))
    }

    var body: some View {
        Group {
            if let program = model.program {
                content(for: program)
            } else if !model.hasLoaded {
                ProgressView()
            } else if model.didFailToLoad {
                ContentUnavailableView(
                    "Não foi possível carregar o programa",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Volte e tente de novo.")
                )
            } else {
                ContentUnavailableView(
                    "Programa não encontrado",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Este programa foi apagado.")
                )
            }
        }
        // Reaparece ao voltar do editor de dia ou do seletor de objetivo: relê o que foi gravado.
        .onAppear {
            model.refresh()
        }
        .alert("Não foi possível continuar", isPresented: $model.isPresentingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func content(for program: ProgramTemplate) -> some View {
        List {
            Section("Nome") {
                HStack(spacing: 8) {
                    Text(program.name)
                        .font(.headline)
                    if program.isActive {
                        activeBadge
                    }
                    Spacer(minLength: 0)
                }
                Button {
                    nameDraft = program.name
                    isRenaming = true
                } label: {
                    Label("Renomear", systemImage: "pencil")
                }
            }

            Section {
                NavigationLink {
                    GoalPickerView(selected: model.goal, references: references) { [model] goal, applyDefaults in
                        model.setGoal(goal, applyDefaults: applyDefaults)
                    }
                } label: {
                    LabeledContent("Objetivo", value: model.goal.displayName)
                }
                WhyButton(topic: model.goal.referenceTopic, catalog: references)
            } header: {
                Text("Objetivo")
            } footer: {
                if let summary = program.summary, !summary.isEmpty {
                    Text(summary)
                }
            }

            Section("Dias") {
                if model.days.isEmpty {
                    Text("Este programa não tem dias de treino.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.days, id: \.id) { day in
                    NavigationLink {
                        DayEditorView(model: model, dayID: day.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.name)
                                .font(.body.weight(.medium))
                            Text(ProgramDetailViewModel.exerciseCountText(day.exercises.count))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        // Alerta de renomear preso à lista, e não ao `Group`, para não dividir o mesmo nó com o
        // alerta de erro.
        .alert("Renomear programa", isPresented: $isRenaming) {
            TextField("Nome do programa", text: $nameDraft)
            Button("Cancelar", role: .cancel) {}
            Button("Renomear") {
                model.rename(to: nameDraft)
            }
        } message: {
            Text("O nome aparece na lista de programas e na tela de treino.")
        }
    }

    private var activeBadge: some View {
        Text("Ativo")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.15), in: Capsule())
            .foregroundStyle(.green)
    }
}
