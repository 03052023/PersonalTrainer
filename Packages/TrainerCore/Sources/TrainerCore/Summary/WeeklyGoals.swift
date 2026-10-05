import Foundation

/// Metas da semana (SPEC RF-52, §7.16; docs/V23-UI-CONTRACT.md §4.3): reúne o progresso da semana em
/// linhas só de leitura (§7.16 W6), sem tocar o motor nem a prescrição (SPEC P12). Código puro, sem
/// `Date()` (AGENTS R3) e sem frequência cardíaca de musculação (AGENTS R2): tudo já chega calculado em
/// `WeeklyGoalsInput`.
public enum WeeklyGoals: Sendable {
    /// As metas, na ordem de W2. Sessões (uma por plano ativo, o principal primeiro), músculos,
    /// aeróbico (com as atividades fora do app, SPEC §7.17 X3), passos (W7: só com Longevidade ou Cardio
    /// ativos), sono e, só com a Longevidade ativa (principal ou não), equilíbrio e mobilidade (X6). As
    /// atividades fora do app não entram nos músculos (X5).
    public static func goals(_ input: WeeklyGoalsInput) -> [WeeklyGoal] {
        var result: [WeeklyGoal] = []
        result.append(contentsOf: planSessionGoals(input))
        if let muscles = musclesGoal(input) {
            result.append(muscles)
        }
        result.append(aerobicGoal(input))
        if showsSteps(activeGoals: input.activeGoals) {
            result.append(stepsGoal(input))
        }
        result.append(sleepGoal(input))
        if input.activeGoals.contains(.longevity) {
            result.append(contentsOf: longevityGoals(input))
        }
        return result
    }

    /// W7 (decisão do dono, item 18, prevalece sobre o item 17): a meta de passos, nas Metas da semana
    /// e em qualquer outro lugar do app (cartão e detalhe de Saúde, sugestão de passos baixos), só
    /// aparece com um plano ativo de Longevidade ou de Cardio.
    public static func showsSteps(activeGoals: [ProgramGoal]) -> Bool {
        activeGoals.contains(.longevity) || activeGoals.contains(.endurance)
    }

    // MARK: - W2.1 Sessões

    private static func planSessionGoals(_ input: WeeklyGoalsInput) -> [WeeklyGoal] {
        input.plans.map { plan in
            WeeklyGoal(
                kind: .planSessions,
                programID: plan.programID,
                planGoal: plan.goal,
                done: Double(plan.completed),
                // Um plano sem dias devolve `perWeek == 0` (PlanWeekProgress); o piso de 1 evita uma
                // meta zero (WeeklyGoal exige target > 0) sem esconder a linha do plano.
                target: Double(max(plan.perWeek, 1)),
                referenceTopic: plan.goal.referenceTopic
            )
        }
    }

    // MARK: - W2.2 Músculos

    /// A marca (fração) é a soma de `min(feito, meta)` dividida pela soma das metas (peso maior aos
    /// grupos com meta maior); o número em palavras é a contagem de grupos com a meta cumprida contra
    /// o total de grupos com meta — dois números diferentes de propósito, por isso `fraction` é
    /// passado à parte de `done`/`target` (SPEC §7.16 W2.2, W3).
    private static func musclesGoal(_ input: WeeklyGoalsInput) -> WeeklyGoal? {
        let entries = input.frequency.entries.filter { $0.target > 0 }
        guard !entries.isEmpty else {
            return nil
        }
        let groupsMet = entries.filter { $0.completed >= $0.target }.count
        let sumMin = entries.reduce(0.0) { $0 + Double(min($1.completed, $1.target)) }
        let sumTarget = entries.reduce(0.0) { $0 + Double($1.target) }
        return WeeklyGoal(
            kind: .muscles,
            done: Double(groupsMet),
            target: Double(entries.count),
            referenceTopic: "topic.frequency",
            fraction: sumTarget > 0 ? sumMin / sumTarget : 0
        )
    }

    // MARK: - W2.3 Aeróbico

    /// `AerobicWeekSummary` não distingue "nenhum treino registrado" de "sem dado": a única forma de
    /// saber que o Saúde não tem informação é `input.health` inteiro ser `nil` (W4).
    ///
    /// Com o app Saúde, o relatório já traz as atividades fora do app (X3). Sem ele, valem os minutos das
    /// atividades registradas, quando há algum (W2.3); sem os dois, "sem dados" (W4).
    private static func aerobicGoal(_ input: WeeklyGoalsInput) -> WeeklyGoal {
        let done: Double?
        if let health = input.health {
            done = Double(health.aerobic.moderateEquivalentMinutes)
        } else if input.outsideAerobicMinutes > 0 {
            done = Double(input.outsideAerobicMinutes)
        } else {
            done = nil
        }
        return WeeklyGoal(
            kind: .aerobic,
            done: done,
            target: Double(input.targets.weeklyModerateEquivalentMinutes),
            referenceTopic: "topic.aerobic"
        )
    }

    // MARK: - W2.4 Passos (W7)

    private static func stepsGoal(_ input: WeeklyGoalsInput) -> WeeklyGoal {
        WeeklyGoal(
            kind: .steps,
            done: input.health?.steps.average7.map(Double.init),
            target: Double(input.targets.dailySteps),
            referenceTopic: "topic.steps"
        )
    }

    // MARK: - W2.5 Sono

    private static func sleepGoal(_ input: WeeklyGoalsInput) -> WeeklyGoal {
        WeeklyGoal(
            kind: .sleep,
            done: input.health?.recovery.sleep7,
            target: input.targets.sleepHours,
            referenceTopic: "topic.sleep"
        )
    }

    // MARK: - W2.6 Equilíbrio e mobilidade (só com a Longevidade ativa)

    /// Cada um conta as vezes registradas na semana (X6: os registros de equilíbrio ou de mobilidade,
    /// inclusive o "Feito" do C8) contra 2 (`OutsideActivities.longevityWeeklyTarget`). Um "Feito" do C8
    /// dado antes da 2.4, sem registro, vale 1.
    private static func longevityGoals(_ input: WeeklyGoalsInput) -> [WeeklyGoal] {
        [
            longevityGoal(.balance, key: CoachInput.balanceKey, input: input),
            longevityGoal(.mobility, key: CoachInput.mobilityKey, input: input),
        ]
    }

    private static func longevityGoal(_ kind: WeeklyGoalKind, key: String, input: WeeklyGoalsInput) -> WeeklyGoal {
        let logged = max(input.longevityCounts[key] ?? 0, 0)
        let marked = input.longevityDone.contains(key) ? 1 : 0
        return WeeklyGoal(
            kind: kind,
            done: Double(max(logged, marked)),
            target: Double(OutsideActivities.longevityWeeklyTarget),
            referenceTopic: ProgramGoal.longevity.referenceTopic
        )
    }
}
