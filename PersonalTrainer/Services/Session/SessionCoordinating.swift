import Foundation
import TrainerCore

/// Único caminho de escrita de sessões (ARCHITECTURE §7, AR-2). Views e ViewModels nunca tocam o
/// `ModelContext` para dados de sessão: produzem `SessionEvent`s (ou usam os atalhos abaixo) e o
/// coordinator aplica, salva imediatamente (RNF-03) e publica em `eventsApplied`.
///
/// Implementação concreta: `SessionCoordinator` (Services/Session/SessionCoordinator.swift, T1.3).
@MainActor
protocol SessionCoordinating: AnyObject {
    /// Sessão com `status == inProgress`, se houver. Há no máximo uma (RF-02).
    var activeSession: WorkoutSessionModel? { get }

    /// Busca por `uuid`. `nil` se não existe.
    func session(withID id: UUID) -> WorkoutSessionModel?

    /// Cria `WorkoutSessionModel` + um `SessionExerciseModel` por `PlannedExercise` (usando
    /// `PlannedExercise.id` como `uuid` e copiando a prescrição), salva e registra internamente um
    /// evento `sessionStarted` em `eventsApplied`. Lança `SessionCoordinatorError.sessionAlreadyInProgress`
    /// se já existe sessão em andamento.
    ///
    /// Nota de desenho: `SessionEvent.Kind.sessionStarted(programDayID:)` sozinho não carrega o plano;
    /// quando um evento desses chegar do relógio (M3), quem o recebe pede o plano ao `SessionPlanning`
    /// para o dia informado e chama este método.
    func startSession(plan: SessionPlan, now: Date, source: DeviceSource) throws -> UUID

    /// Aplica um evento de forma idempotente (mesmo `event.id` duas vezes = uma alteração) e salva.
    /// Eventos para sessões inexistentes lançam `SessionCoordinatorError.sessionNotFound`.
    func apply(_ event: SessionEvent) throws

    /// Eventos efetivamente aplicados, na ordem, para observadores (HealthKit em M2, Watch em M3).
    var eventsApplied: AsyncStream<SessionEvent> { get }

    // M2 — declarados aqui para despacho dinâmico; implementação padrão (lança `.unsupported`)
    // na extensão abaixo, para doubles antigos continuarem compilando.
    func deleteSession(id: UUID) throws
    func substituteExercise(sessionID: UUID, sessionExerciseID: UUID, with planned: PlannedExercise, now: Date) throws
    func completedSessions(startedSince date: Date) -> [WorkoutSessionModel]
}

enum SessionCoordinatorError: Error, Equatable {
    case sessionNotFound(UUID)
    case sessionNotInProgress(UUID)
    case sessionAlreadyInProgress(UUID)
    case sessionExerciseNotFound(UUID)
    case setNotFound(UUID)
    case exerciseNotFound(UUID)
    /// A implementação não suporta a operação (doubles de preview/teste antigos).
    case unsupported
}

// MARK: - Operações do M2 (contrato; implementadas por `SessionCoordinator` em T2.9/T2.13)

/// Requisitos adicionados no M2. Ficam num protocolo separado com implementação padrão
/// para que os doubles de preview/teste existentes continuem compilando sem mudanças.
extension SessionCoordinating {
    /// Apaga uma sessão e todas as suas séries (T2.13, SPEC RF-19). Permitido em qualquer status.
    /// O motor recalcula as prescrições por derivação do histórico (ADR 003).
    func deleteSession(id: UUID) throws {
        throw SessionCoordinatorError.unsupported
    }

    /// Troca um exercício da sessão em andamento por outro (RF-34): emite `exerciseSubstituted`
    /// (guarda `substitutedFromUUID`) e substitui o snapshot de prescrição pelo de `planned`
    /// (carga, séries, faixa, RIR, descanso, nota, `prescribedTargetReps`). Séries já registradas
    /// no exercício antigo são mantidas no mesmo `SessionExerciseModel` só se ainda não houver
    /// nenhuma; se houver, lança `SessionCoordinatorError.unsupported` (troque antes de começar).
    func substituteExercise(sessionID: UUID, sessionExerciseID: UUID, with planned: PlannedExercise, now: Date) throws {
        throw SessionCoordinatorError.unsupported
    }

    /// Sessões `completed` com `startedAt >= date`, da mais recente para a mais antiga. Só leitura:
    /// o gravador do Saúde revisita as sessões recentes (RF-13/RF-14, reconciliação). Implementação
    /// padrão devolve `[]` (doubles antigos: nada a reconciliar).
    func completedSessions(startedSince date: Date) -> [WorkoutSessionModel] {
        []
    }
}

// MARK: - Atalhos para a UI (constroem o evento e chamam `apply`)

extension SessionCoordinating {
    /// Registra uma série concluída (RF-03). `index` é 0-based e sequencial dentro do exercício.
    /// Devolve o `uuid` da nova `SetLogModel`.
    @discardableResult
    func logSet(
        sessionID: UUID,
        sessionExerciseID: UUID,
        index: Int,
        load: Double,
        reps: Int,
        rir: Int?,
        isWarmup: Bool,
        now: Date,
        source: DeviceSource = .iphone
    ) throws -> UUID {
        let setID = UUID()
        try apply(SessionEvent(
            sessionID: sessionID,
            occurredAt: now,
            source: source,
            kind: .setLogged(
                sessionExerciseID: sessionExerciseID,
                setID: setID,
                index: index,
                load: load,
                reps: reps,
                rir: rir,
                isWarmup: isWarmup
            )
        ))
        return setID
    }

    /// Corrige uma série já registrada (RF-19).
    func updateSet(sessionID: UUID, setID: UUID, load: Double, reps: Int, rir: Int?, now: Date, source: DeviceSource = .iphone) throws {
        try apply(SessionEvent(
            sessionID: sessionID,
            occurredAt: now,
            source: source,
            kind: .setUpdated(setID: setID, load: load, reps: reps, rir: rir)
        ))
    }

    /// Exclui uma série (RF-19).
    func deleteSet(sessionID: UUID, setID: UUID, now: Date, source: DeviceSource = .iphone) throws {
        try apply(SessionEvent(sessionID: sessionID, occurredAt: now, source: source, kind: .setDeleted(setID: setID)))
    }

    /// Marca o exercício como pulado (RF-10). Séries já registradas são mantidas.
    func skipExercise(sessionID: UUID, sessionExerciseID: UUID, now: Date, source: DeviceSource = .iphone) throws {
        try apply(SessionEvent(
            sessionID: sessionID,
            occurredAt: now,
            source: source,
            kind: .exerciseSkipped(sessionExerciseID: sessionExerciseID)
        ))
    }

    /// Finaliza a sessão (RF-02): `status = completed`, `endedAt = now`.
    func finishSession(sessionID: UUID, now: Date, source: DeviceSource = .iphone) throws {
        try apply(SessionEvent(sessionID: sessionID, occurredAt: now, source: source, kind: .sessionFinished(endedAt: now)))
    }

    /// Abandona a sessão (RF-19): `status = abandoned`, `endedAt = now`. Séries registradas continuam
    /// contando para o histórico (SPEC P3/S2).
    func abandonSession(sessionID: UUID, now: Date, source: DeviceSource = .iphone) throws {
        try apply(SessionEvent(sessionID: sessionID, occurredAt: now, source: source, kind: .sessionAbandoned(endedAt: now)))
    }
}
