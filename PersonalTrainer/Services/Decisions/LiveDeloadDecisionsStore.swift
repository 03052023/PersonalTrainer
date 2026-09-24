import Foundation
import os
import TrainerCore

/// `DeloadDecisionsStoring` sobre um arquivo JSON em
/// `Application Support/PersonalTrainer/deload-decisions.json`, ao lado do store do SwiftData.
///
/// - Escrita atômica (`Data.WritingOptions.atomic`): um app morto no meio da gravação deixa o
///   arquivo anterior inteiro, nunca um JSON pela metade.
/// - Datas no formato padrão do `JSONEncoder` (segundos desde 2001 como `Double`): volta
///   exatamente o mesmo instante, sem o arredondamento para segundos do ISO 8601. Um
///   `dismissedAt` arredondado para trás poderia reabrir a semana leve dispensada.
/// - Leitura tolerante: arquivo ausente é o normal antes da primeira decisão; arquivo ilegível
///   vira `DeloadDecisions()` com log, e o planejamento segue automático.
final class LiveDeloadDecisionsStore: DeloadDecisionsStoring {
    static let fileName = "deload-decisions.json"

    /// `nil` quando a pasta Application Support não pôde ser resolvida: `load()` devolve vazio e
    /// `save(_:)` lança `DeloadDecisionsStoreError.storageUnavailable`.
    let fileURL: URL?

    /// AGENTS §4: `subsystem` = bundle id, `category` = nome do serviço.
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "DeloadDecisionsStore"
    )

    /// - Parameter fileURL: o app usa o padrão; os testes passam um arquivo temporário.
    init(fileURL: URL? = LiveDeloadDecisionsStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    /// `Application Support/PersonalTrainer/deload-decisions.json`. A pasta `PersonalTrainer` é
    /// criada na primeira gravação, não aqui: resolver o caminho não escreve nada.
    static func defaultFileURL() -> URL? {
        guard let applicationSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return applicationSupport
            .appendingPathComponent("PersonalTrainer", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    func load() -> DeloadDecisions {
        guard let fileURL else {
            return DeloadDecisions()
        }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return DeloadDecisions()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(DeloadDecisions.self, from: data)
        } catch {
            let reason = String(describing: error)
            logger.error("Decisões de semana leve ilegíveis; seguindo sem elas: \(reason, privacy: .public)")
            return DeloadDecisions()
        }
    }

    func save(_ decisions: DeloadDecisions) throws {
        guard let fileURL else {
            logger.error("Sem pasta Application Support: decisão de semana leve não gravada.")
            throw DeloadDecisionsStoreError.storageUnavailable
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(decisions)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            let reason = String(describing: error)
            logger.error("Falha ao gravar as decisões de semana leve: \(reason, privacy: .public)")
            throw error
        }
    }
}
