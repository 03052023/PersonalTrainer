import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Atividades fora do app no aparelho (SPEC §7.17 X8, RF-53; docs/V24-CONTRACT.md §4.3): o double em
/// memória e o arquivo JSON em Application Support. O arquivo real nunca é tocado: cada teste usa uma
/// pasta temporária própria.
@MainActor
final class OutsideActivityStoreTests: XCTestCase {
    /// Com fração de segundo, para provar que o início volta exato.
    private let start = Date(timeIntervalSince1970: 1_790_000_000.25)

    // MARK: - Live

    func testX8_storeRoundTrip() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A pasta `PersonalTrainer` ainda não existe: a primeira gravação a cria.
        let fileURL = directory
            .appendingPathComponent("PersonalTrainer", isDirectory: true)
            .appendingPathComponent(LiveOutsideActivityStore.fileName, isDirectory: false)
        let store = LiveOutsideActivityStore(fileURL: fileURL)
        let log = sampleLog()

        try store.save(log)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
        // Outra instância (o próximo launch) lê o mesmo conteúdo, com a fração de segundo do início.
        let loaded = LiveOutsideActivityStore(fileURL: fileURL).load()
        XCTAssertEqual(loaded, log)
        XCTAssertEqual(loaded.entries.first?.start, start)
        XCTAssertEqual(loaded.version, OutsideActivityLog.currentVersion)

        // Gravar substitui por inteiro: o registro apagado não volta.
        var smaller = log
        smaller.entries.removeFirst()
        try store.save(smaller)
        XCTAssertEqual(LiveOutsideActivityStore(fileURL: fileURL).load(), smaller)
    }

    func testX8_missingFileIsEmpty() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LiveOutsideActivityStore(
            fileURL: directory.appendingPathComponent(LiveOutsideActivityStore.fileName, isDirectory: false)
        )

        XCTAssertEqual(store.load(), OutsideActivityLog.empty)
    }

    func testX8_unreadableFileIsEmpty() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent(LiveOutsideActivityStore.fileName, isDirectory: false)
        try Data("isto não é JSON".utf8).write(to: fileURL)
        let store = LiveOutsideActivityStore(fileURL: fileURL)

        XCTAssertEqual(store.load(), OutsideActivityLog.empty)

        // A próxima gravação substitui o arquivo ilegível.
        let log = sampleLog()
        try store.save(log)
        XCTAssertEqual(LiveOutsideActivityStore(fileURL: fileURL).load(), log)
    }

    /// X8: o arquivo que não decodifica sai do caminho, intacto, antes da próxima gravação; nada se perde.
    func testX8_unreadableFileIsKeptAside() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent(LiveOutsideActivityStore.fileName, isDirectory: false)
        let unreadable = Data("{\"entries\":[{\"kind\":\"tipo-novo\"}]}".utf8)
        try unreadable.write(to: fileURL)
        let store = LiveOutsideActivityStore(fileURL: fileURL)

        XCTAssertEqual(store.load(), OutsideActivityLog.empty)
        let log = sampleLog()
        try store.save(log)

        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
        let aside = names.filter { $0.hasPrefix("outside-activities.unreadable-") && $0.hasSuffix(".json") }
        XCTAssertEqual(aside.count, 1)
        let asideName = try XCTUnwrap(aside.first)
        let kept = try Data(contentsOf: directory.appendingPathComponent(asideName, isDirectory: false))
        XCTAssertEqual(kept, unreadable, "o original fica guardado como estava")
        XCTAssertEqual(LiveOutsideActivityStore(fileURL: fileURL).load(), log)
    }

    func testX8_fileWithoutFixed_decodesMissingKeysAsEmpty() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent(LiveOutsideActivityStore.fileName, isDirectory: false)
        // Formato padrão do `JSONEncoder` para `Date`: segundos desde 2001-01-01. Sem `version` nem `fixed`.
        let json = """
        {"entries":[{"id":"6F1C2D3E-4B5A-4C7D-8E9F-0A1B2C3D4E5F","intensity":"moderate","kind":"pilates","minutes":50,"start":780000000}]}
        """
        try Data(json.utf8).write(to: fileURL)

        let loaded = LiveOutsideActivityStore(fileURL: fileURL).load()

        XCTAssertEqual(loaded.version, 1)
        XCTAssertEqual(loaded.fixed, [])
        XCTAssertEqual(loaded.entries.count, 1)
        XCTAssertEqual(loaded.entries.first?.kind, .pilates)
        XCTAssertEqual(loaded.entries.first?.start, Date(timeIntervalSinceReferenceDate: 780_000_000))
        XCTAssertNil(loaded.entries.first?.fixedActivityID)
    }

    func testX8_withoutLocation_loadsEmpty_andSaveThrowsStorageUnavailable() {
        let store = LiveOutsideActivityStore(fileURL: nil)

        XCTAssertEqual(store.load(), OutsideActivityLog.empty)
        XCTAssertThrowsError(try store.save(sampleLog())) { error in
            XCTAssertEqual(error as? OutsideActivityStoreError, .storageUnavailable)
        }
    }

    func testX8_defaultLocation_isApplicationSupportPersonalTrainer() throws {
        let url = try XCTUnwrap(LiveOutsideActivityStore.defaultFileURL())

        XCTAssertEqual(url.lastPathComponent, "outside-activities.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "PersonalTrainer")
        XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent, "Application Support")
    }

    // MARK: - Fake

    func testX8_fake_savesLoadsCountsAndSaveErrorWritesNothing() {
        let store = FakeOutsideActivityStore()
        XCTAssertEqual(store.load(), OutsideActivityLog.empty)
        XCTAssertEqual(store.loadCount, 1)

        let log = sampleLog()
        XCTAssertNoThrow(try store.save(log))
        XCTAssertEqual(store.load(), log)
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.loadCount, 2)

        store.saveError = OutsideActivityStoreError.storageUnavailable
        XCTAssertThrowsError(try store.save(OutsideActivityLog.empty)) { error in
            XCTAssertEqual(error as? OutsideActivityStoreError, .storageUnavailable)
        }
        XCTAssertEqual(store.log, log, "uma gravação que falha não muda nada")
        XCTAssertEqual(store.saveCount, 1)
    }

    // MARK: - Apoio

    /// Dois registros (um avulso e o "Feito" de uma fixa) e a fixa.
    private func sampleLog() -> OutsideActivityLog {
        let fixedID = UUID()
        let fixed = FixedOutsideActivity(
            id: fixedID,
            kind: .pilates,
            weekday: .tuesday,
            startMinuteOfDay: 19 * 60,
            minutes: 50,
            intensity: .light
        )
        let single = OutsideActivityEntry(
            kind: .teamSport,
            start: start,
            minutes: 90,
            intensity: .vigorous
        )
        let done = OutsideActivityEntry(
            kind: .pilates,
            start: start.addingTimeInterval(86_400),
            minutes: 50,
            intensity: .light,
            fixedActivityID: fixedID
        )
        return OutsideActivityLog(entries: [single, done], fixed: [fixed])
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OutsideActivityStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
