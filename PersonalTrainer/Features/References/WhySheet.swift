import SwiftUI
import TrainerCore

/// Folha "Por quê?" (SPEC RF-32): explicação curta do tópico, a regra da SPEC quando houver e as
/// referências completas do catálogo (autores, ano, título, fonte, nível de evidência e DOI).
/// Só lê o `ReferenceCatalog` recebido; não toca em persistência.
struct WhySheet: View {
    private let topic: String
    private let catalog: ReferenceCatalog

    @Environment(\.dismiss) private var dismiss

    init(topic: String, catalog: ReferenceCatalog) {
        self.topic = topic
        self.catalog = catalog
    }

    var body: some View {
        NavigationStack {
            List {
                explanationSection
                referencesSection
                Section {
                    Text("Critério: diretrizes, consensos e meta-análises primeiro; estudo isolado só quando não há síntese, marcado como evidência limitada.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(Self.title(for: topic))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var explanationSection: some View {
        let explanation = catalog.explanations[topic]
        let rule = Self.ruleLabels[topic]
        if explanation != nil || rule != nil {
            Section {
                if let explanation {
                    Text(explanation)
                }
                if let rule {
                    Text(rule)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var referencesSection: some View {
        let references = catalog.references(for: topic)
        return Section("Referências") {
            if references.isEmpty {
                Text("Sem referências para este item.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(references) { reference in
                    ReferenceRow(reference: reference)
                }
            }
        }
    }
}

// MARK: - Títulos e regras

extension WhySheet {
    /// Título da folha a partir da chave de tópico (chaves documentadas em `ReferenceCatalog`).
    static func title(for topic: String) -> String {
        if let title = titles[topic] {
            return title
        }
        if topic.hasPrefix("goal."), let goal = ProgramGoal(rawValue: String(topic.dropFirst("goal.".count))) {
            return "Objetivo: \(goal.displayName)"
        }
        return "Por quê?"
    }

    private static let titles: [String: String] = [
        "rule.P2": "Sem histórico",
        "rule.P4": "Subir a carga",
        "rule.P5": "Manter e somar repetições",
        "rule.P6": "Falha na faixa",
        "rule.P9": "Retorno após pausa",
        "rule.S2": "Rotação dos dias",
        "rule.D": "Deload",
        "note.calibrate": "Calibração",
        "note.increase": "Subir a carga",
        "note.hold": "Manter a carga",
        "note.retry": "Repetir a carga",
        "note.decrease": "Reduzir a carga",
        "note.returning": "Retorno após pausa",
        "note.deload": "Deload",
        "topic.rir": "Repetições em reserva (RIR)",
        "topic.volume": "Volume semanal",
        "topic.frequency": "Frequência semanal",
        "topic.maintenance": "Volume de manutenção",
        "topic.substitution": "Troca de exercício",
        "topic.rest": "Descanso entre séries",
        "topic.concurrent": "Aeróbico e musculação",
        "topic.hrv": "Variabilidade da frequência cardíaca",
        "topic.aerobic": "Aeróbico semanal",
        "topic.vo2max": "VO2max",
    ]

    /// Regra da SPEC por trás de cada tópico, exibida abaixo da explicação.
    private static let ruleLabels: [String: String] = [
        "rule.P2": "Regra P2 · SPEC §7.2",
        "rule.P4": "Regra P4 · SPEC §7.2",
        "rule.P5": "Regra P5 · SPEC §7.2",
        "rule.P6": "Regra P6 · SPEC §7.2",
        "rule.P9": "Regra P9 · SPEC §7.2",
        "rule.S2": "Regra S2 · SPEC §7.3",
        "rule.D": "Deload · SPEC §7.5",
        "note.calibrate": "Regra P2 · SPEC §7.2",
        "note.increase": "Regra P4 · SPEC §7.2",
        "note.hold": "Regra P5 · SPEC §7.2",
        "note.retry": "Regra P6 · SPEC §7.2",
        "note.decrease": "Regra P6 · SPEC §7.2",
        "note.returning": "Regra P9 · SPEC §7.2",
        "note.deload": "Deload · SPEC §7.5",
        "goal.hypertrophy": "Objetivo do programa · SPEC §7.9",
        "goal.strength": "Objetivo do programa · SPEC §7.9",
        "goal.endurance": "Objetivo do programa · SPEC §7.9",
        "goal.longevity": "Objetivo do programa · SPEC §7.9",
        "goal.combat": "Objetivo do programa · SPEC §7.9",
    ]
}

// MARK: - Linha de referência

extension WhySheet {
    /// Referência completa em uma linha de `List`. Aninhada aqui para ser reaproveitada por
    /// `ReferenceListView` sem criar outro tipo de topo.
    struct ReferenceRow: View {
        let reference: ScientificReference

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(reference.title)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: "\(reference.authors) (\(reference.year))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(reference.source)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
                Text(reference.summary)
                    .font(.footnote)
                HStack(alignment: .center, spacing: 12) {
                    levelBadge
                    Spacer(minLength: 0)
                    if let destination = linkURL {
                        Link(destination: destination) {
                            Label(linkTitle, systemImage: "arrow.up.right.square")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(.vertical, 4)
        }

        private var levelBadge: some View {
            Text(reference.level.displayName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(levelColor)
                .background(levelColor.opacity(0.15), in: Capsule())
                .accessibilityLabel("Nível de evidência: \(reference.level.displayName)")
        }

        private var levelColor: Color {
            switch reference.level {
            case .guideline: return .green
            case .consensus: return .teal
            case .metaAnalysis: return .blue
            case .systematicReview: return .indigo
            case .narrativeReview: return .orange
            case .study: return .gray
            }
        }

        private var linkURL: URL? {
            guard let link = reference.link else { return nil }
            return URL(string: link)
        }

        private var linkTitle: String {
            if let doi = reference.doi {
                return "DOI \(doi)"
            }
            return "Abrir fonte"
        }
    }
}

// MARK: - Preview

extension WhySheet {
    /// Catálogo pequeno e fixo para os `#Preview` de `WhySheet`, `WhyButton` e `ReferenceListView`.
    static let previewCatalog = ReferenceCatalog(
        version: 1,
        references: [
            ScientificReference(
                id: "acsm-2009-progression",
                authors: "American College of Sports Medicine",
                year: 2009,
                title: "Progression Models in Resistance Training for Healthy Adults",
                source: "Medicine & Science in Sports & Exercise",
                doi: "10.1249/MSS.0b013e3181915670",
                level: .guideline,
                summary: "Aumentar a carga em 2–10% quando se completam 1–2 repetições além do alvo."
            ),
            ScientificReference(
                id: "schoenfeld-2017-volume",
                authors: "Schoenfeld BJ, Ogborn D, Krieger JW",
                year: 2017,
                title: "Dose-response relationship between weekly resistance training volume and increases in muscle mass: A systematic review and meta-analysis",
                source: "Journal of Sports Sciences",
                doi: "10.1080/02640414.2016.1210197",
                level: .metaAnalysis,
                summary: "Cada série semanal a mais por músculo se associou a maior ganho de massa muscular."
            ),
            ScientificReference(
                id: "zourdos-2016-rir",
                authors: "Zourdos MC, Klemp A, Dolan C, Quiles JM, Schau KA, Jo E, et al.",
                year: 2016,
                title: "Novel Resistance Training–Specific Rating of Perceived Exertion Scale Measuring Repetitions in Reserve",
                source: "Journal of Strength and Conditioning Research",
                doi: "10.1519/JSC.0000000000001049",
                level: .study,
                summary: "Validou a escala de esforço baseada em repetições em reserva."
            ),
        ],
        topics: [
            "note.increase": ["acsm-2009-progression", "zourdos-2016-rir"],
            "topic.volume": ["schoenfeld-2017-volume"],
        ],
        explanations: [
            "note.increase": "Você completou o topo da faixa em todas as séries, então a carga sobe e a meta volta ao mínimo da faixa.",
            "topic.volume": "Volume é o número de séries de trabalho por grupo muscular por semana.",
        ]
    )
}

#Preview("Por quê? — nota de prescrição") {
    WhySheet(topic: "note.increase", catalog: WhySheet.previewCatalog)
}

#Preview("Por quê? — tópico") {
    WhySheet(topic: "topic.volume", catalog: WhySheet.previewCatalog)
}

#Preview("Por quê? — sem referências") {
    WhySheet(topic: "topic.hrv", catalog: WhySheet.previewCatalog)
}
