import Foundation
import SwiftData
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T1.9 (CA1-7): formatação pt-BR do histórico e filtro de sessões em andamento.
/// Tudo em `@MainActor` (ARCHITECTURE §10); container in-memory; sem `Task.sleep`.
@MainActor
final class HistoryTests: XCTestCase {
    // MARK: - DateFormatting.shortDate

    func testShortDate_ptBR_hasWeekdayDayMonthAndTime() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // 2026-09-22 é terça-feira: o exemplo da tarefa, "ter., 22 de set. · 19:40".
        let date = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 19, minute: 40))
        )

        let text = DateFormatting.shortDate(date, timeZone: timeZone)

        // As abreviações exatas ("ter.", "set.") dependem da versão do ICU do runner; as
        // asserções checam as partes que não mudam entre versões.
        XCTAssertTrue(text.lowercased().hasPrefix("ter"), text)
        XCTAssertTrue(text.contains("22"), text)
        XCTAssertTrue(text.lowercased().contains("set"), text)
        XCTAssertTrue(text.contains(" · "), text)
        XCTAssertTrue(text.hasSuffix("19:40"), text)
    }

    func testShortDate_respectsTimeZone() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let saoPaulo = try XCTUnwrap(TimeZone(identifier: "America/Sao_Paulo"))
        // 2026-09-22T22:40:00Z = 19:40 em São Paulo (UTC−3; o Brasil não tem horário de verão).
        let date = Date(timeIntervalSince1970: 1_790_116_800)

        XCTAssertTrue(DateFormatting.shortDate(date, timeZone: utc).hasSuffix("22:40"))
        XCTAssertTrue(DateFormatting.shortDate(date, timeZone: saoPaulo).hasSuffix("19:40"))
    }

    // MARK: - DateFormatting.duration

    func testDuration_formatsHoursWithPaddedMinutes() {
        XCTAssertEqual(DateFormatting.duration(3_900), "1 h 05 min")
        XCTAssertEqual(DateFormatting.duration(7_200), "2 h 00 min")
        XCTAssertEqual(DateFormatting.duration(5_400), "1 h 30 min")
    }

    func testDuration_belowOneHour_showsOnlyMinutes() {
        XCTAssertEqual(DateFormatting.duration(2_700), "45 min")
        XCTAssertEqual(DateFormatting.duration(59), "0 min")
        XCTAssertEqual(DateFormatting.duration(0), "0 min")
    }

    func testDuration_nil_isInProgress() {
        XCTAssertEqual(DateFormatting.duration(nil), "Em andamento")
    }

    func testDuration_negativeOrNonFinite_neverCrashes() {
        XCTAssertEqual(DateFormatting.duration(-30), "0 min")
        XCTAssertEqual(DateFormatting.duration(.infinity), "—")
        XCTAssertEqual(DateFormatting.duration(.nan), "—")
    }

    // MARK: - HistoryListView.filterVisible

    func testFilterVisible_dropsInProgressAndKeepsNewestFirst() throws {
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        insertSession(status: .completed, startedAt: base, into: context)
        insertSession(status: .inProgress, startedAt: base.addingTimeInterval(2 * 86_400), into: context)
        insertSession(status: .abandoned, startedAt: base.addingTimeInterval(86_400), into: context)
        try context.save()

        let descriptor = FetchDescriptor<WorkoutSessionModel>(
            sortBy: [SortDescriptor(\WorkoutSessionModel.startedAt, order: .reverse)]
        )
        let all = try context.fetch(descriptor)
        let visible = HistoryListView.filterVisible(all)

        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(visible.map { $0.statusRaw }, ["abandoned", "completed"])
    }

    func testFilterVisible_keepsUnknownStatusRaw() throws {
        // Um raw desconhecido indica store corrompido; o histórico prefere mostrar a
        // sessão (sem badge) a escondê-la em silêncio.
        let container = try ModelContainerFactory.make(.inMemory)
        let context = container.mainContext
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: "paused",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: "iphone"
        )
        context.insert(session)

        XCTAssertEqual(HistoryListView.filterVisible([session]).count, 1)
    }

    // MARK: - Fixtures

    private func insertSession(
        status: SessionStatus,
        startedAt: Date,
        into context: ModelContext
    ) {
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: UUID(),
            programDayName: "Dia A",
            statusRaw: status.rawValue,
            startedAt: startedAt,
            endedAt: status == .inProgress ? nil : startedAt.addingTimeInterval(3_600),
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: "iphone"
        )
        context.insert(session)
    }
}
