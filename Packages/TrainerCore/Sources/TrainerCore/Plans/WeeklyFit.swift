import Foundation

/// Encaixe semanal de vários planos (SPEC §7.15 M4 e M5; docs/V23-UI-CONTRACT.md §3.1 e §4.5). Função pura:
/// mesma entrada, mesma semana (P11). Sem `Date()`, sem aleatório e sem frequência cardíaca (P12): a
/// intensidade do aeróbico vem do teste da fala (`CardioIntensity`).
///
/// - Os planos são ordenados como em M1 (`ActivePlanOrder`), qualquer que seja a ordem da entrada.
/// - `sessions[0]` de cada demanda é a sessão do começo da semana (a fase, M3); quem chama roda a demanda
///   com `PlanDemand.startingAt(programDayID:)`.
/// - As sessões por semana de cada plano são as de `preferences.sessionsPerWeek` (a saída "Menos sessões")
///   ou, sem a chave, as da demanda.
/// - Com um plano só, a busca é a mesma (a semana dele); o app não a usa na tela Hoje (M4).
/// - As atividades fixas fora do app (SPEC §7.17 X4) ficam presas ao dia delas em todas as semanas; só
///   empurram as sessões de plano.
/// - A busca é exaustiva (no máximo C(7, k₁) × C(7, k₂) escolhas), em `WeeklyFitSearch`.
public enum WeeklyFit {
    /// A melhor semana para `plans` com `preferences` (M4) ou, se não couber, os motivos e as saídas (M5).
    ///
    /// `fixed`: as atividades fixas fora do app (SPEC §7.17 X4), na ordem de `OutsideActivities.fixedDemands`.
    /// Entram em toda semana da órbita, no dia delas, e voltam em `WeekSchedule.fixed`; os motivos e as
    /// saídas de M5 são calculados com elas.
    public static func fit(
        _ plans: [PlanDemand],
        preferences: WeekPreferences,
        fixed: [FixedActivityDemand] = []
    ) -> FitResult {
        let search = WeeklyFitSearch(plans: plans, preferences: preferences, fixed: fixed)
        if let schedule = search.bestSchedule() {
            return FitResult(schedule: schedule)
        }
        return FitResult(
            schedule: nil,
            problems: problems(of: search),
            alternatives: alternatives(for: search)
        )
    }

    /// M5, motivo (o primeiro que valer): faltam lugares mesmo sem as regras de 48 h e da véspera; caberia
    /// sem os 48 h; caberia sem a véspera; senão, os dois.
    ///
    /// Os lugares são os dias disponíveis, o dobro com 2 por dia só quando um plano tem aeróbico e o outro
    /// tem força: duas forças (ou dois aeróbicos) nunca dividem o dia (achado B9 da 2.3).
    static func problems(of search: WeeklyFitSearch) -> [FitProblem] {
        guard search.exists(rules: .structureOnly) else {
            let needed = search.perWeek.reduce(0, +)
            let perDay = search.preferences.allowsTwoSessionsPerDay && search.mixesCardioAndStrength ? 2 : 1
            return [.notEnoughDays(needed: needed, available: search.preferences.availableDays.count * perDay)]
        }
        if search.exists(rules: WeeklyFitSearch.Rules(muscleRecovery: false, cardioBeforeLegs: true)) {
            return [.muscleRecovery]
        }
        if search.exists(rules: WeeklyFitSearch.Rules(muscleRecovery: true, cardioBeforeLegs: false)) {
            return [.cardioBeforeLegs]
        }
        return [.muscleRecovery, .cardioBeforeLegs]
    }
}
