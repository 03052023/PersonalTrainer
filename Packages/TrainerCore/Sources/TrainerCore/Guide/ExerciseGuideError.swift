import Foundation

/// Problema de uma guia ou do arquivo de guias (SPEC §7.12). `rule` é "E1" a "E10" ou "format"; `slug` é `nil`
/// quando o problema é do arquivo inteiro. As mesmas regras rodam no `-Check` da ferramenta de autoria.
public struct ExerciseGuideError: Error, Sendable, Hashable, CustomStringConvertible {
    public static let formatRule = "format"

    public let slug: String?
    public let rule: String
    public let message: String

    public init(slug: String?, rule: String, message: String) {
        self.slug = slug
        self.rule = rule
        self.message = message
    }

    public var description: String {
        "\(slug ?? "(arquivo)") \(rule): \(message)"
    }
}
