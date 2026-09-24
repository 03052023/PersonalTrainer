import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Contrato V2-FINAL §2.3: `LiveCoachLogStore` (JSON em disco, escrita atômica, leitura tolerante)
/// e `FakeCoachLogStore` (memória, falha simulada).
@MainActor
final class CoachLogStoreTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_262_000)

    // MARK: - Live

    func testLive_emptyDirectory_readsAsNothingStored() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LiveCoachLogStore(directory: directory)

        XCTAssertEqual(store.load(), CoachLog())
        XCTAssertNil(store.loadLastReview())
    }

    func testLive_roundTripsTheLogAcrossInstances() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = CoachLog(
            entries: [
                CoachLogEntry(messageID: "deload:2026-09-24", rule: .deload, itemKey: "scheduled", action: .ok, date: date),
                CoachLogEntry(messageID: "health:lowSleep:2026-09-24", rule: .health, itemKey: "lowSleep", action: .neverAgain, date: date.addingTimeInterval(0.25)),
            ],
            lastReviewAt: date
        )

        try LiveCoachLogStore(directory: directory).save(log)

        XCTAssertEqual(LiveCoachLogStore(directory: directory).load(), log, "Datas com fração de segundo sobrevivem")
        let fileURL = directory.appendingPathComponent(LiveCoachLogStore.logFileName, isDirectory: false)
        XCTAssertNoThrow(try Data(contentsOf: fileURL))
    }

    func testLive_roundTripsTheLastReview() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = ReviewReport(
            generatedAt: date,
            stagnantExerciseIDs: [UUID()],
            fatigueHigh: true,
            weeklySetsByMuscle: [.chest: 8.5, .back: 12],
            adherence: 0.75,
            suggestions: [
                ProgramSuggestion(
                    id: "changeRepRange:abc:2026-W39",
                    kind: .changeRepRange,
                    rule: "R5",
                    title: "Trocar a faixa de repetições",
                    reason: "Sem progresso nas últimas 3 sessões.",
                    targetIDs: [UUID()],
                    proposedRepRange: 6...10,
                    referenceTopic: "topic.substitution"
                ),
            ]
        )

        try LiveCoachLogStore(directory: directory).saveLastReview(report)

        XCTAssertEqual(LiveCoachLogStore(directory: directory).loadLastReview(), report)
    }

    func testLive_createsTheDirectoryOnFirstSave() throws {
        let parent = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("PersonalTrainer", isDirectory: true)
        let store = LiveCoachLogStore(directory: directory)

        try store.save(CoachLog(lastReviewAt: date))

        XCTAssertEqual(store.load().lastReviewAt, date)
    }

    func testLive_unreadableFile_readsAsEmptyAndIsReplacedOnSave() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent(LiveCoachLogStore.logFileName, isDirectory: false)
        try Data("não é JSON".utf8).write(to: fileURL)
        let store = LiveCoachLogStore(directory: directory)

        XCTAssertEqual(store.load(), CoachLog(), "Arquivo ilegível não trava a Home")
        try store.save(CoachLog(lastReviewAt: date))
        XCTAssertEqual(store.load().lastReviewAt, date)
    }

    func testLive_withoutDirectory_readsEmptyAndRefusesToSave() {
        let store = LiveCoachLogStore(directory: nil)

        XCTAssertEqual(store.load(), CoachLog())
        XCTAssertNil(store.loadLastReview())
        XCTAssertThrowsError(try store.save(CoachLog())) { error in
            XCTAssertEqual(error as? CoachLogStoreError, .directoryUnavailable)
        }
    }

    func testLive_defaultDirectory_isInsideApplicationSupport() throws {
        let directory = try XCTUnwrap(LiveCoachLogStore.defaultDirectory())
        XCTAssertEqual(directory.lastPathComponent, "PersonalTrainer")
    }

    // MARK: - Fake

    func testFake_savesInMemoryAndCounts() throws {
        let store = FakeCoachLogStore()
        var log = CoachLog()
        log.lastReviewAt = date

        try store.save(log)

        XCTAssertEqual(store.load(), log)
        XCTAssertEqual(store.saveCount, 1)
    }

    func testFake_saveError_changesNothing() {
        let store = FakeCoachLogStore()
        store.saveError = CoachTestError.disk

        XCTAssertThrowsError(try store.save(CoachLog(lastReviewAt: date)))
        XCTAssertEqual(store.load(), CoachLog())
        XCTAssertEqual(store.saveCount, 0)
    }

    // MARK: - Apoio

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoachLogStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
