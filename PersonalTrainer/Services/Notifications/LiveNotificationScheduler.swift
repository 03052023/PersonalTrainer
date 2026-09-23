import Foundation
import UserNotifications

/// `NotificationScheduling` real sobre `UNUserNotificationCenter` (ARCHITECTURE §10, AGENTS R9).
/// Usado só no app; previews e testes usam `FakeNotificationScheduler`.
///
/// Sem estado: cada método pega `UNUserNotificationCenter.current()` na hora, então a classe
/// é `Sendable` verificada pelo compilador, sem `@unchecked` e sem ator. Nenhum método lança
/// nem propaga erro (contrato do protocolo): uma notificação que não pôde ser autorizada ou
/// agendada não interrompe o timer em primeiro plano (AGENTS §4).
///
/// Comportamento em primeiro plano: sem `UNUserNotificationCenterDelegate`, o sistema não
/// exibe a notificação enquanto o app está visível; o aviso nesse caso é o haptic da
/// `RestTimerView`. Em segundo plano, o sistema entrega alerta + som em `fireDate` (CA1-3).
final class LiveNotificationScheduler: NotificationScheduling {
    /// Título fixo das notificações do app (nome de exibição, `CFBundleDisplayName`).
    static let title = "Personal"

    init() {}

    /// Pede alerta e som. `false` também quando o pedido falha (ex.: centro indisponível).
    func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Remove a pendente com o mesmo `identifier` e agenda outra para `fireDate`. O gatilho é
    /// por intervalo (mínimo 1 s, exigência do `UNTimeIntervalNotificationTrigger`), calculado
    /// aqui a partir do relógio real: `fireDate` já vem do `RestTimer` como instante absoluto.
    func scheduleRestTimerEnd(at fireDate: Date, identifier: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = LiveNotificationScheduler.title
        content.body = body
        content.sound = .default

        let interval = max(1, fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // Falha ao agendar não interrompe o descanso em primeiro plano (AGENTS §4).
        }
    }

    func cancel(identifier: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
