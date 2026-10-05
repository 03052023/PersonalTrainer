import Foundation

/// Como terminou a sessão que acabou de fechar, para a condição (c) do pedido de avaliação (SPEC §7.18 L3).
/// Só `completed` deixa pedir: a caixa nunca aparece depois de um erro nem de uma sessão abandonada.
public enum RatingSessionEnding: String, Sendable, CaseIterable {
    /// Concluída nesta abertura da ficha, gravada, e a ida ao Saúde não falhou (sem o app Saúde ou sem
    /// permissão de gravar não é falha).
    case completed
    /// "Sair sem registrar", ou encerrada sem nenhuma série de trabalho.
    case abandoned
    /// Erro de gravação ou do Saúde, ou o Saúde ainda sem resposta no fim da espera.
    case failed
}
