import Foundation
import Testing
@testable import TrainerCore

/// Table cases for SPEC §7.3 v2 (S5–S7) on top of the §7.4 weekly count.
/// Instants and the calendar are fixed; nothing here reads the clock (SPEC P11).
@Suite("FrequencyAwareSelector")
struct FrequencyAwareSelectorTests {
    // MARK: - S5 — score = primary groups below the weekly target

    @Test("S5 programa vazio → nil")
    func S5_emptyProgram_returnsNil() {
        let program = ProgramTemplate(name: "Vazio", days: [], isActive: true)

        let result = Fixture.selector().nextDay(program: program, recentSessions: [], now: Fixture.now)

        #expect(result == nil)
    }

    @Test("S5 sem histórico: vence o dia com mais grupos abaixo da meta, não D1")
    func S5_noHistory_picksDayWithMostGroupsBelowTarget() {
        // Scores: push 3, pull 2, legs 5. Plain rotation (S2) would say push.
        let result = Fixture.selector().nextDay(
            program: Fixture.program,
            recentSessions: [],
            now: Fixture.now
        )

        #expect(result == Fixture.legs)
    }

    @Test(
        "S5 conta como §7.4: só sessões completed com ≥ 1 série, na semana corrente",
        arguments: FrequencyAwareSelectorTests.WeeklyCountCase.all
    )
    func S5_weeklyCountFollowsSection7_4(_ testCase: WeeklyCountCase) {
        // Two legs sessions ≥ 52 h before `now` (so S6 stays out of the way). Only when
        // they count does legs reach 2/2 on every group and drop to score 0.
        let sessions: [SessionSummary] = testCase.hoursAgo.map {
            Fixture.session(
                Fixture.legs,
                hoursAgo: $0,
                status: testCase.status,
                workingSets: testCase.workingSets
            )
        }

        let result = Fixture.selector().nextDay(
            program: Fixture.program,
            recentSessions: sessions,
            now: Fixture.now
        )

        #expect(result == testCase.expected)
    }

    @Test("S5 meta semanal por grupo e meta padrão são configuráveis", arguments: FrequencyAwareSelectorTests.TargetCase.all)
    func S5_perGroupAndDefaultTargets(_ testCase: TargetCase) {
        // One completed legs session this week (Monday 01:00, 59 h ago): every legs
        // group has 1 this week; push and pull have 0.
        let sessions = [Fixture.session(Fixture.legs, hoursAgo: 59)]
        let selector = Fixture.selector(
            weeklyTargets: testCase.weeklyTargets,
            defaultWeeklyTarget: testCase.defaultTarget
        )

        let result = selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now)

        #expect(result == testCase.expected)
    }

    @Test("S5 semana começa na segunda por padrão e no domingo quando configurado (§7.4)")
    func S5_weekStartIsConfigurable() {
        // Now is Sunday 2024-01-14 12:00Z. Legs was done on Monday and Tuesday of the
        // Monday-started week, days before (S6 does not apply).
        let sunday = Date(timeIntervalSince1970: 1_705_233_600)          // 2024-01-14T12:00:00Z
        let sessions = [
            Fixture.session(Fixture.legs, at: Date(timeIntervalSince1970: 1_704_708_000)), // Mon 01-08 10:00Z
            Fixture.session(Fixture.legs, at: Date(timeIntervalSince1970: 1_704_794_400)), // Tue 01-09 10:00Z
        ]

        let mondayWeek = Fixture.selector(weekStartsOnMonday: true)
            .nextDay(program: Fixture.program, recentSessions: sessions, now: sunday)
        let sundayWeek = Fixture.selector(weekStartsOnMonday: false)
            .nextDay(program: Fixture.program, recentSessions: sessions, now: sunday)

        // Monday week [01-08, 01-15): legs is at 2/2 → score 0 → push (3).
        #expect(mondayWeek == Fixture.push)
        // Sunday week [01-14, 01-21): nothing counted yet → legs (5).
        #expect(sundayWeek == Fixture.legs)
    }

    @Test("S5 dia ausente de dayMuscles pontua 0 e nunca é excluído por S6")
    func S5_dayWithoutMuscles_scoresZeroAndIsNeverExcluded() {
        let mobility = ProgramDayTemplate(id: Fixture.id(4), name: "Mobilidade", order: 3)
        let program = ProgramTemplate(
            name: "Com mobilidade",
            days: [Fixture.push, Fixture.pull, Fixture.legs, mobility],
            isActive: true
        )
        // A full-body session 2 h ago puts every group in recovery: S6 removes the three
        // days that have groups, and the group-less day is the only one left.
        let sessions = [
            Fixture.session(Fixture.legs, hoursAgo: 2, muscles: Set(MuscleGroup.allCases)),
        ]

        let result = Fixture.selector().nextDay(program: program, recentSessions: sessions, now: Fixture.now)

        #expect(result == mobility)
    }

    // MARK: - S6 — recovery window

    @Test("S6 exclui o dia cujo grupo primário foi treinado há < 48 h, mesmo com a maior pontuação")
    func S6_recentlyTrainedDay_isExcluded() {
        // Legs 24 h ago: 1/2 this week, still score 5 — but its groups are recovering.
        let sessions = [Fixture.session(Fixture.legs, hoursAgo: 24)]

        let result = Fixture.selector().nextDay(
            program: Fixture.program,
            recentSessions: sessions,
            now: Fixture.now
        )

        #expect(result == Fixture.push)
    }

    @Test("S6 basta um grupo primário em comum para excluir o dia")
    func S6_singleSharedGroup_excludesDay() {
        // Pull 24 h ago with a core exercise added: legs shares `core` and is excluded
        // too. Rotation (S2) would say legs; S5 alone would also say legs (5).
        let sessions = [
            Fixture.session(Fixture.pull, hoursAgo: 24, muscles: [.back, .biceps, .core]),
        ]

        let result = Fixture.selector().nextDay(
            program: Fixture.program,
            recentSessions: sessions,
            now: Fixture.now
        )

        #expect(result == Fixture.push)
    }

    @Test("S6 fronteira: exatamente 48 h já descansou; 1 s a menos ainda exclui", arguments: FrequencyAwareSelectorTests.RecoveryBoundaryCase.all)
    func S6_boundary(_ testCase: RecoveryBoundaryCase) {
        let sessions = [
            Fixture.session(Fixture.legs, at: Fixture.now.addingTimeInterval(-testCase.secondsAgo)),
        ]

        let result = Fixture.selector().nextDay(
            program: Fixture.program,
            recentSessions: sessions,
            now: Fixture.now
        )

        #expect(result == testCase.expected)
    }

    @Test("S6 janela de recuperação configurável; 0 desliga S6", arguments: FrequencyAwareSelectorTests.RecoveryHoursCase.all)
    func S6_configurableRecoveryHours(_ testCase: RecoveryHoursCase) {
        let sessions = [Fixture.session(Fixture.legs, hoursAgo: testCase.hoursAgo)]

        let result = Fixture.selector(recoveryHours: testCase.recoveryHours).nextDay(
            program: Fixture.program,
            recentSessions: sessions,
            now: Fixture.now
        )

        #expect(result == testCase.expected)
    }

    @Test(
        "S6 conta sessões completed ou abandoned com séries; ignora inProgress e sessões vazias",
        arguments: FrequencyAwareSelectorTests.RecoveryStatusCase.all
    )
    func S6_whichSessionsCount(_ testCase: RecoveryStatusCase) {
        let sessions = [
            Fixture.session(
                Fixture.legs,
                hoursAgo: 24,
                status: testCase.status,
                workingSets: testCase.workingSets
            ),
        ]

        let result = Fixture.selector().nextDay(
            program: Fixture.program,
            recentSessions: sessions,
            now: Fixture.now
        )

        #expect(result == testCase.expected)
    }

    @Test("S6 fallback: se todos os dias forem excluídos, S6 é ignorada e vale a maior pontuação")
    func S6_everyDayExcluded_isIgnored() {
        // Full-body 2 h ago: all three days recover. Scores are push 3, pull 2, legs 5
        // (every group at 1/2), so ignoring S6 gives legs — not the rotation's push.
        let sessions = [
            Fixture.session(Fixture.legs, hoursAgo: 2, muscles: Set(MuscleGroup.allCases)),
        ]

        let result = Fixture.selector().nextDay(
            program: Fixture.program,
            recentSessions: sessions,
            now: Fixture.now
        )

        #expect(result == Fixture.legs)
    }

    @Test("S6 fallback com empate volta à ordem da rotação (S7)")
    func S6_everyDayExcluded_tieFollowsRotation() {
        // Equal-score days, all recovering: the tie goes to the rotation's pick.
        let sessions = [
            Fixture.session(Fixture.tieA, hoursAgo: 2, muscles: Set(MuscleGroup.allCases)),
        ]

        let result = Fixture.selector(dayMuscles: Fixture.tieMuscles).nextDay(
            program: Fixture.tieProgram,
            recentSessions: sessions,
            now: Fixture.now
        )

        #expect(result == Fixture.tieB)
    }

    // MARK: - S7 — highest score, ties by rotation order

    @Test("S7 empate total escolhe o mesmo dia que a rotação (S2)", arguments: FrequencyAwareSelectorTests.TieCase.all)
    func S7_fullTie_matchesRotationSelector(_ testCase: TieCase) {
        // Every day scores 2 and the reference session is from last week (not counted,
        // not recovering), so only the tie-break decides.
        let sessions: [SessionSummary] = testCase.lastDayIndex.map {
            [Fixture.session(Fixture.tieProgram.days[$0], hoursAgo: 64)]
        } ?? []

        let result = Fixture.selector(dayMuscles: Fixture.tieMuscles).nextDay(
            program: Fixture.tieProgram,
            recentSessions: sessions,
            now: Fixture.now
        )
        let rotation = RotationSelector().nextDay(
            program: Fixture.tieProgram,
            recentSessions: sessions,
            now: Fixture.now
        )

        #expect(result == Fixture.tieProgram.days[testCase.expectedIndex])
        #expect(result == rotation)
    }

    @Test("S7 empate é circular: começa no dia da rotação e dá a volta", arguments: FrequencyAwareSelectorTests.CircularTieCase.all)
    func S7_tieBreakIsCircularFromRotationPick(_ testCase: CircularTieCase) {
        // Scores A 2, B 1, C 2. After A the rotation says B; the tie A/C is broken in
        // the circular order B → C → A, so C wins although A has the lower `order`.
        let muscles: [UUID: Set<MuscleGroup>] = [
            Fixture.tieA.id: [.chest, .triceps],
            Fixture.tieB.id: [.back],
            Fixture.tieC.id: [.quads, .glutes],
        ]
        let sessions: [SessionSummary] = testCase.lastDayIndex.map {
            [Fixture.session(Fixture.tieProgram.days[$0], hoursAgo: 64)]
        } ?? []

        let result = Fixture.selector(dayMuscles: muscles).nextDay(
            program: Fixture.tieProgram,
            recentSessions: sessions,
            now: Fixture.now
        )

        #expect(result == Fixture.tieProgram.days[testCase.expectedIndex])
    }

    // MARK: - S3 / P11

    @Test("S3 sessão inProgress não conta para S2, S5 nem S6")
    func S3_inProgressSession_isIgnored() {
        // An open legs session with sets, started 1 h ago: were it counted, legs would
        // be excluded (S6) and the rotation would move to push. Ignored, the result is
        // the no-history answer: legs (5).
        let sessions = [Fixture.session(Fixture.legs, hoursAgo: 1, status: .inProgress)]

        let result = Fixture.selector().nextDay(
            program: Fixture.program,
            recentSessions: sessions,
            now: Fixture.now
        )

        #expect(result == Fixture.legs)
    }

    @Test("P11 determinístico: a ordem das sessões e dos dias no array não muda o resultado")
    func P11_inputOrder_doesNotChangeResult() {
        // Legs 59 h ago (1/2), pull 24 h ago (recovering), push last week (not counted).
        // Scores push 3, pull 2 (excluded), legs 5 → legs.
        let legs = Fixture.session(Fixture.legs, hoursAgo: 59)
        let pull = Fixture.session(Fixture.pull, hoursAgo: 24)
        let push = Fixture.session(Fixture.push, hoursAgo: 64)
        let permutations: [[SessionSummary]] = [
            [legs, pull, push], [legs, push, pull], [pull, legs, push],
            [pull, push, legs], [push, legs, pull], [push, pull, legs],
        ]
        let shuffledProgram = ProgramTemplate(
            name: "Embaralhado",
            days: [Fixture.legs, Fixture.push, Fixture.pull],
            isActive: true
        )
        let selector: any WorkoutSelector = Fixture.selector()

        for sessions in permutations {
            #expect(selector.nextDay(program: Fixture.program, recentSessions: sessions, now: Fixture.now) == Fixture.legs)
            #expect(selector.nextDay(program: shuffledProgram, recentSessions: sessions, now: Fixture.now) == Fixture.legs)
        }
    }
}

// MARK: - Table cases

extension FrequencyAwareSelectorTests {

    struct WeeklyCountCase: Sendable, CustomTestStringConvertible {
        let label: String
        let hoursAgo: [Double]
        let status: SessionStatus
        let workingSets: Int
        let expected: ProgramDayTemplate

        var testDescription: String { label }

        // Monday 01:00Z and 08:00Z are 59 h and 52 h before `now`; Sunday 20:00Z and
        // 22:00Z of the previous week are 64 h and 62 h before.
        static let all: [WeeklyCountCase] = [
            WeeklyCountCase(label: "completed com séries nesta semana → conta (legs 2/2 → push)",
                            hoursAgo: [59, 52], status: .completed, workingSets: 9, expected: Fixture.push),
            WeeklyCountCase(label: "abandoned não conta → legs",
                            hoursAgo: [59, 52], status: .abandoned, workingSets: 9, expected: Fixture.legs),
            WeeklyCountCase(label: "completed sem séries de trabalho não conta → legs",
                            hoursAgo: [59, 52], status: .completed, workingSets: 0, expected: Fixture.legs),
            WeeklyCountCase(label: "inProgress não conta → legs",
                            hoursAgo: [59, 52], status: .inProgress, workingSets: 9, expected: Fixture.legs),
            WeeklyCountCase(label: "semana anterior não conta → legs",
                            hoursAgo: [64, 62], status: .completed, workingSets: 9, expected: Fixture.legs),
        ]
    }

    struct TargetCase: Sendable, CustomTestStringConvertible {
        let label: String
        let weeklyTargets: [MuscleGroup: Int]
        let defaultTarget: Int
        let expected: ProgramDayTemplate

        var testDescription: String { label }

        static let all: [TargetCase] = [
            TargetCase(label: "padrão 2: legs 1/2 ainda pontua 5 → legs",
                       weeklyTargets: [:], defaultTarget: 2, expected: Fixture.legs),
            TargetCase(label: "padrão 1: legs 1/1 pontua 0 → push (3)",
                       weeklyTargets: [:], defaultTarget: 1, expected: Fixture.push),
            TargetCase(label: "metas de 1 nos grupos de legs → push",
                       weeklyTargets: [.quads: 1, .hamstrings: 1, .glutes: 1, .calves: 1, .core: 1],
                       defaultTarget: 2, expected: Fixture.push),
            TargetCase(label: "padrão 1 com meta 3 em quatro grupos de legs → legs (4 > 3)",
                       weeklyTargets: [.quads: 3, .hamstrings: 3, .glutes: 3, .calves: 3],
                       defaultTarget: 1, expected: Fixture.legs),
        ]
    }

    struct RecoveryBoundaryCase: Sendable, CustomTestStringConvertible {
        let label: String
        let secondsAgo: TimeInterval
        let expected: ProgramDayTemplate

        var testDescription: String { label }

        static let all: [RecoveryBoundaryCase] = [
            RecoveryBoundaryCase(label: "48 h − 1 s → legs excluído → push",
                                 secondsAgo: 48 * 3_600 - 1, expected: Fixture.push),
            RecoveryBoundaryCase(label: "exatamente 48 h → legs volta a competir → legs",
                                 secondsAgo: 48 * 3_600, expected: Fixture.legs),
            RecoveryBoundaryCase(label: "sessão 1 h depois de now (relógio adiantado) conta como recente → push",
                                 secondsAgo: -3_600, expected: Fixture.push),
        ]
    }

    struct RecoveryHoursCase: Sendable, CustomTestStringConvertible {
        let label: String
        let recoveryHours: Double
        let hoursAgo: Double
        let expected: ProgramDayTemplate

        var testDescription: String { label }

        static let all: [RecoveryHoursCase] = [
            RecoveryHoursCase(label: "72 h de recuperação, legs há 60 h → excluído → push",
                              recoveryHours: 72, hoursAgo: 60, expected: Fixture.push),
            RecoveryHoursCase(label: "48 h de recuperação, legs há 60 h → legs",
                              recoveryHours: 48, hoursAgo: 60, expected: Fixture.legs),
            RecoveryHoursCase(label: "0 h desliga S6, legs há 1 h → legs",
                              recoveryHours: 0, hoursAgo: 1, expected: Fixture.legs),
        ]
    }

    struct RecoveryStatusCase: Sendable, CustomTestStringConvertible {
        let label: String
        let status: SessionStatus
        let workingSets: Int
        let expected: ProgramDayTemplate

        var testDescription: String { label }

        static let all: [RecoveryStatusCase] = [
            RecoveryStatusCase(label: "completed com séries → push",
                               status: .completed, workingSets: 9, expected: Fixture.push),
            RecoveryStatusCase(label: "abandoned com séries → push",
                               status: .abandoned, workingSets: 3, expected: Fixture.push),
            RecoveryStatusCase(label: "completed sem séries → legs",
                               status: .completed, workingSets: 0, expected: Fixture.legs),
            RecoveryStatusCase(label: "abandoned sem séries → legs",
                               status: .abandoned, workingSets: 0, expected: Fixture.legs),
            RecoveryStatusCase(label: "inProgress com séries → legs",
                               status: .inProgress, workingSets: 9, expected: Fixture.legs),
        ]
    }

    struct TieCase: Sendable, CustomTestStringConvertible {
        let label: String
        /// Index in `Fixture.tieProgram.days` of the last session's day, or nil for none.
        let lastDayIndex: Int?
        let expectedIndex: Int

        var testDescription: String { label }

        static let all: [TieCase] = [
            TieCase(label: "sem sessão → A", lastDayIndex: nil, expectedIndex: 0),
            TieCase(label: "depois de A → B", lastDayIndex: 0, expectedIndex: 1),
            TieCase(label: "depois de B → C", lastDayIndex: 1, expectedIndex: 2),
            TieCase(label: "depois de C → A", lastDayIndex: 2, expectedIndex: 0),
        ]
    }

    struct CircularTieCase: Sendable, CustomTestStringConvertible {
        let label: String
        let lastDayIndex: Int?
        let expectedIndex: Int

        var testDescription: String { label }

        static let all: [CircularTieCase] = [
            CircularTieCase(label: "depois de A (rotação B, 1 pt): empate A/C → C", lastDayIndex: 0, expectedIndex: 2),
            CircularTieCase(label: "depois de B (rotação C): empate C/A → C", lastDayIndex: 1, expectedIndex: 2),
            CircularTieCase(label: "depois de C (rotação A): empate A/C → A", lastDayIndex: 2, expectedIndex: 0),
            CircularTieCase(label: "sem sessão (rotação A): empate A/C → A", lastDayIndex: nil, expectedIndex: 0),
        ]
    }
}

// MARK: - Fixture

private enum Fixture {
    /// UTC Gregorian calendar: the week is [Monday 00:00Z, next Monday 00:00Z).
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    /// Wednesday 2024-01-10 12:00:00Z. Its Monday-started week began on
    /// 2024-01-08 00:00Z, 60 h earlier.
    static let now = Date(timeIntervalSince1970: 1_704_888_000)

    static let push = ProgramDayTemplate(id: id(1), name: "Empurrar", order: 0)
    static let pull = ProgramDayTemplate(id: id(2), name: "Puxar", order: 1)
    static let legs = ProgramDayTemplate(id: id(3), name: "Pernas", order: 2)
    static let program = ProgramTemplate(name: "PPL", days: [push, pull, legs], isActive: true)

    /// push 3 groups, pull 2, legs 5.
    static let dayMuscles: [UUID: Set<MuscleGroup>] = [
        push.id: [.chest, .shoulders, .triceps],
        pull.id: [.back, .biceps],
        legs.id: [.quads, .hamstrings, .glutes, .calves, .core],
    ]

    static let tieA = ProgramDayTemplate(id: id(11), name: "A", order: 0)
    static let tieB = ProgramDayTemplate(id: id(12), name: "B", order: 1)
    static let tieC = ProgramDayTemplate(id: id(13), name: "C", order: 2)
    static let tieProgram = ProgramTemplate(name: "ABC", days: [tieA, tieB, tieC], isActive: true)

    /// Two groups per day, no overlap: every day scores the same.
    static let tieMuscles: [UUID: Set<MuscleGroup>] = [
        tieA.id: [.chest, .triceps],
        tieB.id: [.back, .biceps],
        tieC.id: [.quads, .glutes],
    ]

    static func selector(
        weeklyTargets: [MuscleGroup: Int] = [:],
        defaultWeeklyTarget: Int = 2,
        recoveryHours: Double = 48,
        weekStartsOnMonday: Bool = true,
        dayMuscles: [UUID: Set<MuscleGroup>] = Fixture.dayMuscles
    ) -> FrequencyAwareSelector {
        FrequencyAwareSelector(
            weeklyTargets: weeklyTargets,
            defaultWeeklyTarget: defaultWeeklyTarget,
            recoveryHours: recoveryHours,
            calendar: calendar,
            weekStartsOnMonday: weekStartsOnMonday,
            dayMuscles: dayMuscles
        )
    }

    static func session(
        _ day: ProgramDayTemplate,
        hoursAgo: Double,
        status: SessionStatus = .completed,
        workingSets: Int = 9,
        muscles: Set<MuscleGroup>? = nil
    ) -> SessionSummary {
        session(
            day,
            at: now.addingTimeInterval(-hoursAgo * 3_600),
            status: status,
            workingSets: workingSets,
            muscles: muscles
        )
    }

    /// The trained groups default to the day's groups (every exercise got sets).
    /// The id is derived from the day and the instant, never from `UUID()` (P11).
    static func session(
        _ day: ProgramDayTemplate,
        at startedAt: Date,
        status: SessionStatus = .completed,
        workingSets: Int = 9,
        muscles: Set<MuscleGroup>? = nil
    ) -> SessionSummary {
        SessionSummary(
            id: derivedID(day: day, startedAt: startedAt),
            programDayID: day.id,
            startedAt: startedAt,
            endedAt: status == .inProgress ? nil : startedAt.addingTimeInterval(3_600),
            status: status,
            primaryMusclesTrained: muscles ?? dayMuscles[day.id] ?? tieMuscles[day.id] ?? [],
            workingSetCount: workingSets
        )
    }

    static func id(_ n: UInt8) -> UUID {
        let hex = String(n, radix: 16).uppercased()
        let suffix = String(repeating: "0", count: 12 - hex.count) + hex
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }

    private static func derivedID(day: ProgramDayTemplate, startedAt: Date) -> UUID {
        let stamp = String(UInt64(max(0, startedAt.timeIntervalSince1970)), radix: 16).uppercased()
        let node = String(repeating: "0", count: max(0, 12 - stamp.count)) + stamp
        let order = String(UInt16(truncatingIfNeeded: day.order), radix: 16).uppercased()
        let group = String(repeating: "0", count: 4 - order.count) + order
        return UUID(uuidString: "00000000-0000-0001-\(group)-\(node)")!
    }
}
