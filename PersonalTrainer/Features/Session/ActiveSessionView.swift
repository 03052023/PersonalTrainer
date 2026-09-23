import SwiftUI
import TrainerCore

/// Tela da sessão em andamento (SPEC F2/F3/F4, RF-19, RF-34). Recebe o ViewModel pronto: quem
/// liga `AppEnvironment` → sessão é `SessionFlowView`; a feature não lê o environment
/// (ARCHITECTURE §3).
///
/// `onFinished` é chamado depois de `finish()`/`abandon()` bem-sucedidos, para o fluxo
/// mostrar o resumo (T1.8) e a Home recalcular o próximo treino. `onMinimize` ("Voltar") fecha
/// a tela sem encerrar nada: a sessão continua `inProgress` e a Home oferece "Retomar".
struct ActiveSessionView: View {
    @Bindable private var model: ActiveSessionViewModel
    private let references: ReferenceCatalog
    private let onFinished: () -> Void
    private let onMinimize: () -> Void

    @State private var isShowingSkipDialog = false
    @State private var isShowingFinishDialog = false

    init(
        model: ActiveSessionViewModel,
        references: ReferenceCatalog,
        onFinished: @escaping () -> Void,
        onMinimize: @escaping () -> Void
    ) {
        self._model = Bindable(wrappedValue: model)
        self.references = references
        self.onFinished = onFinished
        self.onMinimize = onMinimize
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
                            references: references,
                            canSubstitute: model.canSubstituteSelectedExercise,
                            onComplete: { model.completeSet() },
                            onSubstitute: { model.beginSubstitution() },
                            onEditSet: { model.beginEditingSet(id: $0) }
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
            // Fica no ScrollView, e não no NavigationStack junto do alerta de erro, para os dois
            // `.alert` nunca dividirem a mesma view.
            .alert(
                zeroLoadTitle,
                isPresented: $model.needsZeroLoadConfirmation
            ) {
                Button("Registrar") {
                    model.confirmZeroLoadSet()
                }
                Button("Corrigir carga", role: .cancel) {
                    model.cancelZeroLoadSet()
                }
            } message: {
                Text("Nenhuma carga foi informada para esta série. Registre assim só se foi mesmo sem peso.")
            }
            .navigationTitle(model.session?.programDayName ?? "Sessão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onMinimize()
                    } label: {
                        Label("Voltar", systemImage: "chevron.down")
                    }
                    .accessibilityHint("O treino continua em andamento; retome pela tela inicial.")
                }
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
            .sheet(
                isPresented: $model.isShowingSubstituteSheet,
                onDismiss: { model.sheetDidDismiss() }
            ) {
                SubstituteExerciseSheet(
                    exerciseName: model.selectedExercise?.exerciseName ?? "",
                    suggestions: model.substituteSuggestions,
                    allExercises: model.substitutionCatalog,
                    references: references,
                    onPick: { model.substituteSelectedExercise(with: $0) },
                    onCancel: { model.cancelSubstitution() }
                )
            }
            .sheet(
                item: $model.editingSet,
                onDismiss: { model.sheetDidDismiss() }
            ) { edit in
                EditSetSheet(
                    edit: edit,
                    onSave: { model.saveEditedSet($0) },
                    onDelete: { model.deleteSet(id: edit.setID) },
                    onCancel: { model.cancelEditingSet() }
                )
            }
        }
        .alert("Erro", isPresented: $model.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
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

    /// "Registrar com 0 kg?" — ou "0 placas"/"nível 0", na unidade do exercício.
    private var zeroLoadTitle: String {
        let unit = model.currentDraft?.loadUnit ?? .kilograms
        return "Registrar com \(LoadStepper.displayText(for: 0, unit: unit))?"
    }

    private var finishMessage: String {
        let count = model.stats.workingSetCount
        let sets = count == 1 ? "1 série de trabalho registrada" : "\(count) séries de trabalho registradas"
        return "\(sets). Finalizar grava a sessão como concluída; abandonar mantém as séries no histórico."
    }
}

#Preview {
    if let fixture = SessionPreviewSupport.makeFixture() {
        ActiveSessionView(model: fixture.viewModel, references: .empty, onFinished: {}, onMinimize: {})
    } else {
        Text("Preview indisponível")
    }
}
