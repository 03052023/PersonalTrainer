import Foundation

/// Ponto do esqueleto que fica parado em todo instante (SPEC E5): `{"joint": "ankle", "at": [0, 0.039]}`. Desde a
/// 2.3 pode ser qualquer ponto da vista, ou `"none"` nos saltos, com a posição do quadril dada em `root` de cada
/// quadro (sem translação).
public struct GuideAnchor: Codable, Sendable, Hashable {
    public static let noneJoint = "none"

    /// Nome de um `GuideJoint` ou `"none"`.
    public let joint: String
    /// Onde o ponto fica, em estaturas. Obrigatório fora de `"none"`.
    public let at: GuidePoint?

    public init(joint: String, at: GuidePoint?) {
        self.joint = joint
        self.at = at
    }

    public var isNone: Bool {
        joint == Self.noneJoint
    }

    /// O ponto âncora, ou `nil` em `"none"` e em nome desconhecido.
    public var point: GuideJoint? {
        GuideJoint(rawValue: joint)
    }
}
