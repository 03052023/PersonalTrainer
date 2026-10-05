import SwiftUI
import TrainerCore

/// Seção "Fora do app" das Metas da semana (SPEC RF-52, RF-53, §7.17; DESIGN §9.2 ponto 5, §9.3 ponto 1): uma
/// linha por registro da semana, do mais antigo ao mais novo ("Pilates · terça · 50 min · leve", o nome do
/// tipo em `textPrimary` e o resto em `textSecondary`). Tocar abre a edição; deslizar mostra "Apagar". Sem
/// registros, "Nada registrado nesta semana.". Embaixo, "Registrar atividade" (`plus.circle`, `accent`, sem
/// fundo) e o "Por quê?" de `topic.activities`.
///
/// É o conteúdo de uma `List` (as Metas da semana): a folha e a confirmação ficam na própria `List`, por
/// fechamentos, para haver uma só de cada na tela.
struct OutsideActivitiesGoalsSection: View {
    let model: ActivitiesModel
    let references: ReferenceCatalog
    let onRegister: () -> Void
    let onEdit: (OutsideActivityEntry) -> Void
    let onDelete: (OutsideActivityEntry) -> Void

    /// Tópico do "Por quê?" das atividades (SPEC §7.17; `references.v1.json`).
    static let referenceTopic = "topic.activities"

    var body: some View {
        Section {
            let entries = model.weekEntries
            if entries.isEmpty {
                Text(ActivityText.nothingThisWeek)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(entries) { entry in
                    row(entry)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    onRegister()
                } label: {
                    Label(ActivityText.register, systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                Spacer(minLength: 8)
                WhyButton(topic: Self.referenceTopic, catalog: references)
            }
        } header: {
            Text(ActivityText.sectionTitle)
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Theme.textPrimary)
                .textCase(nil)
                .accessibilityAddTraits(.isHeader)
        }
        .listRowBackground(Theme.surface)
    }

    private func row(_ entry: OutsideActivityEntry) -> some View {
        let calendar = model.calendar
        let name: Text = Text(entry.kind.displayName).foregroundStyle(Theme.textPrimary)
        let details: Text = Text(" · " + ActivityText.entryDetails(entry, calendar: calendar))
            .foregroundStyle(Theme.textSecondary)
        return Button {
            onEdit(entry)
        } label: {
            Text("\(name)\(details)")
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(ActivityText.entrySpoken(entry, calendar: calendar)))
        .accessibilityHint(Text("Abre para editar"))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Sem `role: .destructive` de propósito (como no Histórico): com esse papel a lista anima a
            // remoção antes da confirmação.
            Button {
                onDelete(entry)
            } label: {
                Label(ActivityText.deleteShort, systemImage: "trash")
            }
            .tint(Theme.destructive)
        }
    }
}
