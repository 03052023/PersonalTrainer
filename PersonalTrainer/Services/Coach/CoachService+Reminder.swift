import Foundation
import TrainerCore

/// Aviso local na véspera da expiração da instalação (SPEC §7.11 C4; contrato V2-FINAL §2.3):
/// às 10h do dia anterior ao da expiração, só se a pessoa ligou `expiryReminderEnabled`.
extension CoachService {
    /// O que o agendador tem (ou deveria ter) pendente para o lembrete de expiração.
    enum ReminderState: Equatable, Sendable {
        case off
        case scheduled(Date)
    }

    nonisolated static let expiryReminderTitle = "O app expira amanhã"

    /// Envia ao agendador o estado desejado do lembrete quando ele mudou (ou quando é preciso
    /// pedir permissão). Pedir permissão só com `requestsAuthorization`, que vem de uma ação da
    /// pessoa (AGENTS §7).
    func syncExpiryReminder(now: Date, requestsAuthorization: Bool) {
        let desired: ReminderState
        if isExpiryReminderEnabled,
           let expiry = provisioningExpiry,
           let fireDate = Self.expiryReminderDate(expiry: expiry, calendar: calendar),
           fireDate > now {
            desired = .scheduled(fireDate)
        } else {
            desired = .off
        }
        guard requestsAuthorization || desired != appliedReminder else {
            return
        }
        appliedReminder = desired

        let notifications = self.notifications
        let identifier = Self.expiryReminderIdentifier
        let title = Self.expiryReminderTitle
        let body = provisioningExpiry.map { Self.expiryReminderBody(expiry: $0, calendar: calendar) } ?? ""
        enqueue { [weak self] in
            if requestsAuthorization {
                let granted = await notifications.requestAuthorization()
                if !granted {
                    self?.errorMessage = "As notificações do Magister estão desligadas nos Ajustes do iPhone; sem elas, o aviso da véspera não aparece."
                }
            }
            switch desired {
            case .scheduled(let fireDate):
                await notifications.scheduleReminder(at: fireDate, identifier: identifier, title: title, body: body)
            case .off:
                await notifications.cancel(identifier: identifier)
            }
        }
    }

    /// 10h do dia anterior ao dia da expiração, no fuso do `calendar`.
    nonisolated static func expiryReminderDate(expiry: Date, calendar: Calendar) -> Date? {
        let expiryDay = calendar.startOfDay(for: expiry)
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: expiryDay) else {
            return nil
        }
        return calendar.date(bySettingHour: expiryReminderHour, minute: 0, second: 0, of: dayBefore)
    }

    /// Texto do lembrete, com a hora da expiração (formatada à mão, como os textos do core).
    nonisolated static func expiryReminderBody(expiry: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: expiry)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let time = "\(hour < 10 ? "0" : "")\(hour):\(minute < 10 ? "0" : "")\(minute)"
        return "A instalação atual vale até amanhã às \(time). Renove hoje pelo Impactor no computador; reinstalar por cima mantém seus dados."
    }
}
