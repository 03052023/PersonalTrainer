import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// T5.3: `HealthViewModel` (SPEC RF-27..RF-31, §7.10) sobre um leitor espião e sobre o
/// `FakeHealthDataReader` do contrato M5. Cobre: app Saúde indisponível, autorização só por ação
/// do usuário (AGENTS §7), cálculo igual ao de `HealthCalculator`, mescla do perfil manual na
/// `UserPhysiology`, sugestões dispensadas pelo log do diálogo (V21-CONTRACT B3, A4/B8) e a
/// formatação pt-BR do card.
/// Relógio e calendário fixos (SPEC P11); cada teste usa uma suite própria de `UserDefaults`.
@MainActor
final class HealthViewModelTests: XCTestCase {
    /// Gregoriano, UTC−3 fixo (sem horário de verão), semana começando na segunda.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -3 * 3_600) ?? .gmt
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Quarta-feira, 23/09/2026, 12:00 em UTC−3.
    private let now = Date(timeIntervalSince1970: 1_790_175_600)

    // MARK: - Chaves e estado inicial

    func testKeys_matchTheStableNamesUsedByTheApp() {
        XCTAssertEqual(HealthViewModel.Keys.readAuthorized, "healthReadAuthorized")
        XCTAssertEqual(HealthViewModel.Keys.birthYear, "profileBirthYear")
        XCTAssertEqual(HealthViewModel.Keys.sex, "profileSex")
    }

    func testInit_withoutStoredFlag_needsAuthorization_andReadsNothing() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = HealthSpyReader(input: sampleInput())

        let model = makeModel(reader: reader, defaults: defaults)

        XCTAssertTrue(model.needsAuthorization)
        XCTAssertNil(model.report)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        let reads = await reader.readCalls
        XCTAssertTrue(reads.isEmpty, "Nada é lido no init")
    }

    func testInit_withStoredFlag_doesNotNeedAuthorization() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")

        let model = makeModel(reader: HealthSpyReader(input: sampleInput()), defaults: defaults)

        XCTAssertFalse(model.needsAuthorization)
    }

    // MARK: - Saúde indisponível

    func testRF31_load_healthUnavailable_setsPortugueseMessage_withoutReading() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        let reader = HealthSpyReader(input: sampleInput(), isAvailable: false)
        let model = makeModel(reader: reader, defaults: defaults)

        await model.load()

        XCTAssertEqual(model.errorMessage, "O app Saúde não está disponível neste aparelho.")
        XCTAssertNil(model.report)
        XCTAssertFalse(model.isLoading)
        let reads = await reader.readCalls
        XCTAssertTrue(reads.isEmpty)
    }

    func testRF31_load_withContractFakeUnavailable_setsPortugueseMessage() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        let model = makeModel(reader: FakeHealthDataReader(isAvailable: false), defaults: defaults)

        await model.load()

        XCTAssertEqual(model.errorMessage, "O app Saúde não está disponível neste aparelho.")
        XCTAssertNil(model.report)
    }

    func testRF31_requestAuthorization_healthUnavailable_neitherAsksNorStoresFlag() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = HealthSpyReader(input: sampleInput(), isAvailable: false)
        let model = makeModel(reader: reader, defaults: defaults)

        await model.requestAuthorization()

        XCTAssertEqual(model.errorMessage, "O app Saúde não está disponível neste aparelho.")
        XCTAssertTrue(model.needsAuthorization)
        XCTAssertFalse(defaults.bool(forKey: "healthReadAuthorized"))
        let authorizationCalls = await reader.authorizationCalls
        XCTAssertEqual(authorizationCalls, 0)
    }

    // MARK: - Autorização (AGENTS §7: só por toque do usuário)

    func testLoad_beforeAuthorization_doesNotReadNorAsk() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = HealthSpyReader(input: sampleInput())
        let model = makeModel(reader: reader, defaults: defaults)

        await model.load()

        XCTAssertNil(model.report)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.needsAuthorization)
        let reads = await reader.readCalls
        let authorizationCalls = await reader.authorizationCalls
        XCTAssertTrue(reads.isEmpty, "Ler antes de conectar seria pedir no launch")
        XCTAssertEqual(authorizationCalls, 0)
    }

    func testRequestAuthorization_asksOnce_storesFlag_andLoadsReport() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = HealthSpyReader(input: sampleInput())
        let model = makeModel(reader: reader, defaults: defaults)

        await model.requestAuthorization()

        let authorizationCalls = await reader.authorizationCalls
        let reads = await reader.readCalls
        XCTAssertEqual(authorizationCalls, 1)
        XCTAssertEqual(reads.count, 1, "Recarrega logo depois de conectar")
        XCTAssertTrue(defaults.bool(forKey: "healthReadAuthorized"))
        XCTAssertFalse(model.needsAuthorization)
        XCTAssertNotNil(model.report)
        XCTAssertNil(model.errorMessage)

        let relaunched = makeModel(reader: reader, defaults: defaults)
        XCTAssertFalse(relaunched.needsAuthorization, "A flag sobrevive a um novo launch")
    }

    func testRequestAuthorization_failure_keepsPrompt_andShowsMessage() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let reader = HealthSpyReader(input: sampleInput())
        await reader.setAuthorizationError(HealthTestError.boom)
        let model = makeModel(reader: reader, defaults: defaults)

        await model.requestAuthorization()

        XCTAssertTrue(model.needsAuthorization)
        XCTAssertFalse(defaults.bool(forKey: "healthReadAuthorized"))
        XCTAssertEqual(model.errorMessage, HealthViewModel.authorizationFailedMessage)
        XCTAssertNil(model.report)
        let reads = await reader.readCalls
        XCTAssertTrue(reads.isEmpty)
    }

    // MARK: - Leitura e cálculo

    func testLoad_passesInjectedClockCalendarAndSessionsToReader() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        let session = SessionSummary(
            programDayID: UUID(),
            startedAt: now.addingTimeInterval(-86_400),
            endedAt: now.addingTimeInterval(-82_800),
            status: .completed,
            primaryMusclesTrained: [.quads, .glutes],
            workingSetCount: 12
        )
        let reader = HealthSpyReader(input: sampleInput())
        let model = makeModel(reader: reader, defaults: defaults, sessions: [session])

        await model.load()

        let reads = await reader.readCalls
        XCTAssertEqual(reads.count, 1)
        XCTAssertEqual(reads.first?.now, now, "SPEC P11: relógio injetado")
        XCTAssertEqual(reads.first?.calendar, calendar)
        XCTAssertEqual(reads.first?.sessions, [session], "Sessões recentes para o encaixe (A5)")
    }

    func testLoad_sampleInput_reportEqualsHealthCalculator() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        let input = sampleInput()
        let model = makeModel(reader: HealthSpyReader(input: input), defaults: defaults)

        await model.load()

        // Sem perfil manual, a mescla preserva exatamente o que o Saúde informou.
        let expected = HealthCalculator.report(input: input, targets: HealthTargets(), now: now, calendar: calendar)
        XCTAssertEqual(model.report, expected)
        XCTAssertEqual(model.physiology, input.physiology)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    func testLoad_withContractFake_producesReportWithDefaultTargets() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        let model = makeModel(reader: FakeHealthDataReader(), defaults: defaults)

        await model.load()

        let report = try XCTUnwrap(model.report)
        XCTAssertEqual(report.aerobic.target, 150, "SPEC A2: 150 min moderados-equivalentes")
        XCTAssertEqual(report.steps.target, 7_000)
        XCTAssertNil(model.errorMessage)
    }

    func testLoad_customTargets_reachTheReport() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        let targets = HealthTargets(weeklyModerateEquivalentMinutes: 300, dailySteps: 10_000, sleepHours: 8)
        let model = makeModel(reader: HealthSpyReader(input: sampleInput()), defaults: defaults, targets: targets)

        await model.load()

        XCTAssertEqual(model.report?.aerobic.target, 300)
        XCTAssertEqual(model.report?.steps.target, 10_000)
    }

    func testLoad_readFailure_keepsPreviousReport_andRecovers() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        let reader = HealthSpyReader(input: sampleInput())
        let model = makeModel(reader: reader, defaults: defaults)
        await model.load()
        let firstReport = try XCTUnwrap(model.report)

        await reader.setReadError(HealthTestError.boom)
        await model.load()

        XCTAssertEqual(model.report, firstReport, "Contexto de ontem vale mais que um card vazio")
        XCTAssertEqual(model.errorMessage, HealthViewModel.readFailedMessage)
        XCTAssertFalse(model.isLoading)

        await reader.setReadError(nil)
        await model.load()

        XCTAssertNil(model.errorMessage)
        XCTAssertNotNil(model.report)
    }

    func testLoadIfStale_skipsFreshData_andReloadsAfterMaxAge() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        let reader = HealthSpyReader(input: sampleInput())
        let clock = HealthTestClock(now)
        let model = HealthViewModel(
            reader: reader,
            sessionsProvider: { [] },
            now: { clock.now },
            calendar: calendar,
            defaults: defaults
        )

        await model.loadIfStale()
        clock.now = now.addingTimeInterval(5 * 60)
        await model.loadIfStale()
        var reads = await reader.readCalls
        XCTAssertEqual(reads.count, 1, "Voltar à Home 5 min depois não relê o Saúde")

        clock.now = now.addingTimeInterval(16 * 60)
        await model.loadIfStale()
        reads = await reader.readCalls
        XCTAssertEqual(reads.count, 2)
        XCTAssertEqual(reads.last?.now, now.addingTimeInterval(16 * 60))
    }

    // MARK: - Perfil manual (idade e sexo quando o Saúde não informa)

    func testLoad_mergesStoredProfile_whenHealthLacksBirthDateAndSex() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        defaults.set(1986, forKey: "profileBirthYear")
        defaults.set("female", forKey: "profileSex")
        let raw = sampleInput(physiology: UserPhysiology(birthDate: nil, sex: nil, maxHeartRateOverride: nil))
        let model = makeModel(reader: HealthSpyReader(input: raw), defaults: defaults)

        await model.load()

        let birthDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 1986, month: 7, day: 1)))
        let merged = UserPhysiology(birthDate: birthDate, sex: .female, maxHeartRateOverride: nil)
        XCTAssertEqual(model.physiology, merged)
        XCTAssertEqual(model.healthProvidedPhysiology, raw.physiology)
        let expected = HealthCalculator.report(
            input: replacingPhysiology(of: raw, with: merged),
            targets: HealthTargets(),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(model.report, expected, "O cálculo recebe um HealthInput novo com o perfil mesclado")
    }

    func testSaveProfile_persistsKeys_andRecalculatesWithoutRereadingHealth() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        let raw = sampleInput(physiology: UserPhysiology(birthDate: nil, sex: nil, maxHeartRateOverride: nil))
        let reader = HealthSpyReader(input: raw)
        let model = makeModel(reader: reader, defaults: defaults)
        await model.load()

        model.saveProfile(birthYear: 1990, sex: .male, maxHeartRate: 188)

        XCTAssertEqual(defaults.integer(forKey: "profileBirthYear"), 1990)
        XCTAssertEqual(defaults.string(forKey: "profileSex"), "male")
        XCTAssertEqual(defaults.integer(forKey: "profileMaxHeartRate"), 188)
        let birthDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 1990, month: 7, day: 1)))
        let merged = UserPhysiology(birthDate: birthDate, sex: .male, maxHeartRateOverride: 188)
        XCTAssertEqual(model.physiology, merged)
        let expected = HealthCalculator.report(
            input: replacingPhysiology(of: raw, with: merged),
            targets: HealthTargets(),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(model.report, expected)
        let reads = await reader.readCalls
        XCTAssertEqual(reads.count, 1, "Salvar o perfil recalcula com a última leitura")

        let relaunched = makeModel(reader: reader, defaults: defaults)
        XCTAssertEqual(relaunched.profileBirthYear, 1990)
        XCTAssertEqual(relaunched.profileSex, .male)
        XCTAssertEqual(relaunched.profileMaxHeartRate, 188)
    }

    func testMerge_healthBirthDateAndSexTakePrecedence_butMeasuredMaxHeartRateWins() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        defaults.set(1970, forKey: "profileBirthYear")
        defaults.set("female", forKey: "profileSex")
        defaults.set(181, forKey: "profileMaxHeartRate")
        let healthBirthDate = try XCTUnwrap(calendar.date(from: DateComponents(year: 1988, month: 3, day: 14)))
        let raw = sampleInput(physiology: UserPhysiology(birthDate: healthBirthDate, sex: .male, maxHeartRateOverride: nil))
        let model = makeModel(reader: HealthSpyReader(input: raw), defaults: defaults)

        await model.load()

        XCTAssertEqual(
            model.physiology,
            UserPhysiology(birthDate: healthBirthDate, sex: .male, maxHeartRateOverride: 181),
            "Saúde vence em data e sexo; a FCmáx medida vence a estimativa (SPEC A1)"
        )
    }

    func testSaveProfile_outOfRangeValues_areStoredAsNotInformed() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(1986, forKey: "profileBirthYear")
        defaults.set(190, forKey: "profileMaxHeartRate")
        let model = makeModel(reader: HealthSpyReader(input: sampleInput()), defaults: defaults)
        XCTAssertEqual(model.profileBirthYear, 1986)

        model.saveProfile(birthYear: 1850, sex: nil, maxHeartRate: 300)
        XCTAssertNil(model.profileBirthYear)
        XCTAssertNil(model.profileMaxHeartRate)
        XCTAssertNil(defaults.object(forKey: "profileBirthYear"))
        XCTAssertNil(defaults.object(forKey: "profileMaxHeartRate"))
        XCTAssertNil(defaults.object(forKey: "profileSex"))

        model.saveProfile(birthYear: 2027, sex: .other, maxHeartRate: nil)
        XCTAssertNil(model.profileBirthYear, "Ano depois do ano corrente é erro de digitação")
        XCTAssertEqual(model.profileSex, .other)
    }

    // MARK: - "Ok, entendi" (V21-CONTRACT B3, A4/B8: fonte única é o log do diálogo)

    /// Sem dado noturno: `HealthSpyReader` isolado para os testes de dispensa (evita reler o Saúde
    /// duas vezes na mesma suíte). SPEC A4 exige a sugestão "use o relógio para dormir".
    private func emptyRecoveryReader() -> HealthSpyReader {
        let empty = HealthInput(
            physiology: UserPhysiology(birthDate: nil, sex: nil, maxHeartRateOverride: nil),
            aerobicWorkouts: [],
            recovery: [],
            steps: [],
            vo2Max: [],
            recentSessions: []
        )
        return HealthSpyReader(input: empty)
    }

    func testDismiss_writesTheSameEntryTheCoachFeedWould_andHidesForTheCooldown() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        let reader = emptyRecoveryReader()
        let logStore = FakeCoachLogStore()
        let model = makeModel(reader: reader, defaults: defaults, logStore: logStore)
        await model.load()
        let report = try XCTUnwrap(model.report)
        let dismissed = try XCTUnwrap(report.suggestions.first, "SPEC A4: sem dado noturno há sugestão")
        XCTAssertEqual(model.visibleSuggestions.map(\.id), report.suggestions.map(\.id))

        model.dismiss(dismissed)

        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.visibleSuggestions.contains { $0.id == dismissed.id })
        XCTAssertEqual(model.visibleSuggestions.count, report.suggestions.count - 1)
        XCTAssertEqual(model.report?.suggestions, report.suggestions, "Dispensar só esconde; o relatório não muda")

        // A entrada gravada é a mesma que o feed da Home grava para "Entendi" (SPEC §7.11 C3):
        // regra `.health`, item = o tipo da sugestão, ação `.understood`.
        let entry = try XCTUnwrap(logStore.log.entries.first)
        XCTAssertEqual(entry.rule, .health)
        XCTAssertEqual(entry.itemKey, dismissed.kind.rawValue)
        XCTAssertEqual(entry.action, .understood)
        XCTAssertEqual(entry.date, now)

        // Mesmo log, um `HealthViewModel` novo (outra instância, outra tela): continua escondida.
        let sameLogAnotherModel = makeModel(reader: reader, defaults: defaults, logStore: logStore)
        await sameLogAnotherModel.load()
        XCTAssertFalse(sameLogAnotherModel.visibleSuggestions.contains { $0.id == dismissed.id })

        // Dentro do prazo de 3 dias (SPEC C3), ainda escondida.
        let stillCooling = makeModel(
            reader: reader,
            defaults: defaults,
            now: now.addingTimeInterval(2 * 86_400),
            logStore: logStore
        )
        await stillCooling.load()
        XCTAssertFalse(stillCooling.visibleSuggestions.contains { $0.id == dismissed.id }, "Ainda dentro dos 3 dias")

        // Depois de 3 dias, volta se a condição persistir.
        let afterCooldown = makeModel(
            reader: reader,
            defaults: defaults,
            now: now.addingTimeInterval(3 * 86_400),
            logStore: logStore
        )
        await afterCooldown.load()
        XCTAssertEqual(
            afterCooldown.visibleSuggestions.map(\.id),
            afterCooldown.report?.suggestions.map(\.id),
            "Depois do prazo de C3 nada fica escondido"
        )
    }

    /// A4/B8, sentido feed → detalhe: uma resposta já gravada por `CoachService` (o feed da Home)
    /// também esconde a sugestão aqui, sem que a tela de Saúde precise dispensar de novo.
    func testVisibleSuggestions_hidesEntryAlreadyRecordedByTheCoachFeed() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        let reader = emptyRecoveryReader()
        var seededLog = CoachLog()
        seededLog.entries.append(
            CoachLogEntry(
                messageID: "health:wearWatchAtNight:2026-09-23",
                rule: .health,
                itemKey: HealthSuggestionKind.wearWatchAtNight.rawValue,
                action: .understood,
                date: now
            )
        )
        let logStore = FakeCoachLogStore(log: seededLog)
        let model = makeModel(reader: reader, defaults: defaults, logStore: logStore)

        await model.load()

        let report = try XCTUnwrap(model.report)
        XCTAssertTrue(report.suggestions.contains { $0.kind == .wearWatchAtNight }, "Pré-condição do teste")
        XCTAssertFalse(
            model.visibleSuggestions.contains { $0.kind == .wearWatchAtNight },
            "Já respondida no feed: não aparece de novo na tela de Saúde"
        )
    }

    /// A4/B8, sentido detalhe → feed: dispensar na tela de Saúde também esconde a mensagem que
    /// `CoachFeedBuilder` (TrainerCore) montaria para o feed da Home.
    func testDismiss_alsoHidesTheMessageCoachFeedBuilderWouldShow() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        let reader = emptyRecoveryReader()
        let logStore = FakeCoachLogStore()
        let model = makeModel(reader: reader, defaults: defaults, logStore: logStore)
        await model.load()
        let report = try XCTUnwrap(model.report)
        let dismissed = try XCTUnwrap(report.suggestions.first)

        let feedBefore = CoachFeedBuilder.feed(
            input: CoachInput(healthSuggestions: report.suggestions),
            log: logStore.load(),
            now: now,
            calendar: calendar
        )
        XCTAssertTrue(feedBefore.contains { $0.rule == .health && $0.itemKey == dismissed.kind.rawValue })

        model.dismiss(dismissed)

        let feedAfter = CoachFeedBuilder.feed(
            input: CoachInput(healthSuggestions: report.suggestions),
            log: logStore.load(),
            now: now,
            calendar: calendar
        )
        XCTAssertFalse(
            feedAfter.contains { $0.rule == .health && $0.itemKey == dismissed.kind.rawValue },
            "O feed da Home lê o mesmo log; a dispensa na tela de Saúde some de lá também"
        )
    }

    func testDismiss_saveFailure_setsPortugueseErrorMessage_butStillFiltersLocally() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "healthReadAuthorized")
        let reader = emptyRecoveryReader()
        let logStore = FakeCoachLogStore()
        logStore.saveError = HealthTestError.boom
        let model = makeModel(reader: reader, defaults: defaults, logStore: logStore)
        await model.load()
        let report = try XCTUnwrap(model.report)
        let dismissed = try XCTUnwrap(report.suggestions.first)

        model.dismiss(dismissed)

        XCTAssertEqual(logStore.saveCount, 0, "A gravação falhou: nada foi persistido")
        XCTAssertNotNil(model.errorMessage)
        // `visibleSuggestions` relê `logStore.load()`, que sem gravação continua sem a resposta:
        // a sugestão volta a aparecer, coerente com o log ser a única fonte.
        XCTAssertTrue(model.visibleSuggestions.contains { $0.id == dismissed.id })
    }

    // MARK: - Formatação pt-BR do card

    func testFormat_cardLines_inBrazilianPortuguese() {
        typealias Format = HealthCardView.Format
        let aerobic = AerobicWeekSummary(
            moderateMinutes: 65,
            vigorousMinutes: 15,
            moderateEquivalentMinutes: 95,
            target: 150,
            perDay: []
        )
        XCTAssertEqual(Format.aerobicHeadline(aerobic), "Aeróbico: 95 de 150 min")
        XCTAssertEqual(Format.clampedProgress(95, of: 150), 95.0 / 150.0, accuracy: 1e-9)
        XCTAssertEqual(Format.clampedProgress(400, of: 150), 1)
        XCTAssertEqual(Format.clampedProgress(10, of: 0), 0, "Meta zero não divide por zero")

        let vo2Max = Vo2MaxSummary(latest: 44, latestDate: now, change90Days: 1.2, band: .good, ageYears: 40)
        XCTAssertEqual(Format.vo2MaxLine(vo2Max), "VO2máx 44 · \(FitnessBand.good.displayName)")
        XCTAssertEqual(Format.vo2MaxLine(nil), "VO2máx sem medição recente")

        XCTAssertEqual(Format.sleepLine(6.8), "Sono 6,8 h")
        XCTAssertEqual(Format.sleepLine(nil), "Sono sem dados")
        XCTAssertEqual(Format.stepsLine(8_200), "Passos 8.200/dia")
        XCTAssertEqual(Format.stepsLine(nil), "Passos sem dados")
        XCTAssertEqual(Format.signedDecimal(1.24), "+1,2")
        XCTAssertEqual(Format.signedDecimal(-0.8), "-0,8")
        XCTAssertEqual(Format.signedDecimal(0.01), "0", "Arredondado a zero, sem sinal")
    }

    // MARK: - Suporte

    private func makeModel(
        reader: any HealthDataReading,
        defaults: UserDefaults,
        sessions: [SessionSummary] = [],
        targets: HealthTargets = HealthTargets(),
        now overrideNow: Date? = nil,
        logStore: any CoachLogStoring = FakeCoachLogStore()
    ) -> HealthViewModel {
        let fixedNow = overrideNow ?? now
        return HealthViewModel(
            reader: reader,
            sessionsProvider: { sessions },
            targets: targets,
            now: { fixedNow },
            calendar: calendar,
            defaults: defaults,
            logStore: logStore
        )
    }

    /// Entrada de exemplo do contrato, opcionalmente com outra fisiologia.
    private func sampleInput(physiology: UserPhysiology? = nil) -> HealthInput {
        let base = FakeHealthDataReader.sampleInput(now: now, calendar: calendar)
        guard let physiology else { return base }
        return replacingPhysiology(of: base, with: physiology)
    }

    private func replacingPhysiology(of input: HealthInput, with physiology: UserPhysiology) -> HealthInput {
        HealthInput(
            physiology: physiology,
            aerobicWorkouts: input.aerobicWorkouts,
            recovery: input.recovery,
            steps: input.steps,
            vo2Max: input.vo2Max,
            recentSessions: input.recentSessions
        )
    }

    /// Suite única por teste, limpa antes de usar; o `defer` do chamador apaga ao terminar.
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "HealthViewModelTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}

// MARK: - Doubles

private enum HealthTestError: Error {
    case boom
}

/// Relógio ajustável pelo teste (só no MainActor, como o ViewModel que o lê).
private final class HealthTestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

/// Leitor espião: devolve sempre o mesmo `HealthInput` (ignora as sessões recebidas, que ficam
/// registradas) e lança os erros configurados. O estado mutável vive num `actor` interno, como no
/// `FakeHealthKitService`, para a classe ser `Sendable` sem `@unchecked`.
private final class HealthSpyReader: HealthDataReading {
    struct ReadCall: Sendable {
        let now: Date
        let calendar: Calendar
        let sessions: [SessionSummary]
    }

    private actor State {
        let input: HealthInput
        var readError: HealthTestError?
        var authorizationError: HealthTestError?
        var readCalls: [ReadCall] = []
        var authorizationCalls = 0

        init(input: HealthInput) {
            self.input = input
        }

        func recordAuthorization() -> HealthTestError? {
            authorizationCalls += 1
            return authorizationError
        }

        func recordRead(_ call: ReadCall) -> HealthTestError? {
            readCalls.append(call)
            return readError
        }

        func setReadError(_ error: HealthTestError?) {
            readError = error
        }

        func setAuthorizationError(_ error: HealthTestError?) {
            authorizationError = error
        }
    }

    let isAvailable: Bool
    private let state: State

    init(input: HealthInput, isAvailable: Bool = true) {
        self.isAvailable = isAvailable
        self.state = State(input: input)
    }

    var readCalls: [ReadCall] {
        get async { await state.readCalls }
    }

    var authorizationCalls: Int {
        get async { await state.authorizationCalls }
    }

    func setReadError(_ error: HealthTestError?) async {
        await state.setReadError(error)
    }

    func setAuthorizationError(_ error: HealthTestError?) async {
        await state.setAuthorizationError(error)
    }

    func requestReadAuthorization() async throws {
        if let error = await state.recordAuthorization() {
            throw error
        }
    }

    func healthInput(now: Date, calendar: Calendar, recentSessions: [SessionSummary]) async throws -> HealthInput {
        if let error = await state.recordRead(ReadCall(now: now, calendar: calendar, sessions: recentSessions)) {
            throw error
        }
        // `let` Sendable de um actor do mesmo módulo: leitura síncrona, sem `await`.
        return state.input
    }
}
