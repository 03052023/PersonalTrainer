import Foundation

/// Acessório que se move com o corpo (docs/V23-CORE-CONTRACT.md §2.5): barra, halter, puxador… preso a um ponto do
/// esqueleto (`attach` + `offset` no mundo), às costas ou ao peito (`back`, `chest`: referencial do tronco), ou ao
/// longo de um segmento (`attach` = segmento, com `along` de 0 a 1 e `side`). `cable` e `band` são linhas de um
/// item da cena (`from`) até um acessório ou ponto do esqueleto (`to`) e não têm `attach`.
public struct GuideProp: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        case barbell
        case dumbbell
        case kettlebell
        case ball
        case vHandle
        case bar
        case rope
        /// `{length, angle}`: placa girada (plataforma do leg press, pedal, banco móvel do remo).
        case plate
        /// `{radius = 0.035}`: rolo acolchoado.
        case roller
        case jumpRope
        case cable
        case band

        /// Cabo e elástico são linhas, sem posição própria.
        public var isLine: Bool {
            self == .cable || self == .band
        }
    }

    public static let backAttach = "back"
    public static let chestAttach = "chest"

    public let id: String
    public let kind: Kind
    public let attach: String?
    public let offset: GuidePoint?
    public let along: Double?
    public let side: Double?
    public let length: Double?
    public let angle: Double?
    public let radius: Double?
    public let from: String?
    public let to: String?

    public init(
        id: String,
        kind: Kind,
        attach: String? = nil,
        offset: GuidePoint? = nil,
        along: Double? = nil,
        side: Double? = nil,
        length: Double? = nil,
        angle: Double? = nil,
        radius: Double? = nil,
        from: String? = nil,
        to: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.attach = attach
        self.offset = offset
        self.along = along
        self.side = side
        self.length = length
        self.angle = angle
        self.radius = radius
        self.from = from
        self.to = to
    }
}
