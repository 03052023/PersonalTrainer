import Foundation

/// Sinal de uma consequência de combinar dois planos (SPEC §7.15 M7): + positiva, − negativa, = neutra.
public enum PlanConsequenceKind: String, Codable, Sendable, Hashable, CaseIterable {
    case positive
    case negative
    case neutral
}
