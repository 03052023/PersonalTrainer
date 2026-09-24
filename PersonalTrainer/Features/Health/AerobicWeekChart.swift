import Charts
import SwiftUI
import TrainerCore

/// Minutos aeróbicos por dia da semana, empilhados em moderado e vigoroso (SPEC RF-27, §7.10 A1).
///
/// As barras mostram minutos reais; a meta (moderados-equivalentes, A2) fica no texto e na barra de
/// progresso acima do gráfico, porque 1 min vigoroso vale 2 e as unidades não se somam na mesma barra.
struct AerobicWeekChart: View {
    /// Um segmento da barra de um dia.
    struct Point: Identifiable, Hashable {
        let id: String
        let dayLabel: String
        let intensity: String
        let minutes: Int
    }

    static let moderateLabel = "Moderado"
    static let vigorousLabel = "Vigoroso"

    private let points: [Point]
    private let hasAnyMinutes: Bool

    init(summary: AerobicWeekSummary, calendar: Calendar) {
        self.points = Self.makePoints(summary.perDay, calendar: calendar)
        self.hasAnyMinutes = summary.perDay.contains { $0.moderate > 0 || $0.vigorous > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(points) { point in
                BarMark(
                    x: .value("Dia", point.dayLabel),
                    y: .value("Minutos", point.minutes)
                )
                .foregroundStyle(by: .value("Intensidade", point.intensity))
            }
            // Paleta neutra provisória (SPEC decisão 15: a passada de design aplica os tokens
            // terrosos). `primary` se adapta ao modo escuro; o cinza claro separa as intensidades.
            .chartForegroundStyleScale([
                Self.moderateLabel: Color.gray.opacity(0.5),
                Self.vigorousLabel: Color.primary.opacity(0.8),
            ])
            .chartYAxisLabel("min")
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 180)
            .accessibilityLabel("Minutos de aeróbico por dia da semana")

            if !hasAnyMinutes {
                Text("Nenhum treino aeróbico registrado no app Saúde nesta semana.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Dois segmentos por dia (moderado, vigoroso), na ordem cronológica. Rótulos categóricos
    /// ("seg.", "ter.") são únicos numa semana de 7 dias, então o eixo X fica na ordem dos dados.
    static func makePoints(_ perDay: [DailyAerobicMinutes], calendar: Calendar) -> [Point] {
        let style = Date.FormatStyle(
            locale: Locale(identifier: "pt_BR"),
            calendar: calendar,
            timeZone: calendar.timeZone
        ).weekday(.abbreviated)

        return perDay
            .sorted { $0.day < $1.day }
            .flatMap { day -> [Point] in
                let label = day.day.formatted(style)
                let key = String(Int(day.day.timeIntervalSince1970))
                return [
                    Point(id: key + "-moderate", dayLabel: label, intensity: moderateLabel, minutes: max(0, day.moderate)),
                    Point(id: key + "-vigorous", dayLabel: label, intensity: vigorousLabel, minutes: max(0, day.vigorous)),
                ]
            }
    }
}
