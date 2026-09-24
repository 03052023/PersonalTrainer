import Foundation

/// Uma sugestão determinística do painel de saúde (SPEC §7.10 A6): texto fixo em pt-BR com o motivo
/// e os números que a geraram. Nunca é gerada por IA (ADR 012).
public struct HealthSuggestion: Codable, Sendable, Hashable, Identifiable {
    /// Identificador estável por tipo, ex.: "wear-watch-at-night". Serve para "ok, entendi" na UI.
    public let id: String
    public let kind: HealthSuggestionKind
    public let title: String
    public let detail: String
    /// Tópico do catálogo de referências para o botão "Por quê?", ex.: "topic.hrv".
    public let referenceTopic: String

    public init(id: String, kind: HealthSuggestionKind, title: String, detail: String, referenceTopic: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.referenceTopic = referenceTopic
    }
}
