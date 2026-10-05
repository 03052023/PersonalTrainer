import Foundation

/// O papel de uma atividade fora do app no encaixe da semana (SPEC §7.17 X4) e na recuperação (X5).
/// Raw values estáveis (AGENTS §4).
public enum OutsideActivityRole: String, Codable, Sendable, Hashable, CaseIterable {
    /// Leve (pilates, ioga, equilíbrio, mobilidade): não ocupa lugar no dia nem entra nos 48 h, mas o dia
    /// deixa de ser de descanso completo.
    case light
    /// Força (cross): ocupa o lugar de força do dia, com os grupos do tipo (48 h, S6).
    case strength
    /// Aeróbico (bicicleta indoor, aula de luta, futebol…): ocupa o lugar de aeróbico do dia, com a intensidade
    /// (forte nunca na véspera de pernas, A5).
    case cardio
}
