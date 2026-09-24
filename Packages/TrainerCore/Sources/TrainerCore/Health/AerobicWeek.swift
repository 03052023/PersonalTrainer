import Foundation

/// Minutos aeróbicos da semana por intensidade (SPEC §7.10 A1/A2, RF-27).
///
/// - Só entram treinos cuja data de **início** cai na semana `[segunda 00:00, próxima segunda)` do
///   calendário recebido (mesma semana de §7.4); o treino inteiro conta no dia do seu início.
/// - Cada minuto com FC é classificado por `HeartRateZones`; leve não conta.
/// - Minutos sem FC (treino sem amostras, leitura inválida ou FC mais curta que o treino) e treinos
///   sem zonas (sem idade e sem FCmáx informada) usam `AerobicActivity.defaultIntensity`.
/// - Moderados-equivalentes = moderado + 2 × vigoroso (OMS 2020; Bull et al. 2020).
enum AerobicWeek {
    /// Teto de minutos contados por treino (uma semana). Só protege contra dado corrompido (fim muito
    /// depois do início) para que a soma em `Int` nunca estoure (ADR 011); nenhum treino real chega perto.
    static let maxMinutesPerWorkout = 7 * 24 * 60

    /// Minutos de um treino por intensidade.
    struct Minutes: Hashable {
        var light = 0
        var moderate = 0
        var vigorous = 0
    }

    static func summary(
        workouts: [AerobicWorkoutSample],
        zones: HeartRateZones?,
        week: DateInterval,
        target: Int,
        calendar: Calendar
    ) -> AerobicWeekSummary {
        let days = (0..<7).map { HealthDays.adding($0, to: week.start, calendar: calendar) }
        var moderateByDay = Array(repeating: 0, count: 7)
        var vigorousByDay = Array(repeating: 0, count: 7)

        for workout in uniqueWorkouts(workouts) {
            // Semana semiaberta: `DateInterval.contains` incluiria a segunda-feira seguinte 00:00.
            guard workout.start >= week.start, workout.start < week.end else { continue }
            let dayIndex = HealthDays.daysBetween(week.start, workout.start, calendar: calendar)
            guard days.indices.contains(dayIndex) else { continue }
            let counted = minutes(of: workout, zones: zones)
            moderateByDay[dayIndex] += counted.moderate
            vigorousByDay[dayIndex] += counted.vigorous
        }

        let moderate = moderateByDay.reduce(0, +)
        let vigorous = vigorousByDay.reduce(0, +)
        let perDay = days.indices.map {
            DailyAerobicMinutes(day: days[$0], moderate: moderateByDay[$0], vigorous: vigorousByDay[$0])
        }
        return AerobicWeekSummary(
            moderateMinutes: moderate,
            vigorousMinutes: vigorous,
            moderateEquivalentMinutes: moderateEquivalent(moderate: moderate, vigorous: vigorous),
            target: target,
            perDay: perDay
        )
    }

    /// OMS 2020: 1 min vigoroso = 2 min moderados.
    static func moderateEquivalent(moderate: Int, vigorous: Int) -> Int {
        moderate + 2 * vigorous
    }

    /// Classifica os minutos de um treino (SPEC §7.10 A1). A duração vem de `end − start`, arredondada
    /// ao minuto; `minuteHeartRates[i]` é a FC do minuto `i`. Entradas além da duração (minuto parcial
    /// no fim) são ignoradas.
    static func minutes(of workout: AerobicWorkoutSample, zones: HeartRateZones?) -> Minutes {
        let seconds = max(0, workout.end.timeIntervalSince(workout.start))
        let total = min(HealthMath.roundedInt(seconds / 60), maxMinutesPerWorkout)
        var result = Minutes()
        guard total > 0 else { return result }

        let fallback = workout.activity.defaultIntensity
        var classified = 0
        for heartRate in workout.minuteHeartRates.prefix(total) {
            add(zones?.intensity(forHeartRate: heartRate) ?? fallback, to: &result)
            classified += 1
        }
        // Minutos sem leitura de FC: intensidade padrão do tipo de treino (A1).
        let withoutHeartRate = total - classified
        switch fallback {
        case .light: result.light += withoutHeartRate
        case .moderate: result.moderate += withoutHeartRate
        case .vigorous: result.vigorous += withoutHeartRate
        }
        return result
    }

    private static func add(_ intensity: AerobicIntensity, to minutes: inout Minutes) {
        switch intensity {
        case .light: minutes.light += 1
        case .moderate: minutes.moderate += 1
        case .vigorous: minutes.vigorous += 1
        }
    }

    /// Um treino por `id` (o mesmo `HKWorkout` lido duas vezes conta uma vez). Ordena antes de
    /// descartar repetidos para que a escolha não dependa da ordem de entrada (SPEC §7.10 A6).
    static func uniqueWorkouts(_ workouts: [AerobicWorkoutSample]) -> [AerobicWorkoutSample] {
        let ordered = workouts.sorted { lhs, rhs in
            if lhs.id != rhs.id { return lhs.id.uuidString < rhs.id.uuidString }
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.end != rhs.end { return lhs.end > rhs.end }
            if lhs.activity != rhs.activity { return lhs.activity.rawValue < rhs.activity.rawValue }
            if lhs.minuteHeartRates.count != rhs.minuteHeartRates.count {
                return lhs.minuteHeartRates.count > rhs.minuteHeartRates.count
            }
            return lhs.minuteHeartRates.lexicographicallyPrecedes(rhs.minuteHeartRates)
        }
        var seen = Set<UUID>()
        return ordered.filter { seen.insert($0.id).inserted }
    }
}
