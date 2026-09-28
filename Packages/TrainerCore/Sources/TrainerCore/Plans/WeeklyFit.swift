import Foundation

/// Encaixe semanal de vários planos (SPEC §7.15 M4 e M5; docs/V23-UI-CONTRACT.md §3.1 e §4.5). Função pura:
/// mesma entrada, mesma semana (P11). Sem `Date()`, sem aleatório.
///
/// Andaime do arquiteto: a assinatura é o contrato entre `plans-core` (dona, que escreve o algoritmo e os
/// testes de tabela M4/M5) e `plans-ui`. Até lá, tudo "cabe" sem semana calculada.
public enum WeeklyFit {
    /// A melhor semana para `plans` com `preferences` (M4) ou, se não couber, os motivos e as saídas (M5).
    public static func fit(_ plans: [PlanDemand], preferences: WeekPreferences) -> FitResult {
        FitResult.unchecked
    }
}
