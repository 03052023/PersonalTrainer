import SwiftUI
import TrainerCore

/// A semana dia a dia (SPEC §7.15 M4; DESIGN §13): de segunda a domingo, as sessões de cada dia
/// ("Dia A — Superior + Cardio forte") e "descanso" nos livres, com um ponto de tinta na cor do objetivo
/// de cada sessão, e os avisos de M4 embaixo. A cor nunca identifica sozinha: o texto diz a sessão.
///
/// View pura: as linhas e os avisos chegam prontos de `PlanWeekText`.
struct WeekScheduleView: View {
    let rows: [PlanWeekText.WeekRow]
    let notes: [String]

    /// Largura da coluna dos pontos: até duas sessões por dia (M4).
    private static let dotColumnWidth: CGFloat = 20
    private static let dotSize: CGFloat = 7

    init(rows: [PlanWeekText.WeekRow], notes: [String] = []) {
        self.rows = rows
        self.notes = notes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows) { row in
                rowView(row)
            }
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowView(_ row: PlanWeekText.WeekRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(row.dayLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 36, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(Array(row.goals.enumerated()), id: \.offset) { _, goal in
                    Circle()
                        .fill(goal.color)
                        .frame(width: Self.dotSize, height: Self.dotSize)
                }
            }
            .frame(width: Self.dotColumnWidth, alignment: .leading)
            Text(row.sessionsText)
                .font(.subheadline)
                .foregroundStyle(row.isRest ? Theme.textSecondary : Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(row.spokenText))
    }
}
