import SwiftUI
import TrainerCore
import UIKit

/// A ficha da sessão em andamento (SPEC RF-44, F2/F3/F4, RF-19, RF-34, RF-47; DESIGN §13; mockup
/// "Sessão: a ficha"). Uma lista rolável com todos os exercícios na ordem, a dica fixa de
/// aquecimento no topo e o descanso preso acima da lista. Recebe o ViewModel pronto: quem liga
/// `AppEnvironment` → sessão é `SessionFlowView`; a feature não lê o environment (ARCHITECTURE §3).
///
/// `onFinished` é chamado depois de concluir ou encerrar com sucesso, para o fluxo mostrar o
/// resumo. `onMinimize` ("Voltar") fecha a tela sem encerrar nada: a sessão continua em andamento
/// e a tela Hoje oferece "Retomar".
///
/// Tela acesa (RF-44 g): `isIdleTimerDisabled` fica ligado só enquanto a ficha está na tela com o
/// app ativo; desliga ao sair da ficha (resumo, minimizar) e quando o app sai de `.active`. Não é
/// permissão (AGENTS §7).
struct ActiveSessionView: View {
    @Bindable private var model: ActiveSessionViewModel
    private let references: ReferenceCatalog
    private let onFinished: () -> Void
    private let onMinimize: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedLoadID: UUID?
    /// Exercício cuja carga está sendo trocada no teclado (toque na carga sublinhada).
    @State private var editingLoadID: UUID? = nil
    /// Exercícios feitos abertos para corrigir uma série.
    @State private var expandedDoneIDs: Set<UUID> = []
    @State private var infoItem: ExerciseInfoContent? = nil
    /// Ação pedida na folha de informações, feita no `onDismiss` dela: o SwiftUI não abre uma
    /// folha sobre outra que está fechando (contrato V22 §2.2).
    @State private var pendingInfoAction: InfoAction? = nil
    @State private var whyItem: WhyTopic? = nil
    @State private var pendingFinish: PendingFinish? = nil
    @State private var isShowingPendingDialog = false

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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        warmupHint

                        if model.exercises.isEmpty {
                            ContentUnavailableView(
                                "Nenhum exercício",
                                systemImage: "list.bullet",
                                description: Text("Esta sessão não tem exercícios. Toque em Concluir.")
                            )
                        }

                        ForEach(Array(model.exercises.enumerated()), id: \.element.uuid) { pair in
                            card(for: pair.element, number: pair.offset + 1)
                                .id(pair.element.uuid)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedLoadID) { _, newValue in
                    guard let newValue else {
                        // Teclado fechado ("OK" ou arrastar): a carga volta a ser só texto.
                        editingLoadID = nil
                        return
                    }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            // RF-44 f: o descanso fica preso no topo, fora da lista que rola.
            .safeAreaInset(edge: .top, spacing: 0) {
                RestTimerView(timer: model.restTimer, nextUp: model.restNextUpText)
            }
            .sensoryFeedback(.success, trigger: model.markCount)
            .navigationTitle(model.session?.programDayName ?? "Sessão")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbar { toolbarContent }
            .confirmationDialog(
                SessionSheetText.pendingTitle(count: pendingFinish?.names.count ?? 0),
                isPresented: $isShowingPendingDialog,
                titleVisibility: .visible,
                presenting: pendingFinish
            ) { pending in
                Button("Marcar como feitos, como previsto") {
                    model.markRemainingAsPrescribed()
                    finishAndClose()
                }
                if pending.hasAnySet {
                    Button("Encerrar só com o que marquei") {
                        finishAndClose()
                    }
                } else {
                    Button("Sair sem registrar") {
                        model.abandon()
                        if model.isFinished {
                            onFinished()
                        }
                    }
                }
                Button("Voltar ao treino", role: .cancel) {}
            } message: { pending in
                Text(SessionSheetText.pendingMessage(names: pending.names))
            }
            .sheet(item: $infoItem, onDismiss: { runPendingInfoAction() }) { content in
                infoSheet(for: content)
            }
            .sheet(item: $whyItem) { item in
                WhySheet(topic: item.id, catalog: references)
                    .presentationDetents([.medium, .large])
                    .tint(Theme.accent)
            }
            .sheet(
                isPresented: $model.isShowingSubstituteSheet,
                onDismiss: { model.sheetDidDismiss() }
            ) {
                SubstituteExerciseSheet(
                    exerciseName: model.substitutingExerciseName,
                    suggestions: model.substituteSuggestions,
                    references: references,
                    context: .session,
                    onPick: { model.substituteSelectedExercise(with: $0) },
                    onCancel: { model.cancelSubstitution() }
                )
                .tint(Theme.accent)
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
                .presentationDetents([.medium, .large])
            }
        }
        .alert("Erro", isPresented: $model.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear {
            updateIdleTimer(for: scenePhase)
        }
        .onChange(of: scenePhase) { _, newPhase in
            updateIdleTimer(for: newPhase)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: - Partes

    /// RF-44 d: a chave Aquecimento saiu; fica esta linha fixa.
    private var warmupHint: some View {
        Label {
            Text(SessionSheetText.warmupHint)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private func card(for exercise: SessionExerciseModel, number: Int) -> some View {
        let exerciseID = exercise.uuid
        return ExerciseSheetCard(
            model: model,
            exercise: exercise,
            number: number,
            references: references,
            focus: $focusedLoadID,
            isEditingLoad: editingLoadID == exerciseID,
            isExpanded: expandedDoneIDs.contains(exerciseID),
            onOpenInfo: {
                focusedLoadID = nil
                infoItem = model.infoContent(for: exercise)
            },
            onOpenWhy: { topic in
                whyItem = WhyTopic(id: topic)
            },
            onEditLoad: {
                editingLoadID = exerciseID
            },
            onToggleExpanded: {
                if expandedDoneIDs.contains(exerciseID) {
                    expandedDoneIDs.remove(exerciseID)
                } else {
                    expandedDoneIDs.insert(exerciseID)
                }
            }
        )
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                focusedLoadID = nil
                onMinimize()
            } label: {
                Label("Voltar", systemImage: "chevron.down")
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityHint("A sessão continua em andamento; retome pela tela Hoje.")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                conclude()
            } label: {
                Text("Concluir")
                    .fontWeight(.semibold)
            }
            .disabled(!model.isOpen)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("OK") {
                focusedLoadID = nil
            }
            .fontWeight(.semibold)
        }
    }

    /// Informações do exercício (RF-47): "Trocar" só antes da 1ª série (RF-34) e "Pular" só se não
    /// foi pulado. As ações fecham a folha e acontecem no `onDismiss`.
    private func infoSheet(for content: ExerciseInfoContent) -> some View {
        let exercise = model.exercises.first { $0.uuid == content.id }
        let canSubstitute = exercise.map { model.canSubstitute($0) } ?? false
        let canSkip = exercise.map { model.canSkip($0) } ?? false
        return ExerciseInfoSheet(
            content: content,
            references: references,
            onSubstitute: canSubstitute ? {
                pendingInfoAction = .substitute(content.id)
                infoItem = nil
            } : nil,
            onSkip: canSkip ? {
                pendingInfoAction = .skip(content.id)
                infoItem = nil
            } : nil
        )
    }

    // MARK: - Ações

    /// "Concluir" (RF-44 e): tudo marcado → resumo direto; faltando algo → pergunta uma vez.
    private func conclude() {
        focusedLoadID = nil
        switch model.requestFinish() {
        case .finished:
            if model.isFinished {
                onFinished()
            }
        case let .needsConfirmation(pendingNames, hasAnySet):
            pendingFinish = PendingFinish(names: pendingNames, hasAnySet: hasAnySet)
            isShowingPendingDialog = true
        }
    }

    private func finishAndClose() {
        model.finish()
        if model.isFinished {
            onFinished()
        }
    }

    private func runPendingInfoAction() {
        guard let action = pendingInfoAction else {
            return
        }
        pendingInfoAction = nil
        switch action {
        case .substitute(let exerciseID):
            model.beginSubstitution(sessionExerciseID: exerciseID)
        case .skip(let exerciseID):
            model.skip(sessionExerciseID: exerciseID)
        }
    }

    /// RF-44 g: acesa só com a ficha na tela e o app ativo.
    private func updateIdleTimer(for phase: ScenePhase) {
        UIApplication.shared.isIdleTimerDisabled = phase == .active
    }
}

// MARK: - Tipos da tela

/// O que a folha de informações pediu.
private enum InfoAction: Hashable {
    case substitute(UUID)
    case skip(UUID)
}

/// Tópico do "Por quê?" aberto pelo selo, como item de `.sheet(item:)`.
private struct WhyTopic: Identifiable, Hashable {
    let id: String
}

/// Dados do diálogo "Faltam N exercícios".
private struct PendingFinish: Hashable {
    let names: [String]
    let hasAnySet: Bool
}

#Preview("Ficha") {
    if let fixture = SessionPreviewSupport.makeFixture() {
        ActiveSessionView(model: fixture.viewModel, references: .empty, onFinished: {}, onMinimize: {})
            .tint(Theme.accent)
    } else {
        Text("Preview indisponível")
    }
}

#Preview("Ficha · Dynamic Type AX3") {
    if let fixture = SessionPreviewSupport.makeFixture() {
        ActiveSessionView(model: fixture.viewModel, references: .empty, onFinished: {}, onMinimize: {})
            .tint(Theme.accent)
            .dynamicTypeSize(.accessibility3)
    } else {
        Text("Preview indisponível")
    }
}
