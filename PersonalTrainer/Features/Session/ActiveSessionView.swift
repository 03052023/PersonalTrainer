import SwiftUI
import TrainerCore

/// Tela da sessão em andamento (SPEC F2/F3/F4). Recebe o ViewModel pronto: quem liga
/// `AppEnvironment` → sessão é `RootView`; a feature não lê o environment (ARCHITECTURE §3).
///
/// `onFinished` é chamado depois de `finish()`/`abandon()` bem-sucedidos, para o `RootView`
/// mostrar o resumo (T1.8) e a Home recalcular o próximo treino.
struct ActiveSessionView: View {
    @Bindable private var model: ActiveSessionViewModel
    private let onFinished: () -> Void

    @State private var isShowingSkipDialog = false
    @State private var isShowingFinishDialog = false

    init(model: ActiveSessionViewModel, onFinished: @escaping () -> Void) {
        self._model = Bindable(wrappedValue: model)
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    RestTimerView(timer: model.restTimer)
                        .padding(.horizontal)

                    ExerciseProgressList(
                        exercises: model.exercises,
                        selectedExerciseID: model.selectedExerciseID,
                        onSelect: { model.select(exerciseID: $0) }
                    )

                    if let exercise = model.selectedExercise {
                        CurrentExercisePanel(
                            exercise: exercise,
                            prescriptionSummary: model.prescriptionSummary(for: exercise),
                            draft: Binding<SetDraft>($model.currentDraft),
                            onComplete: { model.completeSet() }
                        )

                        if !exercise.wasSkipped {
                            skipButton
                        }
                    } else {
                        ContentUnavailableView(
                            "Nenhum exercício",
                            systemImage: "figure.strengthtraining.traditional",
                            description: Text("Esta sessão não tem exercícios. Finalize ou abandone o treino.")
                        )
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(model.session?.programDayName ?? "Sessão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finalizar") {
                        isShowingFinishDialog = true
                    }
                }
            }
            .confirmationDialog(
                "Encerrar o treino?",
                isPresented: $isShowingFinishDialog,
                titleVisibility: .visible
            ) {
                Button("Finalizar treino") {
                    model.finish()
                    if model.isFinished {
                        onFinished()
                    }
                }
                Button("Abandonar", role: .destructive) {
                    model.abandon()
                    if model.isFinished {
                        onFinished()
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text(finishMessage)
            }
            .confirmationDialog(
                "Pular este exercício?",
                isPresented: $isShowingSkipDialog,
                titleVisibility: .visible
            ) {
                Button("Pular exercício", role: .destructive) {
                    model.skipCurrentExercise()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Ele fica registrado como pulado. Séries já feitas são mantidas.")
            }
            .alert("Erro", isPresented: $model.isShowingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    private var skipButton: some View {
        Button(role: .destructive) {
            isShowingSkipDialog = true
        } label: {
            Label("Pular exercício", systemImage: "forward.fill")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
    }

    private var finishMessage: String {
        let count = model.stats.workingSetCount
        let sets = count == 1 ? "1 série de trabalho registrada" : "\(count) séries de trabalho registradas"
        return "\(sets). Finalizar grava a sessão como concluída; abandonar mantém as séries no histórico."
    }
}

#Preview {
    if let fixture = SessionPreviewSupport.makeFixture() {
        ActiveSessionView(model: fixture.viewModel, onFinished: {})
    } else {
        Text("Preview indisponível")
    }
}
