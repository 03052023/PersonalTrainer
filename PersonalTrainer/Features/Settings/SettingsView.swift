import SwiftUI
import TrainerCore
import UniformTypeIdentifiers

/// Aba Ajustes (T2.4, SPEC RF-18, RF-32, RF-39, §7.5, §7.10, §7.11; contrato V2-FINAL §2.6):
/// planejamento (seletor por frequência, semanas entre semanas leves, "Fazer semana leve agora"),
/// avisos (véspera da validade da instalação), perfil de saúde, backup, referências científicas e
/// versão do app.
///
/// Traz a própria `NavigationStack`; quem a coloca numa aba não deve aninhá-la em outra.
/// Nenhuma escrita no `ModelContext` (AGENTS R4): backup por `BackupServicing` e semana leve por
/// `SessionPlanning`, via `SettingsViewModel`; o aviso de validade pelo `CoachService`, que pede a
/// permissão de notificação só quando a pessoa liga o interruptor (AGENTS §7). Depois de importar
/// ou de programar uma semana leve, `onDataChanged` avisa o integrador para reler a Home.
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
        self._model = State(initialValue: SettingsViewModel(
            backup: backup,
            planner: planner,
            now: now,
            appVersion: SettingsViewModel.bundleVersion(.main),
            defaults: defaults,
            onDataChanged: onDataChanged
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                planningSection
                remindersSection
                healthSection
                backupSection
                scienceSection
                aboutSection
            }
            .navigationTitle("Ajustes")
            // Rótulo `onCompletion:` explícito: o iOS 17 acrescentou sobrecargas com
            // `onCancellation:` e o fechamento final poderia ficar ambíguo.
            .fileExporter(
                isPresented: $model.isExporterPresented,
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
                Text("Isso substitui todas as sessões atuais, os programas, o catálogo e os ajustes pelo conteúdo de \(model.pendingImportFileName). Não dá para desfazer.")
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
            isPresented: $model.isAlertPresented,
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

    // MARK: - Seções

    /// SPEC RF-39 (seletor por frequência, chave `plannerFrequencySelector`) e §7.5 (semanas
    /// entre semanas leves, `plannerDeloadWeeks`; pedido manual).
    private var planningSection: some View {
        // Valores lidos aqui, no corpo: a view depende deles e os `Binding`s abaixo ficam em dia.
        let mode = model.frequencySelector
        let weeks = model.deloadWeeks
        return Section {
            Picker(
                "Seletor por frequência",
                selection: Binding<PlannerSettings.FrequencySelectorMode>(
                    get: { mode },
                    set: { newMode in
                        model.setFrequencySelector(newMode)
                    }
                )
            ) {
                Text("Automático").tag(PlannerSettings.FrequencySelectorMode.auto)
                Text("Ligado").tag(PlannerSettings.FrequencySelectorMode.on)
                Text("Desligado").tag(PlannerSettings.FrequencySelectorMode.off)
            }
            Stepper(
                value: Binding<Int>(
                    get: { weeks },
                    set: { newWeeks in
                        model.setDeloadWeeks(newWeeks)
                    }
                ),
                in: SettingsViewModel.deloadWeeksRange
            ) {
                Text(Self.deloadWeeksText(weeks))
            }
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
            Text("Planejamento")
        } footer: {
            Text("Com o seletor por frequência, o próximo dia é o que treina os grupos mais abaixo da meta da semana. No automático, ele liga em programas com 4 dias ou mais. A semana leve reduz o volume por uma passagem pelo programa para você recuperar; o app a programa sozinho no intervalo escolhido.")
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

    private var scienceSection: some View {
        Section {
            NavigationLink {
                ReferenceListView(catalog: references)
            } label: {
                Label("Referências científicas", systemImage: "book")
            }
        } header: {
            Text("Ciência")
        } footer: {
            Text("As fontes por trás das regras de progressão, volume, descanso e objetivos.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Versão", value: model.appVersion)
        } header: {
            Text("Sobre")
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
