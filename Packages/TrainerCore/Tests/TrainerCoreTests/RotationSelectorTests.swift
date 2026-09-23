import Foundation
import Testing
@testable import TrainerCore

/// Table cases for SPEC §7.3 v1 (S1–S4). Dates are fixed; nothing here reads the clock.
@Suite("RotationSelector")
struct RotationSelectorTests {
    private let selector = RotationSelector()

    // MARK: S1 — ordered days

    @Test("S1 programa vazio → nil")
    func S1_emptyProgram_returnsNil() {
        let program = ProgramTemplate(name: "Vazio", days: [], isActive: true)

        let result = selector.nextDay(program: program, recentSessions: [], now: Fixture.now)

        #expect(result == nil)
    }

    @Test("S1 dias fora de ordem no array respeitam 'order'")
    func S1_daysOutOfArrayOrder_followOrderField() {
        // Array layout is C, A, B but `order` says A (0), B (1), C (2).
        let program = ProgramTemplate(
            name: "Embaralhado",
            days: [Fixture.dayC, Fixture.dayA, Fixture.dayB],
            isActive: true
        )

        let fromStart = selector.nextDay(program: program, recentSessions: [], now: Fixture.now)
        let afterA = selector.nextDay(
            program: program,
            recentSessions: [Fixture.session(day: Fixture.dayA, startedAt: Fixture.t1)],
            now: Fixture.now
        )
        let afterC = selector.nextDay(
            program: program,
            recentSessions: [Fixture.session(day: Fixture.dayC, startedAt: Fixture.t1)],
            now: Fixture.now
        )

        #expect(fromStart == Fixture.dayA)
        #expect(afterA == Fixture.dayB)
        #expect(afterC == Fixture.dayA)
    }

    @Test("S1 'order' não contíguo ainda roda pela posição ordenada")
    func S1_nonContiguousOrder_rotatesByRank() {
        let first = ProgramDayTemplate(id: Fixture.id(11), name: "D-0", order: 0)
        let second = ProgramDayTemplate(id: Fixture.id(12), name: "D-5", order: 5)
        let third = ProgramDayTemplate(id: Fixture.id(13), name: "D-10", order: 10)
        let program = ProgramTemplate(name: "Esparso", days: [third, first, second], isActive: true)

        let afterFirst = selector.nextDay(
            program: program,
            recentSessions: [Fixture.session(day: first, startedAt: Fixture.t1)],
            now: Fixture.now
        )

        #expect(afterFirst == second)
    }

    @Test("S1 programa de um dia só volta sempre para ele")
    func S1_singleDayProgram_alwaysReturnsThatDay() {
        let program = ProgramTemplate(name: "Único", days: [Fixture.dayA], isActive: true)

        let afterA = selector.nextDay(
            program: program,
            recentSessions: [Fixture.session(day: Fixture.dayA, startedAt: Fixture.t1)],
            now: Fixture.now
        )

        #expect(afterA == Fixture.dayA)
    }

    // MARK: S2 — next after the last finished session with working sets

    @Test("S2 sem sessões → D1")
    func S2_noSessions_returnsFirstDay() {
        let result = selector.nextDay(program: Fixture.program, recentSessions: [], now: Fixture.now)

        #expect(result == Fixture.dayA)
    }

    @Test("S2 após A → B")
    func S2_afterA_returnsB() {
        let sessions = [Fixture.session(day: Fixture.dayA, startedAt: Fixture.t1)]

        let result = selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now)

        #expect(result == Fixture.dayB)
    }

    @Test("S2 após C (último) → A")
    func S2_afterLastDay_wrapsToFirst() {
        let sessions = [
            Fixture.session(day: Fixture.dayA, startedAt: Fixture.t1),
            Fixture.session(day: Fixture.dayB, startedAt: Fixture.t2),
            Fixture.session(day: Fixture.dayC, startedAt: Fixture.t3),
        ]

        let result = selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now)

        #expect(result == Fixture.dayA)
    }

    @Test("S2 abandonada com séries conta")
    func S2_abandonedWithWorkingSets_counts() {
        let sessions = [
            Fixture.session(day: Fixture.dayA, startedAt: Fixture.t1),
            Fixture.session(day: Fixture.dayB, startedAt: Fixture.t2, status: .abandoned, workingSets: 1),
        ]

        let result = selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now)

        #expect(result == Fixture.dayC)
    }

    @Test("S2 abandonada sem séries não conta (usa a anterior)")
    func S2_abandonedWithoutWorkingSets_usesPreviousSession() {
        let sessions = [
            Fixture.session(day: Fixture.dayA, startedAt: Fixture.t1),
            Fixture.session(day: Fixture.dayB, startedAt: Fixture.t2, status: .abandoned, workingSets: 0),
        ]

        let result = selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now)

        #expect(result == Fixture.dayB)
    }

    @Test("S2 concluída sem séries de trabalho também não conta")
    func S2_completedWithoutWorkingSets_usesPreviousSession() {
        let sessions = [
            Fixture.session(day: Fixture.dayA, startedAt: Fixture.t1),
            Fixture.session(day: Fixture.dayB, startedAt: Fixture.t2, status: .completed, workingSets: 0),
        ]

        let result = selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now)

        #expect(result == Fixture.dayB)
    }

    @Test("S2 só sessões sem séries → D1")
    func S2_onlySessionsWithoutWorkingSets_returnsFirstDay() {
        let sessions = [
            Fixture.session(day: Fixture.dayB, startedAt: Fixture.t1, status: .abandoned, workingSets: 0),
            Fixture.session(day: Fixture.dayC, startedAt: Fixture.t2, status: .completed, workingSets: 0),
        ]

        let result = selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now)

        #expect(result == Fixture.dayA)
    }

    @Test("S2 dayID desconhecido (programa mudou) → D1")
    func S2_unknownProgramDayID_returnsFirstDay() {
        let removedDay = ProgramDayTemplate(id: Fixture.id(99), name: "Dia removido", order: 3)
        let sessions = [
            Fixture.session(day: Fixture.dayA, startedAt: Fixture.t1),
            Fixture.session(day: removedDay, startedAt: Fixture.t2),
        ]

        let result = selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now)

        #expect(result == Fixture.dayA)
    }

    @Test("S2 ordem embaralhada de recentSessions → mesmo resultado")
    func S2_shuffledRecentSessions_sameResult() {
        let a = Fixture.session(day: Fixture.dayA, startedAt: Fixture.t1)
        let b = Fixture.session(day: Fixture.dayB, startedAt: Fixture.t2)
        let cWithoutSets = Fixture.session(day: Fixture.dayC, startedAt: Fixture.t3, status: .abandoned, workingSets: 0)
        let open = Fixture.session(day: Fixture.dayC, startedAt: Fixture.t4, status: .inProgress, workingSets: 0)

        // Explicit permutations keep the test itself deterministic (no `.shuffled()`).
        let permutations: [[SessionSummary]] = [
            [a, b, cWithoutSets, open],
            [open, cWithoutSets, b, a],
            [b, open, a, cWithoutSets],
            [cWithoutSets, a, open, b],
        ]

        for sessions in permutations {
            let result = selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now)
            #expect(result == Fixture.dayC, "permutation \(sessions.map(\.programDayID))")
        }
    }

    @Test("S2 mesmo instante: a sessão de id maior é a referência, em qualquer ordem (P11)")
    func S2_sameInstant_higherSessionIDIsTheReference() {
        let a = Fixture.session(day: Fixture.dayA, startedAt: Fixture.t1, id: Fixture.id(0x0A))
        let b = Fixture.session(day: Fixture.dayB, startedAt: Fixture.t1, id: Fixture.id(0x0B))

        let ab = selector.nextDay(program: Fixture.program, recentSessions: [a, b], now: Fixture.now)
        let ba = selector.nextDay(program: Fixture.program, recentSessions: [b, a], now: Fixture.now)

        // B (…0B) outranks A (…0A) — the same convention as DoubleProgressionRule —
        // so the rotation continues after B.
        #expect(ab == Fixture.dayC)
        #expect(ba == Fixture.dayC)
    }

    @Test("S2 mesma entrada duas vezes → mesma saída (determinismo)")
    func S2_sameInputTwice_sameOutput() {
        let sessions = [
            Fixture.session(day: Fixture.dayC, startedAt: Fixture.t1),
            Fixture.session(day: Fixture.dayA, startedAt: Fixture.t2),
        ]

        let first = selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now)
        let second = selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now)

        #expect(first == Fixture.dayB)
        #expect(first == second)
    }

    // MARK: S3 — in-progress sessions belong to the SessionPlanner

    @Test("S3 sessão inProgress é ignorada pelo seletor")
    func S3_inProgressSession_isIgnored() {
        let sessions = [
            Fixture.session(day: Fixture.dayA, startedAt: Fixture.t1),
            // Even with working sets logged, an open session never moves the rotation.
            Fixture.session(day: Fixture.dayB, startedAt: Fixture.t2, status: .inProgress, workingSets: 4),
        ]

        let result = selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now)

        #expect(result == Fixture.dayB)
    }

    // MARK: S4 — manual override

    @Test("S4 sessão em C escolhida manualmente → A")
    func S4_manuallyChosenDay_rotationContinuesFromIt() {
        // Rotation said B was next after A, but the user picked C by hand and trained it.
        let sessions = [
            Fixture.session(day: Fixture.dayA, startedAt: Fixture.t1),
            Fixture.session(day: Fixture.dayC, startedAt: Fixture.t2),
        ]

        let result = selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now)

        #expect(result == Fixture.dayA)
    }
}

// MARK: - Fixtures

private enum Fixture {
    static let dayA = ProgramDayTemplate(id: id(1), name: "Dia A", order: 0)
    static let dayB = ProgramDayTemplate(id: id(2), name: "Dia B", order: 1)
    static let dayC = ProgramDayTemplate(id: id(3), name: "Dia C", order: 2)

    static let program = ProgramTemplate(name: "ABC", days: [dayA, dayB, dayC], isActive: true)

    /// Fixed instants; `t1 < t2 < t3 < t4 < now`.
    static let t1: TimeInterval = 1_700_000_000
    static let t2: TimeInterval = 1_700_172_800 // +2 days
    static let t3: TimeInterval = 1_700_345_600 // +4 days
    static let t4: TimeInterval = 1_700_518_400 // +6 days
    static let now = Date(timeIntervalSince1970: 1_700_691_200) // +8 days

    /// Stable, readable UUIDs so failures print which day was involved.
    static func id(_ n: UInt8) -> UUID {
        let hex = String(n, radix: 16).uppercased()
        let suffix = String(repeating: "0", count: 12 - hex.count) + hex
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }

    /// The session id defaults to a value derived from the day and the instant, so a
    /// fixture never depends on `UUID()` randomness (SPEC P11). Two sessions of the
    /// same day at the same instant would share it; tie-break tests pass explicit ids.
    static func session(
        day: ProgramDayTemplate,
        startedAt: TimeInterval,
        status: SessionStatus = .completed,
        workingSets: Int = 9,
        id: UUID? = nil
    ) -> SessionSummary {
        SessionSummary(
            id: id ?? derivedID(day: day, startedAt: startedAt),
            programDayID: day.id,
            startedAt: Date(timeIntervalSince1970: startedAt),
            endedAt: status == .inProgress ? nil : Date(timeIntervalSince1970: startedAt + 3_600),
            status: status,
            workingSetCount: workingSets
        )
    }

    private static func derivedID(day: ProgramDayTemplate, startedAt: TimeInterval) -> UUID {
        let stamp = String(UInt64(startedAt), radix: 16).uppercased()
        let node = String(repeating: "0", count: max(0, 12 - stamp.count)) + stamp
        let order = String(UInt16(truncatingIfNeeded: day.order), radix: 16).uppercased()
        let group = String(repeating: "0", count: 4 - order.count) + order
        return UUID(uuidString: "00000000-0000-0000-\(group)-\(node)")!
    }
}
