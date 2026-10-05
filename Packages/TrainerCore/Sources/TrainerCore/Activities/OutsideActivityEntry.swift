import Foundation

/// Um registro de atividade feita fora do app (SPEC §7.17 X1, X2): avulso, ou o "Feito" de uma fixa.
/// Só o que a pessoa disse: nada aqui muda a prescrição (P12, X7).
public struct OutsideActivityEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let kind: OutsideActivityKind
    /// Início, no relógio do aparelho (UTC); o dia é o do calendário da pessoa.
    public let start: Date
    /// Duração em minutos inteiros, em `OutsideActivities.minutesRange` (X1).
    public let minutes: Int
    /// Pelo teste da fala (§7.14 F2): leve, moderada ou forte.
    public let intensity: CardioIntensity
    /// A fixa de onde veio o "Feito" (X2); `nil` num registro avulso.
    public let fixedActivityID: UUID?

    public init(
        id: UUID = UUID(),
        kind: OutsideActivityKind,
        start: Date,
        minutes: Int,
        intensity: CardioIntensity,
        fixedActivityID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.minutes = minutes
        self.intensity = intensity
        self.fixedActivityID = fixedActivityID
    }

    /// Fim = início + duração (uma duração negativa vale 0).
    public var end: Date {
        start.addingTimeInterval(TimeInterval(max(0, minutes)) * 60)
    }
}
