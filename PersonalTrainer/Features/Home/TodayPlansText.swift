import Foundation
import TrainerCore

/// Textos da tela Hoje com dois planos (SPEC §7.15 M6; DESIGN §9.3, §9.7): a linha "Hoje: Superior +
/// Cardio leve 25 min", o detalhe do cartão ("5 exercícios · ≈ 55 min" ou "30 min" no cardio), o dia de
/// descanso, "Feito hoje" e a faixa de quando os planos não cabem. pt-BR, curtos, sem frase de efeito
/// (DESIGN §6): nada depois de "Hoje é dia de descanso.". A intensidade do cardio vem do teste da fala
/// (`CardioIntensity`), nunca da FC (P12). Funções puras, testadas em `HomeMultiPlanTests`.
enum TodayPlansText {
    static let restDay = "Hoje é dia de descanso."
    static let trainAnyway = "Treinar mesmo assim"
    static let allDone = "Tudo feito por hoje."
    static let doneToday = "✓ Feito hoje"
    static let startThis = "Começar esta"
    static let notFitBanner = "Seus planos não cabem nos dias escolhidos. Ajuste em Plano › Seus dias."

    /// "A seguir: Dia B — Inferior": a próxima sessão do plano que já treinou hoje.
    static func upNext(_ plan: SessionPlan) -> String {
        "A seguir: \(plan.programDayName)"
    }

    // MARK: - Cardio (SPEC §7.14 F1, §7.15 M3)

    /// Um exercício é aeróbico pelo padrão `cardio` do catálogo (F1).
    static func isCardio(_ exercise: PlannedExercise) -> Bool {
        exercise.exercise.movementPattern == .cardio
    }

    /// Sessão só de aeróbicos (o plano Cardio): o cartão fala em minutos.
    static func isCardioOnly(_ plan: SessionPlan) -> Bool {
        !plan.exercises.isEmpty && plan.exercises.allSatisfy { isCardio($0) }
    }

    /// A intensidade do dia é a do aeróbico mais forte (M3), pelas séries e pela faixa do plano.
    static func cardioIntensity(_ plan: SessionPlan) -> CardioIntensity? {
        plan.exercises
            .filter { isCardio($0) }
            .map { CardioIntensity.classify(slug: $0.exercise.slug, sets: $0.target.sets, repMax: $0.target.repMax) }
            .max { $0.rank < $1.rank }
    }

    /// Minutos do aeróbico de hoje: as séries × a meta de minutos, mais as recuperações entre elas.
    /// 30 min contínuos dão 30; 4 × 3 min com 3 min de recuperação dão 21. 0 sem aeróbico.
    static func cardioMinutes(_ plan: SessionPlan) -> Int {
        plan.exercises.filter { isCardio($0) }.reduce(0) { total, planned in
            let prescription = planned.prescription
            let sets = max(0, prescription.sets)
            let goal = max(0, TodayTargetText.goal(targetReps: prescription.targetReps, repMin: prescription.repMin))
            let recoveryMinutes = Int((Double(max(0, prescription.restSeconds)) / 60).rounded())
            return total + sets * goal + max(0, sets - 1) * recoveryMinutes
        }
    }

    // MARK: - A linha de cima e o cartão

    /// "Dia A — Superior" → "Superior". Nome sem travessão fica inteiro.
    static func shortDayTitle(_ name: String) -> String {
        guard let range = name.range(of: " — ") else {
            return name
        }
        let suffix = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return suffix.isEmpty ? name : suffix
    }

    /// Como uma sessão aparece na linha de cima: "Superior" ou "Cardio leve 25 min".
    static func sessionLabel(_ plan: SessionPlan) -> String {
        guard isCardioOnly(plan) else {
            return shortDayTitle(plan.programDayName)
        }
        var parts = [PlanWeekText.cardioLabel(cardioIntensity(plan))]
        let minutes = cardioMinutes(plan)
        if minutes > 0 {
            parts.append("\(minutes) min")
        }
        return parts.joined(separator: " ")
    }

    /// Leitura do VoiceOver: "Cardio leve, 25 minutos".
    static func spokenSessionLabel(_ plan: SessionPlan) -> String {
        guard isCardioOnly(plan) else {
            return shortDayTitle(plan.programDayName)
        }
        let label = PlanWeekText.cardioLabel(cardioIntensity(plan))
        let minutes = cardioMinutes(plan)
        guard minutes > 0 else {
            return label
        }
        return "\(label), \(minutesSpoken(minutes))"
    }

    /// "Hoje: Superior + Cardio leve 25 min"; `nil` sem sessão.
    static func todayLine(_ plans: [SessionPlan]) -> String? {
        guard !plans.isEmpty else {
            return nil
        }
        return "Hoje: " + plans.map { sessionLabel($0) }.joined(separator: " + ")
    }

    /// "Hoje: Superior e Cardio leve, 25 minutos".
    static func spokenTodayLine(_ plans: [SessionPlan]) -> String? {
        guard !plans.isEmpty else {
            return nil
        }
        return "Hoje: " + PlanWeekText.joinedList(plans.map { spokenSessionLabel($0) })
    }

    /// Detalhe do cartão: "30 min" numa sessão só de aeróbico; senão, o de sempre
    /// ("5 exercícios · ≈ 55 min", `PlanCard.detailText`).
    static func detailText(for plan: SessionPlan) -> String {
        let minutes = cardioMinutes(plan)
        if isCardioOnly(plan) && minutes > 0 {
            return "\(minutes) min"
        }
        return PlanCard.detailText(for: plan)
    }

    static func detailSpokenText(for plan: SessionPlan) -> String {
        let minutes = cardioMinutes(plan)
        if isCardioOnly(plan) && minutes > 0 {
            return minutesSpoken(minutes)
        }
        return PlanCard.detailAccessibilityText(for: plan)
    }

    /// "1 minuto", "25 minutos".
    static func minutesSpoken(_ minutes: Int) -> String {
        minutes == 1 ? "1 minuto" : "\(minutes) minutos"
    }
}
