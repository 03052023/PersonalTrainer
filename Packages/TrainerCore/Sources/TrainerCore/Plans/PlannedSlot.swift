import Foundation

/// Uma sessão de um plano num dia da semana ideal (SPEC §7.15 M4; docs/V23-UI-CONTRACT.md §3.1).
public struct PlannedSlot: Sendable, Hashable {
    public let weekday: PlanWeekday
    public let programID: UUID
    /// Posição desta sessão na semana do plano: 0 é a primeira. A sessão de verdade é a próxima da
    /// rotação daquele plano (S8), não um dia fixo.
    public let indexInWeek: Int
    public let kind: PlanSessionKind
    /// Ordem no dia: 0 vem primeiro. Com força e aeróbico no mesmo dia, a força vem antes (A5).
    public let orderInDay: Int
    /// O dia do plano previsto para este lugar nesta semana: a rotação contada a partir da sessão do
    /// começo da semana (M3, M4). `nil` quando quem monta não sabe.
    public let programDayID: UUID?
    /// O nome desse dia ("Dia A — Superior"), para a semana da aba Plano. Vazio quando quem monta não sabe.
    public let dayName: String
    /// Só nas sessões de aeróbico: a intensidade desse dia (M3), para textos como "Cardio forte".
    public let cardioIntensity: CardioIntensity?

    public init(
        weekday: PlanWeekday,
        programID: UUID,
        indexInWeek: Int,
        kind: PlanSessionKind,
        orderInDay: Int,
        programDayID: UUID? = nil,
        dayName: String = "",
        cardioIntensity: CardioIntensity? = nil
    ) {
        self.weekday = weekday
        self.programID = programID
        self.indexInWeek = indexInWeek
        self.kind = kind
        self.orderInDay = orderInDay
        self.programDayID = programDayID
        self.dayName = dayName
        self.cardioIntensity = cardioIntensity
    }
}
