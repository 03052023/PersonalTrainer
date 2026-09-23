import Foundation
import XCTest
@testable import PersonalTrainer

/// T1.3: janela de ids aplicados (ARCHITECTURE §7, passo 1). Cobre o modo em memória, a
/// capacidade (remove o mais antigo) e a persistência em `UserDefaults` entre instâncias.
@MainActor
final class AppliedEventStoreTests: XCTestCase {
    // MARK: - Em memória

    func testInMemory_startsEmptyAndRemembersInsertedIDs() {
        let store = AppliedEventStore.inMemory()
        let id = UUID()

        XCTAssertFalse(store.contains(id))
        store.insert(id)

        XCTAssertTrue(store.contains(id))
        XCTAssertFalse(store.contains(UUID()))
    }

    func testInMemory_instancesAreIndependent() {
        let first = AppliedEventStore.inMemory()
        let second = AppliedEventStore.inMemory()
        let id = UUID()

        first.insert(id)

        XCTAssertTrue(first.contains(id))
        XCTAssertFalse(second.contains(id), "Nada é compartilhado nem persiste entre instâncias em memória")
    }

    // MARK: - Capacidade

    func testCapacity_evictsOldestFirst() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppliedEventStore(userDefaults: defaults, key: "ids", capacity: 3)
        let ids = (0..<4).map { _ in UUID() }

        for id in ids {
            store.insert(id)
        }

        XCTAssertFalse(store.contains(ids[0]), "O mais antigo sai quando a janela excede a capacidade")
        XCTAssertTrue(store.contains(ids[1]))
        XCTAssertTrue(store.contains(ids[2]))
        XCTAssertTrue(store.contains(ids[3]))
        XCTAssertEqual(
            defaults.stringArray(forKey: "ids"),
            [ids[1].uuidString, ids[2].uuidString, ids[3].uuidString]
        )
    }

    func testInsert_sameIDTwice_doesNotConsumeCapacity() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppliedEventStore(userDefaults: defaults, key: "ids", capacity: 2)
        let first = UUID()
        let second = UUID()

        store.insert(first)
        store.insert(first)
        store.insert(second)

        XCTAssertTrue(store.contains(first))
        XCTAssertTrue(store.contains(second))
        XCTAssertEqual(defaults.stringArray(forKey: "ids"), [first.uuidString, second.uuidString])
    }

    func testCapacity_belowOne_isClampedToOne() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppliedEventStore(userDefaults: defaults, key: "ids", capacity: 0)
        let first = UUID()
        let second = UUID()

        store.insert(first)
        XCTAssertTrue(store.contains(first))

        store.insert(second)
        XCTAssertFalse(store.contains(first))
        XCTAssertTrue(store.contains(second))
        XCTAssertEqual(defaults.stringArray(forKey: "ids"), [second.uuidString])
    }

    // MARK: - Persistência

    func testPersistence_newInstanceWithSameDefaultsSeesPreviousIDs() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID()
        let second = UUID()

        let writer = AppliedEventStore(userDefaults: defaults, key: "appliedEventIDs")
        writer.insert(first)
        writer.insert(second)

        let reader = AppliedEventStore(userDefaults: defaults, key: "appliedEventIDs")
        XCTAssertTrue(reader.contains(first))
        XCTAssertTrue(reader.contains(second))
        XCTAssertFalse(reader.contains(UUID()))

        let otherKey = AppliedEventStore(userDefaults: defaults, key: "outraChave")
        XCTAssertFalse(otherKey.contains(first), "Chaves diferentes são janelas independentes")
    }

    func testPersistence_readerKeepsEvictingInInsertionOrder() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let ids = (0..<3).map { _ in UUID() }

        let writer = AppliedEventStore(userDefaults: defaults, key: "ids", capacity: 3)
        writer.insert(ids[0])
        writer.insert(ids[1])

        // A nova instância herda a ordem gravada: ao estourar, sai `ids[0]`, não o que ela viu primeiro.
        let reader = AppliedEventStore(userDefaults: defaults, key: "ids", capacity: 3)
        reader.insert(ids[2])
        reader.insert(UUID())

        XCTAssertFalse(reader.contains(ids[0]))
        XCTAssertTrue(reader.contains(ids[1]))
        XCTAssertTrue(reader.contains(ids[2]))
    }

    func testInit_trimsStoredListToCapacityKeepingNewest() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let ids = (0..<5).map { _ in UUID() }
        defaults.set(ids.map { $0.uuidString }, forKey: "ids")

        let store = AppliedEventStore(userDefaults: defaults, key: "ids", capacity: 3)

        XCTAssertFalse(store.contains(ids[0]))
        XCTAssertFalse(store.contains(ids[1]))
        XCTAssertTrue(store.contains(ids[2]))
        XCTAssertTrue(store.contains(ids[3]))
        XCTAssertTrue(store.contains(ids[4]))
    }

    func testInit_ignoresMalformedAndDuplicateEntries() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let valid = UUID()
        defaults.set(["not-a-uuid", valid.uuidString, valid.uuidString], forKey: "ids")

        let store = AppliedEventStore(userDefaults: defaults, key: "ids", capacity: 10)
        XCTAssertTrue(store.contains(valid))

        let next = UUID()
        store.insert(next)

        XCTAssertTrue(store.contains(valid))
        XCTAssertTrue(store.contains(next))
        XCTAssertEqual(
            defaults.stringArray(forKey: "ids"),
            [valid.uuidString, next.uuidString],
            "A próxima gravação normaliza a lista: sem lixo e sem repetições"
        )
    }

    func testInit_withNoStoredValue_startsEmpty() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = AppliedEventStore(userDefaults: defaults)

        XCTAssertFalse(store.contains(UUID()))
        XCTAssertNil(defaults.stringArray(forKey: "appliedEventIDs"), "Nada é gravado até o primeiro insert")
    }

    // MARK: - Suporte

    /// Suite única por teste, limpa antes de usar; o `defer` do chamador apaga ao terminar.
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "AppliedEventStoreTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
