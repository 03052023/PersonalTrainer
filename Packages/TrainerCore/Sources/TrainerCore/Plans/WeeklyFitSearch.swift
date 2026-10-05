import Foundation

/// A busca exaustiva de `WeeklyFit` (SPEC §7.15 M4), separada para que as saídas de M5 possam repeti-la com
/// outras preferências e com as regras de 48 h e da véspera desligadas. Função pura sobre os dados: sem
/// `Date()`, sem aleatório, sem FC (P11, P12).
///
/// - Cada plano escolhe `perWeek` dias entre os disponíveis; as sessões ocupam esses dias na ordem da
///   semana, a partir da fase (`sessions[0]`, M3).
/// - A fase avança `perWeek` sessões por semana. As regras valem em cada semana da órbita (até as fases se
///   repetirem) e na passagem do domingo para a segunda seguinte.
/// - As atividades fixas fora do app (SPEC §7.17 X4) ficam presas ao dia delas em todas as semanas da
///   órbita; nenhuma escolha as move. A de força ocupa o lugar de força do dia, a de aeróbico o de aeróbico,
///   e a leve não ocupa lugar (só tira o descanso completo). As regras valem entre uma fixa e uma sessão de
///   plano; duas fixas entre si nunca invalidam a semana (é escolha da pessoa).
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

    /// Uma sessão num dia de uma semana da órbita: de um plano ou de uma atividade fixa (X4).
    struct Placement: Sendable {
        /// Índice do plano em `plans`; `nil` numa atividade fixa fora do app.
        let plan: Int?
        let session: PlanSessionDemand

        /// Atividade fixa fora do app (X4): presa ao dia, igual em toda escolha.
        var isFixed: Bool {
            plan == nil
        }
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
    /// As atividades fixas fora do app (X4), por dia da semana e, no mesmo dia, na ordem recebida (a de
    /// `OutsideActivities.fixedDemands`).
    let fixed: [FixedActivityDemand]
    /// Sessões por semana de cada plano, na ordem de `plans`: a de `preferences.sessionsPerWeek` ou a da
    /// demanda, limitada a 1…dias (0 num plano sem dias).
    let perWeek: [Int]
    /// Semanas até as fases de todos os planos se repetirem (1 quando cada plano faz todos os dias).
    let orbitLength: Int
    /// As fixas que ocupam lugar (força e aeróbico), por dia (segunda = 0), iguais em toda semana da órbita.
    let fixedPlacements: [[Placement]]
    /// Os dias com alguma fixa, inclusive a leve: não são de descanso completo (X4).
    let fixedDays: Set<PlanWeekday>
    /// Um plano tem aeróbico e outro tem força: só assim um dia tem lugar para duas sessões de plano, porque
    /// duas forças (ou dois aeróbicos) nunca dividem o dia (M5; achado B9 da 2.3).
    let mixesCardioAndStrength: Bool

    init(plans: [PlanDemand], preferences: WeekPreferences, fixed: [FixedActivityDemand] = []) {
        let ordered = WeeklyFitSearch.ordered(plans)
        let counts = ordered.map { WeeklyFitSearch.sessionsPerWeek(of: $0, preferences: preferences) }
        var length = 1
        for (plan, count) in zip(ordered, counts) where count > 0 {
            let cycle = plan.sessions.count / WeeklyFitSearch.greatestCommonDivisor(plan.sessions.count, count)
            length = length / WeeklyFitSearch.greatestCommonDivisor(length, cycle) * cycle
        }
        let orderedFixed = WeeklyFitSearch.orderedFixed(fixed)
        var byDay = Array(repeating: [Placement](), count: PlanWeekday.allCases.count)
        for activity in orderedFixed {
            if let session = WeeklyFitSearch.session(for: activity) {
                byDay[activity.weekday.rawValue].append(Placement(plan: nil, session: session))
            }
        }
        self.plans = ordered
        self.preferences = preferences
        self.fixed = orderedFixed
        self.perWeek = counts
        self.orbitLength = max(1, length)
        self.fixedPlacements = byDay
        self.fixedDays = Set(orderedFixed.map { $0.weekday })
        self.mixesCardioAndStrength = WeeklyFitSearch.mixes(cardioAndStrengthIn: ordered)
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

    /// As sessões de cada dia (segunda = 0) na semana `number` da órbita: as dos planos e depois as fixas
    /// que ocupam lugar (X4), que são as mesmas em toda semana.
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
        for day in days.indices {
            days[day] += fixedPlacements[day]
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

    /// Estrutura do dia (M4, X4):
    /// - no máximo uma força e um aeróbico de plano;
    /// - uma fixa de força ocupa o lugar de força (nenhuma força de plano no dia), e uma fixa de aeróbico o
    ///   de aeróbico;
    /// - força e aeróbico no mesmo dia, com ao menos um de plano, só com "Aceito 2 sessões no mesmo dia" ou,
    ///   com "Cardio leve depois da força", um aeróbico leve ou moderado com uma força que não é de pernas;
    /// - só fixas no dia: escolha da pessoa, sempre vale.
    func isStructureValid(_ placements: [Placement]) -> Bool {
        let planStrengths = placements.filter { !$0.isFixed && $0.session.kind == .strength }
        let planCardios = placements.filter { !$0.isFixed && $0.session.kind == .cardio }
        guard planStrengths.count <= 1, planCardios.count <= 1 else {
            return false
        }
        let fixedStrengths = placements.filter { $0.isFixed && $0.session.kind == .strength }
        let fixedCardios = placements.filter { $0.isFixed && $0.session.kind == .cardio }
        if !fixedStrengths.isEmpty && !planStrengths.isEmpty {
            return false
        }
        if !fixedCardios.isEmpty && !planCardios.isEmpty {
            return false
        }
        let strengths = planStrengths + fixedStrengths
        let cardios = planCardios + fixedCardios
        let hasPlanSession = !planStrengths.isEmpty || !planCardios.isEmpty
        guard !strengths.isEmpty, !cardios.isEmpty, hasPlanSession else {
            return true
        }
        if preferences.allowsTwoSessionsPerDay {
            return true
        }
        guard preferences.allowsLightCardioAfterStrength else {
            return false
        }
        let strongest = cardios
            .map { $0.session.cardioIntensity ?? .moderate }
            .max { $0.rank < $1.rank } ?? .moderate
        let hasLegs = strengths.contains { $0.session.isLowerBody }
        return strongest != .vigorous && !hasLegs
    }

    /// 48 h (S6): duas forças com algum grupo primário em comum em dias seguidos. Duas fixas entre si não
    /// contam (X4).
    static func sharesMuscles(_ today: [Placement], _ tomorrow: [Placement]) -> Bool {
        for first in today where first.session.kind == .strength {
            for second in tomorrow where second.session.kind == .strength {
                if first.isFixed && second.isFixed {
                    continue
                }
                if !first.session.primaryMuscles.isDisjoint(with: second.session.primaryMuscles) {
                    return true
                }
            }
        }
        return false
    }

    /// Véspera de pernas (A5): um aeróbico forte num dia e uma força de pernas no dia seguinte. Duas fixas
    /// entre si não contam (X4).
    static func isVigorousBeforeLegs(_ today: [Placement], _ tomorrow: [Placement]) -> Bool {
        for cardio in today where cardio.session.kind == .cardio && cardio.session.cardioIntensity == .vigorous {
            for strength in tomorrow where strength.session.kind == .strength && strength.session.isLowerBody {
                if cardio.isFixed && strength.isFixed {
                    continue
                }
                return true
            }
        }
        return false
    }

    // MARK: - Escolha e semana

    /// Os critérios de M4. As fixas contam como as outras sessões: são iguais em toda escolha, então só
    /// empurram as sessões de plano para longe delas. A fixa leve não ocupa lugar e não conta.
    func score(of choice: [[PlanWeekday]]) -> Score {
        let weeks = (0..<orbitLength).map { week(choice, number: $0) }
        let doubleDays = weeks.first?.filter { $0.count >= 2 }.count ?? 0
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

    /// A primeira semana da escolha, com o dia previsto em cada lugar de plano, as fixas e os avisos de M4:
    /// "sem descanso completo" quando os 7 dias têm sessão ou fixa (também a leve); "força antes do cardio"
    /// em cada dia com força e aeróbico em que ao menos um é de plano.
    func schedule(for choice: [[PlanWeekday]]) -> WeekSchedule {
        let days = week(choice, number: 0)
        var slots: [PlannedSlot] = []
        var notes: [FitNote] = []
        var sharedDays: [PlanWeekday] = []
        for (dayIndex, placements) in days.enumerated() {
            guard let weekday = PlanWeekday(rawValue: dayIndex) else {
                continue
            }
            let hasPlanSession = placements.contains { !$0.isFixed }
            if hasPlanSession && WeeklyFitSearch.has(.strength, placements) && WeeklyFitSearch.has(.cardio, placements) {
                sharedDays.append(weekday)
            }
            let hasPlanStrength = placements.contains { !$0.isFixed && $0.session.kind == .strength }
            for placement in placements {
                guard let planIndex = placement.plan else {
                    continue
                }
                let session = placement.session
                let indexInWeek = choice[planIndex].firstIndex(of: weekday) ?? 0
                // A5: no dia com as duas de plano, a força vem antes.
                let orderInDay = session.kind == .cardio && hasPlanStrength ? 1 : 0
                slots.append(PlannedSlot(
                    weekday: weekday,
                    programID: plans[planIndex].programID,
                    indexInWeek: indexInWeek,
                    kind: session.kind,
                    orderInDay: orderInDay,
                    programDayID: session.programDayID,
                    dayName: session.dayName,
                    cardioIntensity: session.kind == .cardio ? session.cardioIntensity : nil
                ))
            }
        }
        let usedDays = Set(choice.flatMap { $0 }).union(fixedDays)
        if usedDays.count == PlanWeekday.allCases.count {
            notes.append(.noFullRestDay)
        }
        notes += sharedDays.map { FitNote.strengthBeforeCardio($0) }
        return WeekSchedule(slots: slots, notes: notes, fixed: fixed)
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

    /// As fixas por dia da semana; no mesmo dia, a ordem recebida (a de `OutsideActivities.fixedDemands`,
    /// que já vem pela hora).
    static func orderedFixed(_ fixed: [FixedActivityDemand]) -> [FixedActivityDemand] {
        fixed.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.weekday != rhs.element.weekday {
                    return lhs.element.weekday < rhs.element.weekday
                }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    /// A fixa como sessão do encaixe (X4): a de força com os grupos dela (e dia de pernas quando algum é de
    /// pernas), a de aeróbico com a intensidade dela (moderada quando falta). A leve não ocupa lugar.
    static func session(for activity: FixedActivityDemand) -> PlanSessionDemand? {
        switch activity.role {
        case .light:
            return nil
        case .strength:
            let isLowerBody = activity.isLowerBody || !activity.primaryMuscles.isDisjoint(with: PlanDemand.lowerBodyGroups)
            return PlanSessionDemand(
                programDayID: activity.id,
                dayName: activity.name,
                kind: .strength,
                primaryMuscles: activity.primaryMuscles,
                isLowerBody: isLowerBody,
                estimatedMinutes: max(0, activity.minutes)
            )
        case .cardio:
            return PlanSessionDemand(
                programDayID: activity.id,
                dayName: activity.name,
                kind: .cardio,
                cardioIntensity: activity.cardioIntensity ?? .moderate,
                estimatedMinutes: max(0, activity.minutes)
            )
        }
    }

    /// Algum plano tem um dia de aeróbico e outro plano tem um dia de força (M5).
    static func mixes(cardioAndStrengthIn plans: [PlanDemand]) -> Bool {
        for (index, plan) in plans.enumerated() where plan.sessions.contains(where: { $0.kind == .cardio }) {
            for (otherIndex, other) in plans.enumerated() where otherIndex != index {
                if other.sessions.contains(where: { $0.kind == .strength }) {
                    return true
                }
            }
        }
        return false
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
