import Foundation

/// Intensidade de um aeróbico no plano (SPEC §7.14 F2 e §7.15 M3; docs/V23-UI-CONTRACT.md §3.1), sentida
/// pelo teste da fala e nunca pela frequência cardíaca (§7.6, P12): leve = a conversa é fácil;
/// moderado = dá para conversar, mas não para cantar; forte = só saem poucas palavras.
///
/// Serve ao encaixe da semana (cardio forte nunca na véspera de pernas, A5) e aos textos da ficha. Não
/// entra no motor de progressão.
public enum CardioIntensity: String, Codable, Sendable, Hashable, CaseIterable {
    case light
    case moderate
    case vigorous

    /// Aeróbicos do catálogo que já são esforço forte pelo próprio formato (seed 4).
    public static let vigorousSlugs: Set<String> = ["run-intervals", "bike-intervals", "jump-rope"]

    /// A partir deste teto de faixa (minutos), uma sessão contínua é a longa e leve do plano.
    public static let lightMinimumMinutes: Int = 60

    /// Regra fixa (SPEC §7.15 M3): intervalos (mais de uma série) ou um aeróbico forte pelo nome → forte;
    /// senão, faixa que chega a 60 min ou mais → leve; senão, moderado.
    public static func classify(slug: String, sets: Int, repMax: Int) -> CardioIntensity {
        if sets >= 2 || vigorousSlugs.contains(slug) {
            return .vigorous
        }
        if repMax >= lightMinimumMinutes {
            return .light
        }
        return .moderate
    }

    /// Ordem de força: leve < moderado < forte. Um dia com mais de um aeróbico vale pelo mais forte.
    public var rank: Int {
        switch self {
        case .light: return 0
        case .moderate: return 1
        case .vigorous: return 2
        }
    }
}
