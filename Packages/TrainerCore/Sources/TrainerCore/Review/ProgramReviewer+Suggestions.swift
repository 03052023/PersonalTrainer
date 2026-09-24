import Foundation

// Suggestion side of the periodic review: SPEC §7.8 R3–R6 and §7.11 C2. Every builder
// returns fixed pt-BR text with the numbers that produced it (SPEC R5, R7).

extension ProgramReviewer {
    // MARK: R4 — adherence

    static func reduceDaysSuggestion(attendance: Attendance, programDayCount: Int, week: String) -> ProgramSuggestion {
        let perWeek = Double(attendance.completed) / Double(windowWeeks)
        let fewerDays = programDayCount - 1
        let reason = "Nas últimas 4 semanas você concluiu \(attendance.completed) de "
            + "\(attendance.expected) treinos previstos (\(ReviewText.percent(attendance.completed, of: attendance.expected))), "
            + "cerca de \(ReviewText.number(perWeek)) por semana; um programa de "
            + "\(ReviewText.count(fewerDays, "dia", "dias")) pode caber melhor na sua rotina "
            + "antes de pensar em mais séries."
        return ProgramSuggestion(
            id: "reduceDays:\(week)",
            kind: .reduceDays,
            rule: "R4",
            title: "Treinar menos dias por semana",
            reason: reason,
            referenceTopic: "topic.frequency"
        )
    }

    // MARK: R3 — volume

    /// SPEC R3 for every primary group of the program, in `MuscleGroup.allCases` order.
    ///
    /// Removals (above the ceiling *and* fatigued) are chosen first and a slot changes at
    /// most once per review, so an exercise shared by two groups is never told to gain
    /// and lose a set at the same time: protecting recovery wins (the SPEC R7 order).
    static func volumeSuggestions(
        input: ReviewInput,
        pools: [ExercisePool],
        setsInWindow: [MuscleGroup: Int],
        fatigue: FatigueSignals,
        allowAdditions: Bool,
        week: String
    ) -> [ProgramSuggestion] {
        let muscles = MuscleGroup.allCases.filter { muscle in
            pools.contains { $0.exercise.primaryMuscles.contains(muscle) }
        }
        var changedTargets = Set<UUID>()
        var suggestions: [ProgramSuggestion] = []

        func slots(training muscle: MuscleGroup) -> [(pool: ExercisePool, slot: ExerciseReviewInput)] {
            pools
                .filter { $0.exercise.primaryMuscles.contains(muscle) }
                .flatMap { pool in pool.slots.map { (pool: pool, slot: $0) } }
        }

        if fatigue.isHigh {
            for muscle in muscles {
                let bounds = weeklyBounds(for: muscle, input: input)
                let total = setsInWindow[muscle] ?? 0
                // SPEC R3: strictly above the ceiling (the ceiling itself is in range).
                guard Double(total) > Double(bounds.ceiling) * Double(windowWeeks) else { continue }

                // Most sets first: the cut lands where there is the most to spare.
                let candidates = slots(training: muscle)
                    .filter { $0.slot.sets > minSetsPerExercise }
                    .sorted { lhs, rhs in
                        if lhs.slot.sets != rhs.slot.sets { return lhs.slot.sets > rhs.slot.sets }
                        return lhs.slot.targetID.uuidString < rhs.slot.targetID.uuidString
                    }
                var picked = 0
                for candidate in candidates where picked < maxSetChangesPerMuscle {
                    guard changedTargets.insert(candidate.slot.targetID).inserted else { continue }
                    picked += 1
                    suggestions.append(
                        removeSetsSuggestion(
                            muscle: muscle,
                            total: total,
                            ceiling: bounds.ceiling,
                            exercise: candidate.pool.exercise,
                            slot: candidate.slot,
                            week: week
                        )
                    )
                }
            }
        }

        guard allowAdditions else { return suggestions }

        for muscle in muscles {
            let bounds = weeklyBounds(for: muscle, input: input)
            let total = setsInWindow[muscle] ?? 0
            // SPEC R3: strictly below the minimum (the minimum itself is in range).
            guard bounds.minimum > 0,
                  Double(total) < Double(bounds.minimum) * Double(windowWeeks)
            else { continue }

            // Fewest sets first: spreading the extra sets keeps each exercise short.
            let candidates = slots(training: muscle)
                .filter { $0.slot.sets >= 0 && $0.slot.sets < maxSetsPerExercise }
                .sorted { lhs, rhs in
                    if lhs.slot.sets != rhs.slot.sets { return lhs.slot.sets < rhs.slot.sets }
                    return lhs.slot.targetID.uuidString < rhs.slot.targetID.uuidString
                }
            var picked = 0
            for candidate in candidates where picked < maxSetChangesPerMuscle {
                guard changedTargets.insert(candidate.slot.targetID).inserted else { continue }
                picked += 1
                suggestions.append(
                    addSetsSuggestion(
                        muscle: muscle,
                        total: total,
                        bounds: bounds,
                        target: input.weeklySetTarget,
                        exercise: candidate.pool.exercise,
                        slot: candidate.slot,
                        week: week
                    )
                )
            }
        }
        return suggestions
    }

    /// Weekly working-set bounds of a group: the goal range, with `muscleTargets`
    /// overriding the minimum (a ceiling below an overridden minimum is raised to it).
    static func weeklyBounds(for muscle: MuscleGroup, input: ReviewInput) -> (minimum: Int, ceiling: Int) {
        let minimum = max(0, input.muscleTargets?[muscle] ?? input.weeklySetTarget.lowerBound)
        return (minimum, max(input.weeklySetTarget.upperBound, minimum))
    }

    static func addSetsSuggestion(
        muscle: MuscleGroup,
        total: Int,
        bounds: (minimum: Int, ceiling: Int),
        target: ClosedRange<Int>,
        exercise: ExerciseDefinition,
        slot: ExerciseReviewInput,
        week: String
    ) -> ProgramSuggestion {
        let average = Double(total) / Double(windowWeeks)
        let newSets = slot.sets + 1
        let reason = "\(ReviewText.capitalizingFirstLetter(ReviewText.muscleName(muscle))) teve em média "
            + "\(ReviewText.number(average)) séries por semana nas últimas 4 semanas, abaixo da meta de "
            + "\(bounds.minimum) (faixa do objetivo: \(target.lowerBound) a \(target.upperBound)); "
            + "passar \(exercise.name) de \(slot.sets) para \(newSets) séries aproxima da meta."
        return ProgramSuggestion(
            id: "addSets:\(muscle.rawValue):\(slot.targetID.uuidString):\(week)",
            kind: .addSets,
            rule: "R3",
            title: "Mais uma série de \(exercise.name)",
            reason: reason,
            targetIDs: [slot.targetID],
            muscle: muscle,
            proposedSets: newSets,
            referenceTopic: "topic.volume"
        )
    }

    static func removeSetsSuggestion(
        muscle: MuscleGroup,
        total: Int,
        ceiling: Int,
        exercise: ExerciseDefinition,
        slot: ExerciseReviewInput,
        week: String
    ) -> ProgramSuggestion {
        let average = Double(total) / Double(windowWeeks)
        let newSets = slot.sets - 1
        let reason = "\(ReviewText.capitalizingFirstLetter(ReviewText.muscleName(muscle))) teve em média "
            + "\(ReviewText.number(average)) séries por semana nas últimas 4 semanas, acima do teto de "
            + "\(ceiling), e há sinais de cansaço; passar \(exercise.name) de \(slot.sets) para "
            + "\(newSets) séries ajuda a recuperar."
        return ProgramSuggestion(
            id: "removeSets:\(muscle.rawValue):\(slot.targetID.uuidString):\(week)",
            kind: .removeSets,
            rule: "R3",
            title: "Uma série a menos de \(exercise.name)",
            reason: reason,
            targetIDs: [slot.targetID],
            muscle: muscle,
            proposedSets: newSets,
            referenceTopic: "topic.volume"
        )
    }

    // MARK: R5 — deload

    /// SPEC R5: a lighter week when R2 fires or when ≥ 50 % of the exercises stagnate.
    /// The rule shown is the first signal that fired (R2 before R1); the reason lists all.
    static func deloadSuggestion(
        fatigue: FatigueSignals,
        stagnantCount: Int?,
        exerciseCount: Int,
        week: String
    ) -> ProgramSuggestion {
        var causes: [String] = []
        if fatigue.byReserve {
            causes.append(
                "nas últimas 2 semanas, \(fatigue.zeroReserveSets) de \(fatigue.ratedSets) séries "
                    + "(\(ReviewText.percent(fatigue.zeroReserveSets, of: fatigue.ratedSets))) "
                    + "terminaram sem nenhuma repetição de sobra"
            )
        }
        if fatigue.byPrescriptions {
            causes.append(
                "em \(fatigue.strugglingPrescriptions) de \(fatigue.judgedPrescriptions) exercícios "
                    + "(\(ReviewText.percent(fatigue.strugglingPrescriptions, of: fatigue.judgedPrescriptions))) "
                    + "a última sessão ficou abaixo do mínimo de repetições"
            )
        }
        if let stagnantCount {
            causes.append(
                "\(stagnantCount) de \(exerciseCount) exercícios "
                    + "(\(ReviewText.percent(stagnantCount, of: exerciseCount))) não melhoram há pelo "
                    + "menos \(stagnationSessions) sessões"
            )
        }
        let reason = ReviewText.capitalizingFirstLetter(causes.joined(separator: "; "))
            + ". Uma semana com menos séries e cargas um pouco menores ajuda o corpo a se recuperar "
            + "e a voltar a progredir."
        return ProgramSuggestion(
            id: "deload:\(week)",
            kind: .deload,
            rule: fatigue.isHigh ? "R2" : "R1",
            title: "Semana mais leve",
            reason: reason,
            referenceTopic: "rule.D"
        )
    }

    // MARK: R5 — exercise changes

    /// SPEC R5 for one stagnant exercise: swap it after `swapSessions` sessions without
    /// progress (one suggestion for all its slots), otherwise move each slot to the
    /// neighbouring rep range.
    static func exerciseChangeSuggestions(for pool: ExercisePool, week: String) -> [ProgramSuggestion] {
        guard let progress = pool.progress else { return [] }
        let name = pool.exercise.name
        let stall = "\(name) está há \(progress.sessionsWithoutProgress) sessões sem superar sua melhor "
            + "marca estimada (\(ReviewText.estimate(progress.bestE1RM, unit: pool.exercise.loadUnit)))"

        if progress.sessionsWithoutProgress >= swapSessions {
            return [
                ProgramSuggestion(
                    id: "swapExercise:\(pool.exercise.id.uuidString):\(week)",
                    kind: .swapExercise,
                    rule: "R1",
                    title: "Trocar \(name) por um exercício parecido",
                    reason: stall + "; um exercício diferente para os mesmos músculos renova o estímulo, "
                        + "e as cargas dos outros exercícios continuam.",
                    targetIDs: pool.slots.map(\.targetID),
                    referenceTopic: "topic.substitution"
                ),
            ]
        }

        return pool.slots.compactMap { slot -> ProgramSuggestion? in
            guard let range = neighbouringRepRange(repMin: slot.repMin, repMax: slot.repMax) else {
                return nil
            }
            return ProgramSuggestion(
                id: "changeRepRange:\(slot.targetID.uuidString):\(week)",
                kind: .changeRepRange,
                rule: "R1",
                title: "Outra faixa de repetições em \(name)",
                reason: stall + "; trocar a faixa de \(slot.repMin)–\(slot.repMax) para "
                    + "\(range.lowerBound)–\(range.upperBound) repetições muda o estímulo.",
                targetIDs: [slot.targetID],
                proposedRepRange: range,
                referenceTopic: "topic.substitution"
            )
        }
    }

    /// The range `repRangeShift` reps lower, keeping its width (8–12 → 6–10). When that
    /// would take `repMin` below `lowestRepMin`, the range moves up instead (3–6 → 5–8).
    /// `nil` for an invalid range.
    static func neighbouringRepRange(repMin: Int, repMax: Int) -> ClosedRange<Int>? {
        guard repMin >= 1, repMax >= repMin, repMax <= Int.max - repRangeShift else { return nil }
        if repMin - repRangeShift >= lowestRepMin {
            return (repMin - repRangeShift)...(repMax - repRangeShift)
        }
        return (repMin + repRangeShift)...(repMax + repRangeShift)
    }

    // MARK: C2 — end of the mesocycle

    /// SPEC §7.11 C2: after `mesocycleWeeks` weeks on the same program, suggest switching
    /// (always optional; loads are kept because history is per exercise, SPEC §7.1).
    static func switchProgramSuggestion(
        input: ReviewInput,
        now: Date,
        calendar: Calendar,
        week: String
    ) -> ProgramSuggestion? {
        guard let start = input.programStartDate, input.mesocycleWeeks > 0 else { return nil }
        let (days, overflow) = input.mesocycleWeeks.multipliedReportingOverflow(by: 7)
        guard !overflow,
              let due = calendar.date(byAdding: .day, value: days, to: start),
              due <= now
        else { return nil }

        let weeks = (calendar.dateComponents([.day], from: start, to: now).day ?? days) / 7
        let reason = "Você treina com o programa \(input.programName) há "
            + "\(ReviewText.count(weeks, "semana", "semanas")); depois de "
            + "\(ReviewText.count(input.mesocycleWeeks, "semana", "semanas")), mudar de programa "
            + "renova o estímulo, e as cargas de cada exercício são mantidas."
        return ProgramSuggestion(
            id: "switchProgram:\(input.programID.uuidString):\(week)",
            kind: .switchProgram,
            rule: "R5",
            title: "Experimentar um novo programa",
            reason: reason,
            strength: .optional,
            referenceTopic: "topic.substitution"
        )
    }

    // MARK: R6 — recovery modulation

    /// SPEC R6: aggregated recovery trends only change the strength of suggestions R1–R5
    /// already produced; they never add or remove one and never touch a load (SPEC P12).
    ///
    /// - HRV down or resting heart rate up: deload stays recommended (reinforced) and
    ///   extra sets become optional.
    /// - Stable trends and no R2 fatigue: a deload (then triggered by stagnation alone)
    ///   becomes optional.
    static func modulated(
        _ suggestions: [ProgramSuggestion],
        recovery: RecoveryContext,
        fatigueHigh: Bool
    ) -> [ProgramSuggestion] {
        guard recovery.hasData else { return suggestions }

        if recovery.isStrained {
            let trend = strainDescription(recovery)
            return suggestions.map { suggestion in
                switch suggestion.kind {
                case .deload:
                    return suggestion.modulated(
                        to: .recommended,
                        adding: "Na última semana \(trend) em relação ao último mês, o que reforça a pausa."
                    )
                case .addSets:
                    return suggestion.modulated(
                        to: .optional,
                        adding: "Fica opcional porque, na última semana, \(trend) em relação ao último mês."
                    )
                default:
                    return suggestion
                }
            }
        }

        if recovery.isStable, !fatigueHigh {
            return suggestions.map { suggestion in
                guard suggestion.kind == .deload else { return suggestion }
                return suggestion.modulated(
                    to: .optional,
                    adding: "Fica opcional porque seus sinais de recuperação estão estáveis e não há "
                        + "sinais de cansaço."
                )
            }
        }

        return suggestions
    }

    private static func strainDescription(_ recovery: RecoveryContext) -> String {
        var parts: [String] = []
        if recovery.hrvDropped {
            parts.append("a variabilidade da frequência cardíaca caiu")
        }
        if recovery.restingHeartRateRose {
            parts.append("a frequência cardíaca de repouso subiu")
        }
        return parts.joined(separator: " e ")
    }
}
