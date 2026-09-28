import SwiftUI
import TrainerCore

/// "Ajustar exercícios" (SPEC RF-45, RF-16, RF-36; T2.6, T2.22): os dias do plano ativo, com
/// adicionar, renomear, apagar e reordenar. Tocar num dia abre o `DayEditorView`, que
/// compartilha este ViewModel. Desde a 2.2 não mostra nome do programa, "Renomear programa" nem
/// o seletor de objetivo: objetivo e plano são uma escolha só, na folha "Seu objetivo".
///
/// Monta o próprio `ProgramDetailViewModel` a partir dos repositórios recebidos e o guarda em
/// `@State`; toda escrita vai pelo ViewModel (AGENTS R4).
struct ProgramDetailView: View {
    @State private var model: ProgramDetailViewModel
    private let references: ReferenceCatalog

    /// Dia com o alerta de renomear aberto (T2.22).
    @State private var renamingDayID: UUID?
    @State private var nameDraft = ""

    // Dias do programa (T2.22, RF-36).
    @State private var dayPendingDeletion: ProgramDayTemplate?

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
            if model.program != nil {
                content
            } else if !model.hasLoaded {
                ProgressView()
            } else if model.didFailToLoad {
                ContentUnavailableView(
                    "Não foi possível carregar o plano",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Volte e tente de novo.")
                )
            } else {
                ContentUnavailableView(
                    "Plano não encontrado",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Volte e escolha um objetivo.")
                )
            }
        }
        .navigationTitle("Ajustar exercícios")
        .navigationBarTitleDisplayMode(.inline)
        // Reaparece ao voltar do editor de dia: relê o que foi gravado.
        .onAppear {
            model.refresh()
        }
        .alert("Não foi possível continuar", isPresented: $model.isPresentingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var content: some View {
        List {
            Section {
                if model.days.isEmpty {
                    Text("Este plano não tem dias.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.days, id: \.id) { day in
                    NavigationLink {
                        DayEditorView(model: model, dayID: day.id, references: references)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.name)
                                .font(.body.weight(.medium))
                            Text(ProgramDetailViewModel.exerciseCountText(day.exercises.count))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        // Sem `role: .destructive`: apagar pede confirmação, e o papel destrutivo
                        // anima a saída da linha antes da resposta.
                        Button {
                            dayPendingDeletion = day
                        } label: {
                            Label("Apagar", systemImage: "trash")
                        }
                        .tint(Theme.destructive)
                        .disabled(!model.canRemoveDay)
                        Button {
                            nameDraft = day.name
                            renamingDayID = day.id
                        } label: {
                            Label("Renomear", systemImage: "pencil")
                        }
                        .tint(Theme.accent)
                    }
                }
                .onMove { source, destination in
                    model.moveDays(fromOffsets: source, toOffset: destination)
                }

                Button {
                    model.addDay()
                } label: {
                    Label("Adicionar dia", systemImage: "plus.circle.fill")
                }
                .disabled(!model.canAddDay)
            } header: {
                Text("Dias")
            } footer: {
                Text("Toque num dia para trocar, editar ou reordenar os exercícios. De \(ProgramLimits.minDays) a \(ProgramLimits.maxDays) dias; hoje, \(GoalPlanCatalog.dayCountText(model.days.count)).")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        // Alerta de renomear preso à lista, e não ao `Group`, para não dividir o mesmo nó com o
        // alerta de erro.
        .alert(
            "Renomear dia",
            isPresented: Binding(
                get: { renamingDayID != nil },
                set: { isPresented in
                    if !isPresented { renamingDayID = nil }
                }
            )
        ) {
            TextField("Nome do dia", text: $nameDraft)
            Button("Cancelar", role: .cancel) {}
            Button("Renomear") {
                if let dayID = renamingDayID {
                    model.renameDay(id: dayID, to: nameDraft)
                }
            }
        } message: {
            Text("O nome aparece na tela Hoje e no histórico das próximas sessões.")
        }
        .confirmationDialog(
            "Apagar dia?",
            isPresented: Binding(
                get: { dayPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented { dayPendingDeletion = nil }
                }
            ),
            titleVisibility: .visible,
            presenting: dayPendingDeletion
        ) { day in
            Button("Apagar \(day.name)", role: .destructive) {
                model.removeDay(id: day.id)
                dayPendingDeletion = nil
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("As sessões desse dia continuam no Histórico; só o dia sai do plano.")
        }
    }
}
