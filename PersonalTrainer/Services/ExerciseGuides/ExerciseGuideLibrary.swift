import Foundation
import os
import TrainerCore

/// As guias do "Como fazer" do bundle (SPEC RF-40, §7.12 E8; docs/V23-UI-CONTRACT.md §4.4): lê
/// `exercise-guides.v1.json` e o catálogo `exercises.v2.json`, decodifica e valida as guias contra o catálogo com
/// `ExerciseGuideValidator.validate(_:exercises:)`.
///
/// Mesmo padrão do `ExerciseTraitsLibrary`: se um arquivo faltar, não decodificar ou reprovar na validação, registra
/// no log e devolve `.empty`, em que nenhum botão "Como fazer" aparece. A sessão nunca para (E8). O integrador
/// carrega uma vez, na raiz, e põe no ambiente (`\.exerciseGuides`).
///
/// Os JSON ficam na raiz do bundle, como os do seed (`SeedLoader`, ARCHITECTURE §11).
enum ExerciseGuideLibrary {
    /// Nome do recurso sem extensão.
    static let guidesResourceName = "exercise-guides.v1"

    static func load(bundle: Bundle) -> ExerciseGuideCatalog {
        let logger = Self.logger
        let guidesName = guidesResourceName
        guard let guidesURL = bundle.url(forResource: guidesName, withExtension: "json") else {
            logger.error("Recurso \(guidesName, privacy: .public).json ausente do bundle")
            return .empty
        }
        let catalogName = SeedLoader.catalogResourceName
        guard let catalogURL = bundle.url(forResource: catalogName, withExtension: "json") else {
            logger.error("Recurso \(catalogName, privacy: .public).json ausente do bundle")
            return .empty
        }
        let guidesData: Data
        let catalogData: Data
        do {
            guidesData = try Data(contentsOf: guidesURL)
            catalogData = try Data(contentsOf: catalogURL)
        } catch {
            logger.error("Não foi possível ler as guias: \(String(describing: error), privacy: .public)")
            return .empty
        }
        return load(guidesData: guidesData, catalogData: catalogData)
    }

    /// O mesmo a partir dos bytes (também usado pelos testes de E8): qualquer falha vira `.empty`, com log.
    static func load(guidesData: Data, catalogData: Data) -> ExerciseGuideCatalog {
        let logger = Self.logger
        let guides: ExerciseGuideCatalog
        let exercises: [ExerciseDefinition]
        do {
            guides = try ExerciseGuideCatalog.decode(guidesData)
            exercises = try JSONDecoder().decode(SeedExerciseCatalog.self, from: catalogData).exercises
        } catch {
            logger.error("Arquivo de guias ou catálogo inválido: \(String(describing: error), privacy: .public)")
            return .empty
        }
        do {
            try ExerciseGuideValidator.validate(guides, exercises: exercises)
        } catch {
            logger.error("Guias reprovadas na validação: \(String(describing: error), privacy: .public)")
            return .empty
        }
        return guides
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "ExerciseGuideLibrary"
    )
}
