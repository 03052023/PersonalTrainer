import Foundation
import TrainerCore

// TEMPORÁRIO (onda 3, branch v3/coach). O INTEGRADOR APAGA ESTE ARQUIVO ao mesclar v3/planner,
// junto com PersonalTrainerTests/Services/CoachPlannerShimTests.swift.
//
// Os cinco métodos abaixo são requisitos novos de `SessionPlanning` escritos em paralelo pelo
// agente do planejador (docs/V2-FINAL-CONTRACT.md §2.2), com as MESMAS assinaturas e os mesmos
// padrões (.inactive, no-op, [], nil). Aqui eles existem só para o `CoachService` compilar antes
// da mescla. Mantidos os dois arquivos, o compilador acusa "invalid redeclaration".
//
// Enquanto forem só extensão (sem requisito no protocolo), uma chamada por `any SessionPlanning`
// não chegaria ao double dos testes. Por isso o padrão consulta `CoachPlanningShim`: o double de
// `CoachServiceTests` adota esse protocolo num arquivo de teste também temporário, e os mesmos
// métodos passam a valer como implementação dos requisitos reais depois da mescla.

/// Ponte de teste temporária; some com este arquivo.
@MainActor
protocol CoachPlanningShim: AnyObject {
    func deloadStatus(now: Date) throws -> DeloadStatus
    func requestDeload(now: Date) throws
    func dismissDeload(now: Date) throws
    func completedSessionSummaries() throws -> [SessionSummary]
    func reviewInput(now: Date, recovery: RecoveryContext) throws -> ReviewInput?
}

extension SessionPlanning {
    /// Contrato §2.2: status da semana leve (`DeloadScheduler`); padrão `.inactive`.
    func deloadStatus(now: Date) throws -> DeloadStatus {
        guard let shim = self as? any CoachPlanningShim else {
            return .inactive
        }
        return try shim.deloadStatus(now: now)
    }

    /// Contrato §2.2: pedido manual de semana leve, SPEC §7.5 (c); padrão no-op.
    func requestDeload(now: Date) throws {
        guard let shim = self as? any CoachPlanningShim else {
            return
        }
        try shim.requestDeload(now: now)
    }

    /// Contrato §2.2: "Seguir normal" do C1; padrão no-op.
    func dismissDeload(now: Date) throws {
        guard let shim = self as? any CoachPlanningShim else {
            return
        }
        try shim.dismissDeload(now: now)
    }

    /// Contrato §2.2: todas as sessões registradas; padrão `[]`.
    func completedSessionSummaries() throws -> [SessionSummary] {
        guard let shim = self as? any CoachPlanningShim else {
            return []
        }
        return try shim.completedSessionSummaries()
    }

    /// Contrato §2.2: entrada da revisão periódica do programa ativo; padrão `nil`.
    func reviewInput(now: Date, recovery: RecoveryContext) throws -> ReviewInput? {
        guard let shim = self as? any CoachPlanningShim else {
            return nil
        }
        return try shim.reviewInput(now: now, recovery: recovery)
    }
}
