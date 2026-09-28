import Foundation
import TrainerCore

/// Uma sessão da tela Hoje (SPEC §7.15 M6; docs/V23-UI-CONTRACT.md §3.3): o plano calculado do dia e de
/// qual objetivo ele é. DTO puro, montado pelo `SessionPlanning`.
struct TodaySession: Sendable, Hashable, Identifiable {
    let plan: SessionPlan
    let goal: ProgramGoal
    /// Hoje já houve uma sessão concluída ou abandonada, com ao menos uma série, num dia deste plano:
    /// o cartão mostra "Feito hoje" e o botão principal passa para a próxima.
    let isDoneToday: Bool

    /// Um cartão por plano no mesmo dia.
    var id: UUID {
        plan.programID
    }
}
