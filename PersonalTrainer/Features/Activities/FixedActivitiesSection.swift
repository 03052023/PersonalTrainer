import SwiftUI
import TrainerCore

/// "Atividades fixas" da aba Plano (SPEC §7.17 X2, RF-53; DESIGN §9.3 ponto 3): as atividades fora do app que
/// se repetem toda semana, uma linha por fixa ("Pilates · terça · 19h · 50 min"). Tocar abre a folha de
/// edição (com "Apagar atividade"); tocar e segurar também oferece "Apagar", com confirmação que avisa que os
/// registros já feitos ficam. Embaixo, "Acrescentar atividade fixa", até 10.
///
/// A seção vive dentro do `ScrollView` da aba Plano (não numa `List`), por isso o apagar vem do menu de
/// contexto e da folha, e não do deslizar. Escreve só pelo `ActivitiesModel` (AGENTS R4).
///
/// Andaime da 2.4 (docs/V24-CONTRACT.md §3.2): a assinatura `init(model:)` está congelada (a `plans-ui` põe
/// a seção na aba Plano); o corpo é da tarefa `activities-ui`.
struct FixedActivitiesSection: View {
    let model: ActivitiesModel

    @State private var editorMode: ActivityEditorModel.Mode?
    @State private var pendingDeletion: FixedOutsideActivity?
    @State private var errorText: String?

    init(model: ActivitiesModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ActivityText.fixedTitle)
                    .font(.system(.title3, design: .serif, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(ActivityText.fixedFootnote)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            list
            addButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $editorMode) { mode in
            ActivityEditorSheet(activities: model, mode: mode)
        }
        .confirmationDialog(
            ActivityText.deleteQuestion,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { fixed in
            Button(ActivityText.deleteShort, role: .destructive) {
                delete(fixed)
            }
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text(ActivityText.deleteFixedMessage)
        }
        .alert(
            ActivityText.errorTitle,
            isPresented: Binding(
                get: { errorText != nil },
                set: { isPresented in
                    if !isPresented {
                        errorText = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .onAppear {
            model.refresh()
        }
    }

    // MARK: - Peças

    @ViewBuilder
    private var list: some View {
        let fixed = model.fixedActivities
        if fixed.isEmpty {
            Text(ActivityText.noFixed)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .inkCard(cornerRadius: 12)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(fixed.enumerated()), id: \.element.id) { index, activity in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 14)
                    }
                    row(activity)
                }
            }
            .inkCard(cornerRadius: 12)
        }
    }

    private func row(_ activity: FixedOutsideActivity) -> some View {
        Button {
            editorMode = .editFixed(activity)
        } label: {
            HStack(spacing: 8) {
                Text(ActivityText.fixedLine(activity))
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(ActivityText.fixedSpoken(activity)))
        .accessibilityHint(Text("Abre para editar ou apagar"))
        .contextMenu {
            Button(role: .destructive) {
                pendingDeletion = activity
            } label: {
                Label(ActivityText.deleteShort, systemImage: "trash")
            }
        }
    }

    /// "Acrescentar atividade fixa" (`plus.circle`, `accent`, sem fundo); com 10 fixas, só o fato.
    @ViewBuilder
    private var addButton: some View {
        if model.canAddFixed {
            Button {
                editorMode = .newFixed
            } label: {
                Label(ActivityText.addFixed, systemImage: "plus.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            Text(ActivityText.fixedLimitReached)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func delete(_ activity: FixedOutsideActivity) {
        pendingDeletion = nil
        if !model.deleteFixed(id: activity.id) {
            errorText = model.errorMessage ?? ActivityText.saveFailed
        }
    }
}
