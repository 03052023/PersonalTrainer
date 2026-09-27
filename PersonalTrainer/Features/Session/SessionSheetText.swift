import Foundation
import TrainerCore

/// Textos pt-BR da ficha da sessão (SPEC RF-44, RF-46, RF-12; DESIGN §6, §7 e §13). Funções puras,
/// testáveis sem tela: a dica fixa de aquecimento, a dica de primeira vez, o diálogo de pendentes,
/// a linha compacta do exercício feito, os rótulos do VoiceOver das bolinhas e do "Feito", o
/// "A seguir" do descanso, o campo de carga e os números do resumo.
///
/// Nenhum texto mostra RIR, "com N sobrando" nem "antes do limite" (SPEC RF-41). A única marca
/// indireta do RIR é a dica de primeira vez (RF-44 c), que fala em vezes, não em reserva.
enum SessionSheetText {
    /// Uma série registrada, só com o que a ficha mostra.
    struct LoggedSet: Sendable, Hashable {
        let load: Double
        let reps: Int

        init(load: Double, reps: Int) {
            self.load = load
            self.reps = reps
        }
    }

    // MARK: - Dicas

    /// Linha fixa no topo da ficha (SPEC RF-44 d): a chave Aquecimento saiu.
    static let warmupHint = "Aqueça com 1 ou 2 séries leves antes dos exercícios com carga. Não precisa marcar."

    /// Primeira vez com carga (SPEC RF-44 c, RF-41): "Escolha uma carga que daria para levantar umas
    /// 9 vezes. Hoje faça 6.", com 9 = meta de hoje + RIR alvo do snapshot. Em segundos ou passos, a
    /// frase não usa esse número (uma carga "para 45 segundos" não é intuitiva).
    static func firstTimeHint(goal: Int, targetRIR: Int, measure: ExerciseMeasure) -> String {
        switch measure {
        case .reps:
            let reachable = goal + max(0, targetRIR)
            return "Escolha uma carga que daria para levantar umas \(reachable) vezes. Hoje faça \(goal)."
        case .seconds, .steps:
            let amount = TodayTargetText.amount(goal, measure: measure)
            return "Escolha uma carga com a qual você aguentaria mais do que isso. Hoje faça \(amount)."
        }
    }

    // MARK: - Campo de carga

    /// Maior carga aceita no teclado (kg, placas ou nível). Acima disso é erro de digitação.
    static let maximumLoad: Double = 1_000

    /// Carga válida para gravar: finita, até `maximumLoad` e maior que 0 (em peso do corpo, a carga
    /// extra pode voltar a 0).
    static func isValidLoad(_ value: Double, allowsZero: Bool) -> Bool {
        guard value.isFinite, value <= maximumLoad else {
            return false
        }
        return allowsZero ? value >= 0 : value > 0
    }

    /// Lê o que foi digitado no teclado decimal. Aceita vírgula (teclado pt-BR) ou ponto; vazio ou
    /// inválido devolve `nil`.
    static func parseLoad(_ text: String, allowsZero: Bool) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized) else {
            return nil
        }
        return isValidLoad(value, allowsZero: allowsZero) ? value : nil
    }

    /// Valor inicial do campo, sem unidade: 62.5 → "62,5", 60 → "60".
    static func editableLoadText(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Unidade ao lado do campo.
    static func unitLabel(_ unit: LoadUnit) -> String {
        switch unit {
        case .kilograms: return "kg"
        case .plates: return "placas"
        case .level: return "nível"
        }
    }

    // MARK: - Concluir com pendentes (SPEC RF-44 e)

    /// "Faltam 2 exercícios", "Falta 1 exercício".
    static func pendingTitle(count: Int) -> String {
        count == 1 ? "Falta 1 exercício" : "Faltam \(count) exercícios"
    }

    /// "Caminhada do fazendeiro e Isometria de pescoço ainda não foram marcados."
    static func pendingMessage(names: [String]) -> String {
        let list = namesList(names)
        return names.count == 1 ? "\(list) ainda não foi marcado." : "\(list) ainda não foram marcados."
    }

    /// "A", "A e B", "A, B e C".
    static func namesList(_ names: [String]) -> String {
        guard let last = names.last else {
            return ""
        }
        guard names.count > 1 else {
            return last
        }
        return names.dropLast().joined(separator: ", ") + " e " + last
    }

    // MARK: - Exercício feito (SPEC RF-44 a, RF-46)

    /// Linha compacta do exercício feito, sem o "✓": "5, 5, 4 · 60 kg"; peso do corpo sem carga,
    /// "5, 5, 4"; cargas diferentes, "5 × 60 kg, 4 × 57,5 kg"; segundos, "30, 30 s".
    static func doneSummary(
        _ sets: [LoggedSet],
        unit: LoadUnit,
        equipment: Equipment?,
        measure: ExerciseMeasure
    ) -> String {
        guard let first = sets.first else {
            return ""
        }
        if sets.allSatisfy({ $0.load == first.load }) {
            let amounts = sets.map { String($0.reps) }.joined(separator: ", ") + unitSuffix(measure)
            guard let label = loadLabel(first.load, unit: unit, equipment: equipment) else {
                return amounts
            }
            return "\(amounts) · \(label)"
        }
        return sets.map { (set: LoggedSet) -> String in
            let amount = TodayTargetText.compactAmount(set.reps, measure: measure)
            guard let label = loadLabel(set.load, unit: unit, equipment: equipment) else {
                return amount
            }
            return "\(amount) × \(label)"
        }
        .joined(separator: ", ")
    }

    /// Leitura do VoiceOver da mesma linha: "5, 5 e 4 repetições, 60 kg"; cargas diferentes,
    /// "5 repetições com 60 kg e 4 repetições com 57,5 kg".
    static func spokenDoneSummary(
        _ sets: [LoggedSet],
        unit: LoadUnit,
        equipment: Equipment?,
        measure: ExerciseMeasure
    ) -> String {
        guard let first = sets.first else {
            return ""
        }
        if sets.allSatisfy({ $0.load == first.load }) {
            let amounts: String
            if sets.count == 1 {
                amounts = MeasureText.spokenAmount(first.reps, measure: measure)
            } else {
                amounts = "\(namesList(sets.map { String($0.reps) })) \(MeasureText.pluralNoun(measure))"
            }
            guard let label = loadLabel(first.load, unit: unit, equipment: equipment) else {
                return amounts
            }
            return "\(amounts), \(spokenLoad(label))"
        }
        return namesList(sets.map { (set: LoggedSet) -> String in
            let amount = MeasureText.spokenAmount(set.reps, measure: measure)
            guard let label = loadLabel(set.load, unit: unit, equipment: equipment) else {
                return amount
            }
            return "\(amount) com \(spokenLoad(label))"
        })
    }

    // MARK: - Acessibilidade (SPEC RF-44; contrato V22 §3.1 item 12)

    /// "Série 2 de 3, feita, 5 repetições" ou "Série 3 de 3, marcar como feita".
    static func dotLabel(number: Int, total: Int, reps: Int?, measure: ExerciseMeasure) -> String {
        guard let reps else {
            return "Série \(number) de \(total), marcar como feita"
        }
        return "Série \(number) de \(total), feita, \(MeasureText.spokenAmount(reps, measure: measure))"
    }

    /// Rótulo do "Feito": "Marcar as séries que faltam de Agachamento livre como feitas".
    static func feitoLabel(exerciseName: String) -> String {
        "Marcar as séries que faltam de \(exerciseName) como feitas"
    }

    // MARK: - Descanso (SPEC RF-44 f)

    /// "A seguir: série 3 de Agachamento livre".
    static func nextSet(number: Int, exerciseName: String) -> String {
        "A seguir: série \(number) de \(exerciseName)"
    }

    /// "A seguir: Barra fixa".
    static func nextExercise(_ exerciseName: String) -> String {
        "A seguir: \(exerciseName)"
    }

    /// Descanso depois da última série que faltava.
    static let allMarked = "Tudo marcado. Toque em Concluir."

    // MARK: - Correção de série

    /// Linha sob o título de "Corrigir série": "Agachamento livre · previsto: 3 repetições · 62,5 kg".
    static func plannedLine(exerciseName: String, headline: String) -> String {
        "\(exerciseName) · previsto: \(headline)"
    }

    // MARK: - Resumo (SPEC RF-44 h, RF-12)

    /// "Sessão concluída" ou, abandonada, "Sessão encerrada".
    static func summaryTitle(abandoned: Bool) -> String {
        abandoned ? "Sessão encerrada" : "Sessão concluída"
    }

    /// "5 de 5".
    static func exercisesDone(_ done: Int, of total: Int) -> String {
        "\(done) de \(total)"
    }

    /// "A próxima sessão já está pronta: Dia B — Salto, terra e supino."
    static func nextSession(_ dayName: String) -> String {
        "A próxima sessão já está pronta: \(dayName)."
    }

    /// "1 h 05 min", "54 min" (minutos truncados, como um cronômetro). Sem fim, "—".
    static func duration(_ interval: TimeInterval?) -> String {
        guard let interval, interval.isFinite else {
            return "—"
        }
        let totalMinutes = max(0, Int(interval / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        guard hours > 0 else {
            return "\(minutes) min"
        }
        let paddedMinutes = minutes < 10 ? "0\(minutes)" : "\(minutes)"
        return "\(hours) h \(paddedMinutes) min"
    }

    /// "118 / 164 bpm"; sem máxima, "118 / — bpm"; sem média real (> 0), `nil` (a linha some).
    static func heartRate(average: Double?, maximum: Double?) -> String? {
        guard let average, average.isFinite, average > 0 else {
            return nil
        }
        let averageText = "\(Int(average.rounded()))"
        guard let maximum, maximum.isFinite, maximum > 0 else {
            return "\(averageText) / — bpm"
        }
        return "\(averageText) / \(Int(maximum.rounded())) bpm"
    }

    // MARK: - Privado

    private static func unitSuffix(_ measure: ExerciseMeasure) -> String {
        switch measure {
        case .reps: return ""
        case .seconds: return " s"
        case .steps: return " passos"
        }
    }

    /// Texto da carga de uma série (SPEC RF-46): peso do corpo com 0 não mostra nada.
    private static func loadLabel(_ load: Double, unit: LoadUnit, equipment: Equipment?) -> String? {
        TodayTargetText.loadLabel(TodayTargetText.loadDisplay(load: load, unit: unit, equipment: equipment))
    }

    /// "+ 2,5 kg extra" é lido "mais 2,5 kg extra".
    private static func spokenLoad(_ label: String) -> String {
        guard label.hasPrefix("+ ") else {
            return label
        }
        return "mais " + String(label.dropFirst(2))
    }
}
