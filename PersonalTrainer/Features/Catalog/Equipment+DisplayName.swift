import Foundation
import TrainerCore

extension Equipment {
    /// Nome pt-BR para a UI (catálogo, seletor e editor de exercício).
    var displayName: String {
        switch self {
        case .barbell: return "Barra"
        case .dumbbell: return "Halteres"
        case .machine: return "Máquina"
        case .cable: return "Polia"
        case .bodyweight: return "Peso corporal"
        case .smith: return "Smith"
        case .kettlebell: return "Kettlebell"
        case .household: return "Objetos de casa"
        }
    }

    /// Ordem do Picker do editor. `Equipment` não é `CaseIterable` em `TrainerCore` e a conformidade
    /// retroativa geraria aviso; o teste do catálogo confere que a lista cobre todos os casos. Precisa
    /// de todos: um exercício do seed com "Objetos de casa" aberto no editor deixaria o Picker sem
    /// opção selecionada.
    static let pickerOrder: [Equipment] = [
        .machine, .cable, .barbell, .dumbbell, .smith, .kettlebell, .bodyweight, .household,
    ]
}
