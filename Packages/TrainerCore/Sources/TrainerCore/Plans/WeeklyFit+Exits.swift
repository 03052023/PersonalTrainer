import Foundation

/// As saídas de M5 (SPEC §7.15; owner notes item 9): cada mudança que faz os planos caberem, com as
/// preferências e a semana que resultam dela, nesta ordem:
/// 1. treinar também em outros dias: o menor conjunto de dias que faz caber (1 dia, de segunda a domingo;
///    depois 2, e assim por diante);
/// 2. aceitar 2 sessões no mesmo dia;
/// 3. cardio leve depois da força (só com um plano que tem aeróbico e outro que tem força);
/// 4. menos sessões por semana no plano de aeróbico (o Cardio): a maior quantidade, de k − 1 até 1, que faz
///    caber.
///
/// Saída que já está nas preferências não aparece. Se nenhuma sozinha faz caber, aparecem os pares que
/// fazem, na ordem 1+2, 1+3, 1+4, 2+3, 2+4, 3+4; com o 1, o menor conjunto de dias junto com a outra (no
/// 1+4, a maior quantidade de sessões que ainda acha dias). Sem nenhuma, a lista fica vazia.
extension WeeklyFit {
    /// As quatro saídas de M5, pelo número da SPEC.
    enum Exit: Int, Sendable, CaseIterable {
        case addDays = 1
        case twoSessionsPerDay = 2
        case lightCardioAfterStrength = 3
        case fewerCardioSessions = 4
    }

    /// Os pares de M5, na ordem da SPEC.
    static var exitPairs: [(Exit, Exit)] {
        [
            (.addDays, .twoSessionsPerDay),
            (.addDays, .lightCardioAfterStrength),
            (.addDays, .fewerCardioSessions),
            (.twoSessionsPerDay, .lightCardioAfterStrength),
            (.twoSessionsPerDay, .fewerCardioSessions),
            (.lightCardioAfterStrength, .fewerCardioSessions),
        ]
    }

    static func alternatives(for search: WeeklyFitSearch) -> [FitAlternative] {
        let context = ExitContext(search: search)
        var singles: [FitAlternative] = []
        for exit in Exit.allCases where context.applies(exit) {
            if let changes = context.single(exit) {
                singles.append(context.alternative(changes))
            }
        }
        guard singles.isEmpty else {
            return singles
        }
        var pairs: [FitAlternative] = []
        for (first, second) in exitPairs where context.applies(first) && context.applies(second) {
            if let changes = context.pair(first, second) {
                pairs.append(context.alternative(changes))
            }
        }
        return pairs
    }

    /// O que as saídas precisam saber dos planos, das fixas e das preferências de partida.
    struct ExitContext: Sendable {
        let plans: [PlanDemand]
        let preferences: WeekPreferences
        /// As atividades fixas fora do app (SPEC §7.17 X4): as saídas são calculadas com elas.
        let fixed: [FixedActivityDemand]
        /// Os dias que a pessoa ainda não marcou, de segunda a domingo.
        let missingDays: [PlanWeekday]
        /// O plano de aeróbico (todos os dias de aeróbico) com pelo menos 2 sessões por semana, e quantas.
        let cardioPlan: (programID: UUID, perWeek: Int)?
        /// Um plano tem aeróbico e outro tem força.
        let mixesCardioAndStrength: Bool

        init(search: WeeklyFitSearch) {
            plans = search.plans
            preferences = search.preferences
            fixed = search.fixed
            missingDays = PlanWeekday.allCases.filter { !search.preferences.availableDays.contains($0) }
            var cardio: (programID: UUID, perWeek: Int)?
            for (plan, count) in zip(search.plans, search.perWeek) where plan.isCardio && count >= 2 {
                cardio = (programID: plan.programID, perWeek: count)
                break
            }
            cardioPlan = cardio
            mixesCardioAndStrength = search.mixesCardioAndStrength
        }

        /// A saída faz sentido e ainda não está nas preferências.
        func applies(_ exit: Exit) -> Bool {
            switch exit {
            case .addDays:
                return !missingDays.isEmpty
            case .twoSessionsPerDay:
                return !preferences.allowsTwoSessionsPerDay
            case .lightCardioAfterStrength:
                return !preferences.allowsLightCardioAfterStrength && mixesCardioAndStrength
            case .fewerCardioSessions:
                return cardioPlan != nil
            }
        }

        /// As mudanças de uma saída sozinha, se ela faz caber.
        func single(_ exit: Exit) -> [FitChange]? {
            switch exit {
            case .addDays:
                return smallestDays(from: preferences).map { [FitChange.addDays($0)] }
            case .twoSessionsPerDay:
                return fits(FitChange.allowTwoSessionsPerDay.applied(to: preferences))
                    ? [FitChange.allowTwoSessionsPerDay] : nil
            case .lightCardioAfterStrength:
                return fits(FitChange.allowLightCardioAfterStrength.applied(to: preferences))
                    ? [FitChange.allowLightCardioAfterStrength] : nil
            case .fewerCardioSessions:
                return largestReduction(from: preferences).map { [$0] }
            }
        }

        /// As mudanças de um par (a primeira saída antes), se as duas juntas fazem caber.
        func pair(_ first: Exit, _ second: Exit) -> [FitChange]? {
            switch (first, second) {
            case (.addDays, .fewerCardioSessions):
                for change in reductions() {
                    if let days = smallestDays(from: change.applied(to: preferences)) {
                        return [FitChange.addDays(days), change]
                    }
                }
                return nil
            case (.addDays, _):
                guard let change = simpleChange(second) else {
                    return nil
                }
                return smallestDays(from: change.applied(to: preferences)).map { [FitChange.addDays($0), change] }
            case (_, .fewerCardioSessions):
                guard let change = simpleChange(first) else {
                    return nil
                }
                return largestReduction(from: change.applied(to: preferences)).map { [change, $0] }
            default:
                guard let firstChange = simpleChange(first), let secondChange = simpleChange(second) else {
                    return nil
                }
                let changed = secondChange.applied(to: firstChange.applied(to: preferences))
                return fits(changed) ? [firstChange, secondChange] : nil
            }
        }

        /// A saída com as preferências e a melhor semana que resultam dela.
        func alternative(_ changes: [FitChange]) -> FitAlternative {
            let changed = changes.reduce(preferences) { current, change in change.applied(to: current) }
            let schedule = WeeklyFitSearch(plans: plans, preferences: changed, fixed: fixed).bestSchedule()
                ?? WeekSchedule.empty
            return FitAlternative(changes: changes, preferences: changed, schedule: schedule)
        }

        // MARK: - Apoio

        /// As saídas 2 e 3, que não têm quantidade.
        func simpleChange(_ exit: Exit) -> FitChange? {
            switch exit {
            case .twoSessionsPerDay:
                return .allowTwoSessionsPerDay
            case .lightCardioAfterStrength:
                return .allowLightCardioAfterStrength
            case .addDays, .fewerCardioSessions:
                return nil
            }
        }

        func fits(_ candidate: WeekPreferences) -> Bool {
            WeeklyFitSearch(plans: plans, preferences: candidate, fixed: fixed).exists(rules: .all)
        }

        /// Saída 1: o menor conjunto de dias que falta e faz caber com `base`, na ordem de M5.
        func smallestDays(from base: WeekPreferences) -> [PlanWeekday]? {
            guard !missingDays.isEmpty else {
                return nil
            }
            for size in 1...missingDays.count {
                for days in WeeklyFitSearch.combinations(of: missingDays, choosing: size) {
                    if fits(FitChange.addDays(days).applied(to: base)) {
                        return days
                    }
                }
            }
            return nil
        }

        /// Saída 4: de k − 1 até 1 sessões no plano de aeróbico.
        func reductions() -> [FitChange] {
            guard let cardioPlan, cardioPlan.perWeek >= 2 else {
                return []
            }
            return stride(from: cardioPlan.perWeek - 1, through: 1, by: -1).map { count in
                FitChange.fewerSessions(programID: cardioPlan.programID, perWeek: count)
            }
        }

        /// Saída 4 com `base`: a maior quantidade que faz caber.
        func largestReduction(from base: WeekPreferences) -> FitChange? {
            reductions().first { change in fits(change.applied(to: base)) }
        }
    }
}
