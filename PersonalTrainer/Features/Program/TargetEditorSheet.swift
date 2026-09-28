import SwiftUI
import TrainerCore

/// Edição dos parâmetros de um exercício do plano (RF-16, CA2-4): séries, faixa (em repetições,
/// segundos ou passos, RF-43), descanso e carga inicial opcional. O RIR alvo não aparece nem é
/// editável (RF-16, RF-41): o rascunho guarda o valor gravado, que volta igual ao salvar.
///
/// Só edita um rascunho local; quem grava é o `ProgramDetailViewModel` (via `onSave`), depois
/// que a folha fecha. Os steppers já respeitam os limites do repositório, e o botão de salvar
/// fica desabilitado enquanto o rascunho for inválido.
struct TargetEditorSheet: View {
    private let exerciseName: String
    private let onSave: (ProgramDetailViewModel.TargetDraft) -> Void
    private let onCancel: () -> Void
    @State private var draft: ProgramDetailViewModel.TargetDraft
    // Carga inicial em dois estados simples (em vez de `Binding(get:set:)`): o valor do stepper
    // sobrevive a desligar e religar o interruptor.
    @State private var hasStartingLoad: Bool
    @State private var startingLoad: Double

    init(
        exerciseName: String,
        draft: ProgramDetailViewModel.TargetDraft,
        onSave: @escaping (ProgramDetailViewModel.TargetDraft) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.exerciseName = exerciseName
        self.onSave = onSave
        self.onCancel = onCancel
        self._draft = State(initialValue: draft)
        self._hasStartingLoad = State(initialValue: draft.startingLoad != nil)
        self._startingLoad = State(initialValue: draft.startingLoad ?? draft.defaultStartingLoad)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Séries") {
                    Stepper(value: $draft.sets, in: ProgramDetailViewModel.TargetDraft.setsRange) {
                        valueRow("Séries", value: "\(draft.sets)")
                    }
                }

                Section {
                    Stepper(value: $draft.repMin, in: draft.repMinRange) {
                        valueRow("Mínimo", value: MeasureText.amount(draft.repMin, measure: draft.measure))
                    }
                    Stepper(value: $draft.repMax, in: draft.repMaxRange) {
                        valueRow("Máximo", value: MeasureText.amount(draft.repMax, measure: draft.measure))
                    }
                } header: {
                    Text(MeasureText.title(draft.measure))
                } footer: {
                    Text("Ao chegar ao máximo em todas as séries, a carga sobe e a meta volta ao mínimo.")
                }

                Section("Descanso") {
                    Stepper(
                        value: $draft.restSeconds,
                        in: ProgramDetailViewModel.TargetDraft.restRange,
                        step: ProgramDetailViewModel.TargetDraft.restStep
                    ) {
                        valueRow("Descanso", value: ProgramDetailViewModel.restText(seconds: draft.restSeconds))
                    }
                }

                startingLoadSection

                if let problem = result.validationMessage {
                    Section {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        onSave(result)
                    }
                    .disabled(result.validationMessage != nil)
                }
            }
        }
        .tint(Theme.accent)
    }

    /// Carga inicial (SPEC P2): sem ela, a 1ª sessão é a primeira vez, com a carga escolhida na
    /// própria sessão.
    private var startingLoadSection: some View {
        Section {
            Toggle("Definir carga inicial", isOn: $hasStartingLoad)
            if hasStartingLoad {
                Stepper(
                    value: $startingLoad,
                    in: draft.minimumLoad...draft.maximumLoad,
                    step: draft.loadIncrement
                ) {
                    valueRow("Carga inicial", value: ProgramDetailViewModel.loadText(startingLoad, unit: draft.loadUnit))
                }
            }
        } header: {
            Text("Carga inicial")
        } footer: {
            Text("Sem carga inicial, você escolhe a carga na primeira sessão deste exercício.")
        }
    }

    /// Rascunho final: steppers + carga inicial só se o interruptor estiver ligado. O RIR alvo
    /// segue o gravado.
    private var result: ProgramDetailViewModel.TargetDraft {
        var value = draft
        value.startingLoad = hasStartingLoad ? startingLoad : nil
        return value
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
