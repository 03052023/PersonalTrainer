import Foundation
import TrainerCore

/// Textos pt-BR do aeróbico (SPEC §7.14 F1 e F2, RF-43; DESIGN §13; docs/V23-UI-CONTRACT.md §4.4 item 3): a
/// meta em minutos ("30 min", "4 × 3 min"), a intensidade pelo teste da fala no lugar da carga, a recuperação
/// andando dos intervalos e a linha fixa de aquecimento. Compartilhado pela ficha da sessão, pela folha
/// "Informações do exercício" e pela linha da tela Hoje (`TodayTargetText.row` com `.minutes`).
///
/// Nada de frequência cardíaca, zonas nem ritmo em números (SPEC §7.6, P12): a intensidade é sentida pela fala.
/// Funções puras, sem estado.
enum CardioText {
    /// Nome curto da intensidade: "Leve", "Moderado", "Forte".
    static func intensityName(_ intensity: CardioIntensity) -> String {
        switch intensity {
        case .light: return "Leve"
        case .moderate: return "Moderado"
        case .vigorous: return "Forte"
        }
    }

    /// O teste da fala em minúsculas, para o meio da frase (SPEC F2).
    static func talkTest(_ intensity: CardioIntensity) -> String {
        switch intensity {
        case .light: return "a conversa é fácil"
        case .moderate: return "dá para conversar, mas não para cantar"
        case .vigorous: return "só dá para dizer poucas palavras"
        }
    }

    /// A frase que ocupa o lugar da carga na ficha: "Moderado: dá para conversar, mas não para cantar".
    static func intensityLine(_ intensity: CardioIntensity) -> String {
        "\(intensityName(intensity)): \(talkTest(intensity))"
    }

    /// A meta do aeróbico: uma série, "30 min"; mais de uma (intervalos), "4 × 3 min". Nunca "1 série de 30 min"
    /// (SPEC F1).
    static func amount(sets: Int, minutes: Int) -> String {
        guard sets > 1 else {
            return "\(minutes) min"
        }
        return "\(sets) × \(minutes) min"
    }

    /// Leitura do VoiceOver da meta: "30 minutos", "1 minuto", "4 vezes 3 minutos".
    static func spokenAmount(sets: Int, minutes: Int) -> String {
        let perSet = MeasureText.spokenAmount(minutes, measure: .minutes)
        guard sets > 1 else {
            return perSet
        }
        return "\(sets) vezes \(perSet)"
    }

    /// Nome do descanso entre os blocos dos intervalos (SPEC F1): no aeróbico, o descanso é andar devagar.
    static let recoveryTitle = "Recuperação andando"

    /// Linha fixa dos intervalos (SPEC F2, Dia B): o aquecimento não se marca.
    static let intervalsWarmup = "Antes, aqueça 10 minutos andando devagar."

    /// Até quantos blocos os intervalos crescem (SPEC §7.14 F6; o mesmo número de
    /// `DoubleProgressionRule.maxIntervalBlocks` no motor).
    static let maxIntervalBlocks = 5

    /// Como os intervalos progridem, para a seção "Hoje" das informações (SPEC RF-47, §7.14 F3 e F6; achado
    /// B10 da 2.3: o nome "Intervalos 4 × 4" fica e a folha explica). Sem nível nem carga: "Cada bloco sobe
    /// 1 min por sessão até 4 min. No topo, entra mais um bloco, até 5." Com um nível registrado vale F3, sem
    /// blocos novos: "… No topo, sobe 1 nível e os minutos recomeçam."; com uma carga em kg (raro), "… No
    /// topo, a carga sobe e os minutos recomeçam."
    static func intervalsProgression(repMax: Int, hasLevel: Bool, loadUnit: LoadUnit = .level) -> String {
        let climb = "Cada bloco sobe 1 min por sessão até \(repMax) min."
        guard hasLevel else {
            return "\(climb) No topo, entra mais um bloco, até \(maxIntervalBlocks)."
        }
        if loadUnit == .level {
            return "\(climb) No topo, sobe 1 nível e os minutos recomeçam."
        }
        return "\(climb) No topo, a carga sobe e os minutos recomeçam."
    }

    /// Linha pequena do cartão: nos intervalos, "4 séries · recuperação andando 3 min"; numa série só, `nil`
    /// (não há descanso a mostrar).
    static func detail(sets: Int, restSeconds: Int) -> String? {
        guard sets > 1 else {
            return nil
        }
        let setsText = TodayTargetText.setsText(sets)
        guard restSeconds > 0 else {
            return setsText
        }
        return "\(setsText) · recuperação andando \(TodayTargetText.rest(seconds: restSeconds))"
    }

    /// A intensidade de um aeróbico (SPEC §7.15 M3, `CardioIntensity.classify`): `nil` fora do padrão `cardio`.
    static func intensity(pattern: MovementPattern?, slug: String?, sets: Int, repMax: Int) -> CardioIntensity? {
        guard pattern == .cardio else {
            return nil
        }
        return CardioIntensity.classify(slug: slug ?? "", sets: sets, repMax: repMax)
    }
}
