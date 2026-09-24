import Foundation
import Testing
@testable import TrainerCore

/// Table cases for SPEC §7.5 (deload) and §7.11 C1 (its trigger). Every instant is
/// fixed (SPEC P11): `Fixture.now` plays "today".
@Suite("DeloadPolicy")
struct DeloadPolicyTests {
    // MARK: - C1 / §7.5 (a) — many decreases

    @Test("C1 manyDecreases: ≥ 50 % das prescrições (sem calibrate) com decrease", arguments: DeloadPolicyTests.DecreaseCase.all)
    func C1_manyDecreases_fiftyPercentBoundary(_ testCase: DecreaseCase) {
        // The last deload was a week ago, so (b) can never interfere.
        let result = DeloadPolicy.trigger(
            currentPrescriptions: Fixture.prescriptions(testCase.notes),
            lastDeloadStart: Fixture.now.addingTimeInterval(-Fixture.week),
            firstSessionDate: Fixture.now.addingTimeInterval(-40 * Fixture.week),
            now: Fixture.now
        )

        #expect(result == testCase.expected)
    }

    // MARK: - C1 / §7.5 (b) — scheduled

    @Test("C1 scheduled: N semanas desde o último deload ou desde a 1ª sessão", arguments: DeloadPolicyTests.ScheduleCase.all)
    func C1_scheduled_weeksBoundary(_ testCase: ScheduleCase) {
        let result = DeloadPolicy.trigger(
            currentPrescriptions: Fixture.prescriptions([.hold, .increase, .retry]),
            lastDeloadStart: testCase.lastDeloadSecondsAgo.map { Fixture.now.addingTimeInterval(-$0) },
            firstSessionDate: testCase.firstSessionSecondsAgo.map { Fixture.now.addingTimeInterval(-$0) },
            weeksBetweenDeloads: testCase.weeks,
            now: Fixture.now
        )

        #expect(result == testCase.expected)
    }

    @Test("C1 padrão de N é 6 semanas (§7.5 b)")
    func C1_defaultWeeksIsSix() {
        let prescriptions = Fixture.prescriptions([.hold])

        let atSix = DeloadPolicy.trigger(
            currentPrescriptions: prescriptions,
            lastDeloadStart: Fixture.now.addingTimeInterval(-6 * Fixture.week),
            firstSessionDate: nil,
            now: Fixture.now
        )
        let justBefore = DeloadPolicy.trigger(
            currentPrescriptions: prescriptions,
            lastDeloadStart: Fixture.now.addingTimeInterval(-6 * Fixture.week + 1),
            firstSessionDate: nil,
            now: Fixture.now
        )

        #expect(DeloadPolicy.defaultWeeksBetweenDeloads == 6)
        #expect(atSix == .scheduled)
        #expect(justBefore == nil)
    }

    @Test("C1 com os dois gatilhos, manyDecreases é o motivo exibido")
    func C1_bothTriggers_reportManyDecreases() {
        let result = DeloadPolicy.trigger(
            currentPrescriptions: Fixture.prescriptions([.decrease, .hold]),
            lastDeloadStart: Fixture.now.addingTimeInterval(-10 * Fixture.week),
            firstSessionDate: nil,
            now: Fixture.now
        )

        #expect(result == .manyDecreases)
    }

    @Test("C1 DeloadTrigger tem rawValues estáveis (persistidos no log de decisões)")
    func C1_triggerRawValuesAreStable() {
        #expect(DeloadTrigger.allCases.map(\.rawValue) == ["manyDecreases", "scheduled", "manual"])
    }

    // MARK: - §7.5 content — deload prescription

    @Test("7.5 deload: séries = ⌈0,6 × S⌉, mínimo 1", arguments: DeloadPolicyTests.SetsCase.all)
    func deload_setsAreSixtyPercentRoundedUp(_ testCase: SetsCase) {
        let normal = Fixture.normal(sets: testCase.sets)

        let result = DeloadPolicy.deloadPrescription(from: normal, loadIncrement: 2.5, isBodyweight: false)

        #expect(result.sets == testCase.expected)
    }

    @Test("7.5 deload: carga = arredondar↓(carga × 0,85, inc) com o mínimo de P8", arguments: DeloadPolicyTests.LoadCase.all)
    func deload_loadIsEightyFivePercentRoundedDown(_ testCase: LoadCase) {
        let normal = Fixture.normal(load: testCase.load)

        let result = DeloadPolicy.deloadPrescription(
            from: normal,
            loadIncrement: testCase.increment,
            isBodyweight: testCase.isBodyweight
        )

        #expect(result.load == testCase.expected)
    }

    @Test("7.5 deload: RIR alvo 4, meta = repMin, nota deload; o resto é copiado")
    func deload_fixedFieldsAndCopiedFields() {
        let normal = ExercisePrescription(
            exerciseID: Fixture.exerciseID,
            load: 60,
            sets: 4,
            repMin: 6,
            repMax: 10,
            targetReps: 9,
            targetRIR: 1,
            restSeconds: 150,
            note: .increase
        )

        let result = DeloadPolicy.deloadPrescription(from: normal, loadIncrement: 2.5, isBodyweight: false)

        #expect(result == ExercisePrescription(
            exerciseID: Fixture.exerciseID,
            load: 50,
            sets: 3,
            repMin: 6,
            repMax: 10,
            targetReps: 6,
            targetRIR: 4,
            restSeconds: 150,
            note: .deload
        ))
    }

    @Test("7.5 deload de uma calibração sem carga continua sem carga")
    func deload_calibrationWithoutLoad_keepsNoLoad() {
        let normal = ExercisePrescription(
            exerciseID: Fixture.exerciseID,
            load: nil,
            sets: 3,
            targetRIR: 3,
            note: .calibrate
        )

        let result = DeloadPolicy.deloadPrescription(from: normal, loadIncrement: 2.5, isBodyweight: false)

        #expect(result.load == nil)
        #expect(result.sets == 2)
        #expect(result.targetRIR == 4)
        #expect(result.note == .deload)
    }

    // MARK: - §7.5 duration — one pass of the rotation

    @Test("7.5 deload ativo até uma passagem completa da rotação", arguments: DeloadPolicyTests.ActiveCase.all)
    func deload_activeUntilOneRotationPass(_ testCase: ActiveCase) {
        let result = DeloadPolicy.isDeloadActive(
            deloadStart: testCase.hasStart ? Fixture.deloadStart : nil,
            sessionsSinceStart: testCase.sessions.map(Fixture.session),
            programDayCount: testCase.programDayCount
        )

        #expect(result == testCase.expected)
    }

    // MARK: - SessionSummary.isDeload (tolerant decoding)

    @Test("7.5 SessionSummary.isDeload é false por padrão no init")
    func sessionSummary_isDeloadDefaultsToFalse() {
        let summary = SessionSummary(programDayID: Fixture.id(1), startedAt: Fixture.now)

        #expect(summary.isDeload == false)
    }

    @Test("7.5 SessionSummary com isDeload faz round-trip Codable")
    func sessionSummary_isDeloadRoundTrips() throws {
        let value = Fixture.summary(isDeload: true)

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(SessionSummary.self, from: data)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(decoded == value)
        #expect(decoded.isDeload)
        #expect(object.keys.contains("isDeload"))
    }

    @Test("7.5 SessionSummary anterior ao M4 (sem isDeload) decodifica como false")
    func sessionSummary_legacyJSONWithoutIsDeload_decodesAsFalse() throws {
        let data = try Fixture.encodedSummary(isDeload: true, removing: "isDeload")

        let decoded = try JSONDecoder().decode(SessionSummary.self, from: data)

        #expect(decoded.isDeload == false)
        #expect(decoded.id == Fixture.id(9))
        #expect(decoded.primaryMusclesTrained == [.chest, .triceps])
        #expect(decoded.workingSetCount == 12)
    }

    @Test("7.5 a tolerância vale só para isDeload: campo obrigatório ausente ainda falha")
    func sessionSummary_missingRequiredField_stillThrows() throws {
        let data = try Fixture.encodedSummary(isDeload: false, removing: "workingSetCount")

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SessionSummary.self, from: data)
        }
    }
}

// MARK: - Table cases

extension DeloadPolicyTests {
    struct DecreaseCase: Sendable, CustomTestStringConvertible {
        let label: String
        let notes: [PrescriptionNote]
        let expected: DeloadTrigger?

        var testDescription: String { label }

        static let all: [DecreaseCase] = [
            DecreaseCase(label: "sem prescrições → nil", notes: [], expected: nil),
            DecreaseCase(label: "1 de 1 (100 %) → manyDecreases", notes: [.decrease], expected: .manyDecreases),
            DecreaseCase(label: "1 de 2 (50 %, fronteira) → manyDecreases",
                         notes: [.decrease, .hold], expected: .manyDecreases),
            DecreaseCase(label: "1 de 3 (33 %) → nil",
                         notes: [.decrease, .hold, .increase], expected: nil),
            DecreaseCase(label: "2 de 4 (50 %) → manyDecreases",
                         notes: [.decrease, .decrease, .hold, .retry], expected: .manyDecreases),
            DecreaseCase(label: "2 de 5 (40 %) → nil",
                         notes: [.decrease, .decrease, .hold, .retry, .increase], expected: nil),
            DecreaseCase(label: "3 de 5 (60 %) → manyDecreases",
                         notes: [.decrease, .decrease, .decrease, .hold, .retry], expected: .manyDecreases),
            DecreaseCase(label: "retry não é decrease → nil", notes: [.retry, .retry], expected: nil),
            DecreaseCase(label: "returning não é decrease: 1 de 2 → manyDecreases",
                         notes: [.returning, .decrease], expected: .manyDecreases),
            DecreaseCase(label: "calibrate fica fora da conta: 1 de 2 → manyDecreases",
                         notes: [.decrease, .hold, .calibrate, .calibrate], expected: .manyDecreases),
            DecreaseCase(label: "calibrate fora da conta: 1 de 3 → nil",
                         notes: [.decrease, .hold, .hold, .calibrate, .calibrate, .calibrate], expected: nil),
            DecreaseCase(label: "só calibrate → nil", notes: [.calibrate, .calibrate], expected: nil),
        ]
    }

    struct ScheduleCase: Sendable, CustomTestStringConvertible {
        let label: String
        let lastDeloadSecondsAgo: TimeInterval?
        let firstSessionSecondsAgo: TimeInterval?
        let weeks: Int
        let expected: DeloadTrigger?

        var testDescription: String { label }

        private static let week = 7.0 * 86_400

        static let all: [ScheduleCase] = [
            ScheduleCase(label: "último deload há exatamente 6 semanas → scheduled",
                         lastDeloadSecondsAgo: 6 * week, firstSessionSecondsAgo: 30 * week,
                         weeks: 6, expected: .scheduled),
            ScheduleCase(label: "último deload há 6 semanas − 1 s → nil",
                         lastDeloadSecondsAgo: 6 * week - 1, firstSessionSecondsAgo: 30 * week,
                         weeks: 6, expected: nil),
            ScheduleCase(label: "último deload há 10 semanas → scheduled",
                         lastDeloadSecondsAgo: 10 * week, firstSessionSecondsAgo: 30 * week,
                         weeks: 6, expected: .scheduled),
            ScheduleCase(label: "último deload recente prevalece sobre a 1ª sessão antiga → nil",
                         lastDeloadSecondsAgo: 1 * week, firstSessionSecondsAgo: 30 * week,
                         weeks: 6, expected: nil),
            ScheduleCase(label: "nunca houve deload: 1ª sessão há exatamente 6 semanas → scheduled",
                         lastDeloadSecondsAgo: nil, firstSessionSecondsAgo: 6 * week,
                         weeks: 6, expected: .scheduled),
            ScheduleCase(label: "nunca houve deload: 1ª sessão há 6 semanas − 1 s → nil",
                         lastDeloadSecondsAgo: nil, firstSessionSecondsAgo: 6 * week - 1,
                         weeks: 6, expected: nil),
            ScheduleCase(label: "sem deload e sem sessão → nil",
                         lastDeloadSecondsAgo: nil, firstSessionSecondsAgo: nil,
                         weeks: 6, expected: nil),
            ScheduleCase(label: "N = 4: exatamente 4 semanas → scheduled",
                         lastDeloadSecondsAgo: 4 * week, firstSessionSecondsAgo: nil,
                         weeks: 4, expected: .scheduled),
            ScheduleCase(label: "N = 4: 4 semanas − 1 s → nil",
                         lastDeloadSecondsAgo: 4 * week - 1, firstSessionSecondsAgo: nil,
                         weeks: 4, expected: nil),
            ScheduleCase(label: "N = 0 desliga o gatilho → nil",
                         lastDeloadSecondsAgo: nil, firstSessionSecondsAgo: 30 * week,
                         weeks: 0, expected: nil),
            ScheduleCase(label: "N negativo desliga o gatilho → nil",
                         lastDeloadSecondsAgo: 30 * week, firstSessionSecondsAgo: nil,
                         weeks: -1, expected: nil),
            ScheduleCase(label: "deload com data depois de now (relógio adiantado) → nil",
                         lastDeloadSecondsAgo: -3_600, firstSessionSecondsAgo: 30 * week,
                         weeks: 6, expected: nil),
        ]
    }

    struct SetsCase: Sendable, CustomTestStringConvertible {
        let sets: Int
        let expected: Int

        var testDescription: String { "S = \(sets) → \(expected)" }

        static let all: [SetsCase] = [
            SetsCase(sets: 1, expected: 1),   // 0,6 → 1
            SetsCase(sets: 2, expected: 2),   // 1,2 → 2
            SetsCase(sets: 3, expected: 2),   // 1,8 → 2
            SetsCase(sets: 4, expected: 3),   // 2,4 → 3
            SetsCase(sets: 5, expected: 3),   // 3,0 → 3 (exato, sem ruído de ponto flutuante)
            SetsCase(sets: 6, expected: 4),   // 3,6 → 4
            SetsCase(sets: 10, expected: 6),  // 6,0 → 6
            SetsCase(sets: 0, expected: 1),   // mínimo 1
            SetsCase(sets: -2, expected: 1),  // mínimo 1
            SetsCase(sets: Int.max, expected: 5_534_023_222_112_865_485), // não estoura
        ]
    }

    struct LoadCase: Sendable, CustomTestStringConvertible {
        let label: String
        let load: Double?
        let increment: Double
        let isBodyweight: Bool
        let expected: Double?

        var testDescription: String { label }

        static let all: [LoadCase] = [
            LoadCase(label: "60 × 0,85 = 51 → 50 (inc 2,5)", load: 60, increment: 2.5, isBodyweight: false, expected: 50),
            LoadCase(label: "100 × 0,85 = 85 já no grid → 85", load: 100, increment: 2.5, isBodyweight: false, expected: 85),
            LoadCase(label: "57,5 × 0,85 = 48,875 → 47,5", load: 57.5, increment: 2.5, isBodyweight: false, expected: 47.5),
            LoadCase(label: "50 × 0,85 = 42,5 → 40 (inc 5)", load: 50, increment: 5, isBodyweight: false, expected: 40),
            LoadCase(label: "nível 7 × 0,85 = 5,95 → 5 (inc 1)", load: 7, increment: 1, isBodyweight: false, expected: 5),
            LoadCase(label: "P8: 2,5 × 0,85 → 0 sobe ao mínimo 2,5", load: 2.5, increment: 2.5, isBodyweight: false, expected: 2.5),
            LoadCase(label: "P8: 5 × 0,85 → 0 sobe ao mínimo 5 (inc 5)", load: 5, increment: 5, isBodyweight: false, expected: 5),
            LoadCase(label: "peso corporal: 2,5 × 0,85 → 0 (mínimo 0)", load: 2.5, increment: 2.5, isBodyweight: true, expected: 0),
            LoadCase(label: "peso corporal: 10 × 0,85 = 8,5 → 7,5", load: 10, increment: 2.5, isBodyweight: true, expected: 7.5),
            LoadCase(label: "peso corporal puro: 0 → 0", load: 0, increment: 2.5, isBodyweight: true, expected: 0),
            LoadCase(label: "sem carga → sem carga", load: nil, increment: 2.5, isBodyweight: false, expected: nil),
            LoadCase(label: "carga não finita → sem carga", load: .infinity, increment: 2.5, isBodyweight: false, expected: nil),
        ]
    }

    struct SessionSpec: Sendable {
        let n: UInt8
        let hoursAfterStart: Double
        let status: SessionStatus
        let isDeload: Bool
        let workingSets: Int

        init(
            _ n: UInt8,
            hoursAfterStart: Double = 24,
            status: SessionStatus = .completed,
            isDeload: Bool = true,
            workingSets: Int = 6
        ) {
            self.n = n
            self.hoursAfterStart = hoursAfterStart
            self.status = status
            self.isDeload = isDeload
            self.workingSets = workingSets
        }
    }

    struct ActiveCase: Sendable, CustomTestStringConvertible {
        let label: String
        let hasStart: Bool
        let sessions: [SessionSpec]
        let programDayCount: Int
        let expected: Bool

        var testDescription: String { label }

        init(_ label: String, hasStart: Bool = true, sessions: [SessionSpec], days: Int = 3, expected: Bool) {
            self.label = label
            self.hasStart = hasStart
            self.sessions = sessions
            self.programDayCount = days
            self.expected = expected
        }

        static let all: [ActiveCase] = [
            ActiveCase("sem deload → inativo", hasStart: false, sessions: [], expected: false),
            ActiveCase("sem deload, mesmo com sessões → inativo", hasStart: false,
                       sessions: [SessionSpec(1)], expected: false),
            ActiveCase("deload recém-iniciado, 0 de 3 → ativo", sessions: [], expected: true),
            ActiveCase("2 de 3 concluídas → ativo",
                       sessions: [SessionSpec(1, hoursAfterStart: 1), SessionSpec(2, hoursAfterStart: 30)],
                       expected: true),
            ActiveCase("3 de 3 concluídas → fim do deload",
                       sessions: [SessionSpec(1), SessionSpec(2, hoursAfterStart: 48), SessionSpec(3, hoursAfterStart: 72)],
                       expected: false),
            ActiveCase("4 de 3 → inativo",
                       sessions: [SessionSpec(1), SessionSpec(2), SessionSpec(3), SessionSpec(4)],
                       expected: false),
            ActiveCase("sessão exatamente no início conta",
                       sessions: [SessionSpec(1, hoursAfterStart: 0), SessionSpec(2), SessionSpec(3)],
                       expected: false),
            ActiveCase("abandoned não completa a passagem → ativo",
                       sessions: [SessionSpec(1), SessionSpec(2), SessionSpec(3, status: .abandoned)],
                       expected: true),
            ActiveCase("inProgress não conta → ativo",
                       sessions: [SessionSpec(1), SessionSpec(2), SessionSpec(3, status: .inProgress)],
                       expected: true),
            ActiveCase("sessão normal (não deload) não conta → ativo",
                       sessions: [SessionSpec(1), SessionSpec(2), SessionSpec(3, isDeload: false)],
                       expected: true),
            ActiveCase("deload sem séries de trabalho não conta → ativo",
                       sessions: [SessionSpec(1), SessionSpec(2), SessionSpec(3, workingSets: 0)],
                       expected: true),
            ActiveCase("sessão de deload antes do início (deload anterior) não conta → ativo",
                       sessions: [SessionSpec(1), SessionSpec(2), SessionSpec(3, hoursAfterStart: -1)],
                       expected: true),
            ActiveCase("id repetido conta uma vez → ativo",
                       sessions: [SessionSpec(1), SessionSpec(2), SessionSpec(2, hoursAfterStart: 50)],
                       expected: true),
            ActiveCase("programa de 2 dias: 2 concluídas → fim",
                       sessions: [SessionSpec(1), SessionSpec(2)], days: 2, expected: false),
            ActiveCase("programa de 5 dias: 3 concluídas → ativo",
                       sessions: [SessionSpec(1), SessionSpec(2), SessionSpec(3)], days: 5, expected: true),
            ActiveCase("programa de 1 dia: 1 concluída → fim",
                       sessions: [SessionSpec(1)], days: 1, expected: false),
            ActiveCase("programa sem dias → inativo", sessions: [], days: 0, expected: false),
        ]
    }
}

// MARK: - Fixture

private enum Fixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let week: TimeInterval = 7 * 86_400
    static let deloadStart = now.addingTimeInterval(-3 * 86_400)
    static let exerciseID = id(0xE1)
    static let programDayID = id(0xD1)

    static func id(_ n: UInt8) -> UUID {
        let hex = String(n, radix: 16).uppercased()
        let suffix = String(repeating: "0", count: 12 - hex.count) + hex
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }

    /// One prescription per note, each for its own exercise.
    static func prescriptions(_ notes: [PrescriptionNote]) -> [ExercisePrescription] {
        notes.enumerated().map { index, note in
            ExercisePrescription(
                exerciseID: id(UInt8(truncatingIfNeeded: 0x10 + index)),
                load: note == .calibrate ? nil : 50,
                note: note
            )
        }
    }

    static func normal(load: Double? = 60, sets: Int = 3) -> ExercisePrescription {
        ExercisePrescription(
            exerciseID: exerciseID,
            load: load,
            sets: sets,
            repMin: 8,
            repMax: 12,
            targetReps: 10,
            targetRIR: 2,
            restSeconds: 120,
            note: .hold
        )
    }

    static func session(_ spec: DeloadPolicyTests.SessionSpec) -> SessionSummary {
        let startedAt = deloadStart.addingTimeInterval(spec.hoursAfterStart * 3_600)
        return SessionSummary(
            id: id(spec.n),
            programDayID: programDayID,
            startedAt: startedAt,
            endedAt: spec.status == .inProgress ? nil : startedAt.addingTimeInterval(3_600),
            status: spec.status,
            primaryMusclesTrained: [.chest],
            workingSetCount: spec.workingSets,
            isDeload: spec.isDeload
        )
    }

    static func summary(isDeload: Bool) -> SessionSummary {
        SessionSummary(
            id: id(9),
            programDayID: programDayID,
            startedAt: now,
            endedAt: now.addingTimeInterval(3_600),
            status: .completed,
            primaryMusclesTrained: [.chest, .triceps],
            workingSetCount: 12,
            isDeload: isDeload
        )
    }

    /// JSON of `summary(isDeload:)` with one key removed, as an older app version
    /// (or a damaged file) would have written it.
    static func encodedSummary(isDeload: Bool, removing key: String) throws -> Data {
        let data = try JSONEncoder().encode(summary(isDeload: isDeload))
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object.removeValue(forKey: key) != nil)
        return try JSONSerialization.data(withJSONObject: object)
    }
}
