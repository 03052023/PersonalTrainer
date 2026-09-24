import Foundation

/// Intensidade de um minuto de exercício aeróbico (SPEC §7.10 A1).
/// `light` existe para classificar minutos abaixo do limiar moderado: eles não contam para a meta (A2).
/// Raw values estáveis: podem ser persistidos ou exportados.
public enum AerobicIntensity: String, Codable, Sendable, Hashable, CaseIterable {
    case light
    case moderate
    case vigorous
}
