import SwiftUI
import TrainerCore

/// Editor de um dia do programa (T2.6, T2.20; SPEC RF-16, RF-33, RF-34): reordenar, remover,
/// adicionar, trocar e editar exercícios. Usa o `ProgramDetailViewModel` da tela do programa,
/// que faz todas as escritas pelo repositório (AGENTS R4).
///
/// Seletores e editor abrem em `.sheet`; a escrita correspondente roda no `onDismiss`, depois
/// que a folha fechou, para um eventual alerta de erro não disputar a animação da folha.
struct DayEditorView: View {
    /// Pedido de seletor de exercício: adicionar ao dia ou trocar um alvo.
    private struct PickerRequest: Identifiable {
        enum Kind {
            case add
            case replace(targetID: UUID)
        }

        let id = UUID()
        let kind: Kind
        let title: String
        let highlighted: [ExerciseDefinition]
    }

    /// Pedido de edição de um alvo.
    private struct EditRequest: Identifiable {
        let id: UUID
        let exerciseName: String
        let draft: ProgramDetailViewModel.TargetDraft
    }

    /// Escrita adiada até a folha fechar.
    private enum PendingChange {
        case add(exerciseID: UUID)
        case replace(targetID: UUID, exerciseID: UUID)
        case update(targetID: UUID, draft: ProgramDetailViewModel.TargetDraft)
    }

    @Bindable private var model: ProgramDetailViewModel
    private let dayID: UUID

    @State private var pickerRequest: PickerRequest? = nil
    @State private var editRequest: EditRequest? = nil
    @State private var pendingChange: PendingChange? = nil

    init(model: ProgramDetailViewModel, dayID: UUID) {
        self.model = model
        self.dayID = dayID
    }

    var body: some View {
        Group {
            if let day = model.day(id: dayID) {
                content(for: day)
            } else {
                ContentUnavailableView(
                    "Dia não encontrado",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("Este dia não existe mais no programa.")
                )
            }
        }
        .sheet(item: $pickerRequest, onDismiss: { applyPendingChange() }) { request in
            ExercisePickerView(
                exercises: model.availableExercises,
                title: request.title,
                highlighted: request.highlighted,
                onPick: { exercise in
                    switch request.kind {
                    case .add:
                        pendingChange = .add(exerciseID: exercise.id)
                    case .replace(let targetID):
                        pendingChange = .replace(targetID: targetID, exerciseID: exercise.id)
                    }
                    pickerRequest = nil
                },
                onCancel: {
                    pendingChange = nil
                    pickerRequest = nil
                }
            )
        }
        .sheet(item: $editRequest, onDismiss: { applyPendingChange() }) { request in
            TargetEditorSheet(
                exerciseName: request.exerciseName,
                draft: request.draft,
                onSave: { draft in
                    pendingChange = .update(targetID: request.id, draft: draft)
                    editRequest = nil
                },
                onCancel: {
                    pendingChange = nil
                    editRequest = nil
                }
            )
        }
        .alert("Não foi possível alterar", isPresented: $model.isPresentingDayError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.dayErrorMessage ?? "")
        }
    }

    private func content(for day: ProgramDayTemplate) -> some View {
        let targets = model.targets(inDay: dayID)
        let canAdd = model.canAddExercise(toDay: dayID)
        return List {
            Section {
                ForEach(targets, id: \.id) { target in
                    row(for: target)
                }
                .onMove { source, destination in
                    model.moveTargets(fromOffsets: source, toOffset: destination, inDay: dayID)
                }
                .onDelete { offsets in
                    model.removeTargets(atOffsets: offsets, inDay: dayID)
                }
            } header: {
                Text("Exercícios")
            } footer: {
                Text("\(targets.count) de \(ProgramLimits.maxExercisesPerDay) exercícios. Cada dia tem entre \(ProgramLimits.minExercisesPerDay) e \(ProgramLimits.maxExercisesPerDay).")
            }

            Section {
                Button {
                    pickerRequest = PickerRequest(
                        kind: .add,
                        title: "Adicionar exercício",
                        highlighted: []
                    )
                } label: {
                    Label("Adicionar exercício", systemImage: "plus.circle.fill")
                }
                .disabled(!canAdd)
            } footer: {
                if !canAdd {
                    Text("Limite de \(ProgramLimits.maxExercisesPerDay) exercícios por dia atingido.")
                }
            }
        }
        .navigationTitle(day.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    /// Nome, resumo "3 × 8–12 · RIR 2 · 2 min" e menu com Trocar/Editar.
    private func row(for target: ExerciseTarget) -> some View {
        let name = model.exerciseName(for: target)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.body.weight(.medium))
                Text(model.summary(for: target))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Menu {
                Button {
                    requestReplacement(of: target)
                } label: {
                    Label("Trocar exercício", systemImage: "arrow.triangle.2.circlepath")
                }
                Button {
                    requestEdit(of: target, name: name)
                } label: {
                    Label("Editar", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Opções de \(name)")
        }
        .padding(.vertical, 2)
    }

    private func requestReplacement(of target: ExerciseTarget) {
        pickerRequest = PickerRequest(
            kind: .replace(targetID: target.id),
            title: "Trocar exercício",
            highlighted: model.substitutes(forTargetID: target.id, inDay: dayID)
        )
    }

    private func requestEdit(of target: ExerciseTarget, name: String) {
        guard let draft = model.makeDraft(forTargetID: target.id, inDay: dayID) else { return }
        editRequest = EditRequest(id: target.id, exerciseName: name, draft: draft)
    }

    /// Roda depois que qualquer folha fechou; cancelar deixa `pendingChange` vazio.
    private func applyPendingChange() {
        guard let change = pendingChange else { return }
        pendingChange = nil
        switch change {
        case .add(let exerciseID):
            model.addExercise(exerciseID, toDay: dayID)
        case .replace(let targetID, let exerciseID):
            model.replaceExercise(targetID: targetID, with: exerciseID)
        case .update(let targetID, let draft):
            model.updateTarget(id: targetID, with: draft)
        }
    }
}
