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

    /// Alvo do alerta de renomear: o programa ou um dia (T2.22). Os dois casos compartilham um só
    /// `.alert`, para não empilhar dois alertas no mesmo nó da lista (o comentário mais abaixo
    /// explica por que isso importa: é o mesmo motivo que já mantinha este alerta fora do `Group`
    /// do erro).
    private enum RenameTarget: Equatable {
        case program
        case day(id: UUID, name: String)
    }

    @State private var renameTarget: RenameTarget?
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
                    renameTarget = .program
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

            Section {
                if model.days.isEmpty {
                    Text("Este programa não tem dias de treino.")
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
                        // anima a saída da linha antes da resposta (mesmo cuidado do `ProgramTabView`).
                        Button {
                            dayPendingDeletion = day
                        } label: {
                            Label("Apagar", systemImage: "trash")
                        }
                        .tint(.red)
                        .disabled(!model.canRemoveDay)
                        Button {
                            nameDraft = day.name
                            renameTarget = .day(id: day.id, name: day.name)
                        } label: {
                            Label("Renomear", systemImage: "pencil")
                        }
                        .tint(.blue)
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
                Text("De \(ProgramLimits.minDays) a \(ProgramLimits.maxDays) dias. Hoje: \(ProgramListViewModel.dayCountText(model.days.count)).")
            }
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        // Alerta de renomear preso à lista, e não ao `Group`, para não dividir o mesmo nó com o
        // alerta de erro. Programa e dia compartilham este único `.alert` (ver `RenameTarget`)
        // para a mesma razão não valer duas vezes dentro da própria lista.
        .alert(
            renameAlertTitle,
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { isPresented in
                    if !isPresented { renameTarget = nil }
                }
            )
        ) {
            TextField(renameFieldLabel, text: $nameDraft)
            Button("Cancelar", role: .cancel) {}
            Button("Renomear") {
                switch renameTarget {
                case .program:
                    model.rename(to: nameDraft)
                case .day(let id, _):
                    model.renameDay(id: id, to: nameDraft)
                case nil:
                    break
                }
            }
        } message: {
            Text(renameAlertMessage)
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
            Text("O histórico de sessões desse dia continua no Histórico; só o dia é removido do programa.")
        }
    }

    /// Título, rótulo de campo e mensagem do `.alert` de renomear, conforme `renameTarget`.
    private var renameAlertTitle: String {
        switch renameTarget {
        case .day: return "Renomear dia"
        case .program, nil: return "Renomear programa"
        }
    }

    private var renameFieldLabel: String {
        switch renameTarget {
        case .day: return "Nome do dia"
        case .program, nil: return "Nome do programa"
        }
    }

    private var renameAlertMessage: String {
        switch renameTarget {
        case .day: return "O nome aparece na rotação de treino e no histórico das próximas sessões."
        case .program, nil: return "O nome aparece na lista de programas e na tela de treino."
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
