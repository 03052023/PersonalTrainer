import Foundation
import TrainerCore

extension LoadUnit {
    /// Nome pt-BR da unidade de carga para o editor de exercício (SPEC §7.1: kg, placas, nível).
    var displayName: String {
        switch self {
        case .kilograms: return "Quilos (kg)"
        case .plates: return "Placas"
        case .level: return "Nível da máquina"
        }
    }

    /// Ordem do Picker do editor. `LoadUnit` não é `CaseIterable` em `TrainerCore`; o teste do
    /// catálogo confere que a lista cobre todos os casos.
    static let pickerOrder: [LoadUnit] = [.kilograms, .plates, .level]
}
