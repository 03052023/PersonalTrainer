import Foundation
import TrainerCore

/// A meta de hoje em palavras (SPEC RF-44, RF-46; DESIGN §9 e §13; docs/V22-CONTRACT.md §2.3): a
/// mesma frase na linha da tela Hoje ("3 séries de 3 · 62,5 kg"), na letra grande da ficha da
/// sessão ("3 repetições · 62,5 kg") e na folha "Informações do exercício".
///
/// Mostra a meta (`targetReps`), nunca a faixa: é a meta que um toque grava. Nunca mostra RIR
/// (SPEC RF-41, decisão 18). Peso do corpo sem carga extra não mostra carga nenhuma (RF-46).
///
/// Só formatação pura, sem estado: não depende de outras pastas de `Features/` para que Home, Sessão
/// e Histórico possam usá-la em paralelo.
enum TodayTargetText {
    /// Como a carga aparece (SPEC RF-46).
    enum LoadDisplay: Sendable, Hashable {
        /// Peso do corpo sem carga extra: nada de "0 kg" nem "—".
        case hidden
        /// Sem carga prescrita (SPEC P2, D3) num exercício com equipamento: "sem carga", que a pessoa
        /// pode mudar pondo uma carga.
        case toChoose
        /// Carga normal: "62,5 kg", "4 placas", "nível 7".
        case load(String)
        /// Peso do corpo com carga adicional (P4/H4 no topo da faixa): "+ 2,5 kg extra".
        case extra(String)
    }

    /// Texto de `LoadDisplay.toChoose`. Desde a 2.4 (SPEC RF-46, achado B11 da 2.3), a tela Hoje diz
    /// "sem carga", como a ficha da sessão e a folha de informações (antes, "escolha a carga").
    static let toChooseText = "sem carga"

    /// Meta de hoje: `targetReps` quando conhecida (> 0); senão `repMin`, como nas sessões gravadas
    /// antes do campo existir (SPEC P5).
    static func goal(targetReps: Int, repMin: Int) -> Int {
        targetReps > 0 ? targetReps : repMin
    }

    /// SPEC RF-46: peso do corpo (`equipment == .bodyweight`) com carga 0 ou vazia fica sem carga; com
    /// carga maior que 0 vira "+ N extra". Nos outros equipamentos, carga vazia é a primeira vez
    /// (P2). `equipment` `nil` (exercício que sumiu do catálogo) é tratado como exercício com carga.
    /// Desde a 2.3 (D3), carga 0 num exercício com equipamento é "sem carga externa": nada de "0 kg"
    /// nem "nível 0" (RF-46), como no peso do corpo. A ficha da sessão e a folha de informações dizem
    /// "sem carga" com o próprio mapeamento, antes de chegar aqui.
    static func loadDisplay(load: Double?, unit: LoadUnit, equipment: Equipment?) -> LoadDisplay {
        if equipment == .bodyweight {
            guard let load, load > 0 else {
                return .hidden
            }
            return .extra("+ \(loadText(load, unit: unit)) extra")
        }
        guard let load else {
            return .toChoose
        }
        guard load > 0 else {
            return .hidden
        }
        return .load(loadText(load, unit: unit))
    }

    /// "62,5 kg", "60 kg", "1 placa", "4 placas", "nível 7".
    static func loadText(_ load: Double, unit: LoadUnit) -> String {
        switch unit {
        case .kilograms:
            return "\(decimal(load)) kg"
        case .plates:
            let count = Int(load.rounded())
            return count == 1 ? "1 placa" : "\(count) placas"
        case .level:
            return "nível \(Int(load.rounded()))"
        }
    }

    /// Texto curto da carga para juntar depois de " · "; `nil` quando não há carga a mostrar.
    static func loadLabel(_ display: LoadDisplay) -> String? {
        switch display {
        case .hidden:
            return nil
        case .toChoose:
            return toChooseText
        case .load(let text):
            return text
        case .extra(let text):
            return text
        }
    }

    /// Número com a unidade por extenso, para a letra grande da ficha: "3 repetições",
    /// "1 repetição", "15 segundos", "30 passos", "30 minutos".
    static func amount(_ value: Int, measure: ExerciseMeasure) -> String {
        switch measure {
        case .reps:
            return value == 1 ? "1 repetição" : "\(value) repetições"
        case .seconds:
            return value == 1 ? "1 segundo" : "\(value) segundos"
        case .steps:
            return value == 1 ? "1 passo" : "\(value) passos"
        case .minutes:
            return value == 1 ? "1 minuto" : "\(value) minutos"
        }
    }

    /// Número curto, para a linha da tela Hoje: "3", "15 s", "30 passos", "1 passo", "30 min".
    static func compactAmount(_ value: Int, measure: ExerciseMeasure) -> String {
        switch measure {
        case .reps:
            return "\(value)"
        case .seconds:
            return "\(value) s"
        case .steps:
            return value == 1 ? "1 passo" : "\(value) passos"
        case .minutes:
            return "\(value) min"
        }
    }

    /// "1 série", "3 séries".
    static func setsText(_ sets: Int) -> String {
        sets == 1 ? "1 série" : "\(sets) séries"
    }

    /// Linha da tela Hoje: "3 séries de 3 · 62,5 kg", "3 séries de 5", "2 séries de 15 s",
    /// "3 séries de 30 passos · 22,5 kg", "4 séries de 6 · sem carga",
    /// "3 séries de 5 · + 2,5 kg extra". Em minutos (aeróbico, SPEC §7.14 F1): "30 min" ou
    /// "4 × 3 min", nunca "1 série de 30 min"; o nível da máquina só aparece quando existe.
    static func row(sets: Int, goal: Int, measure: ExerciseMeasure, load: LoadDisplay) -> String {
        if measure == .minutes {
            return joined(CardioText.amount(sets: sets, minutes: goal), cardioLabel(load), separator: " · ")
        }
        let base = "\(setsText(sets)) de \(compactAmount(goal, measure: measure))"
        guard let label = loadLabel(load) else {
            return base
        }
        return "\(base) · \(label)"
    }

    /// Letra grande da ficha: "3 repetições · 62,5 kg", "5 repetições", "15 segundos",
    /// "30 passos · 22,5 kg", "6 repetições · sem carga", "5 repetições · + 2,5 kg extra".
    /// Em minutos, "30 min" ou, com `sets` maior que 1, "4 × 3 min" (SPEC §7.14 F1).
    static func headline(goal: Int, measure: ExerciseMeasure, load: LoadDisplay, sets: Int = 1) -> String {
        if measure == .minutes {
            return joined(CardioText.amount(sets: sets, minutes: goal), cardioLabel(load), separator: " · ")
        }
        let base = amount(goal, measure: measure)
        guard let label = loadLabel(load) else {
            return base
        }
        return "\(base) · \(label)"
    }

    /// Leitura do VoiceOver da linha: "3 séries de 3 repetições, 62,5 kg" (sem "·"; "+" vira "mais").
    /// Em minutos, "30 minutos" ou "4 vezes 3 minutos".
    static func spokenRow(sets: Int, goal: Int, measure: ExerciseMeasure, load: LoadDisplay) -> String {
        if measure == .minutes {
            return joined(CardioText.spokenAmount(sets: sets, minutes: goal), cardioLabel(load).map { spoken($0) }, separator: ", ")
        }
        let base = "\(setsText(sets)) de \(amount(goal, measure: measure))"
        guard let label = loadLabel(load) else {
            return base
        }
        return "\(base), \(spoken(label))"
    }

    /// Leitura do VoiceOver da letra grande: "3 repetições, 62,5 kg"; em minutos, "30 minutos".
    static func spokenHeadline(goal: Int, measure: ExerciseMeasure, load: LoadDisplay, sets: Int = 1) -> String {
        if measure == .minutes {
            return joined(CardioText.spokenAmount(sets: sets, minutes: goal), cardioLabel(load).map { spoken($0) }, separator: ", ")
        }
        let base = amount(goal, measure: measure)
        guard let label = loadLabel(load) else {
            return base
        }
        return "\(base), \(spoken(label))"
    }

    /// Descanso curto: "4 min", "2 min 30 s", "45 s"; 0 ou menos, "sem descanso".
    static func rest(seconds: Int) -> String {
        guard seconds > 0 else {
            return "sem descanso"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes == 0 {
            return "\(remainder) s"
        }
        if remainder == 0 {
            return "\(minutes) min"
        }
        return "\(minutes) min \(remainder) s"
    }

    /// Linha pequena da ficha: "3 séries · descanso 4 min" ou "3 séries · sem descanso".
    static func detail(sets: Int, restSeconds: Int) -> String {
        guard restSeconds > 0 else {
            return "\(setsText(sets)) · sem descanso"
        }
        return "\(setsText(sets)) · descanso \(rest(seconds: restSeconds))"
    }

    // MARK: - Privado

    /// No aeróbico, o nível da máquina (ou uma carga registrada) é opcional (SPEC §7.14 F3): só aparece
    /// quando existe. "sem carga" não vale para quem só caminha ou pedala.
    private static func cardioLabel(_ display: LoadDisplay) -> String? {
        switch display {
        case .hidden, .toChoose:
            return nil
        case .load(let text), .extra(let text):
            return text
        }
    }

    private static func joined(_ base: String, _ label: String?, separator: String) -> String {
        guard let label else {
            return base
        }
        return "\(base)\(separator)\(label)"
    }

    /// Número pt-BR sem casas desnecessárias: 62.5 → "62,5", 60 → "60".
    private static func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// "+ 2,5 kg extra" é lido "mais 2,5 kg extra".
    private static func spoken(_ label: String) -> String {
        guard label.hasPrefix("+ ") else {
            return label
        }
        return "mais " + String(label.dropFirst(2))
    }
}
