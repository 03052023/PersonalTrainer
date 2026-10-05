import SwiftUI
import TrainerCore
import UniformTypeIdentifiers

/// Aba Ajustes (T7.5, SPEC RF-39, RF-42, §7.10, §7.11; contrato V22 §3.5): à vista, "Fazer semana
/// leve agora", Backup, Perfil de saúde e Avisos (véspera da validade da instalação); em
/// "Mais opções", o seletor por frequência, as semanas entre semanas leves, as referências
/// científicas e a versão do app. Desde a 2.2 (RF-42), "Treinar em casa" saiu do Ajustes: a chave
/// fica só no cartão da tela Hoje, que a grava e a lê.
///
/// Traz a própria `NavigationStack`; quem a coloca numa aba não deve aninhá-la em outra.
/// Nenhuma escrita no `ModelContext` (AGENTS R4): backup por `BackupServicing` e semana leve por
/// `SessionPlanning`, via `SettingsViewModel`; o aviso de validade pelo `CoachService`, que pede a
/// permissão de notificação só quando a pessoa liga o interruptor (AGENTS §7). Depois de importar
/// ou de programar uma semana leve, `onDataChanged` avisa o integrador para reler a Home.
///
/// Duas formas de montar:
/// - `init(backup:planner:…)`: a tela é dona do `SettingsViewModel` e apresenta a exportação e os
///   alertas (previews);
/// - `init(model:…)`: o `RootView` é dono do modelo e apresenta a exportação e os alertas na raiz,
///   para o "Fazer backup" do diálogo (C7) abrir a exportação direto de qualquer aba (B10). Aqui
///   ficam só a importação e as confirmações, que nascem nesta tela.
///
/// `fileExporter` e `fileImporter` ficam em níveis diferentes da hierarquia: dois seletores de
/// arquivo no mesmo view já deixaram um deles mudo em versões anteriores do SwiftUI. Pelo mesmo
/// motivo a confirmação da semana leve fica presa ao próprio botão, e não ao `Form`, que já tem a
/// confirmação da importação.
@MainActor
struct SettingsView: View {
    @State private var model: SettingsViewModel
    @State private var isShowingRenewalHelp = false
    private let coach: CoachService
    private let health: HealthViewModel
    private let references: ReferenceCatalog
    /// Falso quando quem monta a tela apresenta o `fileExporter` e o alerta do modelo (`RootView`).
    private let presentsExportAndAlerts: Bool

    /// - Parameter now: relógio da exportação (data do arquivo e `exportedAt`) e do pedido de
    ///   semana leve. O padrão é o relógio do sistema; o integrador passa `environment.now`.
    init(
        backup: any BackupServicing,
        planner: any SessionPlanning,
        coach: CoachService,
        health: HealthViewModel,
        references: ReferenceCatalog,
        onDataChanged: @escaping () -> Void,
        now: @escaping () -> Date = { Date() },
        defaults: UserDefaults = .standard
    ) {
        self.coach = coach
        self.health = health
        self.references = references
        self.presentsExportAndAlerts = true
        self._model = State(initialValue: SettingsViewModel(
            backup: backup,
            planner: planner,
            now: now,
            appVersion: SettingsViewModel.bundleVersion(.main),
            defaults: defaults,
            onDataChanged: onDataChanged
        ))
    }

    /// Modelo de quem monta a tela, que também apresenta o `fileExporter` e o alerta dele
    /// (`model.isExporterPresented`, `model.isAlertPresented`).
    init(
        model: SettingsViewModel,
        coach: CoachService,
        health: HealthViewModel,
        references: ReferenceCatalog
    ) {
        self.coach = coach
        self.health = health
        self.references = references
        self.presentsExportAndAlerts = false
        self._model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Papel (DESIGN §14): as linhas em `surface`, como nas outras listas da direção.
                Group {
                    deloadSection
                    backupSection
                    healthSection
                    remindersSection
                    moreOptionsSection
                }
                .listRowBackground(Theme.surface)
            }
            // Papel (DESIGN §14): o fundo do formulário dá lugar ao papel.
            .scrollContentBackground(.hidden)
            .paperBackground()
            .navigationTitle("Ajustes")
            // Rótulo `onCompletion:` explícito: o iOS 17 acrescentou sobrecargas com
            // `onCancellation:` e o fechamento final poderia ficar ambíguo.
            .fileExporter(
                isPresented: exporterBinding,
                document: model.exportDocument,
                contentType: .json,
                defaultFilename: model.exportFileName,
                onCompletion: { result in
                    model.handleExportResult(result)
                }
            )
            .confirmationDialog(
                "Substituir todos os dados?",
                isPresented: $model.isConfirmingImport,
                titleVisibility: .visible
            ) {
                Button("Substituir pelos dados do backup", role: .destructive) {
                    model.confirmImport()
                }
                Button("Cancelar", role: .cancel) {
                    model.cancelImport()
                }
            } message: {
                Text("Isso substitui todas as sessões atuais, os programas, o catálogo e os ajustes pelo conteúdo de \(model.pendingImportFileName). A semana leve pedida e a última revisão também recomeçam. Não dá para desfazer.")
            }
        }
        .fileImporter(
            isPresented: $model.isImporterPresented,
            allowedContentTypes: [.json],
            onCompletion: { result in
                model.handleImportSelection(result)
            }
        )
        .alert(
            Text(model.alert?.title ?? ""),
            isPresented: alertBinding,
            presenting: model.alert
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        // A view já traz a própria `NavigationStack` e o botão "Fechar".
        .sheet(isPresented: $isShowingRenewalHelp) {
            RenewalHelpView(
                expiry: coach.provisioningExpiry,
                isReminderEnabled: coach.isExpiryReminderEnabled,
                onReminderChange: { enabled in
                    coach.setExpiryReminderEnabled(enabled)
                }
            )
        }
    }

    // MARK: - Apresentações

    /// Uma exportação só tem um `fileExporter` ligado: o desta tela ou o do `RootView`.
    private var exporterBinding: Binding<Bool> {
        presentsExportAndAlerts ? $model.isExporterPresented : .constant(false)
    }

    /// Idem para o alerta de resultado.
    private var alertBinding: Binding<Bool> {
        presentsExportAndAlerts ? $model.isAlertPresented : .constant(false)
    }

    // MARK: - Seções

    /// SPEC §7.5 (c): pedido manual de semana leve, sem esperar o intervalo automático
    /// ("Mais opções").
    private var deloadSection: some View {
        Section {
            Button {
                model.requestDeload()
            } label: {
                Label("Fazer semana leve agora", systemImage: "wind")
            }
            .confirmationDialog(
                "Fazer semana leve agora?",
                isPresented: $model.isConfirmingDeload,
                titleVisibility: .visible
            ) {
                Button("Programar semana leve") {
                    model.confirmDeload()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("As próximas sessões, uma de cada dia do programa, vêm com menos séries e carga um pouco menor. Depois tudo volta ao normal.")
            }
        } header: {
            Text("Semana leve")
        } footer: {
            Text("Não precisa esperar o intervalo automático: peça quando sentir que precisa de um alívio no volume e na carga.")
        }
    }

    /// "Mais opções" (SPEC RF-39, §7.5 b): seletor por frequência, semanas entre semanas leves,
    /// referências científicas e versão.
    private var moreOptionsSection: some View {
        Section {
            NavigationLink {
                MoreOptionsView(model: model, references: references)
            } label: {
                Label("Mais opções", systemImage: "ellipsis.circle")
            }
        }
    }

    /// SPEC §7.11 C4: aviso local às 10h da véspera de a instalação expirar.
    private var remindersSection: some View {
        let isReminderOn = coach.isExpiryReminderEnabled
        return Section {
            Toggle(
                "Avisar na véspera de o app expirar",
                isOn: Binding<Bool>(
                    get: { isReminderOn },
                    set: { enabled in
                        coach.setExpiryReminderEnabled(enabled)
                    }
                )
            )
            Button {
                isShowingRenewalHelp = true
            } label: {
                Label("Como renovar", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("Avisos")
        } footer: {
            Text(Self.expiryFooter(coach.provisioningExpiry))
        }
    }

    /// SPEC §7.10: idade, sexo e FC máxima quando o app Saúde não informa.
    private var healthSection: some View {
        Section {
            NavigationLink {
                HealthProfileView(model: health)
            } label: {
                Label("Perfil de saúde", systemImage: "heart.text.square")
            }
        } header: {
            Text("Saúde")
        } footer: {
            Text("Ano de nascimento, sexo e frequência cardíaca máxima, usados nas faixas de VO2máx e de intensidade do aeróbico.")
        }
    }

    private var backupSection: some View {
        Section {
            Button {
                model.prepareExport()
            } label: {
                Label("Exportar backup", systemImage: "square.and.arrow.up")
            }
            Button {
                model.startImport()
            } label: {
                Label("Importar backup", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("Os dados ficam só neste iPhone. Exporte um backup para o app Arquivos antes de reinstalar ou apagar o app. Importar substitui tudo o que está aqui.")
        }
    }

    // MARK: - Textos

    /// "Semana leve a cada 6 semanas", "a cada semana", "desligada" (0).
    static func deloadWeeksText(_ weeks: Int) -> String {
        switch weeks {
        case ...0:
            return "Semana leve programada: desligada"
        case 1:
            return "Semana leve a cada semana"
        default:
            return "Semana leve a cada \(weeks) semanas"
        }
    }

    /// Validade da instalação (perfil embutido); no simulador não há data.
    static func expiryFooter(_ expiry: Date?) -> String {
        let permission = "O aviso chega às 10h do dia anterior. Na primeira vez, o iPhone pergunta se o Magister pode mandar notificações."
        guard let expiry else {
            return "A data de validade aparece quando o app é instalado no iPhone pelo Impactor. " + permission
        }
        let style = Date.FormatStyle(locale: Locale(identifier: "pt_BR"), calendar: .current, timeZone: .current)
            .day()
            .month(.wide)
            .hour()
            .minute()
        return "Esta instalação vale até \(expiry.formatted(style)). " + permission
    }
}
