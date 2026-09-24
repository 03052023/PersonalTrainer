import Foundation
import TrainerCore

/// Ponte entre o painel de saúde (SPEC §7.10 A4) e a revisão periódica (SPEC §7.8 R6): o
/// `RecoveryContext` que o `CoachService` repassa ao `ProgramReviewer`. Só tendências agregadas
/// de 7 contra 28 dias entram aqui, nunca amostras de sessões (AGENTS R2).
extension RecoveryContext {
    /// Sem relatório (Saúde não conectado, sem app Saúde, primeira leitura ainda não terminou):
    /// `.unknown`, e R6 deixa as sugestões como R1–R5 as geraram.
    static func derived(from report: HealthReport?) -> RecoveryContext {
        guard let report else {
            return .unknown
        }
        return derived(from: report.recovery)
    }

    /// As três marcas vêm dos alertas de A4 (`hrvDrop`, `restingHeartRateRise`, `lowSleep`).
    /// `hasData` exige as médias de 7 e 28 dias de HRV ou de FC de repouso: são as duas
    /// tendências que modulam as sugestões (R6). Com só o sono, R6 não teria como dizer que "a HRV
    /// está estável", e marcar `hasData` enfraqueceria sugestões sem base.
    static func derived(from summary: RecoverySummary) -> RecoveryContext {
        let hasHRVTrend = summary.hrv7 != nil && summary.hrv28 != nil
        let hasRestingTrend = summary.restingHR7 != nil && summary.restingHR28 != nil
        return RecoveryContext(
            hrvDropped: summary.alerts.contains(.hrvDrop),
            restingHeartRateRose: summary.alerts.contains(.restingHeartRateRise),
            sleepLow: summary.alerts.contains(.lowSleep),
            hasData: hasHRVTrend || hasRestingTrend
        )
    }
}
