import Foundation
import TrainerCore

/// Onde o diálogo guarda suas decisões (SPEC §7.11: "Decisões ficam registradas localmente (log
/// JSON) para auditoria e para não repetir") e o relatório da última revisão periódica, que o
/// feed continua mostrando até a próxima (contrato V2-FINAL §2, ajustes da onda 2).
///
/// Implementações (AGENTS R9): `LiveCoachLogStore` (JSON em Application Support) e
/// `FakeCoachLogStore` (memória, para previews e testes). Não é SwiftData: o log não é derivável
/// do histórico e não entra no esquema (ADR 003).
///
/// Leituras nunca lançam: arquivo ausente ou ilegível vale como "nada guardado ainda", e o app
/// segue com o log vazio em vez de travar a Home.
protocol CoachLogStoring: AnyObject {
    /// O log inteiro; `CoachLog()` quando não há nada guardado.
    func load() -> CoachLog
    /// Substitui o log guardado (escrita atômica na implementação real).
    func save(_ log: CoachLog) throws
    /// O relatório da última revisão periódica, ou `nil` se nenhuma rodou.
    func loadLastReview() -> ReviewReport?
    /// Substitui o relatório guardado.
    func saveLastReview(_ report: ReviewReport) throws
}
