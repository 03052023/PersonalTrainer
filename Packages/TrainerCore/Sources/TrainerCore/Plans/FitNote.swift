import Foundation

/// Aviso sobre uma semana que cabe, sem impedir nada (SPEC §7.15 M4). O texto em pt-BR é da tela.
public enum FitNote: Sendable, Hashable {
    /// Todos os 7 dias têm sessão: recomenda-se pelo menos um dia de descanso completo.
    case noFullRestDay
    /// Força e aeróbico no mesmo dia: a força antes, ou 6 h de intervalo (A5).
    case strengthBeforeCardio(PlanWeekday)
}
