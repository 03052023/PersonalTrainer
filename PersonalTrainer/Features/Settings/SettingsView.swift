import SwiftUI
import TrainerCore
import UniformTypeIdentifiers

/// Aba Ajustes (T2.4, SPEC RF-18/RF-32): backup, referências científicas e versão do app.
///
/// Traz a própria `NavigationStack`; quem a coloca numa aba não deve aninhá-la em outra.
/// Nenhuma escrita no `ModelContext` (AGENTS R4): exportar e importar passam por
/// `BackupServicing`, via `SettingsViewModel`. Depois de importar, `onDataChanged` avisa o
/// integrador para reler o que tem em cache (Home, planner).
///
/// `fileExporter` e `fileImporter` ficam em níveis diferentes da hierarquia: dois seletores de
/// arquivo no mesmo view já deixaram um deles mudo em versões anteriores do SwiftUI.
@MainActor
struct SettingsView: View {
    @State private var model: SettingsViewModel
    private let references: ReferenceCatalog

    /// - Parameter now: relógio da exportação (data do arquivo e `exportedAt`). O padrão é o
    ///   relógio do sistema; o integrador pode passar `environment.now`.
    init(
        backup: any BackupServicing,
        references: ReferenceCatalog,
        onDataChanged: @escaping () -> Void,
        now: @escaping () -> Date = { Date() }
    ) {
        self.references = references
        self._model = State(initialValue: SettingsViewModel(
            backup: backup,
            now: now,
            appVersion: SettingsViewModel.bundleVersion(.main),
            onDataChanged: onDataChanged
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
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
                Text("Isso substitui todos os treinos atuais, os programas, o catálogo e os ajustes pelo conteúdo de \(model.pendingImportFileName). Não dá para desfazer.")
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
    }

    // MARK: - Seções

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
}
