import Foundation

/// Tudo que o painel de saúde (SPEC §7.10) precisa, já agregado pelo serviço de HealthKit do app.
/// Nenhum campo aqui entra no motor de prescrição (SPEC P12, AGENTS R2).
public struct HealthInput: Codable, Sendable, Hashable {
    public let physiology: UserPhysiology
    /// Treinos aeróbicos recentes (o serviço lê 28 dias); o cálculo filtra a semana corrente.
    public let aerobicWorkouts: [AerobicWorkoutSample]
    /// Um registro por dia, pelo menos dos últimos 28 dias.
    public let recovery: [DailyRecoverySample]
    /// Um total por dia, pelo menos dos últimos 7 dias completos.
    public let steps: [DailyStepCount]
    /// Estimativas de VO2max (o serviço lê 180 dias).
    public let vo2Max: [Vo2MaxSample]
    /// Sessões de musculação recentes, usadas só para encaixar o aeróbico longe do treino de pernas (A5).
    public let recentSessions: [SessionSummary]

    public init(
        physiology: UserPhysiology = UserPhysiology(),
        aerobicWorkouts: [AerobicWorkoutSample] = [],
        recovery: [DailyRecoverySample] = [],
        steps: [DailyStepCount] = [],
        vo2Max: [Vo2MaxSample] = [],
        recentSessions: [SessionSummary] = []
    ) {
        self.physiology = physiology
        self.aerobicWorkouts = aerobicWorkouts
        self.recovery = recovery
        self.steps = steps
        self.vo2Max = vo2Max
        self.recentSessions = recentSessions
    }
}
