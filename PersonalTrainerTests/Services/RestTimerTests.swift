import Foundation
import XCTest
@testable import PersonalTrainer

/// T1.7: `RestTimer` com relógio injetado e `FakeNotificationScheduler`. Tudo em `@MainActor`
/// porque o timer é `@MainActor`; os registros do fake são `async`, então cada teste que os lê
/// aguarda `timer.notificationTask` (a fila encadeada) em vez de dormir (AGENTS §7).
@MainActor
final class RestTimerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func expectedRequest(fireDate: Date) -> FakeNotificationScheduler.ScheduledRequest {
        FakeNotificationScheduler.ScheduledRequest(
            fireDate: fireDate,
            identifier: RestTimer.notificationIdentifier,
            body: RestTimer.notificationBody
        )
    }

    /// Aguarda a fila de notificações do timer esvaziar (todas as `Task`s encadeadas).
    private func settle(_ timer: RestTimer) async {
        if let task = timer.notificationTask {
            await task.value
        }
    }

    // MARK: - Estado inicial

    func testIdleTimer_isNotRunningAndHasZeroRemaining() {
        let timer = RestTimer(notifications: FakeNotificationScheduler())

        XCTAssertFalse(timer.isRunning)
        XCTAssertNil(timer.endDate)
        XCTAssertEqual(timer.totalSeconds, 0)
        XCTAssertEqual(timer.finishedCount, 0)
        XCTAssertEqual(timer.remainingSeconds(at: start), 0)
    }

    // MARK: - start

    func testStart_setsEndDateAndSchedulesNotificationAtNowPlusSeconds() async {
        let scheduler = FakeNotificationScheduler()
        let timer = RestTimer(notifications: scheduler)
        let fireDate = start.addingTimeInterval(120)

        timer.start(seconds: 120, now: start)

        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.endDate, fireDate)
        XCTAssertEqual(timer.totalSeconds, 120)
        XCTAssertEqual(timer.finishedCount, 0)

        await settle(timer)
        let scheduled = await scheduler.scheduledRequests
        XCTAssertEqual(scheduled, [expectedRequest(fireDate: fireDate)])
        XCTAssertEqual(scheduled.first?.identifier, "rest-timer")
        XCTAssertEqual(scheduled.first?.body, "Descanso terminou. Próxima série.")
        let pending = await scheduler.pendingRequests
        XCTAssertEqual(pending, [expectedRequest(fireDate: fireDate)])
    }

    func testStart_requestsAuthorizationOnlyOnFirstStart() async {
        let scheduler = FakeNotificationScheduler()
        let timer = RestTimer(notifications: scheduler)

        timer.start(seconds: 120, now: start)
        await settle(timer)
        let afterFirst = await scheduler.authorizationRequestCount
        XCTAssertEqual(afterFirst, 1, "Permissão pedida no primeiro start, nunca no launch (AGENTS §7)")

        timer.skip()
        timer.start(seconds: 90, now: start.addingTimeInterval(300))
        await settle(timer)
        let afterSecond = await scheduler.authorizationRequestCount
        XCTAssertEqual(afterSecond, 1, "Uma única solicitação por processo")
    }

    func testStart_schedulesEvenWhenAuthorizationIsDenied() async {
        let scheduler = FakeNotificationScheduler(authorizationToGrant: false)
        let timer = RestTimer(notifications: scheduler)

        timer.start(seconds: 60, now: start)
        await settle(timer)

        XCTAssertTrue(timer.isRunning, "Sem permissão o timer em primeiro plano continua funcionando")
        let pending = await scheduler.pendingRequests
        XCTAssertEqual(pending, [expectedRequest(fireDate: start.addingTimeInterval(60))])
    }

    func testStart_whileRunning_replacesEndDateAndPendingNotification() async {
        let scheduler = FakeNotificationScheduler()
        let timer = RestTimer(notifications: scheduler)

        timer.start(seconds: 120, now: start)
        let secondStart = start.addingTimeInterval(30)
        timer.start(seconds: 60, now: secondStart)

        // Novo fim = start + 90, diferente do primeiro (start + 120): prova a substituição.
        XCTAssertEqual(timer.endDate, secondStart.addingTimeInterval(60))
        XCTAssertEqual(timer.totalSeconds, 60)
        XCTAssertEqual(timer.remainingSeconds(at: secondStart), 60)

        await settle(timer)
        let pending = await scheduler.pendingRequests
        XCTAssertEqual(pending, [expectedRequest(fireDate: secondStart.addingTimeInterval(60))])
        let scheduled = await scheduler.scheduledRequests
        XCTAssertEqual(scheduled.count, 2, "O log do fake guarda as duas chamadas; só a última fica pendente")
    }

    func testStart_negativeSecondsCountAsZero() {
        let timer = RestTimer(notifications: FakeNotificationScheduler())

        timer.start(seconds: -10, now: start)

        XCTAssertEqual(timer.endDate, start)
        XCTAssertEqual(timer.totalSeconds, 0)
        XCTAssertEqual(timer.remainingSeconds(at: start), 0)
    }

    // MARK: - remainingSeconds

    func testRemainingSeconds_decreasesWithInjectedNow() {
        let timer = RestTimer(notifications: FakeNotificationScheduler())
        timer.start(seconds: 120, now: start)

        XCTAssertEqual(timer.remainingSeconds(at: start), 120)
        XCTAssertEqual(timer.remainingSeconds(at: start.addingTimeInterval(60)), 60)
        XCTAssertEqual(timer.remainingSeconds(at: start.addingTimeInterval(120)), 0)
        XCTAssertEqual(timer.remainingSeconds(at: start.addingTimeInterval(200)), 0, "Nunca negativo")
    }

    func testRemainingSeconds_roundsFractionsUp() {
        let timer = RestTimer(notifications: FakeNotificationScheduler())
        timer.start(seconds: 120, now: start)

        XCTAssertEqual(timer.remainingSeconds(at: start.addingTimeInterval(0.2)), 120)
        XCTAssertEqual(timer.remainingSeconds(at: start.addingTimeInterval(59.5)), 61)
        XCTAssertEqual(timer.remainingSeconds(at: start.addingTimeInterval(119.9)), 1)
    }

    // MARK: - add

    func testAdd_whileRunning_extendsEndDateAndReschedules() async {
        let scheduler = FakeNotificationScheduler()
        let timer = RestTimer(notifications: scheduler)
        timer.start(seconds: 120, now: start)

        let later = start.addingTimeInterval(10)
        timer.add(seconds: 30, now: later)

        XCTAssertEqual(timer.endDate, start.addingTimeInterval(150))
        XCTAssertEqual(timer.totalSeconds, 150)
        XCTAssertEqual(timer.remainingSeconds(at: later), 140)

        await settle(timer)
        let cancelled = await scheduler.cancelledIdentifiers
        XCTAssertEqual(cancelled, ["rest-timer"], "add reagenda: cancela e agenda de novo")
        let pending = await scheduler.pendingRequests
        XCTAssertEqual(pending, [expectedRequest(fireDate: start.addingTimeInterval(150))])
        let scheduled = await scheduler.scheduledRequests
        XCTAssertEqual(
            scheduled,
            [
                expectedRequest(fireDate: start.addingTimeInterval(120)),
                expectedRequest(fireDate: start.addingTimeInterval(150)),
            ]
        )
    }

    func testAdd_whenIdle_startsTimer() async {
        let scheduler = FakeNotificationScheduler()
        let timer = RestTimer(notifications: scheduler)

        timer.add(seconds: 30, now: start)

        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.endDate, start.addingTimeInterval(30))
        XCTAssertEqual(timer.totalSeconds, 30)

        await settle(timer)
        let pending = await scheduler.pendingRequests
        XCTAssertEqual(pending, [expectedRequest(fireDate: start.addingTimeInterval(30))])
        let cancelled = await scheduler.cancelledIdentifiers
        XCTAssertTrue(cancelled.isEmpty, "Parado, add vira start: nada a cancelar")
    }

    // MARK: - skip

    func testSkip_stopsTimerAndCancelsNotificationWithoutCountingAsFinished() async {
        let scheduler = FakeNotificationScheduler()
        let timer = RestTimer(notifications: scheduler)
        timer.start(seconds: 120, now: start)

        timer.skip()

        XCTAssertFalse(timer.isRunning)
        XCTAssertNil(timer.endDate)
        XCTAssertEqual(timer.finishedCount, 0, "Pular não é terminar: sem haptic")
        XCTAssertEqual(timer.remainingSeconds(at: start), 0)

        await settle(timer)
        let cancelled = await scheduler.cancelledIdentifiers
        XCTAssertEqual(cancelled, ["rest-timer"])
        let pending = await scheduler.pendingRequests
        XCTAssertTrue(pending.isEmpty)
    }

    func testSkip_immediatelyAfterStart_runsAfterScheduleSoNothingStaysPending() async {
        let scheduler = FakeNotificationScheduler()
        let timer = RestTimer(notifications: scheduler)

        timer.start(seconds: 120, now: start)
        timer.skip()
        await settle(timer)

        let scheduled = await scheduler.scheduledRequests
        XCTAssertEqual(scheduled.count, 1, "O agendamento aconteceu…")
        let pending = await scheduler.pendingRequests
        XCTAssertTrue(pending.isEmpty, "…e o cancelamento veio depois dele, na ordem das chamadas")
    }

    // MARK: - tick

    func testTick_beforeEnd_keepsRunning() {
        let timer = RestTimer(notifications: FakeNotificationScheduler())
        timer.start(seconds: 120, now: start)

        timer.tick(now: start.addingTimeInterval(119))

        XCTAssertTrue(timer.isRunning)
        XCTAssertEqual(timer.finishedCount, 0)
    }

    func testTick_afterEnd_stopsAndIncrementsFinishedCountOnce() {
        let timer = RestTimer(notifications: FakeNotificationScheduler())
        timer.start(seconds: 120, now: start)

        timer.tick(now: start.addingTimeInterval(120))
        XCTAssertFalse(timer.isRunning)
        XCTAssertNil(timer.endDate)
        XCTAssertEqual(timer.finishedCount, 1)

        timer.tick(now: start.addingTimeInterval(121))
        timer.tick(now: start.addingTimeInterval(500))
        XCTAssertEqual(timer.finishedCount, 1, "Ticks depois de parado não contam de novo")
    }

    func testTick_whenIdle_doesNothing() {
        let timer = RestTimer(notifications: FakeNotificationScheduler())

        timer.tick(now: start)

        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.finishedCount, 0)
    }

    func testTick_afterLongBackground_finishesOnFirstTick() {
        let timer = RestTimer(notifications: FakeNotificationScheduler())
        timer.start(seconds: 120, now: start)

        // App ficou 2 min em segundo plano sem ticks (aceite T1.7).
        timer.tick(now: start.addingTimeInterval(240))

        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.finishedCount, 1)
    }

    func testFinishedCount_accumulatesAcrossRests() {
        let timer = RestTimer(notifications: FakeNotificationScheduler())

        timer.start(seconds: 60, now: start)
        timer.tick(now: start.addingTimeInterval(60))
        timer.start(seconds: 60, now: start.addingTimeInterval(100))
        timer.tick(now: start.addingTimeInterval(160))

        XCTAssertEqual(timer.finishedCount, 2)
    }

    // MARK: - RestTimerView (formatação estática)

    func testTimeText_formatsMinutesAndZeroPaddedSeconds() {
        XCTAssertEqual(RestTimerView.timeText(seconds: 92), "1:32")
        XCTAssertEqual(RestTimerView.timeText(seconds: 5), "0:05")
        XCTAssertEqual(RestTimerView.timeText(seconds: 120), "2:00")
        XCTAssertEqual(RestTimerView.timeText(seconds: 0), "0:00")
        XCTAssertEqual(RestTimerView.timeText(seconds: -3), "0:00")
    }

    func testProgress_isRemainingFractionClampedToUnitInterval() {
        XCTAssertEqual(RestTimerView.progress(remaining: 60, total: 120), 0.5)
        XCTAssertEqual(RestTimerView.progress(remaining: 120, total: 120), 1)
        XCTAssertEqual(RestTimerView.progress(remaining: 0, total: 120), 0)
        XCTAssertEqual(RestTimerView.progress(remaining: 150, total: 120), 1)
        XCTAssertEqual(RestTimerView.progress(remaining: 30, total: 0), 0)
    }
}
