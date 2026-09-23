import SwiftUI
import TrainerCore

/// Formulário de exercício do catálogo (SPEC RF-15; TASKS T2.5): nome, grupos primários e
/// secundários, equipamento, unidade, incremento, unilateral, notas da máquina e padrão de
/// movimento. Apresentado em sheet, com `NavigationStack` própria; grava só pelo ViewModel, que usa
/// o `CatalogRepositoring` (AGENTS R4).
struct ExerciseEditorView: View {
    @Bindable private var model: ExerciseEditorViewModel
    private let onSaved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss

    /// - Parameter onSaved: recebe o id gravado, antes de a sheet fechar.
    init(model: ExerciseEditorViewModel, onSaved: @escaping (UUID) -> Void = { _ in }) {
        self.model = model
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                nameSection
                primarySection
                secondarySection
                loadSection
                patternSection
                notesSection
                if model.isSeedExercise {
                    seedNoticeSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        saveAndClose()
                    }
                    .disabled(!model.canSave)
                }
            }
            .alert("Não foi possível salvar", isPresented: $model.isPresentingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        // Arrastar a sheet para baixo não descarta edições sem querer; "Cancelar" continua valendo.
        .interactiveDismissDisabled(model.hasUnsavedChanges)
    }

    // MARK: - Seções

    private var nameSection: some View {
        Section("Nome") {
            TextField("Ex.: Supino inclinado na máquina", text: $model.draft.name)
                .textInputAutocapitalization(.sentences)
        }
    }

    private var primarySection: some View {
        Section {
            MuscleGroupSelector(selected: model.draft.primaryMuscles) { group in
                model.togglePrimary(group)
            }
        } header: {
            Text("Grupos primários")
        } footer: {
            Text(model.mainGroupText)
        }
    }

    private var secondarySection: some View {
        Section {
            MuscleGroupSelector(
                selected: model.draft.secondaryMuscles,
                disabled: Set(model.draft.primaryMuscles)
            ) { group in
                model.toggleSecondary(group)
            }
        } header: {
            Text("Grupos secundários")
        } footer: {
            Text("Opcional. Só os grupos primários contam na frequência semanal.")
        }
    }

    private var loadSection: some View {
        Section {
            Picker("Equipamento", selection: $model.draft.equipment) {
                ForEach(Equipment.pickerOrder, id: \.self) { equipment in
                    Text(equipment.displayName).tag(equipment)
                }
            }
            Picker("Unidade de carga", selection: $model.draft.loadUnit) {
                ForEach(LoadUnit.pickerOrder, id: \.self) { unit in
                    Text(unit.displayName).tag(unit)
                }
            }
            Picker("Incremento", selection: $model.incrementChoice) {
                ForEach(ExerciseEditorViewModel.IncrementChoice.allCases, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            if model.incrementChoice == .custom {
                TextField("Incremento (ex.: 1,25)", text: $model.customIncrementText)
                    .keyboardType(.decimalPad)
            }
            Toggle("Unilateral (um lado por vez)", isOn: $model.draft.isUnilateral)
        } header: {
            Text("Equipamento e carga")
        } footer: {
            Text("Incremento é o menor salto de carga: 2,5 kg para barra e halteres, 5 kg para máquina de placas, 1 para nível ou placa.")
        }
    }

    private var patternSection: some View {
        Section {
            Picker("Padrão de movimento", selection: $model.draft.movementPattern) {
                Text("Nenhum").tag(MovementPattern?.none)
                ForEach(MovementPattern.allCases, id: \.self) { pattern in
                    Text(pattern.displayName).tag(MovementPattern?.some(pattern))
                }
            }
        } footer: {
            Text("Usado pelo botão Trocar: substitutos têm o mesmo padrão e o mesmo grupo primário.")
        }
    }

    private var notesSection: some View {
        Section {
            TextField("Banco, pino, assento…", text: $model.machineNotesText, axis: .vertical)
                .lineLimit(2...5)
        } header: {
            Text("Notas da máquina")
        } footer: {
            Text("Ex.: banco no 4, pino no 7, assento na altura 3.")
        }
    }

    private var seedNoticeSection: some View {
        Section {
            Label(
                "Exercício do catálogo padrão. Uma atualização do catálogo pode restaurar nome, grupos e incremento; as notas da máquina e o arquivamento são sempre mantidos.",
                systemImage: "info.circle"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Ações

    private func saveAndClose() {
        guard model.saveExercise(), let id = model.savedExerciseID else { return }
        onSaved(id)
        dismiss()
    }
}
