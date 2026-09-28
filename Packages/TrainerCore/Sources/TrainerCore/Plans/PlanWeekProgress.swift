import Foundation

/// As sessões de um plano ativo na semana de §7.4 que contém `now` (SPEC §7.16 W2; docs/V23-UI-CONTRACT.md
/// §3.1), para a tela Metas da semana. Quem monta é o planejador do app; os números só aparecem na tela e
/// nunca mudam a prescrição (P12).
public struct PlanWeekProgress: Sendable, Hashable {
    public let programID: UUID
    public let goal: ProgramGoal
    /// Sessões `completed` com ao menos uma série de trabalho, iniciadas na semana, num dia deste plano.
    public let completed: Int
    /// Sessões por semana do plano (M3): a de `WeekPreferences.sessionsPerWeek` ou, sem a chave, o número
    /// de dias do plano. 0 num plano sem dias.
    public let perWeek: Int

    public init(programID: UUID, goal: ProgramGoal, completed: Int, perWeek: Int) {
        self.programID = programID
        self.goal = goal
        self.completed = completed
        self.perWeek = perWeek
    }
}
