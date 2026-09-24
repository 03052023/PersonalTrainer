import Charts
import SwiftUI
import TrainerCore

/// Tendência do VO2máx estimado pelo Apple Watch nos últimos 90 dias (SPEC RF-28, §7.10 A3).
/// Com menos de duas medições não há tendência a desenhar; mostra só um texto.
struct Vo2MaxTrendChart: View {
    private let samples: [Vo2MaxSample]
    private let calendar: Calendar

    init(samples: [Vo2MaxSample], calendar: Calendar) {
        self.samples = samples.sorted { $0.date < $1.date }
        self.calendar = calendar
    }

    var body: some View {
        if samples.count < 2 {
            Text("São precisas ao menos duas medições nos últimos 90 dias para desenhar a tendência.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Chart(samples, id: \.self) { sample in
                LineMark(
                    x: .value("Data", sample.date),
                    y: .value("VO2máx", sample.value)
                )
                .interpolationMethod(.linear)
                // Paleta neutra provisória (SPEC decisão 15), como em `AerobicWeekChart`.
                .foregroundStyle(Color.primary.opacity(0.8))
                PointMark(
                    x: .value("Data", sample.date),
                    y: .value("VO2máx", sample.value)
                )
                .symbolSize(24)
                .foregroundStyle(Color.primary.opacity(0.8))
            }
            .chartYScale(domain: Self.yDomain(for: samples))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxisLabel("mL/kg/min")
            // Rótulos de data em pt-BR e no fuso do cálculo, independentemente do idioma do aparelho.
            .environment(\.locale, Locale(identifier: "pt_BR"))
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
            .frame(height: 160)
            .accessibilityLabel("Tendência do VO2máx nos últimos 90 dias")
        }
    }

    /// Margem de 2 mL/kg/min em volta dos valores: variações de 1–2 pontos ficam visíveis sem que
    /// o eixo comece em zero e achate a linha.
    static func yDomain(for samples: [Vo2MaxSample]) -> ClosedRange<Double> {
        let values = samples.map(\.value).filter(\.isFinite)
        guard let low = values.min(), let high = values.max() else { return 0...60 }
        let lower = max(0, (low - 2).rounded(.down))
        let upper = max(lower + 1, (high + 2).rounded(.up))
        return lower...upper
    }
}
