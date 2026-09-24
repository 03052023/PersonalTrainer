import Foundation

/// Passos: média dos últimos 7 dias completos (hoje não entra) contra a meta diária.
public struct StepsSummary: Codable, Sendable, Hashable {
    /// `nil` quando nenhum dos 7 dias tem registro.
    public let average7: Int?
    public let target: Int

    public init(average7: Int?, target: Int) {
        self.average7 = average7
        self.target = target
    }
}
