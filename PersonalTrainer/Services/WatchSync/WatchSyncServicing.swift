import Foundation
import TrainerCore

/// Canal iPhone ⇄ Apple Watch (ARCHITECTURE §9). Implementações: `NoopWatchSyncService`
/// (M0–M2, sem relógio) e `LiveWatchSyncService` sobre `WCSession` (T3.1).
///
/// - `publish` envia o `ActiveSessionSnapshot` inteiro; só o último estado vale
///   (`updateApplicationContext`). Não lança: falha de sync nunca interrompe a sessão
///   (AGENTS §4); a implementação registra em log e o próximo snapshot corrige.
/// - `incomingEvents` entrega os `SessionEvent` vindos do relógio (`transferUserInfo`,
///   fila garantida). É um `AsyncStream`, portanto tem **um único consumidor**: quem liga
///   o stream ao `SessionCoordinator.apply` é o dono da iteração.
protocol WatchSyncServicing: Sendable {
    /// `WCSession.isSupported()`: `false` em iPad e no Noop.
    var isSupported: Bool { get }

    /// `WCSession.isReachable`: relógio pareado, app ativo e ao alcance. Só habilita
    /// atalhos (`sendMessage`); os canais principais não dependem disso.
    var isReachable: Bool { get }

    /// Eventos do relógio, na ordem em que chegaram. Termina só quando o serviço é encerrado.
    var incomingEvents: AsyncStream<SessionEvent> { get }

    /// Publica o estado atual da sessão ativa (ou do próximo treino) para o relógio.
    func publish(_ snapshot: ActiveSessionSnapshot) async
}
