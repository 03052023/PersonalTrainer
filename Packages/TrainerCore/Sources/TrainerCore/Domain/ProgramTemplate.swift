import Foundation

public struct ProgramTemplate: Codable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let days: [ProgramDayTemplate]
    public let isActive: Bool
    /// Objetivo (SPEC §7.9). `nil` em arquivos v1 = hipertrofia.
    public let goal: ProgramGoal?
    /// Descrição curta em pt-BR para o seletor de programas.
    public let summary: String?

    public init(
        id: UUID = UUID(),
        name: String,
        days: [ProgramDayTemplate] = [],
        isActive: Bool = false,
        goal: ProgramGoal? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.name = name
        self.days = days
        self.isActive = isActive
        self.goal = goal
        self.summary = summary
    }

    /// Objetivo efetivo: `goal ?? .hypertrophy`.
    public var effectiveGoal: ProgramGoal { goal ?? .hypertrophy }
}
