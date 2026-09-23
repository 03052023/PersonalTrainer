import Foundation

/// Backup completo em JSON (T2.4, SPEC RF-18, ARCHITECTURE §12). Implementação: `BackupService`.
/// O arquivo é exportado pelo `fileExporter` (app Arquivos / iCloud Drive) e importado pelo
/// `fileImporter`. A importação substitui TODOS os dados, depois de confirmação na UI.
@MainActor
protocol BackupServicing: AnyObject {
    /// JSON UTF-8 legível (`BackupDocument`, `schemaVersion` = 1), determinístico (`sortedKeys`).
    func exportBackup(now: Date) throws -> Data
    /// Valida o arquivo inteiro antes de tocar no banco; em erro nada é alterado.
    /// Lança `BackupError.inProgressSession` se houver sessão em andamento.
    func importBackup(_ data: Data) throws -> BackupImportReport
    /// Nome sugerido: "PersonalTrainer-backup-2026-09-23.json".
    func suggestedFileName(now: Date) -> String
}

struct BackupImportReport: Sendable, Hashable {
    let exercises: Int
    let programs: Int
    let sessions: Int
    let sets: Int
}

enum BackupError: Error, Equatable {
    case unsupportedVersion(Int)
    case corrupted
    case inProgressSession
    case referentialIntegrity(String)
}
