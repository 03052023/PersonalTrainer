import Foundation

/// Resumo de frequência cardíaca de uma sessão, lido do HealthKit depois do fim
/// (M2, iPhone) ou recebido do relógio via `SessionEvent.Kind.heartRateSummary` (M3).
///
/// Só alimenta exibição e o resumo da sessão (SPEC §7.6 / P12): nunca entra no motor,
/// por isso vive no app e não em `TrainerCore`.
struct HeartRateSummary: Sendable, Hashable {
    /// Média das amostras, em batimentos por minuto.
    let averageBPM: Double
    /// Maior amostra, em batimentos por minuto.
    let maxBPM: Double
    /// Quantidade de amostras usadas. Um serviço devolve `nil` em vez de um resumo
    /// com zero amostras, então aqui o valor é sempre positivo.
    let sampleCount: Int

    init(averageBPM: Double, maxBPM: Double, sampleCount: Int) {
        self.averageBPM = averageBPM
        self.maxBPM = maxBPM
        self.sampleCount = sampleCount
    }
}
