import Foundation
import Observation

/// Timer de descanso entre séries (RF-05, ARCHITECTURE §10). Um por app, guardado no
/// `AppEnvironment` e lido por `ActiveSessionViewModel` e `RestTimerView`.
///
/// Baseado em `endDate`, não em contagem de ticks: o tempo restante é sempre
/// `endDate − now`, então o app pode ir para segundo plano por minutos e, ao voltar, o
/// primeiro `tick(now:)` já mostra o valor certo ou encerra o descanso. O relógio nunca é
/// lido aqui dentro (sem `Date()`): `now` chega por parâmetro, de `TimelineView` na view ou
/// do closure `now` injetado nos ViewModels (SPEC P11), o que torna a classe determinística
/// em teste.
///
/// Notificação local: `start` e `add` agendam (e `add`/`skip` cancelam) via
/// `NotificationScheduling`, sempre com o mesmo `identifier`, para que reagendar substitua a
/// pendente no `UNUserNotificationCenter`. A permissão é pedida uma única vez, no primeiro
/// `start` do processo (AGENTS §7: nunca no launch). O agendamento continua mesmo se a
/// permissão for negada: o centro aceita e só não entrega, e o timer em primeiro plano segue
/// funcionando (AGENTS §4). As chamadas ao serviço são `async` e rodam em `Task`s
/// encadeadas na ordem em que foram pedidas, para que um `skip` logo após um `start` nunca
/// cancele antes de agendar.
///
/// Haptic: ao terminar, `tick` incrementa `finishedCount`; a view usa esse valor como
/// gatilho de `.sensoryFeedback(.success, trigger:)`, sem UIKit.
@Observable
@MainActor
final class RestTimer {
    /// `identifier` único da notificação de fim de descanso (só existe um descanso por vez).
    static let notificationIdentifier = "rest-timer"
    /// Corpo da notificação, em pt-BR fixo (AGENTS §4). O título fica no `LiveNotificationScheduler`.
    static let notificationBody = "Descanso terminou. Próxima série."

    /// Instante em que o descanso termina; `nil` = parado.
    private(set) var endDate: Date?
    /// Duração total do descanso corrente (inclui os `add`), para o anel de progresso da view.
    private(set) var totalSeconds: Int = 0
    /// Quantos descansos terminaram sozinhos (não pulados) neste processo. Só serve de gatilho
    /// para o haptic da view; nunca é persistido.
    private(set) var finishedCount: Int = 0

    /// Última operação de notificação enfileirada. Interna (não `private`) para os testes
    /// aguardarem essa `Task` terminar antes de ler os registros do fake.
    @ObservationIgnored private(set) var notificationTask: Task<Void, Never>?

    private let notifications: any NotificationScheduling
    @ObservationIgnored private var hasRequestedAuthorization = false

    init(notifications: any NotificationScheduling) {
        self.notifications = notifications
    }

    var isRunning: Bool {
        endDate != nil
    }

    /// Segundos inteiros restantes em `now`, arredondados para cima (119,2 s exibe "2:00",
    /// não "1:59"), e nunca negativos. Parado ⇒ 0.
    func remainingSeconds(at now: Date) -> Int {
        guard let endDate else { return 0 }
        let remaining = endDate.timeIntervalSince(now)
        guard remaining > 0 else { return 0 }
        return Int(remaining.rounded(.up))
    }

    /// Inicia (ou reinicia, substituindo o descanso corrente) um descanso de `seconds` a partir
    /// de `now` e agenda a notificação para `endDate`. Valores negativos contam como 0.
    func start(seconds: Int, now: Date) {
        let duration = max(0, seconds)
        let newEndDate = now.addingTimeInterval(TimeInterval(duration))
        endDate = newEndDate
        totalSeconds = duration

        let needsAuthorization = !hasRequestedAuthorization
        hasRequestedAuthorization = true
        let identifier = RestTimer.notificationIdentifier
        let body = RestTimer.notificationBody

        enqueueNotificationWork { notifications in
            if needsAuthorization {
                // O resultado não muda o fluxo: agendamos de qualquer forma (ver doc da classe).
                _ = await notifications.requestAuthorization()
            }
            await notifications.scheduleRestTimerEnd(at: newEndDate, identifier: identifier, body: body)
        }
    }

    /// Estende o descanso corrente em `seconds` e reagenda a notificação (cancela + agenda).
    /// Parado, equivale a `start(seconds:now:)`.
    func add(seconds: Int, now: Date) {
        guard let currentEndDate = endDate else {
            start(seconds: seconds, now: now)
            return
        }
        let newEndDate = currentEndDate.addingTimeInterval(TimeInterval(seconds))
        endDate = newEndDate
        totalSeconds += seconds

        let identifier = RestTimer.notificationIdentifier
        let body = RestTimer.notificationBody

        enqueueNotificationWork { notifications in
            await notifications.cancel(identifier: identifier)
            await notifications.scheduleRestTimerEnd(at: newEndDate, identifier: identifier, body: body)
        }
    }

    /// Encerra o descanso sem contar como terminado (sem haptic) e cancela a notificação.
    /// Parado, apenas cancela (idempotente e barato).
    func skip() {
        endDate = nil

        let identifier = RestTimer.notificationIdentifier
        enqueueNotificationWork { notifications in
            await notifications.cancel(identifier: identifier)
        }
    }

    /// Chamado pela view a cada segundo (e ao voltar do segundo plano). Se o descanso já
    /// terminou em `now`, para e incrementa `finishedCount` uma única vez; a notificação já
    /// foi (ou está sendo) entregue pelo sistema, então não há o que cancelar.
    func tick(now: Date) {
        guard let endDate, now >= endDate else { return }
        self.endDate = nil
        finishedCount += 1
    }

    // MARK: - Fila de notificações

    /// Encadeia `operation` depois da operação anterior, preservando a ordem das chamadas ao
    /// serviço mesmo com os saltos de executor dentro dele. A `Task` herda o `MainActor`;
    /// captura só valores `Sendable` (o serviço e a tarefa anterior), nunca `self`.
    private func enqueueNotificationWork(
        _ operation: @escaping @Sendable (any NotificationScheduling) async -> Void
    ) {
        let notifications = self.notifications
        let previous = notificationTask
        notificationTask = Task {
            if let previous {
                await previous.value
            }
            await operation(notifications)
        }
    }
}
