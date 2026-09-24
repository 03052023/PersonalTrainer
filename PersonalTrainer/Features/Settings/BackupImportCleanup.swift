import Foundation
import os

/// O que a importação de um backup zera além do banco (TASKS A5; docs/V21-CONTRACT.md B1).
///
/// O backup só leva o SwiftData. Três estados do app ficam fora dele e foram decididos sobre os
/// dados antigos, então deixam de valer quando o banco é substituído:
/// - `deload-decisions.json`: "Fazer semana leve agora" e "Seguir normal" (SPEC §7.5 c, §7.11 C1);
/// - `last-review.json`: o relatório da última revisão periódica (§7.8, C2), e a chave
///   `coachLastReviewProgramID`, o programa sobre o qual ele foi feito. A cópia em memória do
///   `CoachService` sai por `resetAfterImport()`, chamado pelo Ajustes depois desta limpeza;
/// - `coachPendingDeloadSince` (e o gatilho gravado junto, `coachPendingDeloadTrigger`): desde
///   quando a semana leve está programada, que dá o período da mensagem C1.
///
/// O log do diálogo (`coach-log.json`) fica: são as respostas da pessoa, e "Não sugerir mais isto"
/// continua valendo depois de restaurar um backup.
///
/// Roda depois de uma importação bem-sucedida. Arquivo ausente não é falha; um arquivo que não pôde
/// ser apagado vai para o log e não desfaz a importação, que já terminou.
struct BackupImportCleanup {
    /// Arquivos apagados.
    let fileURLs: [URL]
    /// Chaves removidas de `defaults`.
    let defaultsKeys: [String]
    let defaults: UserDefaults

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "Settings"
    )

    init(fileURLs: [URL], defaultsKeys: [String], defaults: UserDefaults) {
        self.fileURLs = fileURLs
        self.defaultsKeys = defaultsKeys
        self.defaults = defaults
    }

    /// Os caminhos e as chaves do app: os mesmos arquivos que `LiveDeloadDecisionsStore` e
    /// `LiveCoachLogStore` gravam em Application Support/PersonalTrainer e as chaves do
    /// `CoachService` em `defaults`. Sem Application Support, só as chaves são removidas.
    @MainActor
    static func live(defaults: UserDefaults) -> BackupImportCleanup {
        var files: [URL] = []
        if let decisions = LiveDeloadDecisionsStore.defaultFileURL() {
            files.append(decisions)
        }
        if let directory = LiveCoachLogStore.defaultDirectory() {
            files.append(directory.appendingPathComponent(LiveCoachLogStore.lastReviewFileName, isDirectory: false))
        }
        return BackupImportCleanup(
            fileURLs: files,
            defaultsKeys: [
                CoachService.DefaultsKey.pendingDeloadSince,
                CoachService.DefaultsKey.pendingDeloadTrigger,
                CoachService.DefaultsKey.lastReviewProgramID,
            ],
            defaults: defaults
        )
    }

    /// Remove as chaves e apaga os arquivos que existem. Devolve os que ficaram (falha ao apagar).
    @discardableResult
    func run() -> [URL] {
        for key in defaultsKeys {
            defaults.removeObject(forKey: key)
        }
        let fileManager = FileManager.default
        var remaining: [URL] = []
        for url in fileURLs {
            guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
                continue
            }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                let name = url.lastPathComponent
                let reason = String(describing: error)
                Self.logger.error("Importação: \(name, privacy: .public) não pôde ser apagado: \(reason, privacy: .public)")
                remaining.append(url)
            }
        }
        return remaining
    }
}
