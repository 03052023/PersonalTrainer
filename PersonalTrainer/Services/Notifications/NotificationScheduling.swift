import Foundation

/// Notificações locais do timer de descanso (ARCHITECTURE §10). Implementações:
/// `FakeNotificationScheduler` (previews, testes) e `LiveNotificationScheduler`
/// sobre `UNUserNotificationCenter` (T1.7).
///
/// Nenhum método lança: uma notificação que não pôde ser agendada não impede o timer de
/// rodar em primeiro plano (AGENTS §4). Permissão é pedida na primeira vez que o timer
/// inicia, nunca no launch (AGENTS §7).
protocol NotificationScheduling: Sendable {
    /// Pede permissão de alerta e som; devolve se foi concedida.
    func requestAuthorization() async -> Bool

    /// Agenda a notificação de fim de descanso para `fireDate`. Reagendar com o mesmo
    /// `identifier` substitui a pendente, como no `UNUserNotificationCenter`.
    func scheduleRestTimerEnd(at fireDate: Date, identifier: String, body: String) async

    /// Remove a notificação pendente com esse `identifier` (ex.: usuário pulou o descanso).
    func cancel(identifier: String) async
}
