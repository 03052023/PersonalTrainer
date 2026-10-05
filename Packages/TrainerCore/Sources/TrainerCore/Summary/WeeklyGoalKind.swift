import Foundation

/// Uma meta da tela "Metas da semana" (SPEC RF-52, §7.16 W2; docs/V23-UI-CONTRACT.md §4.3), na ordem
/// fixa em que `WeeklyGoals.goals(_:)` as devolve. Raw values estáveis (persistem em nada hoje, mas
/// seguem a convenção de `AGENTS.md` §4 para enums do domínio).
public enum WeeklyGoalKind: String, Sendable, Hashable, CaseIterable {
    /// Uma linha por plano ativo (W2.1): sessões concluídas contra as sessões por semana do plano.
    case planSessions
    /// A frequência por grupo muscular (W2.2), agregada numa marca só.
    case muscles
    /// Minutos aeróbicos moderados-equivalentes da semana (W2.3).
    case aerobic
    /// Média diária de passos (W2.4); só existe quando `WeeklyGoals.showsSteps` é verdadeiro (W7).
    case steps
    /// Média de horas de sono (W2.5).
    case sleep
    /// Vezes de equilíbrio registradas nesta semana, contra 2 (W2.6, SPEC §7.17 X6); só com a Longevidade
    /// ativa.
    case balance
    /// Vezes de mobilidade registradas nesta semana, contra 2 (W2.6, SPEC §7.17 X6); só com a Longevidade
    /// ativa.
    case mobility
}
