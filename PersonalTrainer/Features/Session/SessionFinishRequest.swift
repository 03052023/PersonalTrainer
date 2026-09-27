import Foundation

/// Resposta de `ActiveSessionViewModel.requestFinish()` ao botão "Concluir" (SPEC RF-44 e).
enum SessionFinishRequest: Sendable, Hashable {
    /// Nada pendente: o ViewModel já tentou concluir a sessão, sem diálogo. Quem chamou confere
    /// `isFinished` (uma falha de gravação vai para `errorMessage` e a sessão continua aberta).
    case finished
    /// Faltam exercícios: a tela pergunta uma vez, com os nomes na ordem da ficha.
    /// `hasAnySet` diz se já há alguma série de trabalho gravada: com alguma, a saída é
    /// "Encerrar só com o que marquei" (conclui); sem nenhuma, "Sair sem registrar" (abandona).
    case needsConfirmation(pendingNames: [String], hasAnySet: Bool)
}
