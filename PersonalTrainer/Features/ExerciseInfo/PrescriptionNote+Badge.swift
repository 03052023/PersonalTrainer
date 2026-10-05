import Foundation
import TrainerCore

/// Selo leigo da nota da prescrição (DESIGN §7; docs/V22-CONTRACT.md §2.3), o mesmo na tela Hoje, na
/// ficha da sessão, na folha "Informações do exercício" e no Histórico. Só aparece quando há
/// novidade: `hold` ("manter") não tem selo. O selo abre o "Por quê?" da nota (DESIGN §9.5).
extension PrescriptionNote {
    /// Selo da nota `increase` num aeróbico sem nível (SPEC §7.14 F6, RF-47; 2.4): nos intervalos, subir é
    /// ganhar mais um bloco, não carga.
    static let moreBlocksBadgeText = "Mais um bloco"
    /// Selo da nota `increase` num aeróbico com nível de máquina registrado (SPEC §7.14 F3): sobe o nível.
    static let higherLevelBadgeText = "Nível maior"

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

    /// O selo que leva em conta o aeróbico (SPEC §7.14 F3 e F6; 2.4). Só muda a nota `increase` num
    /// aeróbico: sem nível nem carga (L = 0), "Mais um bloco"; com um nível registrado (L > 0), "Nível maior";
    /// com uma carga em kg ou placas (raro no aeróbico), "Carga maior", como sempre. Nos outros exercícios e
    /// nas outras notas, o mesmo `badgeText` de sempre.
    func badgeText(isCardio: Bool, hasLevel: Bool, loadUnit: LoadUnit = .level) -> String? {
        guard self == .increase, isCardio else {
            return badgeText
        }
        guard hasLevel else {
            return Self.moreBlocksBadgeText
        }
        return loadUnit == .level ? Self.higherLevelBadgeText : badgeText
    }
}
