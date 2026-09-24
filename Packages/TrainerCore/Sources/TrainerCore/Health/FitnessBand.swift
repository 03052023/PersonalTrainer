import Foundation

/// Faixa de aptidão cardiorrespiratória por idade e sexo (SPEC §7.10 A3), do pior ao melhor.
/// Os limites de cada faixa estão em `Vo2MaxNorms`. Raw values estáveis.
public enum FitnessBand: String, Codable, Sendable, Hashable, CaseIterable {
    case veryPoor
    case poor
    case fair
    case good
    case excellent
    case superior

    /// Nome curto em pt-BR para a UI.
    public var displayName: String {
        switch self {
        case .veryPoor: return "Muito baixo"
        case .poor: return "Baixo"
        case .fair: return "Regular"
        case .good: return "Bom"
        case .excellent: return "Excelente"
        case .superior: return "Superior"
        }
    }
}
