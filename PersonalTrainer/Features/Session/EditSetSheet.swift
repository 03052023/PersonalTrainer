import SwiftUI
import TrainerCore

/// Correção de uma série já registrada (SPEC RF-19, P10): carga, repetições (ou segundos e
/// passos, SPEC RF-43) e RIR, ou apagar.
///
/// Edita uma cópia local (`@State`) e só devolve os valores em "Salvar"; quem grava é o
/// `ActiveSessionViewModel`, pelo coordinator (AGENTS R4). Aquecimento/trabalho não muda aqui:
/// o evento `setUpdated` só carrega carga, reps e RIR.
struct EditSetSheet: View {
    @State private var edit: ActiveSessionViewModel.SetEdit
    @State private var isConfirmingDelete = false

    private let references: ReferenceCatalog
    private let onSave: (ActiveSessionViewModel.SetEdit) -> Void
    private let onDelete: () -> Void
    private let onCancel: () -> Void

    init(
        edit: ActiveSessionViewModel.SetEdit,
        references: ReferenceCatalog = .empty,
        onSave: @escaping (ActiveSessionViewModel.SetEdit) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._edit = State(initialValue: edit)
        self.references = references
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if edit.isWarmup {
                        Label("Série de aquecimento", systemImage: "thermometer.medium")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LoadStepper(value: $edit.load, increment: edit.loadIncrement, unit: edit.loadUnit)

                    RepsStepper(
                        value: $edit.reps,
                        range: MeasureText.stepperRange(edit.measure),
                        highlightRange: SetEntryView.highlightRange(repMin: edit.repMin, repMax: edit.repMax),
                        measure: edit.measure
                    )

                    RIRPicker(selection: $edit.rir, references: references)

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Apagar série", systemImage: "trash")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Corrigir série \(edit.number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        onSave(edit)
                    }
                }
            }
            .confirmationDialog(
                "Apagar esta série?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Apagar série", role: .destructive) {
                    onDelete()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Ela sai deste treino e do histórico do exercício.")
            }
        }
    }
}

#Preview("Série de trabalho") {
    EditSetSheet(
        edit: ActiveSessionViewModel.SetEdit(
            setID: UUID(),
            number: 2,
            load: 62.5,
            reps: 9,
            rir: 1,
            isWarmup: false,
            loadIncrement: 2.5,
            loadUnit: .kilograms,
            repMin: 8,
            repMax: 12
        ),
        onSave: { _ in },
        onDelete: {},
        onCancel: {}
    )
}

#Preview("Carregada em passos") {
    EditSetSheet(
        edit: ActiveSessionViewModel.SetEdit(
            setID: UUID(),
            number: 1,
            load: 20,
            reps: 32,
            rir: 2,
            isWarmup: false,
            loadIncrement: 2,
            loadUnit: .kilograms,
            repMin: 20,
            repMax: 40,
            measure: .steps
        ),
        onSave: { _ in },
        onDelete: {},
        onCancel: {}
    )
}

#Preview("Aquecimento em placas") {
    EditSetSheet(
        edit: ActiveSessionViewModel.SetEdit(
            setID: UUID(),
            number: 1,
            load: 5,
            reps: 12,
            rir: nil,
            isWarmup: true,
            loadIncrement: 1,
            loadUnit: .plates,
            repMin: 8,
            repMax: 12
        ),
        onSave: { _ in },
        onDelete: {},
        onCancel: {}
    )
    .dynamicTypeSize(.accessibility3)
}
