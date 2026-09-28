import Foundation

/// Resultado do encaixe da semana (SPEC §7.15 M4 e M5; docs/V23-UI-CONTRACT.md §3.1).
public struct FitResult: Sendable, Hashable {
    /// A semana escolhida; `nil` quando os planos não cabem.
    public let schedule: WeekSchedule?
    /// Por que não cabe. Vazio quando cabe.
    public let problems: [FitProblem]
    /// As saídas que fazem caber, na ordem de M5. Vazio quando cabe.
    public let alternatives: [FitAlternative]

    public init(schedule: WeekSchedule?, problems: [FitProblem] = [], alternatives: [FitAlternative] = []) {
        self.schedule = schedule
        self.problems = problems
        self.alternatives = alternatives
    }

    public var fits: Bool {
        schedule != nil
    }

    /// "Cabe", sem semana calculada: o padrão dos protocolos do app para doubles e previews.
    public static let unchecked = FitResult(schedule: WeekSchedule.empty)
}
