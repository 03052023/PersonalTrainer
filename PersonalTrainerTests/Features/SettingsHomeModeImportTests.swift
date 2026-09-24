import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// v2.1 B1 (docs/V21-CONTRACT.md) no Ajustes:
/// - "Treinar em casa" grava a mesma chave do interruptor da Home (SPEC RF-42);
/// - A5: importar um backup apaga as decisões de semana leve, a última revisão e o
///   `coachPendingDeloadSince`, e mantém o log do diálogo;
/// - B10: o "Fazer backup" do diálogo usa o mesmo `prepareExport()` (a apresentação na raiz é do
///   `RootView`; aqui só o estado que ele observa).
/// Cada teste usa uma suite própria de `UserDefaults` e uma pasta temporária.
@MainActor
final class SettingsHomeModeImportTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_175_600)

    // MARK: - Treinar em casa (RF-42)

    func testRF42_homeMode_defaultsOff_persistsAndNotifiesHome() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let counter = SettingsHomeCallCounter()
        let model = try makeModel(defaults: defaults, onDataChanged: { counter.count += 1 })
        XCTAssertFalse(model.homeModeEnabled)

        model.setHomeModeEnabled(true)

        XCTAssertTrue(model.homeModeEnabled)
        XCTAssertTrue(defaults.bool(forKey: "homeModeEnabled"))
        XCTAssertTrue(PlannerSettings.load(from: defaults).homeModeEnabled, "O planner lê o que o Ajustes gravou")
        XCTAssertEqual(counter.count, 1, "A Home relê o plano")
        XCTAssertTrue(try makeModel(defaults: defaults).homeModeEnabled, "Um Ajustes novo mostra a escolha gravada")
    }

    func testRF42_reloadHomeMode_picksUpTheHomeToggle() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = try makeModel(defaults: defaults)
        XCTAssertFalse(model.homeModeEnabled)

        // O interruptor "Em casa" da Home grava a mesma chave.
        defaults.set(true, forKey: PlannerSettings.homeModeKey)
        model.reloadHomeMode()

        XCTAssertTrue(model.homeModeEnabled)
    }

    // MARK: - A5: importar zera o que foi decidido sobre os dados antigos

    func testA5_successfulImport_clearsDecisionsReviewAndPendingSince_keepsCoachLog() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let decisions = try writeFile("deload-decisions.json", in: folder)
        let review = try writeFile("last-review.json", in: folder)
        let coachLog = try writeFile("coach-log.json", in: folder)
        defaults.set(now.timeIntervalSince1970, forKey: "coachPendingDeloadSince")
        defaults.set("manual", forKey: "coachPendingDeloadTrigger")
        defaults.set(now.timeIntervalSince1970, forKey: "lastBackupAt")
        let counter = SettingsHomeCallCounter()
        let imported = SettingsHomeCallCounter()
        let model = try makeModel(
            defaults: defaults,
            cleanupFiles: [decisions, review],
            onImported: {
                // O diálogo esquece a revisão em memória depois da limpeza dos arquivos.
                XCTAssertFalse(FileManager.default.fileExists(atPath: review.path(percentEncoded: false)))
                imported.count += 1
            },
            onDataChanged: { counter.count += 1 }
        )

        try selectBackupFile(for: model, in: folder)
        XCTAssertTrue(model.isConfirmingImport)
        XCTAssertTrue(FileManager.default.fileExists(atPath: decisions.path(percentEncoded: false)), "Nada muda antes de confirmar")

        model.confirmImport()

        XCTAssertEqual(model.alert?.title, "Backup importado")
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(imported.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: decisions.path(percentEncoded: false)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: review.path(percentEncoded: false)))
        XCTAssertTrue(FileManager.default.fileExists(atPath: coachLog.path(percentEncoded: false)), "O log do diálogo fica")
        XCTAssertNil(defaults.object(forKey: "coachPendingDeloadSince"))
        XCTAssertNil(defaults.object(forKey: "coachPendingDeloadTrigger"))
        XCTAssertNotNil(defaults.object(forKey: "lastBackupAt"), "Só o que valia para os dados antigos é zerado")
    }

    func testA5_failedImport_keepsEverything() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let decisions = try writeFile("deload-decisions.json", in: folder)
        defaults.set(now.timeIntervalSince1970, forKey: "coachPendingDeloadSince")
        let backup = SettingsHomeTestBackup()
        backup.importError = BackupError.corrupted
        let imported = SettingsHomeCallCounter()
        let model = try makeModel(
            defaults: defaults,
            backup: backup,
            cleanupFiles: [decisions],
            onImported: { imported.count += 1 }
        )

        try selectBackupFile(for: model, in: folder)
        model.confirmImport()

        XCTAssertEqual(model.alert?.title, "Backup não importado")
        XCTAssertEqual(imported.count, 0, "Nada foi importado: a revisão do diálogo continua")
        XCTAssertTrue(FileManager.default.fileExists(atPath: decisions.path(percentEncoded: false)))
        XCTAssertNotNil(defaults.object(forKey: "coachPendingDeloadSince"))
    }

    func testA5_cleanup_missingFilesAreNotAFailure() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let folder = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let missing = folder.appendingPathComponent("deload-decisions.json", isDirectory: false)
        let cleanup = BackupImportCleanup(fileURLs: [missing], defaultsKeys: ["coachPendingDeloadSince"], defaults: defaults)

        XCTAssertEqual(cleanup.run(), [])
    }

    func testA5_liveCleanup_targetsAppFilesAndCoachKeys() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let cleanup = BackupImportCleanup.live(defaults: defaults)

        let names = cleanup.fileURLs.map { $0.lastPathComponent }
        XCTAssertTrue(names.contains("deload-decisions.json"))
        XCTAssertTrue(names.contains("last-review.json"))
        XCTAssertFalse(names.contains("coach-log.json"), "O log do diálogo nunca é apagado")
        XCTAssertEqual(cleanup.defaultsKeys, ["coachPendingDeloadSince", "coachPendingDeloadTrigger", "coachLastReviewProgramID"])
        XCTAssertEqual(CoachService.DefaultsKey.lastReviewProgramID, "coachLastReviewProgramID")
        XCTAssertEqual(CoachService.DefaultsKey.pendingDeloadSince, "coachPendingDeloadSince")
    }

    // MARK: - B10: "Fazer backup" abre a exportação

    func testB10_prepareExport_opensExporterWithFile() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = try makeModel(defaults: defaults)

        model.prepareExport()

        XCTAssertTrue(model.isExporterPresented, "O RootView apresenta o fileExporter com este estado")
        XCTAssertNotNil(model.exportDocument)
        XCTAssertEqual(model.exportFileName, "Magister-backup.json")
    }

    // MARK: - Fixtures

    private func makeModel(
        defaults: UserDefaults,
        backup: SettingsHomeTestBackup? = nil,
        cleanupFiles: [URL] = [],
        onImported: @escaping () -> Void = {},
        onDataChanged: @escaping () -> Void = {}
    ) throws -> SettingsViewModel {
        let fixedNow = now
        return SettingsViewModel(
            backup: backup ?? SettingsHomeTestBackup(),
            planner: SettingsHomeTestPlanner(),
            now: { fixedNow },
            appVersion: "0.1.0 (1)",
            defaults: defaults,
            importCleanup: BackupImportCleanup(
                fileURLs: cleanupFiles,
                defaultsKeys: ["coachPendingDeloadSince", "coachPendingDeloadTrigger"],
                defaults: defaults
            ),
            onImported: onImported,
            onDataChanged: onDataChanged
        )
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "SettingsHomeModeImportTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    /// Pasta temporária própria do teste; quem chama apaga com `defer`.
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsHomeModeImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name, isDirectory: false)
        try Data("{}".utf8).write(to: url)
        return url
    }

    /// O arquivo escolhido no `fileImporter`: lido já na seleção, como no app.
    private func selectBackupFile(for model: SettingsViewModel, in folder: URL) throws {
        let file = try writeFile("Magister-backup.json", in: folder)
        model.handleImportSelection(.success(file))
    }
}

// MARK: - Doubles (privados ao arquivo, prefixo "SettingsHome")

@MainActor
private final class SettingsHomeCallCounter {
    var count = 0
}

@MainActor
private final class SettingsHomeTestBackup: BackupServicing {
    var importError: (any Error)?

    func exportBackup(now: Date) throws -> Data {
        Data("{\"schemaVersion\": 1}".utf8)
    }

    func importBackup(_ data: Data) throws -> BackupImportReport {
        if let importError {
            throw importError
        }
        return BackupImportReport(exercises: 1, programs: 1, sessions: 0, sets: 0)
    }

    func suggestedFileName(now: Date) -> String {
        "Magister-backup.json"
    }
}

@MainActor
private final class SettingsHomeTestPlanner: SessionPlanning {
    func nextPlan(now: Date) throws -> SessionPlan? { nil }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? { nil }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID { UUID() }
}
