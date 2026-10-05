import Foundation

/// Tipo de uma atividade feita fora do app (SPEC §7.17 X1, RF-53; owner notes item 19). A tabela de X1 é
/// fixa: cada tipo traz o nome em pt-BR, o papel no encaixe e na recuperação, a intensidade padrão pelo
/// teste da fala, os grupos (só no papel de força) e se conta no aeróbico da semana.
///
/// Raw values gravados no JSON das atividades e no backup: nunca renomear um case (AGENTS §4).
public enum OutsideActivityKind: String, Codable, Sendable, Hashable, CaseIterable {
    case pilates
    case yoga
    case balance
    case mobility
    case cross
    case fightClass
    case spinning
    case teamSport
    case swimming
    case dance
    case walkRun
    case other

    /// Nome curto em pt-BR para chips e listas (DESIGN §9.3).
    public var displayName: String {
        switch self {
        case .pilates: return "Pilates"
        case .yoga: return "Ioga ou alongamento"
        case .balance: return "Equilíbrio"
        case .mobility: return "Mobilidade"
        case .cross: return "Cross ou funcional"
        case .fightClass: return "Aula de luta"
        case .spinning: return "Spinning ou bicicleta"
        case .teamSport: return "Futebol ou esporte com bola"
        case .swimming: return "Natação"
        case .dance: return "Dança"
        case .walkRun: return "Caminhada ou corrida"
        case .other: return "Outra atividade"
        }
    }

    /// Papel no encaixe da semana (X4) e na recuperação (X5).
    public var role: OutsideActivityRole {
        switch self {
        case .pilates, .yoga, .balance, .mobility:
            return .light
        case .cross:
            return .strength
        case .fightClass, .spinning, .teamSport, .swimming, .dance, .walkRun, .other:
            return .cardio
        }
    }

    /// Intensidade que o editor sugere (X1); a pessoa pode mudar.
    public var defaultIntensity: CardioIntensity {
        switch self {
        case .pilates, .yoga, .balance, .mobility:
            return .light
        case .cross, .spinning, .teamSport:
            return .vigorous
        case .fightClass, .swimming, .dance, .walkRun, .other:
            return .moderate
        }
    }

    /// Grupos que o tipo trabalha como força (X4, X5). Só o papel de força tem grupos: o cross é o corpo
    /// todo. Os aeróbicos fortes entram na recuperação pelas pernas, por A5 (X5), não por esta lista.
    public var primaryMuscles: Set<MuscleGroup> {
        switch self {
        case .cross:
            return Set(MuscleGroup.allCases)
        case .pilates, .yoga, .balance, .mobility, .fightClass, .spinning, .teamSport, .swimming, .dance,
             .walkRun, .other:
            return []
        }
    }

    /// Conta nos minutos de aeróbico da semana com intensidade moderada ou forte (X3). Pilates, ioga,
    /// equilíbrio, mobilidade e cross não contam.
    public var countsAsAerobic: Bool {
        role == .cardio
    }

    /// O tipo de treino do app Saúde mais próximo, só para o relatório de saúde (A1, X3).
    public var aerobicActivity: AerobicActivity {
        switch self {
        case .spinning: return .cycling
        case .swimming: return .swimming
        case .dance: return .dance
        case .walkRun: return .walking
        case .cross: return .hiit
        case .pilates, .yoga, .balance, .mobility, .fightClass, .teamSport, .other: return .other
        }
    }

    /// Duração que o editor sugere, em minutos (X1).
    public var defaultMinutes: Int {
        switch self {
        case .balance, .mobility: return 10
        case .walkRun, .other: return 30
        case .spinning, .swimming: return 45
        case .pilates, .yoga: return 50
        case .cross, .fightClass, .teamSport, .dance: return 60
        }
    }
}
