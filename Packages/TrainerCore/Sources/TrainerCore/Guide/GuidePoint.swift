import Foundation

/// Ponto 2D do "Como fazer" em estaturas (H = 1): x cresce para a frente (à direita no desenho), y para cima, e o
/// chão fica em y = 0 (docs/V23-CORE-CONTRACT.md §2.5). No JSON é a lista `[x, y]`.
public struct GuidePoint: Codable, Sendable, Hashable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Double.self)
        let y = try container.decode(Double.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "um ponto é a lista [x, y]")
        }
        self.x = x
        self.y = y
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}
