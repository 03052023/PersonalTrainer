import Foundation
import Observation
import os

/// Estado da tela de Ajustes (T2.4, SPEC RF-18): exportar e importar o backup JSON.
///
/// Fluxo de exportação: `prepareExport()` gera o arquivo na memória e abre o `fileExporter`.
/// Fluxo de importação: `fileImporter` → `handleImportSelection` lê o arquivo → confirmação
/// destrutiva → `confirmImport()` chama o serviço, mostra as contagens e avisa `onDataChanged`.
///
/// Nada aqui toca o `ModelContext` (AGENTS R4): toda leitura e escrita passa por
/// `BackupServicing`. Datas vêm do `now` injetado (SPEC P11).
@Observable
@MainActor
final class SettingsViewModel {
    /// Conteúdo do alerta de resultado (sucesso ou falha).
    struct AlertMessage: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let message: String
    }

    // MARK: - Estado da tela

    var isExporterPresented = false
    var isImporterPresented = false
    var isConfirmingImport = false
    /// Ligado ao `.alert` da tela; `alert` guarda o conteúdo mostrado.
    var isAlertPresented = false
    private(set) var alert: AlertMessage?

    /// Arquivo pronto para o `fileExporter`; `nil` fora de uma exportação.
    private(set) var exportDocument: BackupFileDocument?
    private(set) var exportFileName = ""
    /// Nome do arquivo escolhido, exibido na confirmação.
    private(set) var pendingImportFileName = ""

    let appVersion: String

    // MARK: - Dependências

    private let backup: any BackupServicing
    private let now: () -> Date
    private let onDataChanged: () -> Void
    @ObservationIgnored private var pendingImportData: Data?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "Settings"
    )

    init(
        backup: any BackupServicing,
        now: @escaping () -> Date,
        appVersion: String,
        onDataChanged: @escaping () -> Void
    ) {
        self.backup = backup
        self.now = now
        self.appVersion = appVersion
        self.onDataChanged = onDataChanged
    }

    // MARK: - Exportar

    func prepareExport() {
        let date = now()
        do {
            let data = try backup.exportBackup(now: date)
            exportDocument = BackupFileDocument(data: data)
            exportFileName = backup.suggestedFileName(now: date)
            isExporterPresented = true
        } catch {
            logger.error("Falha ao gerar o backup: \(String(describing: error), privacy: .public)")
            present(
                title: "Não foi possível exportar",
                message: "O backup não pôde ser gerado. Tente de novo; se persistir, reinicie o app."
            )
        }
    }

    func handleExportResult(_ result: Result<URL, any Error>) {
        exportDocument = nil
        switch result {
        case .success(let url):
            present(
                title: "Backup salvo",
                message: "\(url.lastPathComponent) foi salvo. Guarde-o fora do iPhone (iCloud Drive ou computador) antes de reinstalar o app."
            )
        case .failure(let error):
            if Self.isUserCancellation(error) {
                return
            }
            logger.error("Falha ao salvar o backup: \(String(describing: error), privacy: .public)")
            present(
                title: "Não foi possível salvar",
                message: "O arquivo não foi salvo no local escolhido. Tente outro local."
            )
        }
    }

    // MARK: - Importar

    func startImport() {
        isImporterPresented = true
    }

    /// Lê o arquivo escolhido e pede confirmação. A leitura acontece aqui, e não depois da
    /// confirmação, porque o acesso ao arquivo fora do app (security-scoped) é concedido agora.
    func handleImportSelection(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            let hasScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                pendingImportData = try Data(contentsOf: url)
                pendingImportFileName = url.lastPathComponent
                isConfirmingImport = true
            } catch {
                logger.error("Falha ao ler o arquivo de backup: \(String(describing: error), privacy: .public)")
                pendingImportData = nil
                present(
                    title: "Não foi possível abrir o arquivo",
                    message: "O arquivo escolhido não pôde ser lido. Verifique se ele terminou de baixar do iCloud Drive."
                )
            }
        case .failure(let error):
            if Self.isUserCancellation(error) {
                return
            }
            logger.error("Falha ao escolher o arquivo: \(String(describing: error), privacy: .public)")
            present(
                title: "Não foi possível abrir o arquivo",
                message: "Tente escolher o arquivo de novo."
            )
        }
    }

    func confirmImport() {
        guard let data = pendingImportData else {
            return
        }
        pendingImportData = nil
        do {
            let report = try backup.importBackup(data)
            present(title: "Backup importado", message: Self.summary(of: report))
            onDataChanged()
        } catch {
            logger.error("Falha ao importar o backup: \(String(describing: error), privacy: .public)")
            present(title: "Backup não importado", message: Self.message(for: error))
        }
    }

    func cancelImport() {
        pendingImportData = nil
        pendingImportFileName = ""
    }

    // MARK: - Textos

    static func summary(of report: BackupImportReport) -> String {
        "Exercícios: \(report.exercises)\nProgramas: \(report.programs)\nSessões: \(report.sessions)\nSéries: \(report.sets)"
    }

    /// Mensagens em pt-BR para cada falha do contrato; nenhum dado foi alterado em nenhuma delas.
    static func message(for error: any Error) -> String {
        guard let backupError = error as? BackupError else {
            return "Ocorreu um erro ao gravar os dados. Nada foi alterado."
        }
        switch backupError {
        case .unsupportedVersion(let version):
            return "Este backup usa o formato \(version), que esta versão do app não lê. Nada foi alterado."
        case .corrupted:
            return "O arquivo não é um backup válido do Personal. Nada foi alterado."
        case .inProgressSession:
            return "Há um treino em andamento. Finalize ou abandone o treino antes de importar."
        case .referentialIntegrity(let detail):
            return "O backup tem dados inconsistentes e não foi importado. \(detail)"
        }
    }

    /// "0.1.0 (1)" a partir do Info.plist.
    static func bundleVersion(_ bundle: Bundle) -> String {
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    // MARK: - Apoio

    private func present(title: String, message: String) {
        alert = AlertMessage(title: title, message: message)
        isAlertPresented = true
    }

    /// Cancelar o seletor não é erro. Em algumas versões do iOS o cancelamento chega como falha.
    private static func isUserCancellation(_ error: any Error) -> Bool {
        if let cocoaError = error as? CocoaError, cocoaError.code == .userCancelled {
            return true
        }
        return false
    }
}
