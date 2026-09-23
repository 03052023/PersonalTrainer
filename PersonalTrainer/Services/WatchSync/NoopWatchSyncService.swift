import Foundation
import TrainerCore

/// `WatchSyncServicing` sem relógio (ARCHITECTURE AR-8): usado em M0–M2, em previews e
/// em testes. `publish` descarta o snapshot e `incomingEvents` nunca emite.
///
/// O stream é criado uma única vez no `init` e a `continuation` fica guardada para que
/// `finish()` encerre a iteração de quem estiver aguardando; sem isso, um teste que
/// consome `incomingEvents` nunca terminaria. Todo estado é imutável, então a classe
/// é `Sendable` verificado pelo compilador, sem escape hatch e sem ator.
final class NoopWatchSyncService: WatchSyncServicing {
    let isSupported = false
    let isReachable = false
    let incomingEvents: AsyncStream<SessionEvent>

    private let continuation: AsyncStream<SessionEvent>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: SessionEvent.self)
        self.incomingEvents = stream
        self.continuation = continuation
    }

    deinit {
        continuation.finish()
    }

    func publish(_ snapshot: ActiveSessionSnapshot) async {
        // Sem relógio não há para quem publicar; o iPhone segue como única fonte da verdade.
    }

    /// Encerra `incomingEvents`. Idempotente.
    func finish() {
        continuation.finish()
    }
}
