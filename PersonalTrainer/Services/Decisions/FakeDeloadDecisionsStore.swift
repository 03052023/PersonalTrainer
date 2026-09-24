import Foundation
import TrainerCore

/// `DeloadDecisionsStoring` em memória (AGENTS R9), para testes e previews. Nada vai ao disco.
final class FakeDeloadDecisionsStore: DeloadDecisionsStoring {
    /// O que `load()` devolve; muda só por `save(_:)` ou pelo `init`.
    private(set) var decisions: DeloadDecisions
    /// Gravações bem-sucedidas, para os testes conferirem que nada foi gravado.
    private(set) var saveCount = 0
    /// Quando preenchido, `save(_:)` lança este erro e não grava nada.
    var saveError: (any Error)?

    init(decisions: DeloadDecisions = DeloadDecisions()) {
        self.decisions = decisions
    }

    func load() -> DeloadDecisions {
        decisions
    }

    func save(_ decisions: DeloadDecisions) throws {
        if let saveError {
            throw saveError
        }
        self.decisions = decisions
        saveCount += 1
    }
}
