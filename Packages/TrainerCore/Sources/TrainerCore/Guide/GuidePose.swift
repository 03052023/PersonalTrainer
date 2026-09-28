import Foundation

/// Pose de um quadro: ângulo absoluto de cada segmento, em graus (0 = direita, 90 = cima, −90 = baixo, 180 =
/// esquerda). O rosto aponta para `neck − 90°`. No JSON é um objeto `{"trunk": 84, "neck": 88, …}`; chaves
/// desconhecidas são ignoradas aqui e recusadas pelo `-Check` da ferramenta (docs/V23-CORE-CONTRACT.md §2.5).
public struct GuidePose: Codable, Sendable, Hashable {
    /// Chaves de ângulo. `neck` é o ângulo da cabeça (ombro → cabeça). Os "Far" (lado de lá) são opcionais e,
    /// sem eles, repetem o lado de cá.
    public enum Key: String, CaseIterable, Sendable {
        case trunk
        case neck
        case thigh
        case shin
        case foot
        case upperArm
        case forearm
        case thighFar
        case shinFar
        case footFar
        case upperArmFar
        case forearmFar

        /// As 7 chaves do lado de cá.
        public static let nearKeys: [Key] = [.trunk, .neck, .thigh, .shin, .foot, .upperArm, .forearm]

        /// A chave do lado de lá de um membro; `nil` em `trunk`, `neck` e nas que já são do lado de lá.
        public var far: Key? {
            switch self {
            case .thigh: return .thighFar
            case .shin: return .shinFar
            case .foot: return .footFar
            case .upperArm: return .upperArmFar
            case .forearm: return .forearmFar
            default: return nil
            }
        }
    }

    public let angles: [Key: Double]

    public init(angles: [Key: Double]) {
        self.angles = angles
    }

    public subscript(key: Key) -> Double? {
        angles[key]
    }

    /// Conjunto de chaves presentes: todos os quadros de uma guia têm o mesmo (formato, §2.5).
    public var keys: Set<Key> {
        Set(angles.keys)
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        var angles: [Key: Double] = [:]
        for codingKey in container.allKeys {
            guard let key = Key(rawValue: codingKey.stringValue) else { continue }
            angles[key] = try container.decode(Double.self, forKey: codingKey)
        }
        self.angles = angles
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        for key in Key.allCases {
            guard let value = angles[key], let codingKey = AnyKey(stringValue: key.rawValue) else { continue }
            try container.encode(value, forKey: codingKey)
        }
    }
}
