import Foundation

/// Tipos de sugestão do painel de saúde (SPEC §7.10 A3–A5), na ordem em que são exibidos.
/// Raw values estáveis.
public enum HealthSuggestionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case wearWatchAtNight
    case updateVo2Max
    case aerobicDeficit
    case lowSleep
    case recoveryAlert
    case lowSteps
}
