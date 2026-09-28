import Foundation

/// A tabela de consequências de combinar dois objetivos (SPEC §7.15 M7; owner notes itens 10–12). Determinística:
/// cada par de objetivos diferentes tem uma lista fixa, na ordem da SPEC, que não depende da ordem dos
/// argumentos.
///
/// Andaime do arquiteto: a assinatura é o contrato entre `plans-core` (dona, que escreve a tabela e os
/// testes) e `plans-ui`. Até lá, a tabela está vazia.
public enum PlanCombination {
    /// As consequências de ter `first` e `second` ativos ao mesmo tempo. Vazio para o mesmo objetivo.
    public static func consequences(_ first: ProgramGoal, _ second: ProgramGoal) -> [PlanConsequence] {
        []
    }

    /// Grande sobreposição (Hipertrofia + Força e Força + Combate): os dois planos treinam quase os mesmos
    /// levantamentos, e o app sugere um plano só ou um formato.
    public static func isLargeOverlap(_ first: ProgramGoal, _ second: ProgramGoal) -> Bool {
        false
    }
}
