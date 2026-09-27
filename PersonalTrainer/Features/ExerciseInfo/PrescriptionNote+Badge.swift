import Foundation
import TrainerCore

/// Selo leigo da nota da prescrição (DESIGN §7; docs/V22-CONTRACT.md §2.3), o mesmo na tela Hoje, na
/// ficha da sessão, na folha "Informações do exercício" e no Histórico. Só aparece quando há
/// novidade: `hold` ("manter") não tem selo. O selo abre o "Por quê?" da nota (DESIGN §9.5).
extension PrescriptionNote {
    /// `nil` = sem selo.
    var badgeText: String? {
        switch self {
        case .calibrate: return "Primeira vez"
        case .increase: return "Carga maior"
        case .hold: return nil
        case .retry: return "Tentar de novo"
        case .decrease: return "Carga menor"
        case .returning: return "Retorno"
        case .deload: return "Semana leve"
        }
    }
}
