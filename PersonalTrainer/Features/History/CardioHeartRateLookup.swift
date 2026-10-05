import Foundation
import SwiftUI
import TrainerCore

/// O que o detalhe de uma sessão de aeróbico no Histórico lê para a seção "Coração" (SPEC §7.14 F7; 2.4):
/// a FC média de cada minuto da sessão, as zonas do painel de saúde (A1) e o último VO2máx com a faixa (A3).
/// Só leitura: a FC nunca prescreve nada (§7.6, P12), e a ficha e a tela Hoje continuam só com o teste da fala.
///
/// O integrador injeta na raiz das abas (`\.cardioHeartRate`) com o `HealthKitServicing.heartRateMinutes` e o
/// relatório do `HealthViewModel`. Sem injeção (previews, testes), vale `.none`: tudo vazio, e a seção não
/// aparece. A feature não lê o `AppEnvironment` (ARCHITECTURE §3).
struct CardioHeartRateLookup: Sendable {
    /// FC média por minuto do intervalo (início, fim), em bpm. Minuto sem leitura pode vir como 0 ou faltar.
    var minuteHeartRates: @MainActor @Sendable (Date, Date) async -> [Double]
    /// As zonas do painel de saúde (FCmáx e FC de repouso); `nil` sem idade nem FCmáx informada.
    var zones: @MainActor @Sendable () -> HeartRateZones?
    /// O último VO2máx com a faixa; `nil` sem estimativa no app Saúde.
    var latestVo2Max: @MainActor @Sendable () -> Vo2MaxSummary?

    init(
        minuteHeartRates: @escaping @MainActor @Sendable (Date, Date) async -> [Double],
        zones: @escaping @MainActor @Sendable () -> HeartRateZones?,
        latestVo2Max: @escaping @MainActor @Sendable () -> Vo2MaxSummary?
    ) {
        self.minuteHeartRates = minuteHeartRates
        self.zones = zones
        self.latestVo2Max = latestVo2Max
    }

    /// Tudo vazio: sem FC, sem zonas e sem VO2máx, a seção "Coração" não aparece.
    static let none = CardioHeartRateLookup(
        minuteHeartRates: { _, _ in [] },
        zones: { nil },
        latestVo2Max: { nil }
    )
}

private struct CardioHeartRateKey: EnvironmentKey {
    static let defaultValue: CardioHeartRateLookup = .none
}

extension EnvironmentValues {
    /// A leitura de FC e VO2máx do Histórico (SPEC F7). Padrão `.none`.
    var cardioHeartRate: CardioHeartRateLookup {
        get { self[CardioHeartRateKey.self] }
        set { self[CardioHeartRateKey.self] = newValue }
    }
}
