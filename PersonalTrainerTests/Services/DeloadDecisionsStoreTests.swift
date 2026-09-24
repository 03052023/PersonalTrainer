import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Decisões de semana leve (SPEC §7.5 c, §7.11 C1): o double em memória e o arquivo JSON em
/// Application Support (docs/V2-FINAL-CONTRACT.md §2.2). O arquivo real nunca é tocado: cada
/// teste usa uma pasta temporária própria.
@MainActor
final class DeloadDecisionsStoreTests: XCTestCase {
    private let requestedAt = Date(timeIntervalSince1970: 1_700_000_000)
    /// Com fração de segundo, para provar que a data volta exata (sem arredondar para segundos).
    private let dismissedAt = Date(timeIntervalSince1970: 1_700_086_400.5)

    // MARK: - Fake

    func testFake_startsEmpty_savesAndLoads_andSaveErrorWritesNothing() {
        let store = FakeDeloadDecisionsStore()
        XCTAssertEqual(store.load(), DeloadDecisions())

        let decisions = DeloadDecisions(manualRequestedAt: requestedAt, dismissedAt: nil)
        XCTAssertNoThrow(try store.save(decisions))
        XCTAssertEqual(store.load(), decisions)
        XCTAssertEqual(store.saveCount, 1)

        store.saveError = DeloadDecisionsStoreError.storageUnavailable
        XCTAssertThrowsError(try store.save(DeloadDecisions())) { error in
            XCTAssertEqual(error as? DeloadDecisionsStoreError, .storageUnavailable)
        }
        XCTAssertEqual(store.load(), decisions, "uma gravação que falha não muda nada")
        XCTAssertEqual(store.saveCount, 1)
    }

    // MARK: - Live

    func testLive_missingFile_loadsEmpty() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LiveDeloadDecisionsStore(fileURL: directory.appendingPathComponent("deload-decisions.json", isDirectory: false))

        XCTAssertEqual(store.load(), DeloadDecisions())
    }

    func testLive_saveCreatesFolder_roundTripsExactDates_andOverwrites() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A pasta `PersonalTrainer` ainda não existe: a primeira gravação a cria.
        let fileURL = directory
            .appendingPathComponent("PersonalTrainer", isDirectory: true)
            .appendingPathComponent(LiveDeloadDecisionsStore.fileName, isDirectory: false)
        let store = LiveDeloadDecisionsStore(fileURL: fileURL)
        let decisions = DeloadDecisions(manualRequestedAt: requestedAt, dismissedAt: dismissedAt)

        try store.save(decisions)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
        // Outra instância (o próximo launch) lê os mesmos instantes, com a fração de segundo.
        XCTAssertEqual(LiveDeloadDecisionsStore(fileURL: fileURL).load(), decisions)

        // Gravar substitui por inteiro: o pedido limpo não volta.
        let cleared = DeloadDecisions(manualRequestedAt: nil, dismissedAt: dismissedAt)
        try store.save(cleared)
        XCTAssertEqual(LiveDeloadDecisionsStore(fileURL: fileURL).load(), cleared)
    }

    func testLive_corruptFile_loadsEmpty() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("deload-decisions.json", isDirectory: false)
        try Data("isto não é JSON".utf8).write(to: fileURL)

        XCTAssertEqual(LiveDeloadDecisionsStore(fileURL: fileURL).load(), DeloadDecisions())
    }

    func testLive_fileWithoutDismissedAt_decodesMissingKeyAsNil() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("deload-decisions.json", isDirectory: false)
        // Formato padrão do `JSONEncoder` para `Date`: segundos desde 2001-01-01.
        try Data(#"{"manualRequestedAt":700000000}"#.utf8).write(to: fileURL)

        let loaded = LiveDeloadDecisionsStore(fileURL: fileURL).load()

        XCTAssertEqual(loaded.manualRequestedAt, Date(timeIntervalSinceReferenceDate: 700_000_000))
        XCTAssertNil(loaded.dismissedAt)
    }

    func testLive_withoutLocation_loadsEmpty_andSaveThrowsStorageUnavailable() {
        let store = LiveDeloadDecisionsStore(fileURL: nil)

        XCTAssertEqual(store.load(), DeloadDecisions())
        XCTAssertThrowsError(try store.save(DeloadDecisions(manualRequestedAt: requestedAt))) { error in
            XCTAssertEqual(error as? DeloadDecisionsStoreError, .storageUnavailable)
        }
    }

    func testLive_defaultLocation_isApplicationSupportPersonalTrainer() throws {
        let url = try XCTUnwrap(LiveDeloadDecisionsStore.defaultFileURL())

        XCTAssertEqual(url.lastPathComponent, "deload-decisions.json")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "PersonalTrainer")
        XCTAssertEqual(url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent, "Application Support")
    }

    // MARK: - Apoio

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeloadDecisionsStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
