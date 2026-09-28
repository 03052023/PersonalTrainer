import Foundation

/// Escorço de um membro no plano do desenho, de 0,3 a 1 (1 = paralelo ao plano). Nos braços (`armDepth`,
/// `arms.depth`) é `[braço, antebraço+mão]`; nas pernas (`legDepth`), `[coxa, perna]`. No JSON é um número
/// (os dois iguais) ou a lista de dois números.
public struct GuideDepth: Codable, Sendable, Hashable {
    /// Braço ou coxa.
    public let upper: Double
    /// Antebraço e mão, ou perna.
    public let lower: Double

    /// Sem escorço.
    public static let full = GuideDepth(upper: 1, lower: 1)

    public init(upper: Double, lower: Double) {
        self.upper = upper
        self.lower = lower
    }

    public init(_ both: Double) {
        self.upper = both
        self.lower = both
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let both = try? container.decode(Double.self) {
            self.upper = both
            self.lower = both
            return
        }
        let pair = try container.decode([Double].self)
        guard pair.count == 2 else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "escorço é um número ou [a, b]")
        }
        self.upper = pair[0]
        self.lower = pair[1]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        if upper == lower {
            try container.encode(upper)
        } else {
            try container.encode([upper, lower])
        }
    }
}
