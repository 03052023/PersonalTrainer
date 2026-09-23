import Foundation
import Testing
@testable import TrainerCore

/// Sync DTOs (ARCHITECTURE §7, §9, AR-3). There is no P/S/D rule for transport,
/// so test names cite the ARCHITECTURE section instead.
@Suite("Sync DTOs")
struct SyncDTOTests {
    // MARK: - Fixtures (fixed dates and IDs: encodings must be reproducible)

    /// 2023-11-14T22:13:20Z
    static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)
    static let sessionID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let eventID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let sessionExerciseID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let setID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    static let programDayID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    static let exerciseID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    static let newExerciseID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
    static let hkWorkoutUUID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!

    /// Every `SessionEvent.Kind` case, with both branches of each optional.
    static let allKinds: [SessionEvent.Kind] = [
        .sessionStarted(programDayID: Self.programDayID),
        .setLogged(
            sessionExerciseID: Self.sessionExerciseID,
            setID: Self.setID,
            index: 1,
            load: 62.5,
            reps: 10,
            rir: 2,
            isWarmup: false
        ),
        .setLogged(
            sessionExerciseID: Self.sessionExerciseID,
            setID: Self.setID,
            index: 0,
            load: 40,
            reps: 12,
            rir: nil,
            isWarmup: true
        ),
        .setUpdated(setID: Self.setID, load: 65, reps: 8, rir: 1),
        .setUpdated(setID: Self.setID, load: 65, reps: 8, rir: nil),
        .setDeleted(setID: Self.setID),
        .exerciseSkipped(sessionExerciseID: Self.sessionExerciseID),
        .exerciseSubstituted(sessionExerciseID: Self.sessionExerciseID, newExerciseID: Self.newExerciseID),
        .sessionFinished(endedAt: Self.referenceDate.addingTimeInterval(3_600)),
        .sessionAbandoned(endedAt: Self.referenceDate.addingTimeInterval(1_800)),
        .heartRateSummary(averageBPM: 132.5, maxBPM: 171.25, hkWorkoutUUID: Self.hkWorkoutUUID),
        .heartRateSummary(averageBPM: 120, maxBPM: 150, hkWorkoutUUID: nil),
    ]

    /// The nine `type` discriminators of sync schema v1.
    static let expectedTypeTags: Set<String> = [
        "sessionStarted", "setLogged", "setUpdated", "setDeleted", "exerciseSkipped",
        "exerciseSubstituted", "sessionFinished", "sessionAbandoned", "heartRateSummary",
    ]

    static func makeEvent(kind: SessionEvent.Kind, source: DeviceSource = .watch) -> SessionEvent {
        SessionEvent(
            id: Self.eventID,
            sessionID: Self.sessionID,
            occurredAt: Self.referenceDate,
            source: source,
            kind: kind
        )
    }

    static func makeFullSnapshot() -> ActiveSessionSnapshot {
        let benchPress = ExerciseSnapshot(
            id: Self.sessionExerciseID,
            exerciseID: Self.exerciseID,
            exerciseName: "Supino reto",
            order: 0,
            prescription: ExercisePrescription(
                exerciseID: Self.exerciseID,
                load: 62.5,
                sets: 3,
                repMin: 8,
                repMax: 12,
                targetReps: 9,
                targetRIR: 2,
                restSeconds: 120,
                note: .hold
            ),
            wasSkipped: false,
            sets: [
                SetSnapshot(
                    id: Self.setID,
                    index: 0,
                    load: 40,
                    reps: 12,
                    rir: nil,
                    isWarmup: true,
                    completedAt: Self.referenceDate.addingTimeInterval(60)
                ),
                SetSnapshot(
                    id: Self.hkWorkoutUUID, // any fixed UUID
                    index: 1,
                    load: 62.5,
                    reps: 10,
                    rir: 2,
                    isWarmup: false,
                    completedAt: Self.referenceDate.addingTimeInterval(240)
                ),
            ]
        )
        let skipped = ExerciseSnapshot(
            id: Self.newExerciseID,
            exerciseID: Self.programDayID, // any fixed UUID
            exerciseName: "Crucifixo máquina",
            order: 1,
            prescription: ExercisePrescription(exerciseID: Self.programDayID), // load nil, note .calibrate
            wasSkipped: true,
            sets: []
        )
        let session = SessionSnapshot(
            id: Self.sessionID,
            programDayID: Self.programDayID,
            programDayName: "Dia A — Superior empurrar",
            startedAt: Self.referenceDate,
            status: .inProgress,
            exercises: [benchPress, skipped]
        )
        let plan = PlanSnapshot(
            programDayID: Self.exerciseID, // any fixed UUID
            programDayName: "Dia B — Inferior",
            exercises: [
                ExerciseSnapshot(
                    id: Self.setID,
                    exerciseID: Self.newExerciseID,
                    exerciseName: "Leg press 45°",
                    order: 0,
                    prescription: ExercisePrescription(exerciseID: Self.newExerciseID, load: 180, note: .increase)
                ),
            ]
        )
        return ActiveSessionSnapshot(
            generatedAt: Self.referenceDate.addingTimeInterval(300),
            activeSession: session,
            nextPlan: plan
        )
    }

    // MARK: - SessionEvent (ARCHITECTURE §7)

    @Test("§7 cada SessionEvent.Kind faz round-trip pelo SyncCodec", arguments: SyncDTOTests.allKinds)
    func kindRoundTrip(kind: SessionEvent.Kind) throws {
        let event = Self.makeEvent(kind: kind)

        let decoded = try SyncCodec.decodeEvent(SyncCodec.encode(event))

        #expect(decoded == event)
        #expect(decoded.kind == kind)
        #expect(decoded.hashValue == event.hashValue)
    }

    @Test("§7 fixtures cobrem os nove cases de Kind (discriminador type)")
    func fixturesCoverEveryKind() throws {
        var tags = Set<String>()
        for kind in Self.allKinds {
            let data = try SyncCodec.encode(kind)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            tags.insert(try #require(object["type"] as? String))
        }

        #expect(tags == Self.expectedTypeTags)
    }

    @Test("§7 SessionEvent preserva id, sessionID, occurredAt e source")
    func eventEnvelopeRoundTrip() throws {
        for source in DeviceSource.allCases {
            let event = Self.makeEvent(kind: .setDeleted(setID: Self.setID), source: source)
            let data = try SyncCodec.encode(event)
            let decoded = try SyncCodec.decodeEvent(data)

            #expect(decoded.id == Self.eventID)
            #expect(decoded.sessionID == Self.sessionID)
            #expect(decoded.occurredAt == Self.referenceDate)
            #expect(decoded.source == source)
            #expect(String(decoding: data, as: UTF8.self).contains("\"source\":\"\(source.rawValue)\""))
        }
    }

    @Test("§7 DeviceSource tem rawValues estáveis (AGENTS §4)")
    func deviceSourceRawValuesAreStable() {
        #expect(DeviceSource.iphone.rawValue == "iphone")
        #expect(DeviceSource.watch.rawValue == "watch")
        #expect(DeviceSource.importer.rawValue == "importer")
        #expect(DeviceSource.allCases.count == 3)
    }

    @Test("§7 SessionEvent.id é distinto por evento (Identifiable, idempotência)")
    func eventIDsAreDistinct() {
        let kind = SessionEvent.Kind.setDeleted(setID: Self.setID)
        let first = SessionEvent(sessionID: Self.sessionID, occurredAt: Self.referenceDate, source: .iphone, kind: kind)
        let second = SessionEvent(sessionID: Self.sessionID, occurredAt: Self.referenceDate, source: .iphone, kind: kind)

        #expect(first.id != second.id)
        #expect(first != second)
        #expect(Set([first, second]).count == 2)
        #expect(Self.makeEvent(kind: kind).id == Self.eventID)
    }

    @Test("§9 decodeEvents faz round-trip de uma fila preservando a ordem")
    func eventsArrayRoundTrip() throws {
        let events = Self.allKinds.enumerated().map { offset, kind in
            SessionEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000\(String(format: "%02d", offset))")!,
                sessionID: Self.sessionID,
                occurredAt: Self.referenceDate.addingTimeInterval(TimeInterval(offset)),
                source: .watch,
                kind: kind
            )
        }

        let decoded = try SyncCodec.decodeEvents(SyncCodec.encode(events))

        #expect(decoded == events)
        #expect(try SyncCodec.decodeEvents(SyncCodec.encode([SessionEvent]())).isEmpty)
    }

    @Test("§7 formato de fio v1 do SessionEvent é o documentado (golden)")
    func eventWireFormatIsStable() throws {
        let event = Self.makeEvent(
            kind: .setLogged(
                sessionExerciseID: Self.sessionExerciseID,
                setID: Self.setID,
                index: 1,
                load: 62.5,
                reps: 10,
                rir: 2,
                isWarmup: false
            )
        )

        let json = String(decoding: try SyncCodec.encode(event), as: UTF8.self)

        let expected = """
        {"id":"22222222-2222-2222-2222-222222222222",\
        "kind":{"index":1,"isWarmup":false,"load":62.5,"reps":10,"rir":2,\
        "sessionExerciseID":"33333333-3333-3333-3333-333333333333",\
        "setID":"44444444-4444-4444-4444-444444444444","type":"setLogged"},\
        "occurredAt":"2023-11-14T22:13:20Z",\
        "sessionID":"11111111-1111-1111-1111-111111111111","source":"watch"}
        """
        #expect(json == expected)
    }

    @Test("§7 opcionais nil são omitidos no fio (rir, hkWorkoutUUID)")
    func nilOptionalsAreOmitted() throws {
        let noRIR = try SyncCodec.encode(SessionEvent.Kind.setUpdated(setID: Self.setID, load: 65, reps: 8, rir: nil))
        let noWorkout = try SyncCodec.encode(SessionEvent.Kind.heartRateSummary(averageBPM: 120, maxBPM: 150, hkWorkoutUUID: nil))

        #expect(!String(decoding: noRIR, as: UTF8.self).contains("rir"))
        #expect(!String(decoding: noWorkout, as: UTF8.self).contains("hkWorkoutUUID"))
    }

    // MARK: - ActiveSessionSnapshot (ARCHITECTURE §9)

    @Test("§9 ActiveSessionSnapshot completo (sessão ativa + nextPlan) faz round-trip")
    func fullSnapshotRoundTrip() throws {
        let snapshot = Self.makeFullSnapshot()

        let decoded = try SyncCodec.decodeSnapshot(SyncCodec.encode(snapshot))

        #expect(decoded == snapshot)
        #expect(decoded.schemaVersion == SyncSchema.currentVersion)
        #expect(decoded.activeSession?.exercises.count == 2)
        #expect(decoded.activeSession?.exercises[0].sets.count == 2)
        #expect(decoded.activeSession?.exercises[1].wasSkipped == true)
        #expect(decoded.activeSession?.exercises[1].prescription.load == nil)
        #expect(decoded.nextPlan?.exercises.allSatisfy { $0.sets.isEmpty } == true)
    }

    @Test("§9 ActiveSessionSnapshot vazio (sem sessão, sem plano) faz round-trip")
    func emptySnapshotRoundTrip() throws {
        let snapshot = ActiveSessionSnapshot(generatedAt: Self.referenceDate)

        let data = try SyncCodec.encode(snapshot)
        let decoded = try SyncCodec.decodeSnapshot(data)

        #expect(decoded == snapshot)
        #expect(decoded.activeSession == nil)
        #expect(decoded.nextPlan == nil)
        #expect(String(decoding: data, as: UTF8.self) == "{\"generatedAt\":\"2023-11-14T22:13:20Z\",\"schemaVersion\":1}")
    }

    @Test("§9 SyncSchema.currentVersion é 1 em M0 e é o default do snapshot")
    func schemaVersionDefaultsToCurrent() {
        #expect(SyncSchema.currentVersion == 1)
        #expect(ActiveSessionSnapshot(generatedAt: Self.referenceDate).schemaVersion == 1)
    }

    @Test("§9 decodeSnapshot aceita schemaVersion 1")
    func decodeSnapshotAcceptsCurrentVersion() throws {
        let data = try SyncCodec.encode(ActiveSessionSnapshot(schemaVersion: 1, generatedAt: Self.referenceDate))

        #expect(try SyncCodec.decodeSnapshot(data).schemaVersion == 1)
    }

    @Test("§9 decodeSnapshot rejeita schemaVersion 2 com unsupportedSchemaVersion")
    func decodeSnapshotRejectsNewerVersion() throws {
        let data = try SyncCodec.encode(ActiveSessionSnapshot(schemaVersion: 2, generatedAt: Self.referenceDate))

        #expect(throws: SyncError.unsupportedSchemaVersion(found: 2, supported: 1)) {
            try SyncCodec.decodeSnapshot(data)
        }
    }

    @Test("§9 decodeSnapshot lê a versão antes do resto: payload futuro ilegível ainda reporta a versão")
    func versionIsCheckedBeforeFullDecode() {
        // A v2 producer may have renamed fields; the Watch must still say "update
        // the iPhone app" rather than "corrupted".
        let futurePayload = Data("""
        {"schemaVersion":2,"generatedAt":"not-a-date","session":{"unknown":true}}
        """.utf8)

        #expect(throws: SyncError.unsupportedSchemaVersion(found: 2, supported: 1)) {
            try SyncCodec.decodeSnapshot(futurePayload)
        }
    }

    // MARK: - Corrupted data → SyncError.corrupted (never a raw DecodingError)

    @Test("§9 bytes que não são JSON → SyncError.corrupted em todos os decoders")
    func garbageIsCorrupted() {
        let garbage = Data([0xFF, 0x00, 0x7B, 0x22])

        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeSnapshot(garbage) }
        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeEvent(garbage) }
        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeEvents(garbage) }
        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeSnapshot(Data()) }
    }

    @Test("§9 snapshot sem schemaVersion ou com versão < 1 → SyncError.corrupted")
    func snapshotWithoutValidVersionIsCorrupted() {
        let missing = Data("{\"generatedAt\":\"2023-11-14T22:13:20Z\"}".utf8)
        let zero = Data("{\"schemaVersion\":0,\"generatedAt\":\"2023-11-14T22:13:20Z\"}".utf8)
        let negative = Data("{\"schemaVersion\":-1,\"generatedAt\":\"2023-11-14T22:13:20Z\"}".utf8)
        let wrongType = Data("{\"schemaVersion\":\"1\",\"generatedAt\":\"2023-11-14T22:13:20Z\"}".utf8)

        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeSnapshot(missing) }
        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeSnapshot(zero) }
        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeSnapshot(negative) }
        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeSnapshot(wrongType) }
    }

    @Test("§9 snapshot v1 com campo obrigatório ausente ou data inválida → SyncError.corrupted")
    func snapshotWithBrokenBodyIsCorrupted() {
        let noDate = Data("{\"schemaVersion\":1}".utf8)
        let badDate = Data("{\"schemaVersion\":1,\"generatedAt\":\"yesterday\"}".utf8)
        let badStatus = Data("""
        {"schemaVersion":1,"generatedAt":"2023-11-14T22:13:20Z","activeSession":{\
        "id":"11111111-1111-1111-1111-111111111111","programDayID":"55555555-5555-5555-5555-555555555555",\
        "programDayName":"A","startedAt":"2023-11-14T22:13:20Z","status":"paused","exercises":[]}}
        """.utf8)

        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeSnapshot(noDate) }
        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeSnapshot(badDate) }
        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeSnapshot(badStatus) }
    }

    @Test("§7 evento com type desconhecido, campo faltando ou fora de um array → SyncError.corrupted")
    func brokenEventIsCorrupted() throws {
        let envelope = "\"id\":\"22222222-2222-2222-2222-222222222222\",\"sessionID\":\"11111111-1111-1111-1111-111111111111\",\"occurredAt\":\"2023-11-14T22:13:20Z\",\"source\":\"watch\""
        let unknownKind = Data("{\(envelope),\"kind\":{\"type\":\"setSuperseded\",\"setID\":\"44444444-4444-4444-4444-444444444444\"}}".utf8)
        let missingField = Data("{\(envelope),\"kind\":{\"type\":\"setDeleted\"}}".utf8)
        let unknownSource = Data("{\"id\":\"22222222-2222-2222-2222-222222222222\",\"sessionID\":\"11111111-1111-1111-1111-111111111111\",\"occurredAt\":\"2023-11-14T22:13:20Z\",\"source\":\"ipad\",\"kind\":{\"type\":\"setDeleted\",\"setID\":\"44444444-4444-4444-4444-444444444444\"}}".utf8)
        let singleEvent = try SyncCodec.encode(Self.makeEvent(kind: .setDeleted(setID: Self.setID)))

        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeEvent(unknownKind) }
        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeEvent(missingField) }
        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeEvent(unknownSource) }
        #expect(throws: SyncError.corrupted) { try SyncCodec.decodeEvents(singleEvent) }
    }

    // MARK: - Determinism

    @Test("§9 encode é determinístico: duas codificações iguais byte a byte")
    func encodeIsDeterministic() throws {
        let snapshot = Self.makeFullSnapshot()
        let rebuilt = Self.makeFullSnapshot()
        let event = Self.makeEvent(kind: Self.allKinds[1])

        #expect(try SyncCodec.encode(snapshot) == SyncCodec.encode(snapshot))
        #expect(try SyncCodec.encode(snapshot) == SyncCodec.encode(rebuilt))
        #expect(try SyncCodec.encode(event) == SyncCodec.encode(event))
        #expect(try SyncCodec.encode(Self.allKinds) == SyncCodec.encode(Self.allKinds))
    }

    @Test("§9 datas no fio têm precisão de segundo inteiro (ISO 8601 sem fração)")
    func datesRoundTripAtWholeSecondPrecision() throws {
        let fractional = Date(timeIntervalSince1970: 1_700_000_000.75)
        let event = SessionEvent(id: Self.eventID, sessionID: Self.sessionID, occurredAt: fractional, source: .watch, kind: .setDeleted(setID: Self.setID))

        let decoded = try SyncCodec.decodeEvent(SyncCodec.encode(event))

        // Documented limitation of `.iso8601`: the fraction is dropped, so producers
        // must not rely on sub-second ordering across the sync boundary.
        #expect(abs(decoded.occurredAt.timeIntervalSince(fractional)) < 1)
        #expect(decoded.occurredAt.timeIntervalSince1970 == decoded.occurredAt.timeIntervalSince1970.rounded(.towardZero))
    }
}
