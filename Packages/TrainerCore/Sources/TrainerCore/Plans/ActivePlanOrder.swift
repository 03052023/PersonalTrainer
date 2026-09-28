import Foundation

/// Ordem dos planos ativos (SPEC §7.15 M1; docs/V23-UI-CONTRACT.md §3.1). O primeiro é o plano principal: a
/// pétala da abertura, o topo da tela Hoje, a semana leve do diálogo e a revisão periódica olham para ele.
/// A regra não precisa de nada gravado: a força vem antes do aeróbico, como na ordem do dia (A5).
public enum ActivePlanOrder {
    /// No máximo dois planos ao mesmo tempo nesta versão, de objetivos diferentes.
    public static let maxActivePlans: Int = 2

    /// Prioridade dos objetivos para escolher o principal.
    public static let goalPriority: [ProgramGoal] = [.hypertrophy, .strength, .combat, .longevity, .endurance]

    public static func rank(of goal: ProgramGoal) -> Int {
        goalPriority.firstIndex(of: goal) ?? goalPriority.count
    }

    /// Ordena pela prioridade do objetivo efetivo; empate (não deveria haver: um plano por objetivo) pelo
    /// nome e depois pelo id.
    public static func sorted(_ programs: [ProgramTemplate]) -> [ProgramTemplate] {
        programs.sorted { lhs, rhs in
            let left = rank(of: lhs.effectiveGoal)
            let right = rank(of: rhs.effectiveGoal)
            if left != right {
                return left < right
            }
            if lhs.name != rhs.name {
                return lhs.name < rhs.name
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
