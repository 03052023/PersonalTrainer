import Foundation
import os
import TrainerCore

/// `OutsideActivityStoring` sobre um arquivo JSON em
/// `Application Support/PersonalTrainer/outside-activities.json`, ao lado das decisões da semana leve
/// (SPEC §7.17 X8, RF-53). Mesmo padrão do `LiveDeloadDecisionsStore`:
///
/// - Escrita atômica (`Data.WritingOptions.atomic`): um app morto no meio da gravação deixa o arquivo
///   anterior inteiro, nunca um JSON pela metade.
/// - Datas no formato padrão do `JSONEncoder` (segundos desde 2001 como `Double`): o início de um
///   registro volta exatamente o mesmo instante, e o "Feito" de uma fixa continua no mesmo dia.
/// - Leitura tolerante: arquivo ausente é o normal antes do primeiro registro; arquivo ilegível vira
///   `OutsideActivityLog.empty` com log, e o app segue sem as atividades (X8). O ilegível é guardado ao
///   lado com outro nome, para a próxima gravação não apagar o que havia nele.
final class LiveOutsideActivityStore: OutsideActivityStoring {
    static let fileName = "outside-activities.json"

    /// `nil` quando a pasta Application Support não pôde ser resolvida: `load()` devolve vazio e
    /// `save(_:)` lança `OutsideActivityStoreError.storageUnavailable`.
    let fileURL: URL?

    /// AGENTS §4: `subsystem` = bundle id, `category` = nome do serviço.
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "OutsideActivityStore"
    )

    /// - Parameter fileURL: o app usa o padrão; os testes passam um arquivo temporário.
    init(fileURL: URL? = LiveOutsideActivityStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    /// `Application Support/PersonalTrainer/outside-activities.json`. A pasta `PersonalTrainer` é criada
    /// na primeira gravação, não aqui: resolver o caminho não escreve nada.
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

    func load() -> OutsideActivityLog {
        guard let fileURL else {
            return OutsideActivityLog.empty
        }
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return OutsideActivityLog.empty
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            let reason = String(describing: error)
            logger.error("Atividades fora do app sem leitura agora; seguindo sem elas: \(reason, privacy: .public)")
            return OutsideActivityLog.empty
        }
        do {
            return try JSONDecoder().decode(OutsideActivityLog.self, from: data)
        } catch {
            let reason = String(describing: error)
            logger.error("Atividades fora do app ilegíveis; o arquivo fica guardado ao lado: \(reason, privacy: .public)")
            keepAside(fileURL)
            return OutsideActivityLog.empty
        }
    }

    /// X8: um arquivo que não decodifica (corrompido, ou gravado por uma versão com um tipo que esta não
    /// conhece) muda de nome antes que a próxima gravação o substitua, e nada se perde de vez:
    /// `outside-activities.unreadable-<uuid>.json`, na mesma pasta.
    private func keepAside(_ fileURL: URL) {
        let base = fileURL.deletingPathExtension().lastPathComponent
        let destination = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(base).unreadable-\(UUID().uuidString).json", isDirectory: false)
        do {
            try FileManager.default.moveItem(at: fileURL, to: destination)
        } catch {
            let reason = String(describing: error)
            logger.error("Não foi possível guardar o arquivo ilegível das atividades: \(reason, privacy: .public)")
        }
    }

    func save(_ log: OutsideActivityLog) throws {
        guard let fileURL else {
            logger.error("Sem pasta Application Support: atividades fora do app não gravadas.")
            throw OutsideActivityStoreError.storageUnavailable
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(log)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            let reason = String(describing: error)
            logger.error("Falha ao gravar as atividades fora do app: \(reason, privacy: .public)")
            throw error
        }
    }
}
