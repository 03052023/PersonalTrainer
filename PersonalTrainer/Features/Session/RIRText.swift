import Foundation

/// Textos pt-BR do RIR (SPEC RF-41; DESIGN §7: "RIR: repetições em reserva"). Compartilhado pelo
/// seletor da série, pelo cartão da primeira sessão, pela folha "O que é RIR?" e pela leitura
/// acessível da prescrição na Sessão, na Home e no Histórico.
enum RIRText {
    /// A escala do RF-41 (a), na ordem, para o cartão e a folha de explicação.
    static let scale: [String] = [
        "0 · nenhuma a mais",
        "1 · mais uma",
        "2 · mais duas",
        "3+ · com folga",
    ]

    /// Significado do valor escolhido no seletor (SPEC RF-41 a). O seletor vai de 0 a 5 (RF-03;
    /// P4 compara o RIR com T + 2), então 3, 4 e 5 caem em "com folga", cada um com o próprio
    /// número. `nil` é a série sem RIR informado.
    static func meaning(for rir: Int?) -> String {
        guard let rir else {
            return "Não informado"
        }
        switch rir {
        case ...0: return "0 · nenhuma a mais"
        case 1: return "1 · mais uma"
        case 2: return "2 · mais duas"
        default: return "\(rir) · com folga"
        }
    }

    /// Leitura por voz de um segmento do seletor: "RIR 2, mais duas repetições".
    static func spokenOption(_ rir: Int?) -> String {
        guard let rir else {
            return "RIR não informado"
        }
        switch rir {
        case ...0: return "RIR 0, nenhuma repetição a mais"
        case 1: return "RIR 1, mais uma repetição"
        case 2: return "RIR 2, mais duas repetições"
        default: return "RIR \(rir), com folga"
        }
    }

    /// Leitura acessível do alvo "RIR 2" da prescrição (SPEC RF-41 d): "parar com 2 repetições
    /// de reserva".
    static func spokenTarget(_ rir: Int) -> String {
        switch rir {
        case ...0: return "parar sem repetições de reserva"
        case 1: return "parar com 1 repetição de reserva"
        default: return "parar com \(rir) repetições de reserva"
        }
    }

    /// Leitura por voz do RIR registrado numa série: "RIR 2" continua curto; ausente, "sem RIR".
    static func spokenLogged(_ rir: Int?) -> String {
        guard let rir else {
            return "sem RIR"
        }
        return "RIR \(rir)"
    }
}
