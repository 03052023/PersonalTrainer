import Foundation
import TrainerCore

/// Faixa do cartão da Home que diz por que esta sessão (TASKS CA4-5): o texto e o símbolo, a
/// partir de `SessionPlan.reason` e `SessionPlan.isDeload`. Função pura, testada em
/// `HomeViewModelTests`; a view só desenha.
///
/// - Semana leve (programada, em andamento ou num dia escolhido à mão em semana leve): "Semana
///   leve". Faz parte do plano, então o tom é calmo, nunca de alerta (DESIGN §9.3).
/// - Seletor por frequência (SPEC S5–S7): "Quadríceps: abaixo da meta semanal (0 de 2)".
/// - Sequência (S2) e dia escolhido (S4): sem faixa; o próprio cartão já diz qual é o dia.
struct PlanBanner: Hashable, Sendable {
    let text: String
    let symbolName: String

    static func make(for plan: SessionPlan) -> PlanBanner? {
        make(reason: plan.reason, isDeload: plan.isDeload)
    }

    static func make(reason: PlanReason?, isDeload: Bool) -> PlanBanner? {
        // `isDeload` primeiro: `plan(forDayID:)` devolve `.manual` também em semana leve.
        if isDeload {
            return deload
        }
        guard let reason else {
            return nil
        }
        switch reason {
        case .deload:
            return deload
        case .frequency(let muscle, let done, let target):
            return PlanBanner(
                // `MuscleGroup.displayName` (Catalog): os mesmos nomes do painel semanal.
                text: "\(muscle.displayName): abaixo da meta semanal (\(done) de \(target))",
                symbolName: "calendar"
            )
        case .manual, .rotation:
            return nil
        }
    }

    /// DESIGN §6: "semana leve", nunca "deload".
    static let deload = PlanBanner(text: "Semana leve", symbolName: "wind")
}
