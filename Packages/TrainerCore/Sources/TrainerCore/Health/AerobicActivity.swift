import Foundation

/// Tipo de treino aeróbico lido do HealthKit (SPEC §7.10 A1). O serviço do app mapeia
/// `HKWorkoutActivityType` para estes casos; o que não tiver par vira `other`.
/// Raw values estáveis: nunca renomear um case.
public enum AerobicActivity: String, Codable, Sendable, Hashable, CaseIterable {
    case walking
    case running
    case cycling
    case swimming
    case rowing
    case elliptical
    case hiking
    case stairs
    case hiit
    case dance
    case other

    /// Nome curto em pt-BR para a UI.
    public var displayName: String {
        switch self {
        case .walking: return "Caminhada"
        case .running: return "Corrida"
        case .cycling: return "Ciclismo"
        case .swimming: return "Natação"
        case .rowing: return "Remo"
        case .elliptical: return "Elíptico"
        case .hiking: return "Trilha"
        case .stairs: return "Escada"
        case .hiit: return "HIIT"
        case .dance: return "Dança"
        case .other: return "Outro aeróbico"
        }
    }

    /// Intensidade usada para os minutos sem FC ou quando não há como calcular a FCmáx
    /// (SPEC §7.10 A1: "caminhada = moderado; corrida/HIIT = vigoroso"). Nunca é `light`,
    /// porque um treino registrado como aeróbico conta pelo menos como moderado.
    public var defaultIntensity: AerobicIntensity {
        switch self {
        case .running, .hiit, .stairs:
            return .vigorous
        case .walking, .hiking, .cycling, .swimming, .rowing, .elliptical, .dance, .other:
            return .moderate
        }
    }
}
