import Foundation

/// Tipo de uma sessão do plano no encaixe da semana (SPEC §7.15 M3): um dia com algum aeróbico é
/// `cardio`; os outros são `strength`.
public enum PlanSessionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case strength
    case cardio
}
