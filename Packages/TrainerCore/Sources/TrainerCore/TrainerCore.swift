import Foundation

/// Metadados do pacote. Os tipos de domínio, motor e sync entram em
/// `Domain/`, `Engine/`, `Sync/` e `Summary/` nas tarefas T0.2–T0.7 (TASKS.md).
public enum TrainerCore {
    /// Versão semântica do pacote (não confundir com `SyncSchema.currentVersion`).
    public static let version = "0.1.0"
}
