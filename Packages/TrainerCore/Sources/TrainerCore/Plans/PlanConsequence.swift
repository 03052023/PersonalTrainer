import Foundation

/// Uma frase curta sobre o que muda ao combinar dois planos (SPEC §7.15 M7), com o tópico do "Por quê?".
public struct PlanConsequence: Sendable, Hashable {
    public let kind: PlanConsequenceKind
    /// pt-BR, até 90 caracteres, sem jargão de academia.
    public let text: String
    /// Chave de `ReferenceCatalog.topics` (ex.: "topic.concurrent").
    public let referenceTopic: String

    public init(kind: PlanConsequenceKind, text: String, referenceTopic: String) {
        self.kind = kind
        self.text = text
        self.referenceTopic = referenceTopic
    }
}
