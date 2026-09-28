import Foundation
import TrainerCore

/// O dia de hoje para a tela Hoje e para a tela inicial (SPEC §7.15 M6; docs/V23-UI-CONTRACT.md §3.3). DTO
/// puro, montado pelo `SessionPlanning`.
struct TodayOverview: Sendable, Hashable {
    /// As sessões de hoje, a força antes do aeróbico. Com um plano só, a próxima sessão dele.
    let sessions: [TodaySession]
    /// Com dois planos: a próxima sessão de cada plano que não tem lugar hoje, para "Treinar mesmo
    /// assim" num dia de descanso. Vazio com um plano só.
    let otherSessions: [TodaySession]
    /// Com dois planos, hoje não tem nenhuma sessão na semana ideal.
    let isRestDay: Bool
    /// Falso quando os dois planos não cabem mais nos dias escolhidos: a tela Hoje mostra a próxima
    /// sessão do plano principal e o aviso para ajustar na aba Plano.
    let fitsWeek: Bool

    init(
        sessions: [TodaySession],
        otherSessions: [TodaySession] = [],
        isRestDay: Bool = false,
        fitsWeek: Bool = true
    ) {
        self.sessions = sessions
        self.otherSessions = otherSessions
        self.isRestDay = isRestDay
        self.fitsWeek = fitsWeek
    }

    /// Sem plano ativo.
    static let empty = TodayOverview(sessions: [])

    /// A primeira sessão de hoje que ainda não foi feita: é ela que o botão principal começa.
    var nextPending: TodaySession? {
        sessions.first { !$0.isDoneToday }
    }
}
