import Foundation

/// Resultado do modo casa para um exercício do dia (SPEC §7.13 H1–H3), na ordem do dia.
public struct HomeSwap: Sendable, Hashable {
    /// Id do exercício do plano (o da academia, ou o próprio exercício de casa).
    public let originalID: UUID
    /// Exercício de casa que entra no lugar. `nil` = sem opção em casa: o exercício sai da sessão e o
    /// app mostra o aviso "sem opção em casa para X" (H2).
    public let replacement: ExerciseDefinition?

    /// `true` quando o original já era de casa e fica como está (H2).
    public var isUnchanged: Bool {
        replacement?.id == originalID
    }

    public init(originalID: UUID, replacement: ExerciseDefinition?) {
        self.originalID = originalID
        self.replacement = replacement
    }
}
