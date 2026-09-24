import Foundation
import TrainerCore

/// `CoachLogStoring` em memória para previews e testes (AGENTS R9). Conta as gravações e pode
/// simular falha de disco com `saveError`.
final class FakeCoachLogStore: CoachLogStoring {
    /// O que `load()` devolve; `save(_:)` substitui.
    var log: CoachLog
    /// O que `loadLastReview()` devolve; `saveLastReview(_:)` substitui.
    var lastReview: ReviewReport?
    /// Quando não é `nil`, as duas gravações lançam este erro e nada muda.
    var saveError: (any Error)?
    private(set) var saveCount = 0
    private(set) var reviewSaveCount = 0
    private(set) var loadCount = 0

    init(log: CoachLog = CoachLog(), lastReview: ReviewReport? = nil) {
        self.log = log
        self.lastReview = lastReview
    }

    func load() -> CoachLog {
        loadCount += 1
        return log
    }

    func save(_ log: CoachLog) throws {
        if let saveError {
            throw saveError
        }
        saveCount += 1
        self.log = log
    }

    func loadLastReview() -> ReviewReport? {
        lastReview
    }

    func saveLastReview(_ report: ReviewReport) throws {
        if let saveError {
            throw saveError
        }
        reviewSaveCount += 1
        lastReview = report
    }
}
