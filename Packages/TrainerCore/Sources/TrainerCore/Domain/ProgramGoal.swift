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
        // SPEC RF-48 (versão 2.3, D2): o objetivo virou cardiovascular; o nome "Cardio" é decisão do
        // dono (docs/design/v23-owner-notes.md item 1). O raw value continua `endurance`, porque é
        // persistido (`ProgramModel.goalRaw`).
        case .endurance: return "Cardio"
        case .longevity: return "Longevidade"
        case .combat: return "Combate"
        }
    }

    /// Chave de tópico no catálogo de referências (`ReferenceCatalog.topics`).
    public var referenceTopic: String { "goal.\(rawValue)" }
}
