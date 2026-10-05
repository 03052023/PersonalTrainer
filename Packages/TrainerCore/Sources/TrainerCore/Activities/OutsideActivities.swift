import Foundation

/// Regras das atividades fora do app (SPEC §7.17 X1–X8, RF-53; docs/V24-CONTRACT.md §3.1). Funções puras:
/// sem `Date()`, sem aleatório, sem frequência cardíaca (P11, P12, AGENTS R3). Quem chama passa os
/// registros, a semana e o calendário.
///
/// Nada daqui muda a prescrição, a semana leve ou a revisão (X7): os registros só entram no aeróbico da
/// semana (X3), no encaixe com dois planos (X4), na recuperação (X5) e no equilíbrio e na mobilidade da
/// Longevidade (X6).
public enum OutsideActivities: Sendable {
    /// X1: duração aceita, em minutos inteiros.
    public static let minutesRange: ClosedRange<Int> = 5...300
    /// X2: quantas fixas a pessoa pode ter.
    public static let maxFixed: Int = 10
    /// X3: fração da duração do registro que, coberta por um treino aeróbico do app Saúde, faz o registro
    /// não contar (o relógio já contou; mesmo critério do RF-13).
    public static let minimumOverlapFraction: Double = 0.5
    /// X6: vezes por semana de equilíbrio e de mobilidade (§7.9: 2–3×/semana).
    public static let longevityWeeklyTarget: Int = 2
    /// X6: duração do registro que o "Feito" do C8 grava.
    public static let longevityEntryMinutes: Int = 10
    /// X5: descanso de um grupo depois de uma atividade de força (S6).
    public static let strengthRecoveryHours: Double = 48
    /// X5: descanso das pernas depois de um aeróbico forte (A5).
    public static let vigorousCardioRecoveryHours: Double = 24
    /// Os grupos de pernas de A5 (os mesmos de `PlanDemand.lowerBodyGroups`).
    public static let legMuscles: Set<MuscleGroup> = PlanDemand.lowerBodyGroups

    // MARK: - X1

    /// A duração cabe em `minutesRange`.
    public static func isValidMinutes(_ minutes: Int) -> Bool {
        minutesRange.contains(minutes)
    }

    // MARK: - Semana

    /// Os registros que começam na semana `[início, fim)`, por início (empate pelo id).
    public static func entries(_ entries: [OutsideActivityEntry], in week: DateInterval) -> [OutsideActivityEntry] {
        entries
            .filter { $0.start >= week.start && $0.start < week.end }
            .sorted(by: Self.precedes)
    }

    // MARK: - X2 Fixas

    /// As fixas de um dia da semana, pela hora (empate pelo id).
    public static func fixed(_ fixed: [FixedOutsideActivity], on weekday: PlanWeekday) -> [FixedOutsideActivity] {
        fixed
            .filter { $0.weekday == weekday }
            .sorted { lhs, rhs in
                if lhs.startMinuteOfDay != rhs.startMinuteOfDay {
                    return lhs.startMinuteOfDay < rhs.startMinuteOfDay
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// A fixa já tem o "Feito" de `day` (um registro com o id dela no mesmo dia do calendário).
    public static func isLogged(
        _ fixed: FixedOutsideActivity,
        on day: Date,
        entries: [OutsideActivityEntry],
        calendar: Calendar
    ) -> Bool {
        entries.contains { entry in
            entry.fixedActivityID == fixed.id && calendar.isDate(entry.start, inSameDayAs: day)
        }
    }

    /// O registro que o "Feito" de uma fixa grava em `day`: o tipo, a duração e a intensidade dela, com o
    /// início na hora dela (X2).
    public static func entry(
        loggingFixed fixed: FixedOutsideActivity,
        on day: Date,
        calendar: Calendar,
        id: UUID = UUID()
    ) -> OutsideActivityEntry {
        let minute = min(max(fixed.startMinuteOfDay, 0), 24 * 60 - 1)
        let start = calendar.startOfDay(for: day).addingTimeInterval(TimeInterval(minute) * 60)
        return OutsideActivityEntry(
            id: id,
            kind: fixed.kind,
            start: start,
            minutes: fixed.minutes,
            intensity: fixed.intensity,
            fixedActivityID: fixed.id
        )
    }

    // MARK: - X3 Aeróbico

    /// Conta no aeróbico: tipo aeróbico, intensidade moderada ou forte e duração positiva.
    public static func countsTowardAerobic(_ entry: OutsideActivityEntry) -> Bool {
        entry.kind.countsAsAerobic && entry.intensity != .light && entry.minutes > 0
    }

    /// Os registros que contam no aeróbico, como treinos sem leitura do relógio com a intensidade declarada,
    /// para somar aos treinos do app Saúde no relatório de saúde (A1). Fica de fora o registro que um treino
    /// de `healthWorkouts` cobre em pelo menos `minimumOverlapFraction` da duração (o relógio já contou).
    /// A duração conta até o teto de X1 (`minutesRange`), como em `aerobicMinutes(entries:week:)`.
    public static func aerobicSamples(
        entries: [OutsideActivityEntry],
        excludingOverlapWith healthWorkouts: [AerobicWorkoutSample]
    ) -> [AerobicWorkoutSample] {
        entries
            .filter { Self.countsTowardAerobic($0) && !Self.isCovered($0, by: healthWorkouts) }
            .sorted(by: Self.precedes)
            .map { (entry: OutsideActivityEntry) -> AerobicWorkoutSample in
                AerobicWorkoutSample(
                    id: entry.id,
                    activity: entry.kind.aerobicActivity,
                    start: entry.start,
                    end: Self.countedEnd(of: entry),
                    declaredIntensity: entry.intensity == .vigorous ? .vigorous : .moderate
                )
            }
    }

    /// Minutos moderados-equivalentes dos registros da semana (moderado conta 1, forte conta 2), para as
    /// Metas da semana sem o app Saúde (W4, X3).
    public static func aerobicMinutes(entries: [OutsideActivityEntry], week: DateInterval) -> Int {
        Self.entries(entries, in: week)
            .filter { Self.countsTowardAerobic($0) }
            .reduce(0) { (total: Int, entry: OutsideActivityEntry) -> Int in
                let minutes = Self.countedMinutes(of: entry)
                return total + (entry.intensity == .vigorous ? 2 * minutes : minutes)
            }
    }

    // MARK: - X4 Encaixe

    /// As fixas como o encaixe as vê, por dia, hora e id.
    public static func fixedDemands(_ fixed: [FixedOutsideActivity]) -> [FixedActivityDemand] {
        fixed
            .sorted { lhs, rhs in
                if lhs.weekday != rhs.weekday {
                    return lhs.weekday < rhs.weekday
                }
                if lhs.startMinuteOfDay != rhs.startMinuteOfDay {
                    return lhs.startMinuteOfDay < rhs.startMinuteOfDay
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { (activity: FixedOutsideActivity) -> FixedActivityDemand in
                let role = activity.kind.role
                let muscles: Set<MuscleGroup> = role == .strength ? activity.kind.primaryMuscles : []
                return FixedActivityDemand(
                    id: activity.id,
                    name: activity.kind.displayName,
                    weekday: activity.weekday,
                    role: role,
                    primaryMuscles: muscles,
                    isLowerBody: !muscles.isDisjoint(with: legMuscles),
                    cardioIntensity: role == .cardio ? activity.intensity : nil,
                    minutes: activity.minutes
                )
            }
    }

    // MARK: - X5 Recuperação

    /// O que os registros pedem de descanso para S6: força moderada ou forte, os grupos dela por 48 h;
    /// aeróbico forte, as pernas por 24 h (A5). Leve nunca conta.
    public static func recoveryLoads(entries: [OutsideActivityEntry]) -> [RecoveryLoad] {
        entries.sorted(by: Self.precedes).compactMap { (entry: OutsideActivityEntry) -> RecoveryLoad? in
            guard entry.intensity != .light, entry.minutes > 0 else {
                return nil
            }
            switch entry.kind.role {
            case .strength:
                let muscles = entry.kind.primaryMuscles
                guard !muscles.isEmpty else {
                    return nil
                }
                return RecoveryLoad(start: entry.start, muscles: muscles, hours: strengthRecoveryHours)
            case .cardio:
                guard entry.intensity == .vigorous else {
                    return nil
                }
                return RecoveryLoad(start: entry.start, muscles: legMuscles, hours: vigorousCardioRecoveryHours)
            case .light:
                return nil
            }
        }
    }

    /// Os registros de força com pernas, como sessões de treino de inferior para o encaixe do aeróbico do
    /// relatório de saúde (A5). Só servem para `HealthInput.recentSessions`: nunca entram no planejador.
    public static func placementSessions(entries: [OutsideActivityEntry]) -> [SessionSummary] {
        entries.sorted(by: Self.precedes).compactMap { (entry: OutsideActivityEntry) -> SessionSummary? in
            guard entry.kind.role == .strength, entry.intensity != .light, entry.minutes > 0 else {
                return nil
            }
            let muscles = entry.kind.primaryMuscles
            guard !muscles.isDisjoint(with: legMuscles) else {
                return nil
            }
            return SessionSummary(
                id: entry.id,
                programDayID: entry.id,
                startedAt: entry.start,
                endedAt: entry.end,
                status: .completed,
                primaryMusclesTrained: muscles,
                workingSetCount: 1
            )
        }
    }

    // MARK: - X6 Equilíbrio e mobilidade

    /// Vezes de equilíbrio e de mobilidade na semana, pelas chaves do C8 (`CoachInput.balanceKey`,
    /// `CoachInput.mobilityKey`).
    public static func longevityCounts(entries: [OutsideActivityEntry], week: DateInterval) -> [String: Int] {
        var counts: [String: Int] = [:]
        for entry in Self.entries(entries, in: week) {
            switch entry.kind {
            case .balance:
                counts[CoachInput.balanceKey, default: 0] += 1
            case .mobility:
                counts[CoachInput.mobilityKey, default: 0] += 1
            default:
                continue
            }
        }
        return counts
    }

    /// O registro que o "Feito" do C8 grava (X6): 10 min leves do bloco. `nil` para uma chave desconhecida.
    public static func longevityEntry(key: String, at date: Date, id: UUID = UUID()) -> OutsideActivityEntry? {
        let kind: OutsideActivityKind
        switch key {
        case CoachInput.balanceKey:
            kind = .balance
        case CoachInput.mobilityKey:
            kind = .mobility
        default:
            return nil
        }
        return OutsideActivityEntry(
            id: id,
            kind: kind,
            start: date,
            minutes: longevityEntryMinutes,
            intensity: .light
        )
    }

    // MARK: - Apoio

    /// Ordem estável dos registros: início e depois id (P11).
    static func precedes(_ lhs: OutsideActivityEntry, _ rhs: OutsideActivityEntry) -> Bool {
        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// A duração que conta (X1): de 0 ao teto de `minutesRange`. Um registro fora da faixa só chega por um
    /// arquivo antigo ou editado à mão; ele não pode inflar a semana.
    static func countedMinutes(of entry: OutsideActivityEntry) -> Int {
        min(max(entry.minutes, 0), minutesRange.upperBound)
    }

    /// Início + a duração que conta.
    static func countedEnd(of entry: OutsideActivityEntry) -> Date {
        entry.start.addingTimeInterval(TimeInterval(Self.countedMinutes(of: entry)) * 60)
    }

    /// Um treino de `workouts` cobre ao menos `minimumOverlapFraction` da duração do registro (X3, o mesmo
    /// critério do RF-13). Cada treino é olhado sozinho: dois treinos curtos não somam.
    static func isCovered(_ entry: OutsideActivityEntry, by workouts: [AerobicWorkoutSample]) -> Bool {
        let end = Self.countedEnd(of: entry)
        let duration = end.timeIntervalSince(entry.start)
        guard duration > 0 else {
            return false
        }
        return workouts.contains { (workout: AerobicWorkoutSample) -> Bool in
            let overlap = min(end, workout.end).timeIntervalSince(max(entry.start, workout.start))
            return overlap >= duration * minimumOverlapFraction
        }
    }
}
