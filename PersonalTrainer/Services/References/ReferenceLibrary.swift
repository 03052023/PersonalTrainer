import Foundation
import os
import TrainerCore

/// Carrega o catálogo de referências científicas do botão "Por quê?" (SPEC RF-32) a partir de
/// `Resources/Seed/references.v1.json`.
///
/// Diferente do seed, o catálogo não vai para o SwiftData: é lido do bundle a cada launch e
/// vive em memória (`AppEnvironment.references`). Qualquer falha — arquivo ausente, JSON
/// inválido ou reprovado no `ReferenceValidator` — só é logada e devolve `.empty`; a UI então
/// esconde os botões "Por quê?" em vez de interromper o app.
enum ReferenceLibrary {
    /// Nome do recurso sem extensão. Como os JSON do seed, fica na RAIZ do bundle (o
    /// `project.yml` copia `Resources/Seed/*.json` sem preservar a pasta).
    static let resourceName = "references.v1"

    static func load(bundle: Bundle) -> ReferenceCatalog {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer", category: "References")
        let fileName = "\(resourceName).json"

        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            logger.error("Recurso \(fileName, privacy: .public) ausente do bundle")
            return .empty
        }

        do {
            let data = try Data(contentsOf: url)
            let catalog = try JSONDecoder().decode(ReferenceCatalog.self, from: data)
            try ReferenceValidator.validate(catalog)
            logger.info("Catálogo de referências v\(catalog.version, privacy: .public) carregado: \(catalog.references.count, privacy: .public) referências")
            return catalog
        } catch {
            logger.error("Catálogo de referências inválido: \(String(describing: error), privacy: .public)")
            return .empty
        }
    }
}
