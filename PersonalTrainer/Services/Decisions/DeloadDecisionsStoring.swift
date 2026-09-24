import Foundation
import TrainerCore

/// Guarda as duas decisões da pessoa sobre a semana leve (SPEC §7.5 c e §7.11 C1): o pedido
/// "Fazer semana leve agora" e o "Seguir normal". É o único estado de deload que não sai do
/// histórico (ARCHITECTURE ADR 003), por isso fica num JSON pequeno, fora do SwiftData.
///
/// Implementações (AGENTS R9): `LiveDeloadDecisionsStore` (arquivo em Application Support) e
/// `FakeDeloadDecisionsStore` (memória, para testes e previews). Quem escreve é o
/// `SessionPlanner` (`requestDeload`/`dismissDeload`); nenhuma view grava aqui.
protocol DeloadDecisionsStoring: AnyObject {
    /// As decisões gravadas, ou `DeloadDecisions()` (tudo `nil`) quando não há nenhuma ou o
    /// arquivo não pôde ser lido. Nunca lança: sem decisões, vale o comportamento automático.
    func load() -> DeloadDecisions

    /// Substitui as decisões gravadas por `decisions`.
    func save(_ decisions: DeloadDecisions) throws
}

/// Falhas ao gravar as decisões de semana leve.
enum DeloadDecisionsStoreError: Error, Equatable {
    /// Não há onde gravar (a pasta Application Support não pôde ser resolvida).
    case storageUnavailable
}
