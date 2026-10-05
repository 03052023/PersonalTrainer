import Foundation

/// Uma atividade fora do app que se repete toda semana (SPEC §7.17 X2): "Pilates toda terça, 19h, 50 min".
/// Entra no encaixe da semana (X4), mas só conta nas metas e na recuperação depois do "Feito" do dia, que
/// grava um `OutsideActivityEntry` (nada é contado sem confirmação).
public struct FixedOutsideActivity: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let kind: OutsideActivityKind
    public let weekday: PlanWeekday
    /// Hora de início em minutos desde 00:00, de 0 a 1439.
    public let startMinuteOfDay: Int
    /// Duração em minutos inteiros, em `OutsideActivities.minutesRange` (X1).
    public let minutes: Int
    public let intensity: CardioIntensity

    public init(
        id: UUID = UUID(),
        kind: OutsideActivityKind,
        weekday: PlanWeekday,
        startMinuteOfDay: Int,
        minutes: Int,
        intensity: CardioIntensity
    ) {
        self.id = id
        self.kind = kind
        self.weekday = weekday
        self.startMinuteOfDay = startMinuteOfDay
        self.minutes = minutes
        self.intensity = intensity
    }
}
