import Foundation

/// Uma atividade fixa fora do app vista pelo encaixe da semana (SPEC §7.17 X4; docs/V24-CONTRACT.md §3.1):
/// fica presa ao dia dela em todas as semanas e nunca muda de lugar. Montada por
/// `OutsideActivities.fixedDemands(_:)`.
public struct FixedActivityDemand: Sendable, Hashable {
    /// `FixedOutsideActivity.id`.
    public let id: UUID
    /// "Pilates", para a semana da aba Plano.
    public let name: String
    public let weekday: PlanWeekday
    public let role: OutsideActivityRole
    /// Só no papel de força: os grupos do tipo, para os 48 h de S6.
    public let primaryMuscles: Set<MuscleGroup>
    /// Força com algum grupo de pernas: conta como "dia de pernas" para A5.
    public let isLowerBody: Bool
    /// Só no papel de aeróbico: a intensidade (forte nunca na véspera de pernas, A5).
    public let cardioIntensity: CardioIntensity?
    public let minutes: Int

    public init(
        id: UUID,
        name: String,
        weekday: PlanWeekday,
        role: OutsideActivityRole,
        primaryMuscles: Set<MuscleGroup> = [],
        isLowerBody: Bool = false,
        cardioIntensity: CardioIntensity? = nil,
        minutes: Int = 0
    ) {
        self.id = id
        self.name = name
        self.weekday = weekday
        self.role = role
        self.primaryMuscles = primaryMuscles
        self.isLowerBody = isLowerBody
        self.cardioIntensity = cardioIntensity
        self.minutes = minutes
    }
}
