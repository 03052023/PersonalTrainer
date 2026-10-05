import SwiftUI
import TrainerCore

/// "Corrigir série" (SPEC RF-19, RF-44 b; DESIGN §13): uma folha pequena só com carga ("Carga
/// extra" em peso do corpo, SPEC RF-46), repetições (ou segundos e passos, SPEC RF-43) e "Apagar
/// série". Abre ao tocar numa bolinha cheia da ficha.
///
/// Edita uma cópia local (`@State`) e só devolve os valores em "Salvar"; quem grava é o
/// `ActiveSessionViewModel`, pelo coordinator (AGENTS R4), com o RIR que a série já tinha (SPEC
/// RF-41: a folha não mostra nem muda o RIR).
struct EditSetSheet: View {
    @State private var edit: ActiveSessionViewModel.SetEdit
    @State private var isConfirmingDelete = false

    private let onSave: (ActiveSessionViewModel.SetEdit) -> Void
    private let onDelete: () -> Void
    private let onCancel: () -> Void

    init(
        edit: ActiveSessionViewModel.SetEdit,
        onSave: @escaping (ActiveSessionViewModel.SetEdit) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._edit = State(initialValue: edit)
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !edit.plannedLine.isEmpty {
                        Text(edit.plannedLine)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // SPEC §7.14: caminhar e correr (aeróbico de peso do corpo) não têm carga a corrigir.
                    if !(edit.isCardio && edit.isBodyweight) {
                        LoadStepper(
                            value: $edit.load,
                            increment: edit.loadIncrement,
                            unit: edit.loadUnit,
                            title: loadTitle
                        )
                    }

                    RepsStepper(
                        value: $edit.reps,
                        range: MeasureText.stepperRange(edit.measure),
                        highlightRange: RepsStepper.highlightRange(repMin: edit.repMin, repMax: edit.repMax),
                        measure: edit.measure
                    )

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
            .paperBackground()
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
                    .fontWeight(.semibold)
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
                Text("Ela sai desta sessão e do histórico do exercício.")
            }
        }
        .tint(Theme.accent)
    }

    /// "Nível" na máquina com nível (aeróbico, SPEC §7.14 F3), "Carga extra" no peso do corpo (RF-46),
    /// "Carga" no resto.
    private var loadTitle: String {
        if edit.loadUnit == .level {
            return "Nível"
        }
        return edit.isBodyweight ? "Carga extra" : "Carga"
    }
}

#Preview("Série com carga") {
    EditSetSheet(
        edit: ActiveSessionViewModel.SetEdit(
            setID: UUID(),
            number: 3,
            load: 62.5,
            reps: 2,
            rir: nil,
            loadIncrement: 2.5,
            loadUnit: .kilograms,
            repMin: 3,
            repMax: 5,
            plannedLine: "Agachamento livre · previsto: 3 repetições · 62,5 kg"
        ),
        onSave: { _ in },
        onDelete: {},
        onCancel: {}
    )
}

#Preview("Peso do corpo") {
    EditSetSheet(
        edit: ActiveSessionViewModel.SetEdit(
            setID: UUID(),
            number: 1,
            load: 0,
            reps: 5,
            rir: nil,
            loadIncrement: 2.5,
            loadUnit: .kilograms,
            repMin: 5,
            repMax: 8,
            isBodyweight: true,
            plannedLine: "Barra fixa · previsto: 5 repetições"
        ),
        onSave: { _ in },
        onDelete: {},
        onCancel: {}
    )
    .dynamicTypeSize(.accessibility3)
}

#Preview("Passos") {
    EditSetSheet(
        edit: ActiveSessionViewModel.SetEdit(
            setID: UUID(),
            number: 1,
            load: 22.5,
            reps: 30,
            rir: nil,
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
