import Foundation

/// Marcas de um exercício do catálogo do seed que não estão no esquema de dados (versão 2.1, sem
/// SchemaV3): a medida da série (SPEC RF-43) e se ele dá para fazer em casa (SPEC §7.13 H1).
///
/// Decodificação tolerante: chave ausente vale o padrão, porque o seed só escreve `measure` quando
/// ela não é `reps`.
public struct ExerciseTraits: Codable, Sendable, Hashable {
    /// Padrão `.reps`.
    public let measure: ExerciseMeasure
    /// Padrão `false`. SPEC §7.13 H1: peso do corpo sem aparelho ou objeto comum de casa.
    public let atHome: Bool

    /// Repetições e fora do modo casa: vale para exercício personalizado e para slug desconhecido.
    public static let `default` = ExerciseTraits()

    public init(measure: ExerciseMeasure = .reps, atHome: Bool = false) {
        self.measure = measure
        self.atHome = atHome
    }

    private enum CodingKeys: String, CodingKey {
        case measure, atHome
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.measure = try container.decodeIfPresent(ExerciseMeasure.self, forKey: .measure) ?? .reps
        self.atHome = try container.decodeIfPresent(Bool.self, forKey: .atHome) ?? false
    }
}
