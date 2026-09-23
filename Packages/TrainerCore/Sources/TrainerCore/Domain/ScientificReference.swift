import Foundation

/// Referência científica exibida pelo botão "Por quê?" (SPEC RF-32). Vem do catálogo versionado
/// `references.v1.json` no bundle do app, como o seed.
public struct ScientificReference: Codable, Sendable, Hashable, Identifiable {
    /// Nível de evidência, do mais forte ao mais fraco (critério de inclusão em SPEC §7.9).
    public enum EvidenceLevel: String, Codable, Sendable, Hashable, CaseIterable {
        case guideline
        case consensus
        case metaAnalysis
        case systematicReview
        case narrativeReview
        case study

        public var displayName: String {
            switch self {
            case .guideline: return "Diretriz"
            case .consensus: return "Consenso de especialistas"
            case .metaAnalysis: return "Meta-análise"
            case .systematicReview: return "Revisão sistemática"
            case .narrativeReview: return "Revisão"
            case .study: return "Estudo (evidência limitada)"
            }
        }
    }

    /// Identificador estável em kebab-case, ex.: "schoenfeld-2017-volume".
    public let id: String
    /// Autores no formato "Schoenfeld BJ, Ogborn D, Krieger JW".
    public let authors: String
    public let year: Int
    public let title: String
    /// Revista ou organização (para diretrizes).
    public let source: String
    /// DOI sem prefixo de URL, ex.: "10.1080/02640414.2016.1210197". `nil` só para diretrizes sem DOI.
    public let doi: String?
    /// URL alternativa quando não há DOI.
    public let url: String?
    public let level: EvidenceLevel
    /// Uma frase em pt-BR dizendo o que a fonte sustenta no app.
    public let summary: String

    public init(
        id: String,
        authors: String,
        year: Int,
        title: String,
        source: String,
        doi: String? = nil,
        url: String? = nil,
        level: EvidenceLevel,
        summary: String
    ) {
        self.id = id
        self.authors = authors
        self.year = year
        self.title = title
        self.source = source
        self.doi = doi
        self.url = url
        self.level = level
        self.summary = summary
    }

    /// Link clicável: `https://doi.org/<doi>` quando há DOI; senão `url`.
    public var link: String? {
        if let doi { return "https://doi.org/\(doi)" }
        return url
    }
}

/// Catálogo de referências e mapeamento tópico → referências (SPEC RF-32).
///
/// Chaves de tópico (contrato do M2):
/// - `rule.<ID>` para regras da SPEC: `rule.P2`, `rule.P4`, `rule.P5`, `rule.P6`, `rule.P9`, `rule.S2`, `rule.D` (deload).
/// - `note.<PrescriptionNote.rawValue>`: `note.calibrate`, `note.increase`, `note.hold`, `note.retry`,
///   `note.decrease`, `note.returning`, `note.deload`.
/// - `goal.<ProgramGoal.rawValue>`: `goal.hypertrophy`, `goal.strength`, `goal.endurance`, `goal.longevity`, `goal.combat`.
/// - `topic.<nome>`: `topic.rir`, `topic.volume`, `topic.frequency`, `topic.maintenance`,
///   `topic.substitution`, `topic.rest`, `topic.concurrent`, `topic.hrv`, `topic.aerobic`, `topic.vo2max`.
public struct ReferenceCatalog: Codable, Sendable, Hashable {
    public let version: Int
    public let references: [ScientificReference]
    /// Tópico → ids de referências, na ordem de exibição.
    public let topics: [String: [String]]
    /// Tópico → explicação curta em pt-BR (1–3 frases) exibida acima das referências.
    public let explanations: [String: String]

    public init(version: Int, references: [ScientificReference], topics: [String: [String]], explanations: [String: String]) {
        self.version = version
        self.references = references
        self.topics = topics
        self.explanations = explanations
    }

    /// Catálogo vazio, usado quando o arquivo não carrega (a UI esconde o botão "Por quê?").
    public static let empty = ReferenceCatalog(version: 0, references: [], topics: [:], explanations: [:])

    /// Referências de um tópico, na ordem declarada; ids desconhecidos são ignorados.
    public func references(for topic: String) -> [ScientificReference] {
        guard let ids = topics[topic] else { return [] }
        let byID = Dictionary(references.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    /// Tópico de uma nota de prescrição (`note.increase` etc.).
    public static func topic(for note: PrescriptionNote) -> String { "note.\(note.rawValue)" }
}
