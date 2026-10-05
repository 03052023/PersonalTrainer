import Foundation
import HealthKit
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T10.4 (SPEC RF-13, §7.14 F5 e F7): o tipo de treino que o app grava no Saúde para o Cardio e a
/// FC por minuto do intervalo. Tudo puro (sem aparelho): a tabela slug → tipo, a tabela tipo →
/// `HKWorkoutActivityType` do `LiveHealthKitService`, a leitura desses tipos como aeróbicos pelo
/// `LiveHealthDataReader` (A1) e o `FakeHealthKitService`. O fluxo do gravador com sessões de
/// verdade está em `HealthKitWorkoutRecorderTests`.
final class F5WorkoutKindTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Slug → tipo (F5)

    func testF5_slugMappingTable() {
        let table: [(slug: String, kind: WorkoutRecordKind)] = [
            ("brisk-walk", .aerobic(.walking)),
            ("easy-run", .aerobic(.running)),
            ("run-intervals", .aerobic(.running)),
            ("stationary-bike", .aerobic(.cycling)),
            ("bike-intervals", .aerobic(.cycling)),
            ("rowing-machine", .aerobic(.rowing)),
            ("elliptical", .aerobic(.elliptical)),
            ("stair-climb", .aerobic(.stairs)),
            ("jump-rope", .jumpRope),
            ("bodyweight-circuit", .aerobic(.hiit)),
            // Exercício criado pela pessoa (padrão `cardio`, slug fora da tabela): cardio misto.
            ("meu-cardio-proprio", .aerobic(.other)),
            ("", .aerobic(.other)),
        ]

        for row in table {
            XCTAssertEqual(WorkoutRecordKind.aerobicKind(forSlug: row.slug), row.kind, "slug \"\(row.slug)\"")
        }
    }

    func testF5_everySeedCardioExerciseHasAKind() throws {
        let seed = try decodeSeed()
        let cardioSlugs = seed.catalog.exercises.filter { $0.movementPattern == .cardio }.map(\.slug)

        XCTAssertFalse(cardioSlugs.isEmpty)
        for slug in cardioSlugs {
            XCTAssertNotEqual(
                WorkoutRecordKind.aerobicKind(forSlug: slug),
                WorkoutRecordKind.aerobic(.other),
                "O aeróbico \"\(slug)\" do catálogo caiu no tipo genérico: falta na tabela de F5"
            )
        }
    }

    // MARK: - Tipo → HKWorkoutActivityType (Live)

    func testF5_liveActivityTypeTable() {
        let table: [(kind: WorkoutRecordKind, type: HKWorkoutActivityType)] = [
            (.strength, .traditionalStrengthTraining),
            (.aerobic(.walking), .walking),
            (.aerobic(.running), .running),
            (.aerobic(.cycling), .cycling),
            (.aerobic(.rowing), .rowing),
            (.aerobic(.elliptical), .elliptical),
            (.aerobic(.stairs), .stairClimbing),
            (.jumpRope, .jumpRope),
            (.aerobic(.hiit), .highIntensityIntervalTraining),
            (.aerobic(.swimming), .swimming),
            (.aerobic(.hiking), .hiking),
            (.aerobic(.dance), .cardioDance),
            (.aerobic(.other), .mixedCardio),
        ]

        for row in table {
            XCTAssertEqual(LiveHealthKitService.activityType(for: row.kind), row.type, "\(row.kind)")
        }
    }

    func testF5_slugToHealthKitTypeTable() {
        let table: [(slug: String, type: HKWorkoutActivityType)] = [
            ("brisk-walk", .walking),
            ("easy-run", .running),
            ("run-intervals", .running),
            ("stationary-bike", .cycling),
            ("bike-intervals", .cycling),
            ("rowing-machine", .rowing),
            ("elliptical", .elliptical),
            ("stair-climb", .stairClimbing),
            ("jump-rope", .jumpRope),
            ("bodyweight-circuit", .highIntensityIntervalTraining),
        ]

        for row in table {
            let kind = WorkoutRecordKind.aerobicKind(forSlug: row.slug)
            XCTAssertEqual(LiveHealthKitService.activityType(for: kind), row.type, "slug \"\(row.slug)\"")
        }
    }

    // MARK: - Vínculo pelo mesmo tipo (RF-13)

    func testF5_linkMatchesTheSameKindOnly() {
        // Força vincula com força (a tradicional e a funcional), e com nada mais.
        XCTAssertTrue(LiveHealthKitService.workoutType(.traditionalStrengthTraining, matches: .strength))
        XCTAssertTrue(LiveHealthKitService.workoutType(.functionalStrengthTraining, matches: .strength))
        XCTAssertFalse(LiveHealthKitService.workoutType(.walking, matches: .strength))
        XCTAssertFalse(LiveHealthKitService.workoutType(.highIntensityIntervalTraining, matches: .strength))

        // Aeróbico vincula com qualquer treino aeróbico, de qualquer tipo, e não com força.
        let aerobicKinds: [WorkoutRecordKind] = [.aerobic(.walking), .aerobic(.running), .jumpRope]
        for kind in aerobicKinds {
            XCTAssertTrue(LiveHealthKitService.workoutType(.walking, matches: kind), "\(kind)")
            XCTAssertTrue(LiveHealthKitService.workoutType(.cycling, matches: kind), "\(kind)")
            XCTAssertTrue(LiveHealthKitService.workoutType(.jumpRope, matches: kind), "\(kind)")
            XCTAssertFalse(LiveHealthKitService.workoutType(.traditionalStrengthTraining, matches: kind), "\(kind)")
            XCTAssertFalse(LiveHealthKitService.workoutType(.functionalStrengthTraining, matches: kind), "\(kind)")
            XCTAssertFalse(LiveHealthKitService.workoutType(.yoga, matches: kind), "\(kind)")
            XCTAssertFalse(LiveHealthKitService.workoutType(.golf, matches: kind), "\(kind)")
        }
    }

    // MARK: - Leitura dos tipos gravados (A1)

    func testF5_readerRecognisesEveryWrittenTypeAsAerobic() {
        let written: [HKWorkoutActivityType] = [
            .walking, .running, .cycling, .rowing, .elliptical, .stairClimbing,
            .jumpRope, .highIntensityIntervalTraining, .mixedCardio,
        ]

        for type in written {
            XCTAssertNotNil(LiveHealthDataReader.aerobicActivity(for: type), "tipo \(type.rawValue)")
        }
        XCTAssertEqual(LiveHealthDataReader.aerobicActivity(for: .walking), AerobicActivity.walking)
        XCTAssertEqual(LiveHealthDataReader.aerobicActivity(for: .running), AerobicActivity.running)
        XCTAssertEqual(LiveHealthDataReader.aerobicActivity(for: .cycling), AerobicActivity.cycling)
        XCTAssertEqual(LiveHealthDataReader.aerobicActivity(for: .rowing), AerobicActivity.rowing)
        XCTAssertEqual(LiveHealthDataReader.aerobicActivity(for: .elliptical), AerobicActivity.elliptical)
        XCTAssertEqual(LiveHealthDataReader.aerobicActivity(for: .stairClimbing), AerobicActivity.stairs)
        XCTAssertEqual(LiveHealthDataReader.aerobicActivity(for: .highIntensityIntervalTraining), AerobicActivity.hiit)
        XCTAssertEqual(
            LiveHealthDataReader.aerobicActivity(for: .jumpRope),
            AerobicActivity.hiit,
            "O pular corda entra como HIIT: forte pelo tipo (A1), sem depender de FC"
        )
        XCTAssertEqual(LiveHealthDataReader.aerobicActivity(for: .mixedCardio), AerobicActivity.other)
        XCTAssertNil(LiveHealthDataReader.aerobicActivity(for: .traditionalStrengthTraining))
    }

    func testF5_writtenTypesKeepTheIntensityOfTheExercise() {
        // O que o app grava, lido de volta: a intensidade padrão por tipo (A1) é a esperada para o
        // Cardio (caminhada e bicicleta moderadas; corrida, HIIT e corda fortes).
        let table: [(kind: WorkoutRecordKind, intensity: AerobicIntensity)] = [
            (.aerobic(.walking), .moderate),
            (.aerobic(.cycling), .moderate),
            (.aerobic(.rowing), .moderate),
            (.aerobic(.elliptical), .moderate),
            (.aerobic(.running), .vigorous),
            (.aerobic(.hiit), .vigorous),
            (.jumpRope, .vigorous),
        ]

        for row in table {
            let type = LiveHealthKitService.activityType(for: row.kind)
            let read = LiveHealthDataReader.aerobicActivity(for: type)
            XCTAssertEqual(read?.defaultIntensity, row.intensity, "\(row.kind)")
        }
    }

    // MARK: - Padrões do protocolo (fakes antigos)

    func testF5_protocolDefaultsKeepLegacyConformersWorking() async throws {
        let strengthOverlap = UUID()
        let savedStrength = UUID()
        let legacy = LegacyHealthKit(overlappingStrength: strengthOverlap, savedStrength: savedStrength)
        let end = start.addingTimeInterval(3_600)

        let saved = try await legacy.saveWorkout(.aerobic(.walking), start: start, end: end, sessionUUID: UUID())
        let strengthLink = try await legacy.findOverlappingWorkout(.strength, start: start, end: end)
        let aerobicLink = try await legacy.findOverlappingWorkout(.aerobic(.walking), start: start, end: end)
        let ropeLink = try await legacy.findOverlappingWorkout(.jumpRope, start: start, end: end)
        let minutes = try await legacy.heartRateMinutes(start: start, end: end)

        XCTAssertEqual(saved, savedStrength, "Padrão: grava como força, como antes da 2.4")
        XCTAssertEqual(strengthLink, strengthOverlap)
        XCTAssertNil(aerobicLink)
        XCTAssertNil(ropeLink)
        XCTAssertEqual(minutes, [])
    }

    func testF5_fakeDispatchesTheNewRequirementsThroughTheProtocol() async throws {
        let aerobicWorkout = UUID()
        let fake = FakeHealthKitService(overlappingAerobicWorkoutToReturn: aerobicWorkout, minuteHeartRatesToReturn: [101, 102])
        let service: any HealthKitServicing = fake
        let end = start.addingTimeInterval(1_800)
        try await service.requestAuthorization()

        let saved = try await service.saveWorkout(.aerobic(.cycling), start: start, end: end, sessionUUID: UUID())
        let link = try await service.findOverlappingWorkout(.aerobic(.cycling), start: start, end: end)
        let strengthLink = try await service.findOverlappingWorkout(.strength, start: start, end: end)
        let minutes = try await service.heartRateMinutes(start: start, end: end)

        // Se um rótulo ou tipo da assinatura divergisse do protocolo, o Swift usaria o padrão em
        // silêncio: o `kind` registrado e a FC configurada só aparecem com a implementação do fake.
        let records = await fake.savedWorkouts
        XCTAssertEqual(records.map(\.kind), [WorkoutRecordKind.aerobic(.cycling)])
        XCTAssertEqual(records.first?.returnedUUID, saved)
        XCTAssertEqual(link, aerobicWorkout)
        XCTAssertNil(strengthLink, "O treino aeróbico configurado não serve para a força")
        XCTAssertEqual(minutes, [101, 102])
    }

    // MARK: - F7: FC por minuto

    func testF7_fakeHeartRateMinutes() async throws {
        let end = start.addingTimeInterval(30 * 60 + 20)
        let configured: [Double] = [96, 110, 124]
        let service = FakeHealthKitService(minuteHeartRatesToReturn: configured)

        let minutes = try await service.heartRateMinutes(start: start, end: end)

        XCTAssertEqual(minutes, configured)
        let queries = await service.heartRateMinuteQueries
        XCTAssertEqual(queries, [FakeHealthKitService.HeartRateQuery(start: start, end: end)])
        let summaryQueries = await service.heartRateQueries
        XCTAssertTrue(summaryQueries.isEmpty, "É outra consulta: o resumo continua separado")
        let authorizationRequests = await service.authorizationRequestCount
        XCTAssertEqual(authorizationRequests, 0, "Leitura nunca pede autorização (AGENTS §7)")
    }

    func testF7_fakeHeartRateMinutes_emptyListMeansNoHeartRate() async throws {
        let service = FakeHealthKitService(minuteHeartRatesToReturn: [])

        let minutes = try await service.heartRateMinutes(start: start, end: start.addingTimeInterval(3_600))

        XCTAssertEqual(minutes, [])
    }

    func testF7_fakeHeartRateMinutes_defaultIsSyntheticAndDeterministic() async throws {
        let service = FakeHealthKitService()
        let end = start.addingTimeInterval(30 * 60 + 20)

        let first = try await service.heartRateMinutes(start: start, end: end)
        let second = try await service.heartRateMinutes(start: start, end: end)

        XCTAssertEqual(first.count, 30, "Um valor por minuto inteiro do intervalo")
        XCTAssertEqual(first, second)
        XCTAssertEqual(Array(first.prefix(3)), [100, 108, 116], "Três minutos de aquecimento")
        XCTAssertTrue(first.allSatisfy { $0 >= 100 && $0 <= 140 })
    }

    func testF7_fakeHeartRateMinutes_shortOrBackwardsIntervalIsEmpty() async throws {
        let service = FakeHealthKitService()

        let tooShort = try await service.heartRateMinutes(start: start, end: start.addingTimeInterval(59))
        let backwards = try await service.heartRateMinutes(start: start, end: start.addingTimeInterval(-3_600))

        XCTAssertEqual(tooShort, [])
        XCTAssertEqual(backwards, [])
    }

    func testF7_fakeHeartRateMinutes_canBeReconfiguredAfterInit() async throws {
        let service = FakeHealthKitService(minuteHeartRatesToReturn: [])
        let end = start.addingTimeInterval(600)

        await service.setMinuteHeartRatesToReturn([88, 90])
        let configured = try await service.heartRateMinutes(start: start, end: end)
        await service.setMinuteHeartRatesToReturn(nil)
        let synthetic = try await service.heartRateMinutes(start: start, end: end)

        XCTAssertEqual(configured, [88, 90])
        XCTAssertEqual(synthetic.count, 10)
    }

    func testF7_fakeHeartRateMinutes_unavailableThrows() async {
        let service = FakeHealthKitService(isAvailable: false)

        do {
            _ = try await service.heartRateMinutes(start: start, end: start.addingTimeInterval(3_600))
            XCTFail("Esperava HealthKitServiceError.unavailable")
        } catch let error as HealthKitServiceError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }

    // MARK: - Apoio

    /// Só os requisitos de antes da 2.4: os três novos vêm dos padrões do protocolo.
    private struct LegacyHealthKit: HealthKitServicing {
        let isAvailable = true
        let overlappingStrength: UUID
        let savedStrength: UUID

        func requestAuthorization() async throws {}

        func saveStrengthWorkout(start: Date, end: Date, sessionUUID: UUID) async throws -> UUID {
            savedStrength
        }

        func heartRateSummary(start: Date, end: Date) async throws -> HeartRateSummary? {
            nil
        }

        func findOverlappingStrengthWorkout(start: Date, end: Date) async throws -> UUID? {
            overlappingStrength
        }
    }

    /// O seed é recurso do app; os testes são hospedados por ele, então `Bundle.main` é o bundle do
    /// app (como em `SeedLoaderTests`).
    private func decodeSeed() throws -> SeedBundle {
        let catalogURL = try XCTUnwrap(
            Bundle.main.url(forResource: SeedLoader.catalogResourceName, withExtension: "json"),
            "\(SeedLoader.catalogResourceName).json não está na raiz do bundle do app"
        )
        let programURL = try XCTUnwrap(
            Bundle.main.url(forResource: SeedLoader.programResourceName, withExtension: "json"),
            "\(SeedLoader.programResourceName).json não está na raiz do bundle do app"
        )
        return try SeedBundle.decode(
            catalogData: Data(contentsOf: catalogURL),
            programData: Data(contentsOf: programURL)
        )
    }
}
