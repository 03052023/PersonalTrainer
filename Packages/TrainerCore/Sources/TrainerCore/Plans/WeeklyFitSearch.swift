import Foundation

/// A busca exaustiva de `WeeklyFit` (SPEC §7.15 M4), separada para que as saídas de M5 possam repeti-la com
/// outras preferências e com as regras de 48 h e da véspera desligadas. Função pura sobre os dados: sem
/// `Date()`, sem aleatório, sem FC (P11, P12).
///
/// - Cada plano escolhe `perWeek` dias entre os disponíveis; as sessões ocupam esses dias na ordem da
///   semana, a partir da fase (`sessions[0]`, M3).
/// - A fase avança `perWeek` sessões por semana. As regras valem em cada semana da órbita (até as fases se
///   repetirem) e na passagem do domingo para a segunda seguinte.
/// - As escolhas são percorridas em ordem lexicográfica (o principal por fora, o segundo por dentro), e só
///   uma semana estritamente melhor pelos critérios de M4 substitui a guardada.
struct WeeklyFitSearch: Sendable {
    /// Quais regras de M4 valem. A estrutura do dia vale sempre; M5 desliga as outras duas para achar o
    /// motivo de não caber.
    struct Rules: Sendable, Hashable {
        var muscleRecovery: Bool
        var cardioBeforeLegs: Bool

        static let all = Rules(muscleRecovery: true, cardioBeforeLegs: true)
        static let structureOnly = Rules(muscleRecovery: false, cardioBeforeLegs: false)
    }

    /// Uma sessão de um plano num dia de uma semana da órbita.
    struct Placement: Sendable {
        /// Índice do plano em `plans`.
        let plan: Int
        let session: PlanSessionDemand
    }

    /// Critérios de escolha de M4, na ordem: menos dias com duas sessões, menos pares de dias seguidos com
    /// força, menos pares de dias seguidos com aeróbico e a que começa mais cedo.
    struct Score: Sendable {
        let doubleDays: Int
        let strengthPairs: Int
        let cardioPairs: Int
        /// Os dias do principal e depois os do segundo (`PlanWeekday.rawValue`), um a um.
        let start: [Int]

        func isBetter(than other: Score) -> Bool {
            if doubleDays != other.doubleDays {
                return doubleDays < other.doubleDays
            }
            if strengthPairs != other.strengthPairs {
                return strengthPairs < other.strengthPairs
            }
            if cardioPairs != other.cardioPairs {
                return cardioPairs < other.cardioPairs
            }
            return start.lexicographicallyPrecedes(other.start)
        }
    }

    /// Os planos na ordem de M1 (`ActivePlanOrder`): o principal primeiro.
    let plans: [PlanDemand]
    let preferences: WeekPreferences
    /// Sessões por semana de cada plano, na ordem de `plans`: a de `preferences.sessionsPerWeek` ou a da
    /// demanda, limitada a 1…dias (0 num plano sem dias).
    let perWeek: [Int]
    /// Semanas até as fases de todos os planos se repetirem (1 quando cada plano faz todos os dias).
    let orbitLength: Int

    init(plans: [PlanDemand], preferences: WeekPreferences) {
        let ordered = WeeklyFitSearch.ordered(plans)
        let counts = ordered.map { WeeklyFitSearch.sessionsPerWeek(of: $0, preferences: preferences) }
        var length = 1
        for (plan, count) in zip(ordered, counts) where count > 0 {
            let cycle = plan.sessions.count / WeeklyFitSearch.greatestCommonDivisor(plan.sessions.count, count)
            length = length / WeeklyFitSearch.greatestCommonDivisor(length, cycle) * cycle
        }
        self.plans = ordered
        self.preferences = preferences
        self.perWeek = counts
        self.orbitLength = max(1, length)
    }

    // MARK: - Busca

    /// A melhor semana com todas as regras, ou `nil` se nenhuma escolha vale.
    func bestSchedule() -> WeekSchedule? {
        guard let choice = search(rules: .all, stopAtFirst: false) else {
            return nil
        }
        return schedule(for: choice)
    }

    /// Alguma escolha vale com `rules`? Para no primeiro achado.
    func exists(rules: Rules) -> Bool {
        search(rules: rules, stopAtFirst: true) != nil
    }

    /// Os dias de cada plano (na ordem de `plans`) da melhor escolha, ou da primeira válida com
    /// `stopAtFirst`.
    func search(rules: Rules, stopAtFirst: Bool) -> [[PlanWeekday]]? {
        let days = preferences.availableDays.sorted()
        let choices = perWeek.map { WeeklyFitSearch.combinations(of: days, choosing: $0) }
        guard choices.allSatisfy({ !$0.isEmpty }) else {
            return nil
        }

        var cursor = Array(repeating: 0, count: choices.count)
        var bestChoice: [[PlanWeekday]]?
        var bestScore: Score?
        while true {
            var choice: [[PlanWeekday]] = []
            choice.reserveCapacity(cursor.count)
            for (planIndex, choiceIndex) in cursor.enumerated() {
                choice.append(choices[planIndex][choiceIndex])
            }
            if isValid(choice, rules: rules) {
                if stopAtFirst {
                    return choice
                }
                let candidate = score(of: choice)
                if let current = bestScore {
                    if candidate.isBetter(than: current) {
                        bestChoice = choice
                        bestScore = candidate
                    }
                } else {
                    bestChoice = choice
                    bestScore = candidate
                }
            }
            // Odômetro: o último plano gira mais rápido, como dois laços aninhados.
            var position = cursor.count - 1
            while position >= 0 {
                cursor[position] += 1
                if cursor[position] < choices[position].count {
                    break
                }
                cursor[position] = 0
                position -= 1
            }
            if position < 0 {
                break
            }
        }
        return bestChoice
    }

    // MARK: - Regras de M4

    /// As sessões de cada dia (segunda = 0) na semana `number` da órbita.
    func week(_ choice: [[PlanWeekday]], number: Int) -> [[Placement]] {
        var days = Array(repeating: [Placement](), count: PlanWeekday.allCases.count)
        for (planIndex, plan) in plans.enumerated() {
            let count = plan.sessions.count
            guard count > 0, planIndex < choice.count else {
                continue
            }
            let offset = number * perWeek[planIndex]
            for (position, weekday) in choice[planIndex].enumerated() {
                let session = plan.sessions[(offset + position) % count]
                days[weekday.rawValue].append(Placement(plan: planIndex, session: session))
            }
        }
        return days
    }

    func isValid(_ choice: [[PlanWeekday]], rules: Rules) -> Bool {
        let weeks = (0..<orbitLength).map { week(choice, number: $0) }
        for days in weeks {
            for placements in days where !isStructureValid(placements) {
                return false
            }
        }
        for (index, days) in weeks.enumerated() {
            let following = weeks[(index + 1) % weeks.count]
            for day in days.indices {
                let today = days[day]
                // Domingo → segunda da semana seguinte da órbita (a mesma semana quando a órbita tem 1).
                let tomorrow = day + 1 < days.count ? days[day + 1] : following[0]
                if rules.muscleRecovery && WeeklyFitSearch.sharesMuscles(today, tomorrow) {
                    return false
                }
                if rules.cardioBeforeLegs && WeeklyFitSearch.isVigorousBeforeLegs(today, tomorrow) {
                    return false
                }
            }
        }
        return true
    }

    /// Estrutura do dia (M4): no máximo uma força e um aeróbico. Duas sessões só com "Aceito 2 sessões no
    /// mesmo dia" ou, com "Cardio leve depois da força", um aeróbico leve ou moderado com uma força que não
    /// é de pernas.
    func isStructureValid(_ placements: [Placement]) -> Bool {
        let strengths = placements.filter { $0.session.kind == .strength }
        let cardios = placements.filter { $0.session.kind == .cardio }
        guard strengths.count <= 1, cardios.count <= 1 else {
            return false
        }
        guard placements.count == 2, !preferences.allowsTwoSessionsPerDay else {
            return true
        }
        guard
            preferences.allowsLightCardioAfterStrength,
            let strength = strengths.first,
            let cardio = cardios.first
        else {
            return false
        }
        let intensity = cardio.session.cardioIntensity ?? .moderate
        return intensity != .vigorous && !strength.session.isLowerBody
    }

    /// 48 h (S6): duas forças com algum grupo primário em comum em dias seguidos.
    static func sharesMuscles(_ today: [Placement], _ tomorrow: [Placement]) -> Bool {
        for first in today where first.session.kind == .strength {
            for second in tomorrow where second.session.kind == .strength {
                if !first.session.primaryMuscles.isDisjoint(with: second.session.primaryMuscles) {
                    return true
                }
            }
        }
        return false
    }

    /// Véspera de pernas (A5): um aeróbico forte num dia e uma força de pernas no dia seguinte.
    static func isVigorousBeforeLegs(_ today: [Placement], _ tomorrow: [Placement]) -> Bool {
        let hasVigorous = today.contains { $0.session.kind == .cardio && $0.session.cardioIntensity == .vigorous }
        guard hasVigorous else {
            return false
        }
        return tomorrow.contains { $0.session.kind == .strength && $0.session.isLowerBody }
    }

    // MARK: - Escolha e semana

    func score(of choice: [[PlanWeekday]]) -> Score {
        let weeks = (0..<orbitLength).map { week(choice, number: $0) }
        let doubleDays = weeks.first?.filter { $0.count == 2 }.count ?? 0
        var strengthPairs = 0
        var cardioPairs = 0
        for (index, days) in weeks.enumerated() {
            let following = weeks[(index + 1) % weeks.count]
            for day in days.indices {
                let today = days[day]
                let tomorrow = day + 1 < days.count ? days[day + 1] : following[0]
                if WeeklyFitSearch.has(.strength, today) && WeeklyFitSearch.has(.strength, tomorrow) {
                    strengthPairs += 1
                }
                if WeeklyFitSearch.has(.cardio, today) && WeeklyFitSearch.has(.cardio, tomorrow) {
                    cardioPairs += 1
                }
            }
        }
        let start = choice.flatMap { days in days.map(\.rawValue) }
        return Score(doubleDays: doubleDays, strengthPairs: strengthPairs, cardioPairs: cardioPairs, start: start)
    }

    static func has(_ kind: PlanSessionKind, _ placements: [Placement]) -> Bool {
        placements.contains { $0.session.kind == kind }
    }

    /// A primeira semana da escolha, com o dia previsto em cada lugar e os avisos de M4.
    func schedule(for choice: [[PlanWeekday]]) -> WeekSchedule {
        let days = week(choice, number: 0)
        var slots: [PlannedSlot] = []
        var notes: [FitNote] = []
        var sharedDays: [PlanWeekday] = []
        for (dayIndex, placements) in days.enumerated() {
            guard let weekday = PlanWeekday(rawValue: dayIndex) else {
                continue
            }
            let hasStrength = WeeklyFitSearch.has(.strength, placements)
            if hasStrength && WeeklyFitSearch.has(.cardio, placements) {
                sharedDays.append(weekday)
            }
            for placement in placements {
                let session = placement.session
                let indexInWeek = choice[placement.plan].firstIndex(of: weekday) ?? 0
                // A5: no dia com as duas, a força vem antes.
                let orderInDay = session.kind == .cardio && hasStrength ? 1 : 0
                slots.append(PlannedSlot(
                    weekday: weekday,
                    programID: plans[placement.plan].programID,
                    indexInWeek: indexInWeek,
                    kind: session.kind,
                    orderInDay: orderInDay,
                    programDayID: session.programDayID,
                    dayName: session.dayName,
                    cardioIntensity: session.kind == .cardio ? session.cardioIntensity : nil
                ))
            }
        }
        let usedDays = Set(choice.flatMap { $0 })
        if usedDays.count == PlanWeekday.allCases.count {
            notes.append(.noFullRestDay)
        }
        notes += sharedDays.map { FitNote.strengthBeforeCardio($0) }
        return WeekSchedule(slots: slots, notes: notes)
    }

    // MARK: - Apoio

    /// A ordem de M1 sobre as demandas: prioridade do objetivo, nome e id.
    static func ordered(_ plans: [PlanDemand]) -> [PlanDemand] {
        plans.sorted { lhs, rhs in
            let left = ActivePlanOrder.rank(of: lhs.goal)
            let right = ActivePlanOrder.rank(of: rhs.goal)
            if left != right {
                return left < right
            }
            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }
            return lhs.programID.uuidString < rhs.programID.uuidString
        }
    }

    /// M3: a de "Menos sessões" ou a da demanda, limitada a 1…dias; 0 num plano sem dias.
    static func sessionsPerWeek(of plan: PlanDemand, preferences: WeekPreferences) -> Int {
        let count = plan.sessions.count
        guard count > 0 else {
            return 0
        }
        let wanted = preferences.sessionsPerWeek[plan.programID] ?? plan.sessionsPerWeek
        return min(max(wanted, 1), count)
    }

    /// Todas as escolhas de `count` dias entre `days` (já em ordem), em ordem lexicográfica.
    static func combinations(of days: [PlanWeekday], choosing count: Int) -> [[PlanWeekday]] {
        guard count > 0 else {
            return [[]]
        }
        guard count <= days.count else {
            return []
        }
        var result: [[PlanWeekday]] = []
        var indices = Array(0..<count)
        while true {
            result.append(indices.map { days[$0] })
            var position = count - 1
            while position >= 0 && indices[position] == days.count - count + position {
                position -= 1
            }
            if position < 0 {
                break
            }
            indices[position] += 1
            var next = position + 1
            while next < count {
                indices[next] = indices[next - 1] + 1
                next += 1
            }
        }
        return result
    }

    static func greatestCommonDivisor(_ first: Int, _ second: Int) -> Int {
        var a = abs(first)
        var b = abs(second)
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return max(a, 1)
    }
}
