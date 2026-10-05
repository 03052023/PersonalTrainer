import SwiftUI
import TrainerCore

/// "Também hoje" da tela Hoje (SPEC §7.17 X2, RF-53; DESIGN §9 item 8, §9.3 ponto 4): um cartão de papel com
/// o rótulo pequeno "Também hoje" e uma linha por atividade fixa de hoje ("Pilates · 19h · 50 min"), com
/// "Feito" em `accent` à direita (botão sem fundo, ≥ 44 pt), que grava o registro do dia (uma vez por dia).
/// Depois do toque, a linha vira "✓ Feito", em `textSecondary`. Sem fixa hoje, não desenha nada. Nunca é o
/// botão proeminente da tela.
///
/// Andaime da 2.4 (docs/V24-CONTRACT.md §3.2): a assinatura `init(model:)` está congelada (a `plans-ui` põe o
/// cartão na tela Hoje); o corpo é da tarefa `activities-ui`.
struct TodayActivitiesCard: View {
    let model: ActivitiesModel

    @State private var errorText: String?

    init(model: ActivitiesModel) {
        self.model = model
    }

    var body: some View {
        let items = model.todayItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(ActivityText.alsoToday)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                ForEach(items) { item in
                    row(item)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .inkCard()
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
        }
    }

    private func row(_ item: ActivitiesModel.TodayItem) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(ActivityText.todayFixedLine(item.activity))
                .font(.body)
                .foregroundStyle(item.isDone ? Theme.textSecondary : Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(ActivityText.todayFixedSpoken(item.activity)))
            Spacer(minLength: 8)
            if item.isDone {
                Text(ActivityText.doneMark)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 44)
                    .accessibilityLabel(Text("Feito hoje"))
            } else {
                Button {
                    markDone(item.activity)
                } label: {
                    Text(ActivityText.done)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Marcar \(item.activity.kind.displayName) como feito hoje"))
            }
        }
    }

    private func markDone(_ activity: FixedOutsideActivity) {
        if !model.markDone(fixedID: activity.id) {
            errorText = model.errorMessage ?? ActivityText.saveFailed
        }
    }
}
