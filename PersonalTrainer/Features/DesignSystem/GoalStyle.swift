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
        // SPEC RF-48 (2.3): o Cardio é cardiovascular; "wind" (vento, respiração) existe desde o iOS 13.
        case .endurance: return "wind"
        }
    }

    /// Frase curta e humana, sem jargão de academia (DESIGN §4/§6), igual à tabela de pétalas.
    var subtitle: String {
        switch self {
        case .longevity: return "Viver bem por mais tempo"
        case .hypertrophy: return "Ganhar massa muscular"
        case .strength: return "Ficar mais forte"
        // SPEC decisão 18 (2026-09-27): troca "Saber se defender", que prometia técnica de defesa
        // que o app não ensina (SPEC §7.9).
        case .combat: return "Potência e resistência"
        // SPEC RF-48 (2.3, D2): o objetivo `endurance` virou Cardio, cardiovascular; subtítulo do
        // dono (docs/design/v23-owner-notes.md item 1).
        case .endurance: return "Coração forte e mais condicionamento"
        }
    }

    /// Posição na flor de 5 pétalas (DESIGN §4), no sentido horário a partir do topo (índice 0).
    /// `FlowerView` usa este índice para escolher a pétala Brisa certa (`PetalShape(petalIndex:)`),
    /// que já nasce na posição e no giro certos — nada de rotacionar por fora.
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
