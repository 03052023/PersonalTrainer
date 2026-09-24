import SwiftUI
import TrainerCore

/// Card "Saúde" da Home (SPEC RF-31): resumo compacto de aeróbico, VO2máx, sono e passos, e a
/// primeira sugestão. Toque abre `HealthDetailView` por `NavigationLink` (a Home vive num
/// `NavigationStack`).
///
/// Só leitura do Saúde; nada aqui muda a musculação (SPEC P12). O pedido de autorização só sai do
/// botão "Conectar ao Saúde" (AGENTS §7: nunca no launch). O card dispara a própria leitura em
/// `.task` (`loadIfStale`), então a Home só precisa criá-lo.
struct HealthCardView: View {
    private let model: HealthViewModel
    private let references: ReferenceCatalog
    /// `false` esconde a primeira sugestão do card: o diálogo (SPEC §7.11 C3) já mostra as
    /// sugestões de saúde no próprio feed, e repeti-las aqui duplicaria o aviso (contrato onda 3
    /// §2.1). O padrão `true` mantém o card completo onde ninguém passa o diálogo (previews).
    private let showsSuggestions: Bool

    init(model: HealthViewModel, references: ReferenceCatalog, showsSuggestions: Bool = true) {
        self.model = model
        self.references = references
        self.showsSuggestions = showsSuggestions
    }

    var body: some View {
        content
            // Captura só o ViewModel (classe @MainActor, portanto Sendable), como a HomeView.
            .task { @MainActor [model] in
                await model.loadIfStale()
            }
    }

    @ViewBuilder
    private var content: some View {
        if !model.isHealthAvailable {
            card {
                header(showsChevron: false)
                Text(HealthViewModel.unavailableMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if model.needsAuthorization {
            connectPrompt
        } else if let report = model.report {
            NavigationLink {
                HealthDetailView(model: model, references: references)
            } label: {
                card {
                    summary(report)
                }
            }
            .buttonStyle(.plain)
        } else if model.isLoading || model.errorMessage == nil {
            // Sem relatório e sem erro = a primeira leitura ainda não terminou (o `.task` pode
            // não ter começado): mostra "lendo" em vez de piscar o estado de erro.
            card {
                header(showsChevron: false)
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Lendo o app Saúde…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            card {
                header(showsChevron: false)
                Text(model.errorMessage ?? "Sem dados do app Saúde por enquanto.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Tentar de novo") {
                    Task { @MainActor [model] in
                        await model.load()
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    // MARK: - Estados

    private var connectPrompt: some View {
        card {
            header(showsChevron: false)
            Text("Conecte ao app Saúde para ver aeróbico, VO2máx, sono e recuperação")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = model.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Button {
                Task { @MainActor [model] in
                    await model.requestAuthorization()
                }
            } label: {
                Text("Conectar ao Saúde")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(model.isRequestingAuthorization)
        }
    }

    private func summary(_ report: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(showsChevron: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(Format.aerobicHeadline(report.aerobic))
                    .font(.headline)
                ProgressView(
                    value: Format.clampedProgress(report.aerobic.moderateEquivalentMinutes, of: report.aerobic.target),
                    total: 1
                )
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                metricLine(systemImage: "lungs", text: Format.vo2MaxLine(report.vo2Max))
                metricLine(systemImage: "bed.double", text: Format.sleepLine(report.recovery.sleep7))
                metricLine(systemImage: "figure.walk", text: Format.stepsLine(report.steps.average7))
            }

            if showsSuggestions, let suggestion = model.visibleSuggestions.first {
                Divider()
                Label {
                    Text(suggestion.title)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: HealthSuggestionRow.symbolName(for: suggestion.kind))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Abre os detalhes de saúde")
    }

    // MARK: - Peças

    private func header(showsChevron: Bool) -> some View {
        HStack {
            Label("Saúde", systemImage: "heart.text.square")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func metricLine(systemImage: String, text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }

    /// Mesmo acabamento do `PlanCard` da Home; a passada de design troca por tokens terrosos.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Formatação pt-BR (compartilhada com a tela de detalhe)

extension HealthCardView {
    /// Textos e números da feature Saúde. Só a View formata (AGENTS §4); o relatório guarda
    /// minutos, bpm, ms, horas e passos crus. Locale fixo pt-BR, como o resto da UI.
    enum Format {
        private static let locale = Locale(identifier: "pt_BR")

        /// "6,8", "44", "1.234,5". Arredonda antes para não exibir "-0".
        static func decimal(_ value: Double, maxFractionDigits: Int = 1) -> String {
            guard value.isFinite else { return "—" }
            let digits = max(0, maxFractionDigits)
            let scale = pow(10, Double(digits))
            let rounded = (value * scale).rounded() / scale
            let clean = rounded == 0 ? 0 : rounded
            return clean.formatted(.number.locale(locale).precision(.fractionLength(0...digits)))
        }

        /// "+1,2", "-0,8", "0".
        static func signedDecimal(_ value: Double, maxFractionDigits: Int = 1) -> String {
            let text = decimal(value, maxFractionDigits: maxFractionDigits)
            guard value.isFinite, text != "0", value > 0 else { return text }
            return "+" + text
        }

        /// "8.200".
        static func integer(_ value: Int) -> String {
            value.formatted(.number.locale(locale))
        }

        /// "23 de set. de 2026", no fuso do calendário do cálculo.
        static func date(_ date: Date, calendar: Calendar) -> String {
            let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            return date.formatted(style.day().month(.abbreviated).year())
        }

        /// Fração 0...1 para `ProgressView`; meta zero ou negativa vira barra vazia (sem divisão por zero).
        static func clampedProgress(_ value: Int, of target: Int) -> Double {
            guard target > 0 else { return 0 }
            return min(1, max(0, Double(value) / Double(target)))
        }

        /// "Aeróbico: 95 de 150 min".
        static func aerobicHeadline(_ aerobic: AerobicWeekSummary) -> String {
            "Aeróbico: \(integer(aerobic.moderateEquivalentMinutes)) de \(integer(aerobic.target)) min"
        }

        /// "VO2máx 44 · Bom" ou "VO2máx sem medição recente".
        static func vo2MaxLine(_ summary: Vo2MaxSummary?) -> String {
            guard let summary else { return "VO2máx sem medição recente" }
            let value = decimal(summary.latest)
            if let band = summary.band {
                return "VO2máx \(value) · \(band.displayName)"
            }
            return "VO2máx \(value)"
        }

        /// "Sono 6,8 h" ou "Sono sem dados".
        static func sleepLine(_ hours: Double?) -> String {
            guard let hours else { return "Sono sem dados" }
            return "Sono \(decimal(hours)) h"
        }

        /// "Passos 8.200/dia" ou "Passos sem dados".
        static func stepsLine(_ average: Int?) -> String {
            guard let average else { return "Passos sem dados" }
            return "Passos \(integer(average))/dia"
        }
    }
}
