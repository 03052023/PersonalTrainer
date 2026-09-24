import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Integração onda 3 (contrato V2-FINAL §2.6): o Ajustes grava `lastBackupAt` depois de exportar
/// (SPEC §7.11 C7), guarda os ajustes do planejamento nas chaves de `PlannerSettings` (SPEC RF-39,
/// §7.5 b) e pede a semana leve pelo `SessionPlanning`, com confirmação e explicação quando o
/// pedido não cabe (§7.5 c). Cada teste usa uma suite própria de `UserDefaults`.
@MainActor
final class SettingsViewModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_175_600)

    // MARK: - lastBackupAt (C7)

    func testC7_successfulExport_recordsLastBackupAt() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)
        model.prepareExport()
        XCTAssertTrue(model.isExporterPresented)
        XCTAssertNil(defaults.object(forKey: "lastBackupAt"), "Gerar o arquivo ainda não é backup feito")

        model.handleExportResult(.success(URL(fileURLWithPath: "/tmp/Magister-backup.json")))

        XCTAssertEqual(defaults.double(forKey: "lastBackupAt"), now.timeIntervalSince1970)
        XCTAssertEqual(CoachService.DefaultsKey.lastBackupAt, "lastBackupAt", "Chave compartilhada com o diálogo")
        XCTAssertEqual(model.alert?.title, "Backup salvo")
    }

    func testC7_cancelledOrFailedExport_keepsLastBackupAt() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)
        model.prepareExport()

        model.handleExportResult(.failure(CocoaError(.userCancelled)))
        XCTAssertNil(defaults.object(forKey: "lastBackupAt"))

        model.handleExportResult(.failure(CocoaError(.fileWriteNoPermission)))
        XCTAssertNil(defaults.object(forKey: "lastBackupAt"))
        XCTAssertEqual(model.alert?.title, "Não foi possível salvar")
    }

    // MARK: - Planejamento (RF-39, §7.5 b)

    func testRF39_frequencySelector_defaultsToAuto_andPersistsTheChoice() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)
        XCTAssertEqual(model.frequencySelector, .auto)

        model.setFrequencySelector(.on)
        XCTAssertEqual(model.frequencySelector, .on)
        XCTAssertEqual(defaults.string(forKey: "plannerFrequencySelector"), "on")
        XCTAssertEqual(PlannerSettings.load(from: defaults).frequencySelector, .on, "O planner lê o que o Ajustes gravou")

        model.setFrequencySelector(.off)
        XCTAssertEqual(defaults.string(forKey: "plannerFrequencySelector"), "off")
        XCTAssertEqual(makeModel(defaults: defaults).frequencySelector, .off, "Um Ajustes novo mostra a escolha gravada")
    }

    func testD_deloadWeeks_defaultsToSix_clampsAndPersists() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = makeModel(defaults: defaults)
        XCTAssertEqual(model.deloadWeeks, 6, "SPEC §7.5 (b): padrão 6")

        model.setDeloadWeeks(8)
        XCTAssertEqual(defaults.integer(forKey: "plannerDeloadWeeks"), 8)
        XCTAssertEqual(PlannerSettings.load(from: defaults).deloadWeeks, 8)

        model.setDeloadWeeks(0)
        XCTAssertEqual(model.deloadWeeks, 0)
        XCTAssertEqual(PlannerSettings.load(from: defaults).deloadWeeks, 0, "0 desliga o gatilho por tempo")

        model.setDeloadWeeks(20)
        XCTAssertEqual(model.deloadWeeks, 12, "Limite do Stepper")
        model.setDeloadWeeks(-3)
        XCTAssertEqual(model.deloadWeeks, 0)
        XCTAssertEqual(defaults.integer(forKey: "plannerDeloadWeeks"), 0)
    }

    func testD_deloadWeeksText() {
        XCTAssertEqual(SettingsView.deloadWeeksText(0), "Semana leve programada: desligada")
        XCTAssertEqual(SettingsView.deloadWeeksText(1), "Semana leve a cada semana")
        XCTAssertEqual(SettingsView.deloadWeeksText(6), "Semana leve a cada 6 semanas")
    }

    // MARK: - Fazer semana leve agora (§7.5 c)

    func testD_manual_inactive_asksForConfirmation_thenRequests() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let planner = SettingsTestPlanner()
        let counter = SettingsCallCounter()
        let model = makeModel(defaults: defaults, planner: planner, onDataChanged: { counter.count += 1 })

        model.requestDeload()
        XCTAssertTrue(model.isConfirmingDeload, "Cabe: pede confirmação antes de gravar")
        XCTAssertTrue(planner.requestedAt.isEmpty)

        model.confirmDeload()

        XCTAssertFalse(model.isConfirmingDeload)
        XCTAssertEqual(planner.requestedAt, [now], "SPEC P11: o relógio injetado vai para o planner")
        XCTAssertEqual(model.alert?.title, "Semana leve programada")
        XCTAssertEqual(counter.count, 1, "A Home relê: o próximo plano já é leve")
    }

    func testD_manual_alreadyPendingOrActive_explainsWithoutAsking() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let planner = SettingsTestPlanner()
        planner.status = .pending(trigger: .scheduled)
        let model = makeModel(defaults: defaults, planner: planner)

        model.requestDeload()
        XCTAssertFalse(model.isConfirmingDeload)
        XCTAssertEqual(model.alert?.title, "Semana leve já programada")

        planner.status = .active(start: now.addingTimeInterval(-86_400))
        model.requestDeload()
        XCTAssertFalse(model.isConfirmingDeload)
        XCTAssertEqual(model.alert?.title, "Semana leve em andamento")
        XCTAssertTrue(planner.requestedAt.isEmpty)
    }

    func testD_manual_withoutActiveProgram_explains() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let planner = SettingsTestPlanner()
        planner.days = []
        let model = makeModel(defaults: defaults, planner: planner)

        model.requestDeload()

        XCTAssertFalse(model.isConfirmingDeload)
        XCTAssertEqual(model.alert?.title, "Nenhum programa ativo")
        XCTAssertTrue(planner.requestedAt.isEmpty)
    }

    func testD_manual_requestThatDidNotFit_saysSoAndKeepsHome() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let planner = SettingsTestPlanner()
        planner.statusAfterRequest = .inactive
        let counter = SettingsCallCounter()
        let model = makeModel(defaults: defaults, planner: planner, onDataChanged: { counter.count += 1 })

        model.requestDeload()
        model.confirmDeload()

        XCTAssertEqual(model.alert?.title, "Semana leve não programada")
        XCTAssertEqual(counter.count, 0)
    }

    func testD_manual_plannerFailure_isExplained() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let planner = SettingsTestPlanner()
        planner.requestError = SettingsTestError.boom
        let model = makeModel(defaults: defaults, planner: planner)

        model.requestDeload()
        model.confirmDeload()

        XCTAssertEqual(model.alert?.title, "Não foi possível programar")
    }

    // MARK: - Fixtures

    private func makeModel(
        defaults: UserDefaults,
        planner: SettingsTestPlanner? = nil,
        onDataChanged: @escaping () -> Void = {}
    ) -> SettingsViewModel {
        let fixedNow = now
        return SettingsViewModel(
            backup: SettingsTestBackup(),
            planner: planner ?? SettingsTestPlanner(),
            now: { fixedNow },
            appVersion: "0.1.0 (1)",
            defaults: defaults,
            onDataChanged: onDataChanged
        )
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "SettingsViewModelTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}

// MARK: - Doubles (privados ao arquivo, prefixo "Settings")

private enum SettingsTestError: Error {
    case boom
}

/// Conta as chamadas de `onDataChanged` (classe: o fechamento guarda a referência).
@MainActor
private final class SettingsCallCounter {
    var count = 0
}

@MainActor
private final class SettingsTestBackup: BackupServicing {
    func exportBackup(now: Date) throws -> Data {
        Data("{\"schemaVersion\": 1}".utf8)
    }

    func importBackup(_ data: Data) throws -> BackupImportReport {
        BackupImportReport(exercises: 0, programs: 0, sessions: 0, sets: 0)
    }

    func suggestedFileName(now: Date) -> String {
        "Magister-backup.json"
    }
}

/// Planner com o estado da semana leve controlado pelo teste: `requestDeload` passa o status a
/// `statusAfterRequest` (por padrão `.pending(.manual)`), como o `SessionPlanner` faz quando cabe.
@MainActor
private final class SettingsTestPlanner: SessionPlanning {
    var days: [ProgramDayTemplate] = [ProgramDayTemplate(name: "Dia A", order: 0)]
    var status: DeloadStatus = .inactive
    var statusAfterRequest: DeloadStatus = .pending(trigger: .manual)
    var requestError: (any Error)?
    private(set) var requestedAt: [Date] = []

    func nextPlan(now: Date) throws -> SessionPlan? { nil }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? { nil }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID { UUID() }

    func activeProgramDays() throws -> [ProgramDayTemplate] { days }

    func deloadStatus(now: Date) throws -> DeloadStatus { status }

    func requestDeload(now: Date) throws {
        if let requestError {
            throw requestError
        }
        requestedAt.append(now)
        status = statusAfterRequest
    }
}
