import Foundation
import TrainerCore

/// Um cartão da tela Hoje com dois planos (SPEC §7.15 M6; DESIGN §9.7): a sessão de um plano, já com o
/// dia escolhido à mão (S4) quando houver, os dias daquele plano para o menu e o papel do cartão (o
/// primeiro que dá para começar leva o botão principal; os outros, "Começar esta"). DTO puro, montado
/// pelo `HomeViewModel`.
struct HomeTodayCard: Sendable, Hashable, Identifiable {
    let session: TodaySession
    /// O plano do cartão: o do dia escolhido à mão, se houver; senão, o da rotação (`session.plan`).
    let plan: SessionPlan
    /// Dias do plano, ordenados por `order`, para o menu do nome do dia.
    let days: [ProgramDayTemplate]
    /// `nil` = próximo da rotação; senão, o dia escolhido à mão.
    let selectedDayID: UUID?
    /// Dá para começar esta sessão agora (sem sessão em andamento; feita hoje só com "Treinar mesmo assim").
    let isStartable: Bool
    /// A primeira que dá para começar: é ela que o "Começar" principal abre.
    let isPrimary: Bool

    /// Um cartão por plano: o id do programa.
    var id: UUID {
        session.id
    }

    var goal: ProgramGoal {
        session.goal
    }

    var isDoneToday: Bool {
        session.isDoneToday
    }
}
