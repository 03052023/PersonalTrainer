import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Gregoriano com fuso fixo -03:00 (sem horário de verão): todo dia tem 24 h, então as contas
/// com `86_400` abaixo são exatas e o resultado não depende do fuso da máquina do CI.
private func fixedCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: -3 * 3_600)!
    return calendar
}

/// Quarta-feira, 23/09/2026, 10:00 em -03:00 (13:00 UTC).
private let fixedNow = Date(timeIntervalSince1970: 1_790_168_400)

private func average(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
}

/// T5.2: `FakeHealthDataReader` (AGENTS R9), usado no simulador e nos previews do painel de saúde.
/// Cobre o `sampleInput` determinístico (o que a tela mostra sem HealthKit), o repasse de
/// `recentSessions` e os erros configuráveis, inclusive `isAvailable == false`.
@MainActor
final class FakeHealthDataReaderTests: XCTestCase {
    private let now = fixedNow
    private let calendar = fixedCalendar()

    private var today: Date {
        calendar.startOfDay(for: now)
    }

    private func day(_ offset: Int) -> Date {
        today.addingTimeInterval(TimeInterval(offset) * 86_400)
    }

    // MARK: - sampleInput

    func testSampleInput_sameNowAndCalendar_returnsSameInput() {
        let first = FakeHealthDataReader.sampleInput(now: now, calendar: calendar)
        let second = FakeHealthDataReader.sampleInput(now: now, calendar: calendar)

        XCTAssertEqual(first, second)
        XCTAssertEqual(
            first.aerobicWorkouts.map(\.id),
            second.aerobicWorkouts.map(\.id),
            "IDs fixos: nada de UUID() aleatório"
        )
        XCTAssertEqual(Set(first.aerobicWorkouts.map(\.id)).count, first.aerobicWorkouts.count, "IDs distintos")
    }

    func testSampleInput_nowOneDayLater_shiftsEverythingOneDay() {
        let base = FakeHealthDataReader.sampleInput(now: now, calendar: calendar)
        let shifted = FakeHealthDataReader.sampleInput(now: now.addingTimeInterval(86_400), calendar: calendar)

        XCTAssertEqual(shifted.aerobicWorkouts.map(\.start), base.aerobicWorkouts.map { $0.start.addingTimeInterval(86_400) })
        XCTAssertEqual(shifted.recovery.map(\.day), base.recovery.map { $0.day.addingTimeInterval(86_400) })
        XCTAssertEqual(shifted.steps.map(\.day), base.steps.map { $0.day.addingTimeInterval(86_400) })
        XCTAssertEqual(shifted.vo2Max.map(\.date), base.vo2Max.map { $0.date.addingTimeInterval(86_400) })
    }

    func testSampleInput_workouts_lastSevenDaysHaveThreeWalksAndOneRun() {
        let workouts = FakeHealthDataReader.sampleInput(now: now, calendar: calendar).aerobicWorkouts
        let windowStart = day(-28)
        let lastWeekStart = day(-7)
        let startOfToday = today

        XCTAssertEqual(workouts.count, 16, "4 semanas × (3 caminhadas + 1 corrida)")
        XCTAssertEqual(workouts.map(\.start), workouts.map(\.start).sorted(), "Em ordem de início")
        XCTAssertTrue(
            workouts.allSatisfy { $0.start >= windowStart && $0.end <= startOfToday },
            "Dentro dos 28 dias lidos e nenhum treino hoje"
        )

        let lastSeven = workouts.filter { $0.start >= lastWeekStart }
        XCTAssertEqual(lastSeven.count, 4)
        XCTAssertEqual(lastSeven.filter { $0.activity == .walking }.count, 3)
        XCTAssertEqual(lastSeven.filter { $0.activity == .running }.count, 1)

        for workout in workouts {
            let minutes = Int(workout.end.timeIntervalSince(workout.start) / 60)
            XCTAssertEqual(workout.minuteHeartRates.count, minutes, "Uma FC média por minuto do treino")
            XCTAssertTrue(workout.minuteHeartRates.allSatisfy { $0 >= 90 && $0 <= 170 }, "FC plausível")
        }

        let runHeartRates = lastSeven.filter { $0.activity == .running }.flatMap(\.minuteHeartRates)
        XCTAssertTrue(runHeartRates.dropFirst(3).allSatisfy { $0 >= 150 }, "Corrida vigorosa depois do aquecimento")
        let walkHeartRates = lastSeven.filter { $0.activity == .walking }.flatMap { $0.minuteHeartRates.dropFirst(3) }
        XCTAssertTrue(walkHeartRates.allSatisfy { $0 >= 118 && $0 <= 126 }, "Caminhada moderada depois do aquecimento")
    }

    func testSampleInput_vo2Max_risesFrom42To44WithRecentEstimate() throws {
        let calendar = self.calendar
        let samples = FakeHealthDataReader.sampleInput(now: now, calendar: calendar).vo2Max
        let sorted = samples.sorted { $0.date < $1.date }
        let ninetyDaysAgo = day(-90)
        let windowStart = day(-180)
        let referenceNow = now

        let latest = try XCTUnwrap(sorted.last)
        XCTAssertEqual(latest.value, 44.0, accuracy: 0.001)
        XCTAssertLessThan(now.timeIntervalSince(latest.date), 60 * 86_400, "Estimativa recente: sem sugestão A3")

        let ninetyDaySample = try XCTUnwrap(sorted.first { calendar.isDate($0.date, inSameDayAs: ninetyDaysAgo) })
        XCTAssertEqual(ninetyDaySample.value, 42.0, accuracy: 0.001)

        XCTAssertTrue(sorted.allSatisfy { $0.date >= windowStart && $0.date <= referenceNow }, "Dentro dos 180 dias")
        XCTAssertEqual(sorted.map(\.value), sorted.map(\.value).sorted(), "Tendência de alta")
    }

    func testSampleInput_recovery_twoNightsWithoutWatchInLastSevenDays() {
        let recovery = FakeHealthDataReader.sampleInput(now: now, calendar: calendar).recovery
        let expectedDays = (0..<28).reversed().map { day(-$0) }
        let lastWeekStart = day(-6)

        XCTAssertEqual(recovery.count, 28)
        XCTAssertEqual(recovery.map(\.day), expectedDays, "Um registro por dia, de 27 dias atrás até hoje")

        let lastSeven = recovery.filter { $0.day >= lastWeekStart }
        XCTAssertEqual(lastSeven.count, 7)
        XCTAssertEqual(lastSeven.filter { $0.hrvSDNN == nil }.count, 2, "Duas noites sem o relógio")
        XCTAssertEqual(lastSeven.filter { $0.sleepHours == nil }.count, 2, "Duas noites sem o relógio")
        XCTAssertTrue(lastSeven.allSatisfy { $0.restingHeartRate != nil }, "FC de repouso vem do dia")

        XCTAssertEqual(average(recovery.compactMap(\.hrvSDNN)), 55, accuracy: 0.001)
        XCTAssertEqual(average(recovery.compactMap(\.restingHeartRate)), 58, accuracy: 0.001)
        XCTAssertEqual(average(recovery.compactMap(\.sleepHours)), 6.8, accuracy: 0.05)
        XCTAssertEqual(average(lastSeven.compactMap(\.hrvSDNN)), 55, accuracy: 0.001, "Sem alerta de HRV")
    }

    func testSampleInput_steps_averageEightThousandOnCompleteDays() {
        let steps = FakeHealthDataReader.sampleInput(now: now, calendar: calendar).steps
        let expectedDays = (1...28).reversed().map { day(-$0) }

        XCTAssertEqual(steps.count, 28)
        XCTAssertEqual(steps.map(\.day), expectedDays, "28 dias completos antes de hoje, em ordem")
        XCTAssertEqual(steps.suffix(7).map(\.steps).reduce(0, +), 7 * 8_000, "Média de 8.000 na última semana")
        XCTAssertEqual(steps.map(\.steps).reduce(0, +), 28 * 8_000)
        XCTAssertTrue(steps.allSatisfy { $0.steps >= 7_000 && $0.steps <= 9_500 })
    }

    func testSampleInput_physiology_is38YearOldMaleWithoutOverride() throws {
        let physiology = FakeHealthDataReader.sampleInput(now: now, calendar: calendar).physiology

        let birthDate = try XCTUnwrap(physiology.birthDate)
        XCTAssertEqual(calendar.dateComponents([.year], from: birthDate, to: now).year, 38)
        XCTAssertEqual(physiology.sex, .male)
        XCTAssertNil(physiology.maxHeartRateOverride)
    }

    func testSampleInput_hasNoSessions() {
        let input = FakeHealthDataReader.sampleInput(now: now, calendar: calendar)

        XCTAssertTrue(input.recentSessions.isEmpty, "Sessões vêm da chamada, nunca do exemplo")
    }

    // MARK: - healthInput

    func testHealthInput_withoutConfiguredInput_returnsSampleWithCallerSessions() async throws {
        let sessions = [SessionSummary(programDayID: UUID(), startedAt: day(-1), status: .completed, workingSetCount: 15)]
        let reader = FakeHealthDataReader()

        let input = try await reader.healthInput(now: now, calendar: calendar, recentSessions: sessions)

        let sample = FakeHealthDataReader.sampleInput(now: now, calendar: calendar)
        XCTAssertEqual(input.physiology, sample.physiology)
        XCTAssertEqual(input.aerobicWorkouts, sample.aerobicWorkouts)
        XCTAssertEqual(input.recovery, sample.recovery)
        XCTAssertEqual(input.steps, sample.steps)
        XCTAssertEqual(input.vo2Max, sample.vo2Max)
        XCTAssertEqual(input.recentSessions, sessions)
    }

    func testHealthInput_configuredInput_isReturnedWithCallerSessions() async throws {
        let configured = HealthInput(
            physiology: UserPhysiology(birthDate: nil, sex: .female, maxHeartRateOverride: 185),
            aerobicWorkouts: [
                AerobicWorkoutSample(
                    id: UUID(),
                    activity: .cycling,
                    start: day(-1),
                    end: day(-1).addingTimeInterval(1_800),
                    minuteHeartRates: []
                ),
            ],
            recovery: [DailyRecoverySample(day: day(0), hrvSDNN: 60, restingHeartRate: 55, sleepHours: 7.5)],
            steps: [DailyStepCount(day: day(-1), steps: 9_500)],
            vo2Max: [Vo2MaxSample(date: day(-10), value: 40)],
            recentSessions: [SessionSummary(programDayID: UUID(), startedAt: day(-3), status: .completed)]
        )
        let callerSessions = [SessionSummary(programDayID: UUID(), startedAt: day(-1), status: .completed)]
        let reader = FakeHealthDataReader(input: configured)

        let input = try await reader.healthInput(now: now, calendar: calendar, recentSessions: callerSessions)

        XCTAssertEqual(input.physiology, configured.physiology)
        XCTAssertEqual(input.aerobicWorkouts, configured.aerobicWorkouts)
        XCTAssertEqual(input.recovery, configured.recovery)
        XCTAssertEqual(input.steps, configured.steps)
        XCTAssertEqual(input.vo2Max, configured.vo2Max)
        XCTAssertEqual(input.recentSessions, callerSessions, "Como o Live: sessões sempre da chamada")
    }

    // MARK: - Disponibilidade e erros

    func testUnavailable_bothMethodsThrowUnavailable() async {
        let empty = HealthInput(
            physiology: UserPhysiology(birthDate: nil, sex: nil, maxHeartRateOverride: nil),
            aerobicWorkouts: [],
            recovery: [],
            steps: [],
            vo2Max: [],
            recentSessions: []
        )
        let reader = FakeHealthDataReader(input: empty, isAvailable: false)
        XCTAssertFalse(reader.isAvailable)

        do {
            try await reader.requestReadAuthorization()
            XCTFail("Esperava HealthKitServiceError.unavailable")
        } catch let error as HealthKitServiceError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }

        do {
            _ = try await reader.healthInput(now: now, calendar: calendar, recentSessions: [])
            XCTFail("Esperava HealthKitServiceError.unavailable")
        } catch let error as HealthKitServiceError {
            XCTAssertEqual(error, .unavailable)
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }

    func testAvailableByDefault_authorizationSucceeds() async throws {
        let reader = FakeHealthDataReader()

        XCTAssertTrue(reader.isAvailable)
        try await reader.requestReadAuthorization()
    }

    func testAuthorizationError_isThrownAndReadsStillWork() async throws {
        let reader = FakeHealthDataReader(authorizationError: .notAuthorized)

        do {
            try await reader.requestReadAuthorization()
            XCTFail("Esperava HealthKitServiceError.notAuthorized")
        } catch let error as HealthKitServiceError {
            XCTAssertEqual(error, .notAuthorized)
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }

        // Leitura negada é opaca no HealthKit (ARCHITECTURE §15): a leitura não falha por isso.
        let input = try await reader.healthInput(now: now, calendar: calendar, recentSessions: [])
        XCTAssertFalse(input.aerobicWorkouts.isEmpty)
    }

    func testReadError_isThrownFromHealthInput() async {
        let reader = FakeHealthDataReader(readError: .queryFailed(underlying: "banco bloqueado"))

        do {
            _ = try await reader.healthInput(now: now, calendar: calendar, recentSessions: [])
            XCTFail("Esperava HealthKitServiceError.queryFailed")
        } catch let error as HealthKitServiceError {
            XCTAssertEqual(error, .queryFailed(underlying: "banco bloqueado"))
        } catch {
            XCTFail("Erro inesperado: \(error)")
        }
    }
}

/// Agregação pura do `LiveHealthDataReader` (sono de A4, junção da recuperação e passos). Só usa
/// tipos do Foundation, então roda no simulador; as consultas ao HealthKit ficam para o aparelho.
@MainActor
final class LiveHealthDataReaderAggregationTests: XCTestCase {
    private let calendar = fixedCalendar()

    private var today: Date {
        calendar.startOfDay(for: fixedNow)
    }

    private func day(_ offset: Int) -> Date {
        today.addingTimeInterval(TimeInterval(offset) * 86_400)
    }

    /// Instante `hour:minute` do dia `dayOffset` (0 = hoje).
    private func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        day(dayOffset).addingTimeInterval(TimeInterval(hour * 3_600 + minute * 60))
    }

    private func segment(_ start: Date, _ end: Date, watch: Bool) -> LiveHealthDataReader.SleepSegment {
        LiveHealthDataReader.SleepSegment(start: start, end: end, isFromWatch: watch)
    }

    // MARK: - Sono

    func testNightDay_segmentsEndingFrom18hBelongToNextDay() {
        XCTAssertEqual(LiveHealthDataReader.nightDay(endingAt: at(0, 7), calendar: calendar), day(0))
        XCTAssertEqual(LiveHealthDataReader.nightDay(endingAt: at(-1, 23, 40), calendar: calendar), day(0))
        XCTAssertEqual(LiveHealthDataReader.nightDay(endingAt: at(-1, 17, 59), calendar: calendar), day(-1))
        XCTAssertEqual(LiveHealthDataReader.nightDay(endingAt: at(-1, 18), calendar: calendar), day(0))
    }

    func testSleep_wholeNightCountsOnWakeDay() {
        let segments = [
            segment(at(-1, 22, 30), at(-1, 23, 40), watch: true),
            segment(at(-1, 23, 50), at(0, 6, 30), watch: true),
        ]

        let byDay = LiveHealthDataReader.sleepHoursByDay(segments, calendar: calendar)

        XCTAssertEqual(Set(byDay.keys), [day(0)])
        XCTAssertEqual(byDay[day(0)] ?? 0, 7 + 50.0 / 60, accuracy: 0.001, "1h10 + 6h40, sem os 10 min acordado")
    }

    func testSleep_watchSegmentsWinOverOtherSourcesOnSameNight() {
        let segments = [
            segment(at(-1, 22), at(0, 7, 30), watch: false),
            segment(at(-1, 23), at(0, 6), watch: true),
        ]

        let byDay = LiveHealthDataReader.sleepHoursByDay(segments, calendar: calendar)

        XCTAssertEqual(byDay[day(0)] ?? 0, 7, accuracy: 0.001)
    }

    func testSleep_withoutWatch_overlappingSourcesAreUnioned() {
        let segments = [
            segment(at(-1, 23), at(0, 5), watch: false),
            segment(at(0, 4), at(0, 7), watch: false),
        ]

        let byDay = LiveHealthDataReader.sleepHoursByDay(segments, calendar: calendar)

        XCTAssertEqual(byDay[day(0)] ?? 0, 8, accuracy: 0.001, "23h–7h, sem contar 4h–5h duas vezes")
    }

    func testSleep_eachNightIsDecidedSeparately() {
        let segments = [
            segment(at(-2, 23), at(-1, 6), watch: true),
            segment(at(-2, 22), at(-1, 7), watch: false),
            segment(at(-1, 23), at(0, 5), watch: false),
            segment(at(0, 14), at(0, 15, 30), watch: false),
        ]

        let byDay = LiveHealthDataReader.sleepHoursByDay(segments, calendar: calendar)

        XCTAssertEqual(Set(byDay.keys), [day(-1), day(0)])
        XCTAssertEqual(byDay[day(-1)] ?? 0, 7, accuracy: 0.001, "Noite com Watch: só o Watch")
        XCTAssertEqual(byDay[day(0)] ?? 0, 7.5, accuracy: 0.001, "Noite sem Watch (6 h) + cochilo (1h30)")
    }

    func testUnionDuration_mergesOverlappingAndTouchingSegments() {
        let segments = [
            segment(at(0, 1), at(0, 2), watch: true),
            segment(at(0, 1, 30), at(0, 2, 30), watch: true),
            segment(at(0, 2, 30), at(0, 3), watch: true),
            segment(at(0, 4), at(0, 5), watch: true),
        ]

        XCTAssertEqual(LiveHealthDataReader.unionDuration(of: segments), 3 * 3_600, accuracy: 0.001)
        XCTAssertEqual(LiveHealthDataReader.unionDuration(of: []), 0)
    }

    // MARK: - Recuperação e passos

    func testMergeRecovery_unionOfDaysSortedWithMissingValuesAsNil() {
        let merged = LiveHealthDataReader.mergeRecovery(
            hrv: [day(0): 60, day(-2): 50],
            restingHeartRate: [day(0): 56, day(-1): 57],
            sleepHours: [day(-2): 7]
        )

        XCTAssertEqual(merged, [
            DailyRecoverySample(day: day(-2), hrvSDNN: 50, restingHeartRate: nil, sleepHours: 7),
            DailyRecoverySample(day: day(-1), hrvSDNN: nil, restingHeartRate: 57, sleepHours: nil),
            DailyRecoverySample(day: day(0), hrvSDNN: 60, restingHeartRate: 56, sleepHours: nil),
        ])
    }

    func testMergeRecovery_noDataReturnsEmpty() {
        XCTAssertTrue(LiveHealthDataReader.mergeRecovery(hrv: [:], restingHeartRate: [:], sleepHours: [:]).isEmpty)
    }

    func testDailySteps_roundsAndSortsByDay() {
        let steps = LiveHealthDataReader.dailySteps(from: [day(0): 1_234.6, day(-1): 8_000.4])

        XCTAssertEqual(steps, [
            DailyStepCount(day: day(-1), steps: 8_000),
            DailyStepCount(day: day(0), steps: 1_235),
        ])
    }
}
