import Foundation
import TrainerCore

/// Frases da folha "Informações do exercício" (SPEC RF-47; DESIGN §13; docs/V22-CONTRACT.md §3.2):
/// "Hoje" em frase, "Por que esta carga" com os números da última sessão e "Da última vez". Só
/// funções puras, testáveis sem SwiftUI — o `body` da folha só chama estas funções.
///
/// Nada aqui menciona RIR, "sobrando" nem "antes do limite" (SPEC RF-41, decisão 18):
/// `ExerciseInfoContent.targetRIR` só entra na conta da frase de primeira vez com carga, nunca
/// como palavra na tela.
enum ExerciseInfoText {

    // MARK: - "Hoje"

    /// "3 séries de 3 repetições com 62,5 kg. Descanso de 4 min entre as séries."; peso do corpo:
    /// "..., com o peso do corpo. ..."; carga extra: "... com + 2,5 kg extra. ..."; primeira vez:
    /// "... Na primeira vez você escolhe a carga. ...". Segundos e passos usam a unidade certa
    /// (`TodayTargetText.amount`).
    static func today(_ content: ExerciseInfoContent) -> String {
        let base = "\(TodayTargetText.setsText(content.sets)) de \(TodayTargetText.amount(content.targetReps, measure: content.measure))"
        let sentence: String
        switch content.loadDisplay {
        case .hidden:
            sentence = "\(base), com o peso do corpo."
        case .toChoose:
            sentence = "\(base). Na primeira vez você escolhe a carga."
        case .load(let text), .extra(let text):
            sentence = "\(base) com \(text)."
        }
        return sentence + restClause(seconds: content.restSeconds)
    }

    /// " Descanso de 4 min entre as séries."; vazio sem descanso (raro: todo exercício do catálogo
    /// tem descanso > 0, mas a função não presume isso).
    private static func restClause(seconds: Int) -> String {
        guard seconds > 0 else { return "" }
        return " Descanso de \(TodayTargetText.rest(seconds: seconds)) entre as séries."
    }

    // MARK: - "Por que esta carga"

    /// "Por que 62,5 kg" só quando a carga de hoje é um número concreto (`LoadDisplay.load`);
    /// nos outros casos (peso do corpo, carga extra, primeira vez), "Por que assim hoje".
    static func whyTitle(_ content: ExerciseInfoContent) -> String {
        if case .load(let text) = content.loadDisplay {
            return "Por que \(text)"
        }
        return "Por que assim hoje"
    }

    /// Uma frase por nota (SPEC P2, P4–P9), com os números da última sessão (`lastSession`) e da
    /// faixa quando há histórico; sem `lastSession`, frase qualitativa, sem números (contrato
    /// §3.2). `calibrate` nunca depende de `lastSession`: é a nota de quando não há histórico.
    static func why(_ content: ExerciseInfoContent) -> String {
        if content.note == .calibrate {
            return calibrateWhy(content)
        }
        guard
            let lastSession = content.lastSession,
            let representativeLoad = modeLoad(of: lastSession.sets)
        else {
            return fallbackWhy(for: content.note)
        }

        let reps = commaAndList(lastSession.sets.map { TodayTargetText.compactAmount($0.reps, measure: content.measure) })
        if content.equipment == .bodyweight {
            return bodyweightWhy(content, reps: reps, lastLoad: representativeLoad)
        }
        let lastLoadText = TodayTargetText.loadText(representativeLoad, unit: content.loadUnit)

        switch content.note {
        case .calibrate:
            // Tratado acima; mantido para o `switch` continuar exaustivo.
            return calibrateWhy(content)

        case .increase:
            let delta = abs((content.load ?? representativeLoad) - representativeLoad)
            let deltaText = TodayTargetText.loadText(delta, unit: content.loadUnit)
            let subject = measureSubjectPlural(content.measure)
            return "Na última vez você fez \(reps) com \(lastLoadText), o máximo de \(content.repMin) a \(content.repMax). "
                + "A carga sobe \(deltaText) e \(subject) recomeçam em \(content.repMin)."

        case .hold:
            let goal = TodayTargetText.amount(content.targetReps, measure: content.measure)
            return "Na última vez você fez \(reps) com \(lastLoadText), dentro da faixa de \(content.repMin) a \(content.repMax). "
                + "A carga fica a mesma e a meta sobe para \(goal)."

        case .retry:
            return "Na última vez você fez \(reps) com \(lastLoadText), abaixo do mínimo de \(content.repMin). "
                + "A carga se repete para confirmar se foi só esse dia."

        case .decrease:
            let tail = content.load.map { " A carga desce para \(TodayTargetText.loadText($0, unit: content.loadUnit))." }
                ?? " A carga desce um pouco."
            return "Na última vez você fez \(reps) com \(lastLoadText), abaixo do mínimo de \(content.repMin) de novo."
                + tail

        case .returning:
            let newLoad = content.load.map { TodayTargetText.loadText($0, unit: content.loadUnit) } ?? "uma carga menor"
            return "Faz mais de 3 semanas que você não faz este exercício. A carga volta a \(newLoad), "
                + "um pouco abaixo dos \(lastLoadText) da última vez."

        case .deload:
            let loadClause = content.load.map { " com \(TodayTargetText.loadText($0, unit: content.loadUnit))" } ?? ""
            return "Semana leve: \(TodayTargetText.setsText(content.sets))\(loadClause), um pouco menos que o normal, "
                + "para descansar sem perder o ganho."
        }
    }

    /// Peso do corpo com histórico (SPEC RF-46, P8): nunca "0 kg". A carga só entra na frase como
    /// carga extra, quando é maior que 0 na última vez ou hoje; sem ela, a frase fala da meta.
    private static func bodyweightWhy(_ content: ExerciseInfoContent, reps: String, lastLoad: Double) -> String {
        let todayLoad = max(content.load ?? 0, 0)
        let lastExtra = lastLoad > 0 ? " com + \(TodayTargetText.loadText(lastLoad, unit: content.loadUnit)) extra" : ""
        let lastTime = "Na última vez você fez \(reps)\(lastExtra)"
        let range = "\(content.repMin) a \(content.repMax)"
        let goal = TodayTargetText.amount(content.targetReps, measure: content.measure)
        let minimum = TodayTargetText.amount(content.repMin, measure: content.measure)
        let todayText = TodayTargetText.loadText(todayLoad, unit: content.loadUnit)

        switch content.note {
        case .calibrate:
            return calibrateWhy(content)

        case .increase:
            let head = "\(lastTime), o máximo de \(range). "
            let subject = measureSubjectPlural(content.measure)
            if todayLoad > 0 && lastLoad > 0 {
                let delta = TodayTargetText.loadText(abs(todayLoad - lastLoad), unit: content.loadUnit)
                return head + "A carga extra sobe \(delta) e \(subject) recomeçam em \(content.repMin)."
            }
            if todayLoad > 0 {
                return head + "Hoje entra + \(todayText) extra e \(subject) recomeçam em \(content.repMin)."
            }
            return head + "Hoje a meta volta para \(minimum)."

        case .hold:
            let tail = todayLoad > 0
                ? "A carga extra fica a mesma e a meta sobe para \(goal)."
                : "A meta sobe para \(goal)."
            return "\(lastTime), dentro da faixa de \(range). " + tail

        case .retry:
            return "\(lastTime), abaixo do mínimo de \(content.repMin). "
                + "Hoje a meta é \(goal), para confirmar se foi só esse dia."

        case .decrease:
            let tail: String
            if todayLoad > 0 {
                tail = " A carga extra desce para \(todayText)."
            } else if lastLoad > 0 {
                tail = " Hoje fica sem a carga extra."
            } else {
                tail = " Hoje a meta é \(goal); a próxima sessão se ajusta."
            }
            return "\(lastTime), abaixo do mínimo de \(content.repMin) de novo." + tail

        case .returning:
            let head = "Faz mais de 3 semanas que você não faz este exercício."
            if todayLoad > 0 && lastLoad > 0 {
                let lastText = TodayTargetText.loadText(lastLoad, unit: content.loadUnit)
                return head + " A carga extra volta a \(todayText), um pouco abaixo dos \(lastText) da última vez."
            }
            if lastLoad > 0 {
                return head + " Hoje fica sem a carga extra, para voltar com calma."
            }
            return head + " Hoje a meta volta para \(minimum), para retomar com calma."

        case .deload:
            let loadClause = todayLoad > 0 ? " com + \(todayText) extra" : ""
            return "Semana leve: \(TodayTargetText.setsText(content.sets))\(loadClause), um pouco menos que o normal, "
                + "para descansar sem perder o ganho."
        }
    }

    /// `calibrate` (SPEC P2, RF-41): com carga concreta, a frase de primeira vez com carga;
    /// peso do corpo, a frase de RF-41 para peso do corpo. Nunca usa `lastSession` (não existe).
    private static func calibrateWhy(_ content: ExerciseInfoContent) -> String {
        if content.equipment == .bodyweight {
            let goal = TodayTargetText.amount(content.targetReps, measure: content.measure)
            return "Primeira vez: faça \(goal) com boa técnica; a próxima sessão se ajusta."
        }
        if let load = content.load {
            let loadText = TodayTargetText.loadText(load, unit: content.loadUnit)
            return "Primeira vez com este exercício: comece com \(loadText) e ajuste a partir da próxima sessão."
        }
        if content.measure == .reps {
            let upper = content.targetReps + content.targetRIR
            return "Escolha uma carga que daria para levantar umas \(upper) vezes. Hoje faça \(content.targetReps)."
        }
        let goal = TodayTargetText.amount(content.targetReps, measure: content.measure)
        return "Escolha uma carga com a qual você aguentaria mais do que isso. Hoje faça \(goal)."
    }

    /// Sem `lastSession`: frase qualitativa, sem números (contrato §3.2). Caminho raro: as notas
    /// abaixo normalmente só existem quando há histórico; isto é só uma rede de segurança.
    private static func fallbackWhy(for note: PrescriptionNote) -> String {
        switch note {
        case .calibrate:
            return ""
        case .increase:
            return "A carga sobe porque você completou o topo da faixa na última vez."
        case .hold:
            return "A carga continua a mesma e a meta sobe mais um pouco."
        case .retry:
            return "A carga se repete para confirmar se a última vez foi só um dia ruim."
        case .decrease:
            return "A carga desce um pouco para você voltar à faixa com folga."
        case .returning:
            return "Faz tempo que você não faz este exercício, então a carga volta um pouco mais leve."
        case .deload:
            return "Semana leve: menos séries e carga um pouco menor para descansar sem perder o ganho."
        }
    }

    // MARK: - "Da última vez"

    /// "Da última vez · qua, 23 set" (data pt-BR curta, sem depender de símbolos abreviados do
    /// sistema, que variam com a versão do ICU: tabela fixa de dia da semana e mês).
    static func lastTimeTitle(_ lastSession: ExerciseLastSession, calendar: Calendar = .autoupdatingCurrent) -> String {
        "Da última vez · \(shortDate(lastSession.date, calendar: calendar))"
    }

    /// "5, 5, 5 · 60 kg"; peso do corpo sem carga: "5, 5, 5"; cargas diferentes:
    /// "5 × 60 kg, 4 × 57,5 kg"; semana leve: sufixo " (semana leve)".
    static func lastTime(
        _ lastSession: ExerciseLastSession,
        unit: LoadUnit,
        equipment: Equipment?,
        measure: ExerciseMeasure
    ) -> String {
        let sets = lastSession.sets
        guard !sets.isEmpty else { return "" }

        let repsTexts = sets.map { TodayTargetText.compactAmount($0.reps, measure: measure) }
        let loadTexts: [String?] = sets.map { set in
            if equipment == .bodyweight {
                guard set.load > 0 else { return nil }
                return "+ \(TodayTargetText.loadText(set.load, unit: unit)) extra"
            }
            return TodayTargetText.loadText(set.load, unit: unit)
        }

        let base: String
        if loadTexts.allSatisfy({ $0 == nil }) {
            base = repsTexts.joined(separator: ", ")
        } else if let first = loadTexts.first ?? nil, loadTexts.allSatisfy({ $0 == first }) {
            base = "\(repsTexts.joined(separator: ", ")) · \(first)"
        } else {
            base = zip(repsTexts, loadTexts).map { reps, load in
                load.map { "\(reps) × \($0)" } ?? reps
            }.joined(separator: ", ")
        }
        return lastSession.wasDeload ? "\(base) (semana leve)" : base
    }

    // MARK: - Privado

    /// "5, 5 e 5" (mais de um item, "e" antes do último); "5" (um só item).
    private static func commaAndList(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        guard items.count > 1 else { return last }
        let head = items.dropLast().joined(separator: ", ")
        return "\(head) e \(last)"
    }

    private static func measureSubjectPlural(_ measure: ExerciseMeasure) -> String {
        switch measure {
        case .reps: return "as repetições"
        case .seconds: return "os segundos"
        case .steps: return "os passos"
        case .minutes: return "os minutos"
        }
    }

    /// Moda das cargas das séries de trabalho (SPEC P3): a mais frequente; empate → a maior.
    /// `nil` só se `sets` estiver vazio (não deveria acontecer: `ExerciseLastSession.sets` nunca é
    /// vazio pelo contrato do andaime).
    private static func modeLoad(of sets: [SetResult]) -> Double? {
        guard !sets.isEmpty else { return nil }
        var counts: [Double: Int] = [:]
        for set in sets {
            counts[set.load, default: 0] += 1
        }
        let maxCount = counts.values.max() ?? 0
        return counts.filter { $0.value == maxCount }.keys.max()
    }

    private static let weekdayAbbreviations = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
    private static let monthAbbreviations = [
        "jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez",
    ]

    /// "qua, 23 set": tabela fixa em vez de `DateFormatter`/`Date.FormatStyle`, para não depender
    /// de como o ICU do sistema abrevia dia da semana e mês em pt-BR (com ou sem ponto, com ou
    /// sem "de").
    private static func shortDate(_ date: Date, calendar: Calendar) -> String {
        let weekdayIndex = calendar.component(.weekday, from: date) - 1
        let day = calendar.component(.day, from: date)
        let monthIndex = calendar.component(.month, from: date) - 1
        let weekday = weekdayAbbreviations.indices.contains(weekdayIndex) ? weekdayAbbreviations[weekdayIndex] : ""
        let month = monthAbbreviations.indices.contains(monthIndex) ? monthAbbreviations[monthIndex] : ""
        return "\(weekday), \(day) \(month)"
    }
}
