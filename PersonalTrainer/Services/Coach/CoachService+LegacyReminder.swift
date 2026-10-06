import Foundation

/// O aviso antigo da 2.4 (SPEC §7.18 L4). Até a 2.4, quem ligava o aviso da véspera tinha um
/// pedido local agendado com o identificador abaixo e a chave abaixo gravada. A 2.5 não agenda
/// mais nada; na primeira atualização do diálogo, se a chave existe, o app cancela o pedido e
/// apaga a chave, uma vez só, sem pedir permissão de notificação.
extension CoachService.DefaultsKey {
    /// Legado da 2.4 (Bool): só é lido para ser apagado.
    static let expiryReminderEnabled = "expiryReminderEnabled"
}

extension CoachService {
    /// Legado da 2.4: identificador do pedido local que a 2.4 agendava.
    nonisolated static let expiryReminderIdentifier = "coach.expiryReminder"

    /// Com a chave antiga gravada, apaga a chave e enfileira o cancelamento do pedido antigo (os
    /// testes aguardam `pendingWork?.value`). Sem a chave, não faz nada: o cancelamento acontece
    /// uma vez só. `cancel` só remove um pendente e não precisa de permissão.
    func cancelLegacyExpiryReminderIfNeeded() {
        guard defaults.object(forKey: DefaultsKey.expiryReminderEnabled) != nil else {
            return
        }
        defaults.removeObject(forKey: DefaultsKey.expiryReminderEnabled)
        Self.logger.info("Aviso antigo da 2.4 cancelado e chave apagada (SPEC §7.18 L4).")
        let notifications = self.notifications
        let identifier = Self.expiryReminderIdentifier
        enqueue {
            await notifications.cancel(identifier: identifier)
        }
    }
}
