import TrainerCore

extension CoachRule {
    /// Símbolo calmo de cada regra do diálogo. DESIGN §8: nada de halteres, figuras de academia,
    /// chamas, raios ou troféus; a melhor marca usa um gráfico, não uma taça.
    var symbolName: String {
        switch self {
        case .deload: return "moon.zzz"
        case .review: return "list.bullet.clipboard"
        case .health: return "heart"
        // C4, removida na 2.5: nunca exibida (L4). O case fica porque o `switch` precisa ser exaustivo.
        case .installExpiry: return "calendar.badge.clock"
        case .comeback: return "sun.max"
        case .personalRecord: return "chart.line.uptrend.xyaxis"
        case .backup: return "externaldrive"
        case .longevity: return "tree"
        }
    }
}
