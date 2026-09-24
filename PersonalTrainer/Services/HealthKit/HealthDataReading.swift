import Foundation
import TrainerCore

/// Leitura agregada do app Saúde para o painel de saúde (SPEC §7.10, RF-27..RF-31; T5.2).
/// Implementações: `LiveHealthDataReader` (a única que importa HealthKit) e
/// `FakeHealthDataReader` (simulador, previews e testes), conforme AGENTS R9.
///
/// - Só leitura (ARCHITECTURE §8, ADR 013): nada aqui grava no HealthKit.
/// - Amostras brutas não saem da implementação: o retorno já vem nos structs de
///   `TrainerCore/Health`, prontos para `HealthCalculator.report(...)`.
/// - `Sendable` porque é injetado e chamado de tarefas assíncronas; cada implementação
///   protege o próprio estado.
/// - Falhas nunca interrompem o fluxo de treino (AGENTS §4): o painel mostra a mensagem e segue.
/// - Autorização só na primeira ação que precisa dela (AGENTS §7), nunca no launch.
protocol HealthDataReading: Sendable {
    /// `false` em simulador sem HealthKit e em iPad (`HKHealthStore.isHealthDataAvailable()`).
    /// Com `false`, os métodos abaixo lançam `HealthKitServiceError.unavailable`.
    var isAvailable: Bool { get }

    /// Pede só leitura (treinos, FC, VO2max, HRV, FC de repouso, passos, sono, data de
    /// nascimento e sexo). O sistema não revela negação de leitura: negar e "sem dados"
    /// aparecem igual, como listas vazias em `healthInput` (ARCHITECTURE §15).
    func requestReadAuthorization() async throws

    /// Lê as janelas usadas pelas regras A1–A4 (treinos aeróbicos, recuperação e passos dos
    /// últimos 28 dias; VO2max dos últimos 180) e devolve tudo agregado. `recentSessions` é
    /// repassado sem alteração para `HealthInput.recentSessions` (encaixe A5).
    /// "Sem dados" vira lista vazia ou campo `nil`; erros reais viram `HealthKitServiceError`.
    func healthInput(now: Date, calendar: Calendar, recentSessions: [SessionSummary]) async throws -> HealthInput
}
