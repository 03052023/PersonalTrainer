import Foundation

/// Por que os planos não cabem na semana (SPEC §7.15 M5). O texto em pt-BR é da tela.
public enum FitProblem: Sendable, Hashable {
    /// Há mais sessões que lugares: `needed` sessões por semana, `available` dias (com 2 por dia, se aceito).
    case notEnoughDays(needed: Int, available: Int)
    /// Os dias bastam, mas duas sessões de força com o mesmo grupo ficariam a menos de 48 h (S6).
    case muscleRecovery
    /// Os dias bastam, mas um aeróbico forte cairia na véspera de um dia de pernas (A5).
    case cardioBeforeLegs
}
