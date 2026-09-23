import Foundation

/// `NotificationScheduling` em memória para previews e testes: registra cada chamada e
/// mantém a lista de pendentes com a mesma semântica do `UNUserNotificationCenter`
/// (mesmo `identifier` substitui; `cancel` remove).
///
/// Mesmo desenho do `FakeHealthKitService`: estado num `actor` interno e classe `Sendable`
/// não isolada, para não amarrar o `RestTimer` nem os testes dele ao `@MainActor`.
final class FakeNotificationScheduler: NotificationScheduling {
    /// Uma chamada a `scheduleRestTimerEnd`.
    struct ScheduledRequest: Sendable, Hashable {
        let fireDate: Date
        let identifier: String
        let body: String
    }

    private let state: State

    /// - Parameter authorizationToGrant: resposta de `requestAuthorization()`.
    init(authorizationToGrant: Bool = true) {
        self.state = State(authorizationToGrant: authorizationToGrant)
    }

    // MARK: Registros e configuração (testes e previews)

    var authorizationRequestCount: Int {
        get async { await state.authorizationRequestCount }
    }

    /// Toda chamada a `scheduleRestTimerEnd`, na ordem, inclusive as já canceladas ou substituídas.
    var scheduledRequests: [ScheduledRequest] {
        get async { await state.scheduledRequests }
    }

    /// Todo `identifier` passado a `cancel`, na ordem, mesmo sem pendente correspondente.
    var cancelledIdentifiers: [String] {
        get async { await state.cancelledIdentifiers }
    }

    /// O que o centro de notificações teria pendente agora.
    var pendingRequests: [ScheduledRequest] {
        get async { await state.pendingRequests }
    }

    func setAuthorizationToGrant(_ grant: Bool) async {
        await state.setAuthorizationToGrant(grant)
    }

    // MARK: NotificationScheduling

    func requestAuthorization() async -> Bool {
        await state.requestAuthorization()
    }

    func scheduleRestTimerEnd(at fireDate: Date, identifier: String, body: String) async {
        await state.schedule(ScheduledRequest(fireDate: fireDate, identifier: identifier, body: body))
    }

    func cancel(identifier: String) async {
        await state.cancel(identifier: identifier)
    }

    // MARK: Estado protegido

    private actor State {
        private(set) var authorizationToGrant: Bool
        private(set) var authorizationRequestCount = 0
        private(set) var scheduledRequests: [ScheduledRequest] = []
        private(set) var cancelledIdentifiers: [String] = []
        private(set) var pendingRequests: [ScheduledRequest] = []

        init(authorizationToGrant: Bool) {
            self.authorizationToGrant = authorizationToGrant
        }

        func setAuthorizationToGrant(_ grant: Bool) {
            authorizationToGrant = grant
        }

        func requestAuthorization() -> Bool {
            authorizationRequestCount += 1
            return authorizationToGrant
        }

        /// Agenda mesmo sem permissão: `UNUserNotificationCenter.add` também aceita e só
        /// não entrega. Decidir se pede permissão é papel do `RestTimer`.
        func schedule(_ request: ScheduledRequest) {
            scheduledRequests.append(request)
            pendingRequests.removeAll { $0.identifier == request.identifier }
            pendingRequests.append(request)
        }

        func cancel(identifier: String) {
            cancelledIdentifiers.append(identifier)
            pendingRequests.removeAll { $0.identifier == identifier }
        }
    }
}
