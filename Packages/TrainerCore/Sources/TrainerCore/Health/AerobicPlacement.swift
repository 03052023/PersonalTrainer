import Foundation

/// Encaixe do aeróbico longe do treino de inferior (SPEC §7.10 A5, RF-30): decide o que dá para
/// sugerir **hoje** a partir das sessões de musculação recentes.
///
/// - Sessão de inferior = `primaryMusclesTrained` contém quadríceps, posteriores, glúteos ou panturrilhas.
/// - Se a sessão de inferior mais recente terminou há < 24 h → hoje só baixo impacto leve (caminhada,
///   bicicleta), e com ≥ 6 h de intervalo depois do treino; nunca corrida/HIIT.
/// - Senão → hoje pode ser vigoroso. O app não conhece os próximos treinos (o `HealthInput` só traz
///   sessões passadas), então o texto da sugestão sempre lembra de evitar vigoroso na véspera e no dia
///   do treino de pernas.
///
/// Base: interferência do treino concorrente na hipertrofia e na força é pequena e depende de volume,
/// modalidade e proximidade das sessões (Wilson 2012; Schumann 2022).
enum AerobicPlacement: Hashable {
    /// Nenhum treino de inferior nas últimas 24 h.
    case vigorousAllowed
    /// Treino de inferior terminou há `hoursSinceLowerBody` horas (< 24).
    case lowImpactOnly(hoursSinceLowerBody: Double)

    /// Grupos que fazem de uma sessão um "treino de inferior" (A5).
    static let lowerBodyMuscles: Set<MuscleGroup> = [.quads, .hamstrings, .glutes, .calves]
    /// Janela sem aeróbico vigoroso depois de um treino de inferior.
    static let recoveryWindowHours = 24.0
    /// Intervalo mínimo entre o treino de inferior e um aeróbico no mesmo dia.
    static let sameDayGapHours = 6.0

    static func isLowerBody(_ session: SessionSummary) -> Bool {
        !session.primaryMusclesTrained.isDisjoint(with: lowerBodyMuscles)
    }

    /// Instante em que a sessão de inferior mais recente terminou (fim, ou início se ainda não tem fim),
    /// limitado a `now`. Sessões que começam depois de `now` são ignoradas.
    static func lastLowerBodyEnd(sessions: [SessionSummary], now: Date) -> Date? {
        sessions
            .filter { $0.startedAt <= now && isLowerBody($0) }
            .map { min($0.endedAt ?? $0.startedAt, now) }
            .max()
    }

    static func today(sessions: [SessionSummary], now: Date) -> AerobicPlacement {
        guard let end = lastLowerBodyEnd(sessions: sessions, now: now) else { return .vigorousAllowed }
        let hours = now.timeIntervalSince(end) / 3_600
        guard hours < recoveryWindowHours else { return .vigorousAllowed }
        return .lowImpactOnly(hoursSinceLowerBody: max(0, hours))
    }
}
