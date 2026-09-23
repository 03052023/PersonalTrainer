import Foundation
import TrainerCore

extension MuscleGroup {
    /// Nome pt-BR para a UI, na mesma grafia da lista de grupos da SPEC §7.4. Fica no app (e não
    /// em `TrainerCore`) porque é texto de tela; o motor só conhece o `rawValue`.
    var displayName: String {
        switch self {
        case .chest: return "Peito"
        case .back: return "Costas"
        case .shoulders: return "Ombros"
        case .biceps: return "Bíceps"
        case .triceps: return "Tríceps"
        case .quads: return "Quadríceps"
        case .hamstrings: return "Posteriores"
        case .glutes: return "Glúteos"
        case .calves: return "Panturrilhas"
        case .core: return "Core"
        }
    }
}
