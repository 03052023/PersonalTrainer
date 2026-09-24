import Foundation

/// Notificações locais do timer de descanso (ARCHITECTURE §10) e lembretes do diálogo (SPEC §7.11
/// C4). Implementações: `FakeNotificationScheduler` (previews, testes) e
/// `LiveNotificationScheduler` sobre `UNUserNotificationCenter` (T1.7).
///
/// Nenhum método lança: uma notificação que não pôde ser agendada não impede o timer de
/// rodar em primeiro plano (AGENTS §4). Permissão é pedida na primeira ação que precisa dela
/// (o timer iniciar, a mensagem C4), nunca no launch (AGENTS §7).
protocol NotificationScheduling: Sendable {
    /// Pede permissão de alerta e som; devolve se foi concedida.
    func requestAuthorization() async -> Bool

    /// Agenda a notificação de fim de descanso para `fireDate`. Reagendar com o mesmo
    /// `identifier` substitui a pendente, como no `UNUserNotificationCenter`.
    func scheduleRestTimerEnd(at fireDate: Date, identifier: String, body: String) async

    /// Remove a notificação pendente com esse `identifier` (ex.: usuário pulou o descanso).
    func cancel(identifier: String) async

    /// Agenda um lembrete com título próprio para o instante `fireDate` (ex.: aviso de expiração
    /// da instalação às 10h da véspera, SPEC §7.11 C4). O mesmo `identifier` substitui o
    /// pendente. Padrão na extensão: encaminha para `scheduleRestTimerEnd`, sem o título.
    func scheduleReminder(at fireDate: Date, identifier: String, title: String, body: String) async
}

extension NotificationScheduling {
    /// Padrão para quem ainda não implementa lembretes (contrato V2-FINAL §2.3): o mesmo
    /// agendamento do fim de descanso, que usa o título fixo do app.
    func scheduleReminder(at fireDate: Date, identifier: String, title: String, body: String) async {
        await scheduleRestTimerEnd(at: fireDate, identifier: identifier, body: body)
    }
}
