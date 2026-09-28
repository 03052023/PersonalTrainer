import Foundation

/// Conteúdo de `Resources/Seed/exercise-guides.v1.json`: `{"version": 1, "rig": "mannequin-v2", "units":
/// "stature", "guides": […]}`. O arquivo é gerado por `docs/design/exercise-guides/merge-guides.ps1` a partir dos
/// lotes; nunca é editado à mão (docs/V23-CORE-CONTRACT.md §2.7).
public struct ExerciseGuideCatalog: Codable, Sendable, Hashable {
    public static let currentVersion = 1
    public static let statureUnits = "stature"

    /// Catálogo vazio: o app o usa quando o arquivo falta ou reprova na validação (SPEC E8), e não mostra
    /// "Como fazer".
    public static let empty = ExerciseGuideCatalog(guides: [])

    public let version: Int
    public let rig: String
    public let units: String
    public let guides: [ExerciseGuide]

    public init(
        version: Int = ExerciseGuideCatalog.currentVersion,
        rig: String = GuideRig.name,
        units: String = ExerciseGuideCatalog.statureUnits,
        guides: [ExerciseGuide]
    ) {
        self.version = version
        self.rig = rig
        self.units = units
        self.guides = guides
    }

    /// Só decodifica, com um `JSONDecoder` simples; quem valida é o `ExerciseGuideValidator`. Lança o erro do
    /// decodificador sem mudança.
    public static func decode(_ data: Data) throws -> ExerciseGuideCatalog {
        try JSONDecoder().decode(ExerciseGuideCatalog.self, from: data)
    }

    /// A guia do exercício (SPEC E1); `nil` para exercício sem guia, como um personalizado.
    public func guide(forSlug slug: String) -> ExerciseGuide? {
        guides.first { $0.slug == slug }
    }
}
