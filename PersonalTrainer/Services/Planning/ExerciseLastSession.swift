import Foundation
import TrainerCore

/// "Da última vez" de um exercício (SPEC RF-47; docs/V22-CONTRACT.md §2.1): a sessão concluída ou
/// abandonada mais recente em que ele teve ao menos uma série de trabalho (SPEC P1), com essas
/// séries na ordem em que foram feitas. DTO puro, lido por `SessionPlanning.lastSession(forExerciseID:)`
/// para a folha "Informações do exercício", na tela Hoje e na ficha da sessão, sem `@Query`
/// (ARCHITECTURE §15).
struct ExerciseLastSession: Sendable, Hashable {
    let sessionID: UUID
    /// `startedAt` da sessão.
    let date: Date
    /// Só séries de trabalho (`isWarmup == false`), na ordem de `index`. Nunca vazio.
    let sets: [SetResult]
    /// Sessão de semana leve (SPEC §7.5): entra em "Da última vez", mas não é a referência de P3.
    let wasDeload: Bool

    init(sessionID: UUID, date: Date, sets: [SetResult], wasDeload: Bool) {
        self.sessionID = sessionID
        self.date = date
        self.sets = sets
        self.wasDeload = wasDeload
    }
}
