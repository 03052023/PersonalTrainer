import Foundation
import os
import TrainerCore

/// `CoachLogStoring` real: dois arquivos JSON em Application Support/PersonalTrainer, ao lado do
/// store do SwiftData (contrato V2-FINAL §2.3):
/// - `coach-log.json`: o `CoachLog` (respostas e `lastReviewAt`);
/// - `last-review.json`: o `ReviewReport` da última revisão periódica.
///
/// Escrita atômica (`Data.WritingOptions.atomic`): um corte de energia deixa o arquivo antigo ou
/// o novo, nunca meio arquivo. Um arquivo ilegível (versão futura, disco corrompido) é logado e
/// lido como vazio; a próxima gravação o substitui.
final class LiveCoachLogStore: CoachLogStoring {
    static let logFileName = "coach-log.json"
    static let lastReviewFileName = "last-review.json"

    /// `nil` quando Application Support não pôde ser localizada: leituras devolvem vazio e
    /// gravações lançam `CoachLogStoreError.directoryUnavailable`.
    private let directory: URL?

    /// AGENTS §4: `subsystem` = bundle id, `category` = nome do serviço.
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "CoachLogStore"
    )

    /// - Parameter directory: pasta dos dois arquivos; os testes passam uma pasta temporária.
    init(directory: URL?) {
        self.directory = directory
    }

    /// A pasta padrão do app (Application Support/PersonalTrainer).
    convenience init() {
        self.init(directory: LiveCoachLogStore.defaultDirectory())
    }

    /// Application Support/PersonalTrainer, a mesma pasta do store e do retrato de importação.
    /// A subpasta é criada na primeira gravação.
    static func defaultDirectory() -> URL? {
        guard let applicationSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        return applicationSupport.appendingPathComponent("PersonalTrainer", isDirectory: true)
    }

    // MARK: - CoachLogStoring

    func load() -> CoachLog {
        read(CoachLog.self, from: Self.logFileName) ?? CoachLog()
    }

    func save(_ log: CoachLog) throws {
        try write(log, to: Self.logFileName)
    }

    func loadLastReview() -> ReviewReport? {
        read(ReviewReport.self, from: Self.lastReviewFileName)
    }

    func saveLastReview(_ report: ReviewReport) throws {
        try write(report, to: Self.lastReviewFileName)
    }

    // MARK: - Arquivos

    private func read<Value: Decodable>(_ type: Value.Type, from fileName: String) -> Value? {
        guard let directory else {
            return nil
        }
        let url = directory.appendingPathComponent(fileName, isDirectory: false)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            // Arquivo ausente é o estado normal antes da primeira resposta.
            return nil
        }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            let reason = String(describing: error)
            logger.error("Arquivo \(fileName, privacy: .public) ilegível, lido como vazio: \(reason, privacy: .public)")
            return nil
        }
    }

    private func write<Value: Encodable>(_ value: Value, to fileName: String) throws {
        guard let directory else {
            throw CoachLogStoreError.directoryUnavailable
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        // Legível para auditoria (SPEC §7.11) e estável entre gravações.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: directory.appendingPathComponent(fileName, isDirectory: false), options: .atomic)
    }
}
