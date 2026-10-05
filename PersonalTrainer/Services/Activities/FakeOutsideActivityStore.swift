import Foundation
import TrainerCore

/// `OutsideActivityStoring` em memória (AGENTS R9), para testes e previews. Nada vai ao disco.
final class FakeOutsideActivityStore: OutsideActivityStoring {
    /// O que `load()` devolve; muda só por `save(_:)` ou pelo `init`.
    private(set) var log: OutsideActivityLog
    /// Gravações bem-sucedidas, para os testes conferirem que nada foi gravado.
    private(set) var saveCount = 0
    /// Leituras, para os testes conferirem quem lê as atividades (o planejador, por exemplo).
    private(set) var loadCount = 0
    /// Quando preenchido, `save(_:)` lança este erro e não grava nada.
    var saveError: (any Error)?

    init(log: OutsideActivityLog = .empty) {
        self.log = log
    }

    func load() -> OutsideActivityLog {
        loadCount += 1
        return log
    }

    func save(_ log: OutsideActivityLog) throws {
        if let saveError {
            throw saveError
        }
        self.log = log
        saveCount += 1
    }
}
