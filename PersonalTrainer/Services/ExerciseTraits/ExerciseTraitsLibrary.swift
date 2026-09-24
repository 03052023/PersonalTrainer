import Foundation
import os
import TrainerCore

/// Medida e marca "de casa" de cada exercício do seed (SPEC RF-42, RF-43, §7.13), lidas do
/// catálogo do bundle pelo `slug`. Assim não é preciso mudar o esquema SwiftData: o store guarda
/// o exercício, e o catálogo do bundle diz como medi-lo e se dá para fazê-lo em casa.
///
/// Mesmo padrão do `ReferenceLibrary`: se o arquivo faltar ou não decodificar, registra no log e
/// devolve `.empty`, em que tudo é medido em repetições e nada é "de casa". A sessão nunca para.
enum ExerciseTraitsLibrary {
    static func load(bundle: Bundle) -> ExerciseTraitsCatalog {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer", category: "ExerciseTraits")
        let resourceName = SeedLoader.catalogResourceName

        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            logger.error("Recurso \(resourceName, privacy: .public).json ausente do bundle")
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            return try ExerciseTraitsCatalog.decode(seedCatalogJSON: data)
        } catch {
            logger.error("Catálogo de medidas inválido: \(String(describing: error), privacy: .public)")
            return .empty
        }
    }
}
