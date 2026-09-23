import SwiftUI
import TrainerCore

/// Raiz da aba Programa (T2.6): lista de programas com o ativo no topo, objetivo e resumo.
/// Tocar abre o `ProgramDetailView`; deslizar ou tocar e segurar oferece Ativar, Duplicar e
/// Apagar (este só para inativos). A barra leva ao catálogo de exercícios (`CatalogListView`).
///
/// Nada aqui lê o `AppEnvironment` do ambiente nem escreve no `ModelContext` (AGENTS R4): os
/// repositórios chegam por `init`. `now` só carimba cópias; o padrão existe para o integrador
/// poder chamar `ProgramTabView(programs:catalog:references:)` e é o único relógio real da aba
/// (os ViewModels recebem o closure, SPEC P11).
struct ProgramTabView: View {
    @State private var model: ProgramListViewModel
    private let programs: any ProgramRepositoring
    private let catalog: any CatalogRepositoring
    private let references: ReferenceCatalog

    init(
        programs: any ProgramRepositoring,
        catalog: any CatalogRepositoring,
        references: ReferenceCatalog,
        now: @escaping () -> Date = { Date() }
    ) {
        self.programs = programs
        self.catalog = catalog
        self.references = references
        self._model = State(initialValue: ProgramListViewModel(programs: programs, now: now))
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Programa")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink("Exercícios") {
                            CatalogListView(catalog: catalog)
                        }
                    }
                }
                // Também dispara ao voltar do detalhe: a lista reflete nome, objetivo e ativo.
                .onAppear {
                    model.refresh()
                }
                .alert("Não foi possível continuar", isPresented: $model.isPresentingError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(model.errorMessage ?? "")
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.programs.isEmpty {
            if !model.hasLoaded {
                ProgressView()
            } else if model.didFailToLoad {
                ContentUnavailableView(
                    "Não foi possível carregar os programas",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Saia da aba e volte para tentar de novo.")
                )
            } else {
                ContentUnavailableView(
                    "Nenhum programa",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Os programas prontos aparecem aqui.")
                )
            }
        } else {
            programList
        }
    }

    private var programList: some View {
        List {
            ForEach(model.programs, id: \.id) { program in
                NavigationLink {
                    ProgramDetailView(
                        programID: program.id,
                        programs: programs,
                        catalog: catalog,
                        references: references
                    )
                } label: {
                    row(for: program)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if !program.isActive {
                        Button {
                            model.activate(program.id)
                        } label: {
                            Label("Ativar", systemImage: "checkmark.circle")
                        }
                        .tint(.green)
                    }
                }
                // Sem `role: .destructive`: a exclusão pede confirmação, e o papel destrutivo
                // anima a saída da linha antes da resposta.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !program.isActive {
                        Button {
                            model.requestDeletion(of: program.id)
                        } label: {
                            Label("Apagar", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                    Button {
                        model.duplicate(program.id)
                    } label: {
                        Label("Duplicar", systemImage: "plus.square.on.square")
                    }
                    .tint(.blue)
                }
                .contextMenu {
                    if !program.isActive {
                        Button {
                            model.activate(program.id)
                        } label: {
                            Label("Ativar", systemImage: "checkmark.circle")
                        }
                    }
                    Button {
                        model.duplicate(program.id)
                    } label: {
                        Label("Duplicar", systemImage: "plus.square.on.square")
                    }
                    if !program.isActive {
                        Button(role: .destructive) {
                            model.requestDeletion(of: program.id)
                        } label: {
                            Label("Apagar", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            "Apagar programa?",
            isPresented: $model.isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: model.pendingDeletion
        ) { program in
            Button("Apagar \(program.name)", role: .destructive) {
                model.confirmDeletion()
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("O histórico de treinos continua salvo; só o programa é removido.")
        }
    }

    private func row(for program: ProgramTemplate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(program.name)
                    .font(.headline)
                if program.isActive {
                    Text("Ativo")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                }
            }
            Text("\(program.effectiveGoal.displayName) · \(ProgramListViewModel.dayCountText(program.days.count))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let summary = program.summary, !summary.isEmpty {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
