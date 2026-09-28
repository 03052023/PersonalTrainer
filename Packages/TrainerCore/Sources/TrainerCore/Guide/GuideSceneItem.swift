import Foundation

/// Estrutura fixa do desenho (banco, torre, caixa, barra fixa…; docs/V23-CORE-CONTRACT.md §2.5). Cada tipo usa
/// alguns dos campos opcionais; o validador exige os do tipo. A máquina é genérica, só sugerida.
public struct GuideSceneItem: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        /// `{x, top, length}`: banco com dois pés.
        case bench
        /// `{x, top, length}`: assento com um pé.
        case seat
        /// `{x1, x2}`: trilho no chão.
        case rail
        /// `{x, width, height}`: torre de polia com placas.
        case tower
        /// `{at, length, angle}`: plataforma dos pés.
        case footPlate
        /// `{id, at}`: polia (ponto de partida de um cabo).
        case pulley
        /// `{x, y, width, height}`: retângulo arredondado (caixa, degrau, assento de cadeira).
        case block
        /// `{at, length, angle, thick}`: cápsula girada (encosto, apoio do joelho, guidão).
        case pad
        /// `{from, to, thick}`: barra fina entre dois pontos (armação, tubo, suporte).
        case post
        /// `{at, radius}`: aro (volante do remo, pedivela, barra fixa vista de ponta).
        case wheel
        /// `{x, count, rise, run}`: escada que sobe para a frente a partir de x.
        case steps

        /// Camada padrão quando o item não diz `layer`.
        public var defaultLayer: Layer {
            switch self {
            case .rail, .tower, .footPlate, .post, .steps: return .back
            case .bench, .seat, .pulley, .block, .pad, .wheel: return .mid
            }
        }
    }

    public enum Layer: String, Codable, Sendable, Hashable, CaseIterable {
        case back
        case mid
        case front
    }

    public enum Tone: String, Codable, Sendable, Hashable, CaseIterable {
        case structure
        case soft
    }

    public let kind: Kind
    public let id: String?
    public let layer: Layer?
    public let tone: Tone?
    public let x: Double?
    public let x1: Double?
    public let x2: Double?
    public let y: Double?
    public let top: Double?
    public let at: GuidePoint?
    public let from: GuidePoint?
    public let to: GuidePoint?
    public let length: Double?
    public let width: Double?
    public let height: Double?
    public let angle: Double?
    public let thick: Double?
    public let radius: Double?
    public let count: Int?
    public let rise: Double?
    public let run: Double?

    public init(
        kind: Kind,
        id: String? = nil,
        layer: Layer? = nil,
        tone: Tone? = nil,
        x: Double? = nil,
        x1: Double? = nil,
        x2: Double? = nil,
        y: Double? = nil,
        top: Double? = nil,
        at: GuidePoint? = nil,
        from: GuidePoint? = nil,
        to: GuidePoint? = nil,
        length: Double? = nil,
        width: Double? = nil,
        height: Double? = nil,
        angle: Double? = nil,
        thick: Double? = nil,
        radius: Double? = nil,
        count: Int? = nil,
        rise: Double? = nil,
        run: Double? = nil
    ) {
        self.kind = kind
        self.id = id
        self.layer = layer
        self.tone = tone
        self.x = x
        self.x1 = x1
        self.x2 = x2
        self.y = y
        self.top = top
        self.at = at
        self.from = from
        self.to = to
        self.length = length
        self.width = width
        self.height = height
        self.angle = angle
        self.thick = thick
        self.radius = radius
        self.count = count
        self.rise = rise
        self.run = run
    }

    public var resolvedLayer: Layer {
        layer ?? kind.defaultLayer
    }

    public var resolvedTone: Tone {
        tone ?? .structure
    }

    /// Ponto de onde sai um `cable` ou `band` (`from`): `at` na polia, no aro, no apoio e na plataforma; `to` no
    /// tubo. Os outros itens não têm.
    public var referencePoint: GuidePoint? {
        switch kind {
        case .pulley, .wheel, .pad, .footPlate: return at
        case .post: return to
        case .bench, .seat, .rail, .tower, .block, .steps: return nil
        }
    }
}
