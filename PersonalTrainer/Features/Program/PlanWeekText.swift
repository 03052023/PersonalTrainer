import Foundation
import TrainerCore

/// Textos da semana com dois planos (SPEC §7.15 M4, M5, M7, M8, M9; DESIGN §7, §13): o motivo de não
/// caber, as saídas, os avisos, a semana dia a dia e as frases da folha "Seu objetivo" e da aba Plano.
/// pt-BR, curtos, sem jargão de academia e sem frase de efeito (DESIGN §6). Nada de FC (P12) nem de RIR
/// (RF-41). Funções puras, testadas em tabela (`PlanWeekTextTests`).
enum PlanWeekText {
    /// Uma linha da semana: o dia e o que cabe nele ("Qui · Dia A — Superior + Cardio forte").
    struct WeekRow: Sendable, Hashable, Identifiable {
        let day: PlanWeekday
        /// "Qui".
        let dayLabel: String
        /// "Dia A — Superior + Cardio forte", "Dia B — Inferior + Pilates" (com uma atividade fixa, 2.4) ou
        /// "descanso" num dia livre.
        let sessionsText: String
        /// Objetivo de cada sessão do dia, na ordem do dia (a cor do ponto de tinta de cada uma). A atividade
        /// fixa não tem ponto.
        let goals: [ProgramGoal]
        /// Nenhuma sessão e nenhuma atividade fixa neste dia.
        let isRest: Bool

        var id: PlanWeekday { day }

        /// "Qui · Dia A — Superior + Cardio forte".
        var text: String { "\(dayLabel) · \(sessionsText)" }

        /// Leitura do VoiceOver, sem os sinais: "quinta: Dia A — Superior e Cardio forte".
        var spokenText: String {
            "\(day.name): \(sessionsText.replacingOccurrences(of: " + ", with: " e "))"
        }
    }

    // MARK: - Dias

    /// "na segunda", "no sábado".
    static func onDay(_ day: PlanWeekday) -> String {
        switch day {
        case .saturday, .sunday:
            return "no \(day.name)"
        case .monday, .tuesday, .wednesday, .thursday, .friday:
            return "na \(day.name)"
        }
    }

    /// "Na terça", "No domingo".
    static func onDayCapitalized(_ day: PlanWeekday) -> String {
        capitalizedFirst(onDay(day))
    }

    /// "no domingo"; "na terça e no domingo"; "na segunda, na quarta e no sábado".
    static func onDays(_ days: [PlanWeekday]) -> String {
        joinedList(days.sorted().map { onDay($0) })
    }

    /// "a", "a e b", "a, b e c".
    static func joinedList(_ parts: [String]) -> String {
        guard let last = parts.last else {
            return ""
        }
        if parts.count == 1 {
            return last
        }
        return parts.dropLast().joined(separator: ", ") + " e " + last
    }

    // MARK: - Motivo (M5)

    /// Uma frase por motivo. `twoPerDay`: com "Aceito 2 sessões no mesmo dia", o número de lugares é o
    /// dobro dos dias (M5), e a frase não fala em dias.
    static func problem(_ problem: FitProblem, twoPerDay: Bool = false) -> String {
        switch problem {
        case .notEnoughDays(let needed, let available):
            if twoPerDay {
                return "São \(sessionCount(needed)), e cabem \(available) nos seus dias."
            }
            return "São \(sessionCount(needed)) para \(dayCount(available))."
        case .muscleRecovery:
            return "Duas sessões de força com os mesmos músculos ficariam a menos de 48 h."
        case .cardioBeforeLegs:
            return "Um cardio forte cairia na véspera de pernas."
        }
    }

    /// O motivo em uma frase (M5: o primeiro que valer; com os dois, as duas frases). `nil` sem motivo.
    static func problemSentence(_ problems: [FitProblem], twoPerDay: Bool = false) -> String? {
        guard !problems.isEmpty else {
            return nil
        }
        return problems.map { problem($0, twoPerDay: twoPerDay) }.joined(separator: " ")
    }

    // MARK: - Saídas (M5)

    /// "Treinar também no domingo", "Aceitar 2 sessões no mesmo dia", "Cardio leve depois da força",
    /// "Cardio 2 vezes por semana". `goals` diz o objetivo de cada plano pelo id do programa.
    static func change(_ change: FitChange, goals: [UUID: ProgramGoal]) -> String {
        switch change {
        case .addDays(let days):
            return "Treinar também \(onDays(days))"
        case .allowTwoSessionsPerDay:
            return "Aceitar 2 sessões no mesmo dia"
        case .allowLightCardioAfterStrength:
            return "Cardio leve depois da força"
        case .fewerSessions(let programID, let perWeek):
            let name = goals[programID]?.displayName ?? "Este plano"
            return "\(name) \(timesPerWeek(perWeek))"
        }
    }

    /// As mudanças de uma saída, uma por linha, na ordem de M5.
    static func changes(of alternative: FitAlternative, goals: [UUID: ProgramGoal]) -> [String] {
        alternative.changes.map { change($0, goals: goals) }
    }

    /// Leitura do VoiceOver de uma saída: "Treinar também no domingo e aceitar 2 sessões no mesmo dia".
    static func spokenChanges(of alternative: FitAlternative, goals: [UUID: ProgramGoal]) -> String {
        let parts = changes(of: alternative, goals: goals)
        guard let first = parts.first else {
            return ""
        }
        let rest = parts.dropFirst().map { lowercasedFirst($0) }
        return joinedList([first] + rest)
    }

    static let noAlternative = "Esses dois planos não cabem juntos na semana. Escolha um só."
    static let chooseAlternative = "Escolher esta"
    static let alternativesTitle = "O que faz caber"
    static let fitsText = "Cabe nos seus dias."
    static let checkFailed = "Não foi possível conferir a semana."

    // MARK: - Avisos (M4)

    static func note(_ note: FitNote) -> String {
        switch note {
        case .noFullRestDay:
            return "Sem um dia de descanso completo."
        case .strengthBeforeCardio(let day):
            return "\(onDayCapitalized(day)), faça a força antes do cardio."
        }
    }

    // MARK: - A semana (M4)

    static let restText = "descanso"

    /// Intensidade pelo teste da fala (SPEC §7.14 F2), nunca pela FC: "leve", "moderado", "forte".
    static func intensityWord(_ intensity: CardioIntensity) -> String {
        switch intensity {
        case .light: return "leve"
        case .moderate: return "moderado"
        case .vigorous: return "forte"
        }
    }

    /// "Cardio forte", "Cardio" sem intensidade conhecida.
    static func cardioLabel(_ intensity: CardioIntensity?) -> String {
        guard let intensity else {
            return "Cardio"
        }
        return "Cardio \(intensityWord(intensity))"
    }

    /// Uma sessão da semana: a força pelo nome do dia previsto ("Dia A — Superior"), o aeróbico pela
    /// intensidade ("Cardio forte"). Sem o nome do dia, o nome do objetivo.
    static func slotText(_ slot: PlannedSlot, goal: ProgramGoal?) -> String {
        switch slot.kind {
        case .cardio:
            return cardioLabel(slot.cardioIntensity)
        case .strength:
            let name = slot.dayName.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                return name
            }
            return goal?.displayName ?? "Sessão"
        }
    }

    /// Os 7 dias, de segunda a domingo, com as sessões de cada um na ordem do dia e, depois delas, as
    /// atividades fixas do dia (SPEC §7.17 X4; DESIGN §9.3 ponto 5): "Ter · Dia B — Inferior + Pilates"; um
    /// dia só com fixa: "Ter · Pilates". A fixa não tem cor de objetivo e o dia com ela não é de descanso.
    static func weekRows(_ schedule: WeekSchedule, goals: [UUID: ProgramGoal]) -> [WeekRow] {
        PlanWeekday.allCases.map { day in
            let slots = schedule.slots(on: day)
            let fixed = schedule.fixed(on: day)
            let sessionTexts: [String] = slots.map { slotText($0, goal: goals[$0.programID]) }
            let fixedTexts: [String] = fixed.map { $0.name }
            let texts = sessionTexts + fixedTexts
            return WeekRow(
                day: day,
                dayLabel: day.shortName,
                sessionsText: texts.isEmpty ? restText : texts.joined(separator: " + "),
                goals: slots.compactMap { goals[$0.programID] },
                isRest: texts.isEmpty
            )
        }
    }

    /// Os avisos da semana (M4), na ordem em que vieram.
    static func notes(_ schedule: WeekSchedule) -> [String] {
        schedule.notes.map { note($0) }
    }

    // MARK: - O que muda (M7)

    /// A ordem dos grupos na tela: "Ganha", "Fica igual", "Custa".
    static let consequenceOrder: [PlanConsequenceKind] = [.positive, .neutral, .negative]

    static func groupTitle(_ kind: PlanConsequenceKind) -> String {
        switch kind {
        case .positive: return "Ganha"
        case .neutral: return "Fica igual"
        case .negative: return "Custa"
        }
    }

    /// O sinal ao lado de cada frase (DESIGN §13): +, = e −.
    static func sign(_ kind: PlanConsequenceKind) -> String {
        switch kind {
        case .positive: return "+"
        case .neutral: return "="
        case .negative: return "−"
        }
    }

    static let overlapWarning = "Os dois planos treinam quase os mesmos levantamentos. Um plano só, ou outro formato, pode bastar."

    // MARK: - Folha "Seu objetivo" e aba Plano (M8, M9)

    /// "Adicionar Cardio ao seu plano".
    static func addTitle(_ goal: ProgramGoal) -> String {
        "Adicionar \(goal.displayName) ao seu plano"
    }

    /// Botão da última página do fluxo: "Adicionar Cardio".
    static func addConfirmTitle(_ goal: ProgramGoal) -> String {
        "Adicionar \(goal.displayName)"
    }

    /// Aviso da troca com dois planos ativos (M8).
    static func alsoLeaves(_ goal: ProgramGoal) -> String {
        "O plano de \(goal.displayName) também sai."
    }

    static let saveDaysTitle = "Salvar os dias"
    static let addPlanButton = "Adicionar um plano"
    static let removePlanButton = "Tirar este plano"
    static let yourWeekTitle = "Sua semana"
    static let yourDaysTitle = "Seus dias"
    static let twoSessionsToggle = "Aceito 2 sessões no mesmo dia"
    static let twoSessionsHint = "Uma de força e uma de cardio, com a força antes."
    static let lightCardioToggle = "Cardio leve depois da força"
    static let lightCardioHint = "Nos dias sem pernas, um cardio leve ou moderado logo depois da força."
    static let daysQuestion = "Em quais dias você pode treinar?"

    /// Na aba Plano, quando os dois planos não cabem mais nos dias escolhidos (M6).
    static let notFitInPlanTab = "Seus planos não cabem nos dias escolhidos. Ajuste em Seus dias."

    /// Confirmação de "Tirar este plano" (M8).
    static func removeQuestion(_ goal: ProgramGoal) -> String {
        "Tirar o plano de \(goal.displayName)?"
    }

    static func removeMessage(kept goal: ProgramGoal) -> String {
        "O plano de \(goal.displayName) continua. As sessões feitas ficam no Histórico."
    }

    static let removeConfirm = "Tirar o plano"

    // MARK: - Ajudantes

    /// "1 sessão", "7 sessões".
    static func sessionCount(_ count: Int) -> String {
        count == 1 ? "1 sessão" : "\(count) sessões"
    }

    /// "1 dia", "6 dias".
    static func dayCount(_ count: Int) -> String {
        count == 1 ? "1 dia" : "\(count) dias"
    }

    /// "1 vez por semana", "2 vezes por semana".
    static func timesPerWeek(_ count: Int) -> String {
        count == 1 ? "1 vez por semana" : "\(count) vezes por semana"
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }
        return first.uppercased() + text.dropFirst()
    }

    private static func lowercasedFirst(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }
        return first.lowercased() + text.dropFirst()
    }
}
