import SwiftUI
import TrainerCore

/// Aparência de cada objetivo dentro do app (DESIGN.md §4): a mesma flor do ícone dá identidade
/// visual às cinco metas, cada uma com cor, símbolo, subtítulo humano e posição de pétala.
extension ProgramGoal {
    /// Cor do objetivo (DESIGN §3), usada por `FlowerView` e por qualquer cartão que precise
    /// identificar o objetivo sem repetir "a cor nunca identifica sozinha" (nome + símbolo + pétala
    /// sempre acompanham).
    var color: Color {
        switch self {
        case .hypertrophy: return Theme.goalHypertrophy
        case .strength: return Theme.goalStrength
        case .endurance: return Theme.goalEndurance
        case .longevity: return Theme.goalLongevity
        case .combat: return Theme.goalCombat
        }
    }

    /// SF Symbol do objetivo (DESIGN §4). Incerto sem simulador: confirmar que os cinco existem no
    /// catálogo do SF Symbols do iOS 18 / watchOS 11.
    var symbolName: String {
        switch self {
        case .longevity: return "tree"
        case .hypertrophy: return "leaf"
        case .strength: return "mountain.2"
        case .combat: return "shield"
        case .endurance: return "repeat"
        }
    }

    /// Frase curta e humana, sem jargão de academia (DESIGN §4/§6), igual à tabela de pétalas.
    var subtitle: String {
        switch self {
        case .longevity: return "Viver bem por mais tempo"
        case .hypertrophy: return "Ganhar massa muscular"
        case .strength: return "Ficar mais forte"
        case .combat: return "Saber se defender"
        case .endurance: return "Aguentar mais"
        }
    }

    /// Posição na flor de 5 pétalas (DESIGN §4), no sentido horário a partir do topo (índice 0).
    /// `FlowerView` gira cada pétala em `72° × petalIndex`.
    var petalIndex: Int {
        switch self {
        case .longevity: return 0
        case .hypertrophy: return 1
        case .strength: return 2
        case .combat: return 3
        case .endurance: return 4
        }
    }
}
