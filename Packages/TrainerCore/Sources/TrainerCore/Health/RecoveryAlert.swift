import Foundation

/// Alertas amarelos de recuperação (SPEC §7.10 A4). Só informam e alimentam a revisão (§7.8 R6);
/// nunca alteram a musculação (P12). Raw values estáveis.
public enum RecoveryAlert: String, Codable, Sendable, Hashable, CaseIterable {
    /// HRV média de 7 dias ≥ 10 % abaixo da média de 28 dias.
    case hrvDrop
    /// FC de repouso média de 7 dias ≥ 5 bpm acima da média de 28 dias.
    case restingHeartRateRise
    /// Sono médio de 7 dias abaixo da meta.
    case lowSleep
}
