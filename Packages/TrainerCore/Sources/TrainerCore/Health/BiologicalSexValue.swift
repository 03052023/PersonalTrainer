import Foundation

/// Sexo biológico lido do HealthKit (opcional). Usado só para escolher a tabela normativa de
/// VO2max (SPEC §7.10 A3); `other` não tem tabela e deixa a faixa em branco.
public enum BiologicalSexValue: String, Codable, Sendable, Hashable, CaseIterable {
    case female
    case male
    case other
}
