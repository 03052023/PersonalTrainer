import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Integração onda 3 (contrato V2-FINAL §2.6): o `RecoveryContext` que o `RootView` passa ao
/// diálogo sai do relatório de saúde (SPEC §7.10 A4 → §7.8 R6). As marcas vêm dos alertas de A4;
/// `hasData` exige as médias de HRV ou de FC de repouso (as duas tendências que modulam R6).
final class RecoveryContextDerivationTests: XCTestCase {
    /// Gregoriano, UTC−3 fixo, semana começando na segunda (SPEC P11: nada depende do runner).
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -3 * 3_600) ?? .gmt
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Quarta-feira, 23/09/2026, 12:00 em UTC−3.
    private let now = Date(timeIntervalSince1970: 1_790_175_600)

    // MARK: - Sem relatório

    func testR6_withoutReport_isUnknown() {
        let context = RecoveryContext.derived(from: nil as HealthReport?)

        XCTAssertEqual(context, .unknown)
        XCTAssertFalse(context.hasData, "Saúde não conectado: R6 deixa as sugestões como estão")
    }

    // MARK: - A partir do resumo de recuperação

    func testR6_alertsBecomeFlags_andHRVTrendMeansData() {
        let summary = makeSummary(
            hrv7: 45, hrv28: 56,
            alerts: [.hrvDrop, .lowSleep]
        )

        let context = RecoveryContext.derived(from: summary)

        XCTAssertTrue(context.hrvDropped)
        XCTAssertFalse(context.restingHeartRateRose)
        XCTAssertTrue(context.sleepLow)
        XCTAssertTrue(context.hasData)
    }

    func testR6_restingHeartRateTrendAloneMeansData() {
        let summary = makeSummary(
            restingHR7: 62, restingHR28: 56,
            alerts: [.restingHeartRateRise]
        )

        let context = RecoveryContext.derived(from: summary)

        XCTAssertFalse(context.hrvDropped)
        XCTAssertTrue(context.restingHeartRateRose)
        XCTAssertFalse(context.sleepLow)
        XCTAssertTrue(context.hasData)
    }

    func testR6_sleepOnly_isNoData() {
        // Só o sono não diz se a HRV está estável: marcar dados enfraqueceria a semana leve sem base.
        let summary = makeSummary(sleep7: 7.5, sleep28: 7.4, alerts: [])

        let context = RecoveryContext.derived(from: summary)

        XCTAssertFalse(context.hasData)
    }

    func testR6_onlyTheOldWindow_isNoData() {
        // Médias de 28 dias sem nenhuma noite recente: não há tendência de 7 contra 28.
        let summary = makeSummary(hrv28: 58, restingHR28: 55, alerts: [])

        XCTAssertFalse(RecoveryContext.derived(from: summary).hasData)
    }

    func testR6_stableTrends_haveDataWithoutFlags() {
        let summary = makeSummary(hrv7: 60, hrv28: 58, restingHR7: 55, restingHR28: 55, sleep7: 7.6, sleep28: 7.5, alerts: [])

        let context = RecoveryContext.derived(from: summary)

        XCTAssertEqual(context, RecoveryContext(hrvDropped: false, restingHeartRateRose: false, sleepLow: false, hasData: true))
    }

    // MARK: - A partir do relatório completo

    func testR6_fromHealthReport_followsTheA4Alerts() {
        // 21 dias antigos estáveis e uma semana com HRV em queda, FC de repouso em alta e sono curto.
        let today = calendar.startOfDay(for: now)
        var samples: [DailyRecoverySample] = []
        for daysAgo in 0..<28 {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            if daysAgo < 7 {
                samples.append(DailyRecoverySample(day: day, hrvSDNN: 45, restingHeartRate: 62, sleepHours: 6))
            } else {
                samples.append(DailyRecoverySample(day: day, hrvSDNN: 60, restingHeartRate: 55, sleepHours: 7.5))
            }
        }
        let report = HealthCalculator.report(
            input: HealthInput(recovery: samples),
            targets: HealthTargets(),
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(report.recovery.alerts, [.hrvDrop, .restingHeartRateRise, .lowSleep], "Pré-condição do cenário")

        let context = RecoveryContext.derived(from: report)

        XCTAssertEqual(context, RecoveryContext(hrvDropped: true, restingHeartRateRose: true, sleepLow: true, hasData: true))
        XCTAssertEqual(context, RecoveryContext.derived(from: report.recovery))
    }

    func testR6_fromHealthReportWithoutRecovery_isNoData() {
        let report = HealthCalculator.report(
            input: HealthInput(),
            targets: HealthTargets(),
            now: now,
            calendar: calendar
        )

        let context = RecoveryContext.derived(from: report)

        XCTAssertFalse(context.hasData)
        XCTAssertFalse(context.hrvDropped)
        XCTAssertFalse(context.restingHeartRateRose)
    }

    // MARK: - Fixtures

    private func makeSummary(
        hrv7: Double? = nil,
        hrv28: Double? = nil,
        restingHR7: Double? = nil,
        restingHR28: Double? = nil,
        sleep7: Double? = nil,
        sleep28: Double? = nil,
        alerts: [RecoveryAlert]
    ) -> RecoverySummary {
        RecoverySummary(
            hrv7: hrv7,
            hrv28: hrv28,
            restingHR7: restingHR7,
            restingHR28: restingHR28,
            sleep7: sleep7,
            sleep28: sleep28,
            nightsWithData7: 7,
            alerts: alerts
        )
    }
}
