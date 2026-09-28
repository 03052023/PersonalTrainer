import Foundation

/// Seta do caminho da ida (SPEC E9): acompanha `track` (ponto do esqueleto ou id de acessório) do primeiro ao
/// último quadro, recortada em `span` (frações do comprimento) e afastada do corpo por `offset` e/ou por `gap` para
/// o lado `side` de quem anda pelo caminho. O cálculo está em `GuideMotion.cuePath`.
public struct GuideCue: Codable, Sendable, Hashable {
    public enum Side: String, Codable, Sendable, Hashable, CaseIterable {
        case left
        case right
    }

    public let track: String
    /// `[a, b]` com 0 ≤ a < b ≤ 1; sem ele, o caminho inteiro.
    public let span: [Double]?
    public let offset: GuidePoint?
    public let side: Side?
    public let gap: Double?

    public init(track: String, span: [Double]? = nil, offset: GuidePoint? = nil, side: Side? = nil, gap: Double? = nil) {
        self.track = track
        self.span = span
        self.offset = offset
        self.side = side
        self.gap = gap
    }
}
