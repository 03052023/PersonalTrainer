import Foundation

/// Como terminou, para uma sessão, a ida ao app Saúde (`HealthKitWorkoutRecorder.healthOutcome(for:)`).
/// Serve à condição (c) do pedido de avaliação (SPEC §7.18 L3): depois de um erro do Saúde o app não pede.
/// Fica só em memória, pelo processo: nada disso é gravado.
enum HealthRecordOutcome: Equatable, Sendable {
    /// O Saúde está no aparelho e a sessão ainda está sendo gravada, ou o `sessionFinished` ainda não chegou.
    case pending
    /// Nada a gravar: o app Saúde não está no aparelho, ou não há permissão de gravar treinos. Não é erro.
    case notAttempted
    /// O treino foi gravado no Saúde, ou vinculado ao de outro app (ex.: o app Exercício do relógio).
    case saved
    /// A gravação, a busca do treino sobreposto ou o `apply` do resumo na sessão deu erro.
    case failed
}
