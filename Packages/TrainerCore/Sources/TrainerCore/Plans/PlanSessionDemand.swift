import Foundation

/// Um dia de um plano visto pelo encaixe da semana (SPEC §7.15 M3; docs/V23-UI-CONTRACT.md §3.1).
public struct PlanSessionDemand: Sendable, Hashable {
    public let programDayID: UUID
    public let dayName: String
    public let kind: PlanSessionKind
    /// Grupos primários dos exercícios do dia, para os 48 h de S6. Vazio nos dias de aeróbico: as
    /// pernas do aeróbico são convenção de contagem (§7.4) e os complementos não entram no encaixe.
    public let primaryMuscles: Set<MuscleGroup>
    /// Dia de força com algum grupo de pernas como primário (quadríceps, posteriores, glúteos ou
    /// panturrilhas): é o "dia de pernas" de A5.
    public let isLowerBody: Bool
    /// Só nos dias de aeróbico: o mais forte dos aeróbicos do dia (`CardioIntensity.classify`).
    public let cardioIntensity: CardioIntensity?
    /// Duração estimada em minutos (0 quando quem monta não sabe).
    public let estimatedMinutes: Int

    public init(
        programDayID: UUID,
        dayName: String,
        kind: PlanSessionKind,
        primaryMuscles: Set<MuscleGroup> = [],
        isLowerBody: Bool = false,
        cardioIntensity: CardioIntensity? = nil,
        estimatedMinutes: Int = 0
    ) {
        self.programDayID = programDayID
        self.dayName = dayName
        self.kind = kind
        self.primaryMuscles = primaryMuscles
        self.isLowerBody = isLowerBody
        self.cardioIntensity = cardioIntensity
        self.estimatedMinutes = estimatedMinutes
    }
}
