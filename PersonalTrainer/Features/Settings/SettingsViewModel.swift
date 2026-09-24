import Foundation
import Observation
import os
import TrainerCore

/// Estado da tela de Ajustes (T2.4, SPEC RF-18, RF-39, RF-42, §7.5; contrato V2-FINAL §2.6 e
/// V21 B1): backup JSON, modo casa e planejamento.
///
/// Fluxo de exportação: `prepareExport()` gera o arquivo na memória e abre o `fileExporter`; ao
/// salvar, grava `lastBackupAt` (lembrete de backup do diálogo, SPEC §7.11 C7). O "Fazer backup"
/// do diálogo (C7) chama o mesmo `prepareExport()` (B10); por isso, no app, o `RootView` guarda
/// esta instância e apresenta o `fileExporter` e os alertas na raiz, visíveis em qualquer aba.
/// Fluxo de importação: `fileImporter` → `handleImportSelection` lê o arquivo → confirmação
/// destrutiva → `confirmImport()` chama o serviço, zera o que foi decidido sobre os dados antigos
/// (`BackupImportCleanup`, A5), mostra as contagens e avisa `onDataChanged`.
/// Modo casa: a chave `PlannerSettings.homeModeKey`, a mesma do interruptor da Home.
/// Planejamento: seletor por frequência e semanas entre semanas leves em `UserDefaults` (chaves de
/// `PlannerSettings`, lidas pelo planner a cada plano) e "Fazer semana leve agora" pelo
/// `SessionPlanning.requestDeload`, com confirmação.
///
/// Nada aqui toca o `ModelContext` (AGENTS R4): backup só por `BackupServicing`, semana leve só
/// pelo `SessionPlanning`. Datas vêm do `now` injetado (SPEC P11).
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

    /// Seletor por frequência (SPEC RF-39): automático, ligado ou desligado.
    private(set) var frequencySelector: PlannerSettings.FrequencySelectorMode
    /// Semanas entre semanas leves (SPEC §7.5 b), dentro de `deloadWeeksRange`; 0 desliga.
    private(set) var deloadWeeks: Int
    /// "Treinar em casa" (SPEC RF-42). A Home grava a mesma chave: `reloadHomeMode()` ao abrir.
    private(set) var homeModeEnabled: Bool
    /// Ligado ao `confirmationDialog` de "Fazer semana leve agora".
    var isConfirmingDeload = false

    let appVersion: String

    /// Faixa do Stepper de semanas entre semanas leves (0 = desligado).
    static let deloadWeeksRange = 0...12

    // MARK: - Dependências

    private let backup: any BackupServicing
    private let planner: any SessionPlanning
    private let now: () -> Date
    private let defaults: UserDefaults
    private let importCleanup: BackupImportCleanup
    private let onDataChanged: () -> Void
    @ObservationIgnored private var pendingImportData: Data?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "Settings"
    )

    /// - Parameters:
    ///   - defaults: onde ficam os ajustes do planejamento, o modo casa e `lastBackupAt` (contratos
    ///     V2-FINAL §2 e V21 B1: chaves compartilhadas). Testes passam uma suite isolada.
    ///   - importCleanup: o que a importação zera (A5); `nil` usa os arquivos e as chaves do app
    ///     (`BackupImportCleanup.live(defaults:)`). Testes passam arquivos temporários.
    ///   - onDataChanged: depois de importar um backup, programar uma semana leve ou mudar o modo
    ///     casa, para quem guarda o plano em cache (Home) reler.
    init(
        backup: any BackupServicing,
        planner: any SessionPlanning,
        now: @escaping () -> Date,
        appVersion: String,
        defaults: UserDefaults = .standard,
        importCleanup: BackupImportCleanup? = nil,
        onDataChanged: @escaping () -> Void
    ) {
        self.backup = backup
        self.planner = planner
        self.now = now
        self.appVersion = appVersion
        self.defaults = defaults
        if let importCleanup {
            self.importCleanup = importCleanup
        } else {
            self.importCleanup = BackupImportCleanup.live(defaults: defaults)
        }
        self.onDataChanged = onDataChanged
        let settings = PlannerSettings.load(from: defaults)
        self.frequencySelector = settings.frequencySelector
        self.deloadWeeks = SettingsViewModel.clampedDeloadWeeks(settings.deloadWeeks)
        self.homeModeEnabled = settings.homeModeEnabled
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
            // SPEC §7.11 C7: o lembrete de backup conta a partir daqui.
            defaults.set(now().timeIntervalSince1970, forKey: CoachService.DefaultsKey.lastBackupAt)
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
            // A5: semana leve pedida ou dispensada e a última revisão valiam para os dados
            // antigos. O log do diálogo fica. Uma falha aqui só vai para o log: o banco já é o
            // do backup.
            importCleanup.run()
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

    // MARK: - Modo casa (SPEC RF-42)

    /// Grava a chave que o planner e a Home leem. O programa não muda; a Home relê o plano.
    func setHomeModeEnabled(_ enabled: Bool) {
        homeModeEnabled = enabled
        defaults.set(enabled, forKey: PlannerSettings.homeModeKey)
        onDataChanged()
    }

    /// O interruptor da Home grava a mesma chave: relida sempre que o Ajustes aparece.
    func reloadHomeMode() {
        homeModeEnabled = PlannerSettings.load(from: defaults).homeModeEnabled
    }

    // MARK: - Planejamento

    /// Grava o modo do seletor por frequência; o planner lê a cada plano.
    func setFrequencySelector(_ mode: PlannerSettings.FrequencySelectorMode) {
        frequencySelector = mode
        defaults.set(mode.rawValue, forKey: PlannerSettings.frequencySelectorKey)
    }

    /// Grava as semanas entre semanas leves, limitadas a `deloadWeeksRange` (0 desliga o gatilho
    /// por tempo, SPEC §7.5 b; os gatilhos por reduções e manual continuam).
    func setDeloadWeeks(_ weeks: Int) {
        let clamped = Self.clampedDeloadWeeks(weeks)
        deloadWeeks = clamped
        defaults.set(clamped, forKey: PlannerSettings.deloadWeeksKey)
    }

    /// "Fazer semana leve agora" (SPEC §7.5 c): pede confirmação só quando o pedido cabe. Sem
    /// programa ativo, ou com semana leve já programada ou em andamento, explica em vez de pedir.
    func requestDeload() {
        do {
            let days = try planner.activeProgramDays()
            guard !days.isEmpty else {
                present(
                    title: "Nenhum programa ativo",
                    message: "Ative um programa com pelo menos um dia para programar uma semana leve."
                )
                return
            }
            let status = try planner.deloadStatus(now: now())
            switch status {
            case .inactive:
                isConfirmingDeload = true
            case .pending:
                present(
                    title: "Semana leve já programada",
                    message: "As próximas sessões já vêm mais leves. Não é preciso pedir de novo."
                )
            case .active:
                present(
                    title: "Semana leve em andamento",
                    message: "Você já está numa semana leve. Um novo pedido cabe depois que ela terminar."
                )
            }
        } catch {
            logger.error("Falha ao ler a semana leve: \(String(describing: error), privacy: .public)")
            present(
                title: "Não foi possível verificar",
                message: "Não deu para ler o programa agora. Tente de novo."
            )
        }
    }

    /// Confirmação do pedido. O planner só grava com a semana leve inativa; se ela deixou de
    /// caber entre a pergunta e a resposta, a pessoa fica sabendo.
    func confirmDeload() {
        isConfirmingDeload = false
        let date = now()
        do {
            try planner.requestDeload(now: date)
            let status = try planner.deloadStatus(now: date)
            guard case .pending = status else {
                present(
                    title: "Semana leve não programada",
                    message: "O pedido não coube agora: já há uma semana leve programada ou em andamento, ou o programa mudou. Nada foi alterado."
                )
                return
            }
            present(
                title: "Semana leve programada",
                message: "As próximas sessões, uma de cada dia do programa, vêm com menos séries e carga um pouco menor. Depois tudo volta ao normal."
            )
            onDataChanged()
        } catch {
            logger.error("Falha ao pedir a semana leve: \(String(describing: error), privacy: .public)")
            present(
                title: "Não foi possível programar",
                message: "A semana leve não foi gravada. Tente de novo."
            )
        }
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
            return "O arquivo não é um backup válido do Magister. Nada foi alterado."
        case .inProgressSession:
            return "Há uma sessão em andamento. Finalize ou abandone a sessão antes de importar."
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

    private static func clampedDeloadWeeks(_ weeks: Int) -> Int {
        min(max(weeks, deloadWeeksRange.lowerBound), deloadWeeksRange.upperBound)
    }

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
