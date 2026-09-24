import Foundation
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// SPEC §7.11 C4: `ProvisioningExpiryReader` acha e lê o perfil embutido; o parse é do core.
/// Também cobre os lembretes no `NotificationScheduling` (padrão na extensão e o fake).
@MainActor
final class CoachExpiryReaderTests: XCTestCase {
    /// 30/09/2026 18:40 UTC, minuto cheio (o plist XML guarda segundos inteiros).
    private let expiry = Date(timeIntervalSince1970: 1_790_793_600)

    // MARK: - ProvisioningExpiryReader

    func testReader_readsExpirationDateFromTheProfileBytes() throws {
        let data = try CoachServiceTests.profileData(expiry: expiry)
        let reader = ProvisioningExpiryReader(readData: { data })

        XCTAssertEqual(reader.expirationDate(), expiry)
    }

    func testReader_withoutFile_returnsNil() {
        XCTAssertNil(ProvisioningExpiryReader(readData: { nil }).expirationDate())
        XCTAssertNil(ProvisioningExpiryReader.unavailable.expirationDate())
    }

    func testReader_withBytesThatAreNotAProfile_returnsNil() {
        let reader = ProvisioningExpiryReader(readData: { Data("sem plist aqui".utf8) })

        XCTAssertNil(reader.expirationDate())
    }

    func testReader_onTheSimulatorBundle_returnsNil() {
        // Build de simulador sem assinatura: não há embedded.mobileprovision no app.
        XCTAssertNil(ProvisioningExpiryReader(bundle: .main).expirationDate())
    }

    // MARK: - NotificationScheduling.scheduleReminder

    func testDefaultReminder_forwardsToTheRestTimerSchedule() async {
        let inner = FakeNotificationScheduler()
        let scheduler: any NotificationScheduling = CoachRestOnlyScheduler(inner: inner)
        let fireDate = expiry.addingTimeInterval(-86_400)

        await scheduler.scheduleReminder(at: fireDate, identifier: "coach.expiryReminder", title: "Título", body: "Corpo")

        let scheduled = await inner.scheduledRequests
        XCTAssertEqual(
            scheduled,
            [FakeNotificationScheduler.ScheduledRequest(fireDate: fireDate, identifier: "coach.expiryReminder", body: "Corpo")],
            "Contrato: o padrão encaminha para scheduleRestTimerEnd, sem o título"
        )
    }

    func testFakeReminder_keepsTheTitleAndReplacesTheSameIdentifier() async {
        let scheduler = FakeNotificationScheduler()
        let first = expiry.addingTimeInterval(-86_400)
        let second = expiry.addingTimeInterval(-43_200)

        await scheduler.scheduleReminder(at: first, identifier: "coach.expiryReminder", title: "A", body: "1")
        await scheduler.scheduleReminder(at: second, identifier: "coach.expiryReminder", title: "B", body: "2")

        let pending = await scheduler.pendingRequests
        XCTAssertEqual(
            pending,
            [FakeNotificationScheduler.ScheduledRequest(fireDate: second, identifier: "coach.expiryReminder", body: "2", title: "B")]
        )
        let scheduled = await scheduler.scheduledRequests
        XCTAssertEqual(scheduled.count, 2)
    }
}

/// Agendador que só conhece o fim de descanso: prova o padrão de `scheduleReminder`.
private final class CoachRestOnlyScheduler: NotificationScheduling {
    private let inner: FakeNotificationScheduler

    init(inner: FakeNotificationScheduler) {
        self.inner = inner
    }

    func requestAuthorization() async -> Bool {
        await inner.requestAuthorization()
    }

    func scheduleRestTimerEnd(at fireDate: Date, identifier: String, body: String) async {
        await inner.scheduleRestTimerEnd(at: fireDate, identifier: identifier, body: body)
    }

    func cancel(identifier: String) async {
        await inner.cancel(identifier: identifier)
    }
}
