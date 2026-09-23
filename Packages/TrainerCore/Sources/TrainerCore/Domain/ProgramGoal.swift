import Foundation

/// Objetivo do programa (SPEC §7.9). Define os padrões de faixa de repetições, RIR, volume semanal
/// e descanso usados pelo seed, pela edição de programa e pela revisão periódica.
/// Raw values são persistidos (`ProgramModel.goalRaw`): nunca renomear um case.
public enum ProgramGoal: String, Codable, Sendable, Hashable, CaseIterable {
    case hypertrophy
    case strength
    case endurance
    case longevity
    case combat

    /// Nome curto em pt-BR para a UI.
    public var displayName: String {
        switch self {
        case .hypertrophy: return "Hipertrofia"
        case .strength: return "Força"
        case .endurance: return "Resistência muscular"
        case .longevity: return "Longevidade"
        case .combat: return "Combate"
        }
    }

    /// Chave de tópico no catálogo de referências (`ReferenceCatalog.topics`).
    public var referenceTopic: String { "goal.\(rawValue)" }
}
