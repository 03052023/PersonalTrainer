import Foundation
import SwiftData
import TrainerCore

/// Implementação de `SessionCoordinating` sobre SwiftData (ARCHITECTURE §7, AR-2): o único lugar do
/// app que cria, altera ou apaga `WorkoutSessionModel`, `SessionExerciseModel` e `SetLogModel`.
///
/// Cada `apply` segue os três passos da §7: (1) descarta o evento se `appliedEvents` já o conhece,
/// (2) aplica ao `ModelContext` e salva **imediatamente** (RNF-03/RF-06), (3) publica em
/// `eventsApplied` para observadores (HealthKit em M2, Watch em M3). Roda inteiro no `MainActor`
/// porque `@Model` não é `Sendable` (ARCHITECTURE §10).
///
/// Vive pelo processo inteiro (pertence ao `AppEnvironment`); por isso não encerra os streams em
/// `deinit`. Continuations de consumidores que cancelaram a iteração são descartadas no próximo
/// `yield`, quando o resultado vem `.terminated`.
@MainActor
final class SessionCoordinator: SessionCoordinating {
    private let modelContext: ModelContext
    private let appliedEvents: AppliedEventStore
    /// Um consumidor por `AsyncStream`; cada leitura de `eventsApplied` acrescenta uma entrada.
    private var continuations: [AsyncStream<SessionEvent>.Continuation] = []

    init(modelContext: ModelContext, appliedEvents: AppliedEventStore) {
        self.modelContext = modelContext
        self.appliedEvents = appliedEvents
    }

    // MARK: - SessionCoordinating

    /// O protocolo não lança; uma falha de fetch (store inacessível) aparece como "sem sessão
    /// ativa", e o próximo `startSession`, que usa a versão lançante, expõe o erro real.
    var activeSession: WorkoutSessionModel? {
        try? fetchActiveSession()
    }

    func session(withID id: UUID) -> WorkoutSessionModel? {
        try? fetchSession(uuid: id)
    }

    func startSession(plan: SessionPlan, now: Date, source: DeviceSource) throws -> UUID {
        if let active = try fetchActiveSession() {
            throw SessionCoordinatorError.sessionAlreadyInProgress(active.uuid)
        }

        // `programDayUUID`/`programDayName` são cópias, não relação: editar o programa depois não
        // reescreve o histórico (ARCHITECTURE §5, decisão 3; AR-10).
        let session = WorkoutSessionModel(
            uuid: UUID(),
            programDayUUID: plan.programDayID,
            programDayName: plan.programDayName,
            statusRaw: SessionStatus.inProgress.rawValue,
            startedAt: now,
            endedAt: nil,
            notes: "",
            hkWorkoutUUID: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            isDeload: false,
            sourceRaw: source.rawValue
        )
        // Inserir antes de ligar relações é o caminho mais previsível do SwiftData (SchemaV1Tests).
        modelContext.insert(session)

        // `order` é a posição no plano (já ordenado por `target.order`): 0-based e sem buracos,
        // que é o que a UI precisa para listar e para achar "o próximo exercício".
        for (order, planned) in plan.exercises.enumerated() {
            let prescription = planned.prescription
            let sessionExercise = SessionExerciseModel(
                // O mesmo id do plano, para a UI referenciar o exercício antes e depois do início.
                uuid: planned.id,
                order: order,
                exerciseUUID: planned.exercise.id,
                exerciseName: planned.exercise.name,
                prescribedLoad: prescription.load,
                prescribedSets: prescription.sets,
                prescribedRepMin: prescription.repMin,
                prescribedRepMax: prescription.repMax,
                prescribedRIR: prescription.targetRIR,
                restSeconds: prescription.restSeconds,
                noteRaw: prescription.note.rawValue,
                wasSkipped: false,
                substitutedFromUUID: nil
            )
            // Atribuído fora do init: o campo é do SchemaV2 (T2.11) e a posição do parâmetro no
            // init é irrelevante aqui. Sem ele a 1ª série pré-preenchia `repMin` mesmo em `hold`
            // (SPEC P5).
            sessionExercise.prescribedTargetReps = prescription.targetReps
            modelContext.insert(sessionExercise)
            // Só navegação (`nullify`); `nil` se o catálogo não tem o exercício. O snapshot acima
            // já basta para exibir e para o histórico, que filtra por `exerciseUUID`.
            sessionExercise.exercise = try fetchExercise(uuid: planned.exercise.id)
            session.exercises.append(sessionExercise)
        }

        try modelContext.save()

        // Registrado direto nos streams, sem passar por `apply`: o evento não carrega o plano, então
        // não há como "aplicá-lo" (ver nota em `SessionCoordinating.startSession`).
        publish(SessionEvent(
            sessionID: session.uuid,
            occurredAt: now,
            source: source,
            kind: .sessionStarted(programDayID: plan.programDayID)
        ))
        return session.uuid
    }

    func apply(_ event: SessionEvent) throws {
        // Passo 1 (ARCHITECTURE §7): duplicata por `id` é ignorada em silêncio (SPEC RF-22).
        if appliedEvents.contains(event.id) {
            return
        }

        guard let session = try fetchSession(uuid: event.sessionID) else {
            throw SessionCoordinatorError.sessionNotFound(event.sessionID)
        }

        switch event.kind {
        case .sessionStarted:
            // A sessão já existe (foi criada por `startSession`); nada a fazer além de registrar.
            break

        case let .heartRateSummary(averageBPM, maxBPM, hkWorkoutUUID):
            // Permitido após finalizar: o resumo do relógio chega depois do `sessionFinished`.
            // Só exibição; nunca entra no motor (SPEC P12, AGENTS R2).
            // O evento só preenche, nunca apaga. Ele não tem opcionais: FC 0 significa "sem FC" e
            // fica `nil` na sessão (não "FC 0", que iria para o backup e para a revisão como leitura
            // real). Um UUID `nil` não desfaz o vínculo que outro escritor já gravou (ex.: o resumo
            // do relógio chegando enquanto o gravador do iPhone espera o HealthKit).
            if averageBPM.isFinite, averageBPM > 0 {
                session.avgHeartRate = averageBPM
            }
            if maxBPM.isFinite, maxBPM > 0 {
                session.maxHeartRate = maxBPM
            }
            if let hkWorkoutUUID {
                session.hkWorkoutUUID = hkWorkoutUUID
            }

        case let .setLogged(sessionExerciseID, setID, index, load, reps, rir, isWarmup):
            try requireInProgress(session)
            try insertSet(
                in: session,
                sessionExerciseID: sessionExerciseID,
                setID: setID,
                index: index,
                load: load,
                reps: reps,
                rir: rir,
                isWarmup: isWarmup,
                event: event
            )

        case let .setUpdated(setID, load, reps, rir):
            try requireInProgress(session)
            guard let setLog = try findSet(withID: setID, in: session) else {
                throw SessionCoordinatorError.setNotFound(setID)
            }
            // Último que escreve vence, por `occurredAt` (ARCHITECTURE §7, regra de conflito).
            if event.occurredAt >= setLog.updatedAt {
                setLog.load = load
                setLog.reps = reps
                setLog.rir = rir
                setLog.updatedAt = event.occurredAt
            }

        case .setDeleted(let setID):
            try requireInProgress(session)
            guard let setLog = try findSet(withID: setID, in: session) else {
                throw SessionCoordinatorError.setNotFound(setID)
            }
            modelContext.delete(setLog)

        case .exerciseSkipped(let sessionExerciseID):
            try requireInProgress(session)
            let sessionExercise = try findSessionExercise(withID: sessionExerciseID, in: session)
            // Séries já registradas são mantidas (RF-10).
            sessionExercise.wasSkipped = true

        case let .exerciseSubstituted(sessionExerciseID, newExerciseID):
            try requireInProgress(session)
            let sessionExercise = try findSessionExercise(withID: sessionExerciseID, in: session)
            guard let newExercise = try fetchExercise(uuid: newExerciseID) else {
                throw SessionCoordinatorError.exerciseNotFound(newExerciseID)
            }
            // Vale só para esta sessão (RF-11); a prescrição copiada permanece a do original.
            sessionExercise.substitutedFromUUID = sessionExercise.exerciseUUID
            sessionExercise.exerciseUUID = newExercise.uuid
            sessionExercise.exerciseName = newExercise.name
            sessionExercise.exercise = newExercise

        case .sessionFinished(let endedAt):
            try requireInProgress(session)
            session.statusRaw = SessionStatus.completed.rawValue
            session.endedAt = endedAt

        case .sessionAbandoned(let endedAt):
            try requireInProgress(session)
            // Séries registradas continuam contando para o histórico (SPEC P3/S2).
            session.statusRaw = SessionStatus.abandoned.rawValue
            session.endedAt = endedAt
        }

        // Passo 2: salvar já. Matar o app não perde nenhuma série concluída (RF-06).
        try modelContext.save()
        appliedEvents.insert(event.id)
        // Passo 3: observadores.
        publish(event)
    }

    /// Apaga a sessão com tudo o que pende dela (T2.13, SPEC RF-19), em qualquer status.
    ///
    /// - A regra `cascade` de `WorkoutSessionModel.exercises` e de `SessionExerciseModel.sets`
    ///   apaga exercícios e séries no mesmo `save`; o catálogo fica intacto (`nullify`).
    /// - Não há estado a limpar: `activeSession` é lido do store, então apagar a sessão em
    ///   andamento já a faz voltar `nil`.
    /// - A próxima prescrição e o próximo dia mudam sozinhos porque são derivados do histórico
    ///   (ADR 003); não existe cache de progressão para invalidar.
    /// - Nenhum evento é publicado em `eventsApplied`: `SessionEvent.Kind` não tem um caso de
    ///   exclusão e acrescentar um muda o formato de sync (`SyncSchema`), decisão que fica para
    ///   o M3, quando o relógio passar a espelhar sessões. O `HKWorkout` já gravado ou vinculado
    ///   continua no app Saúde; apagá-lo é com o usuário.
    func deleteSession(id: UUID) throws {
        guard let session = try fetchSession(uuid: id) else {
            throw SessionCoordinatorError.sessionNotFound(id)
        }
        modelContext.delete(session)
        try modelContext.save()
    }

    /// Troca o exercício de um `SessionExerciseModel` da sessão em andamento e substitui o
    /// snapshot de prescrição pelo de `planned` (RF-34; `planned` vem de
    /// `SessionPlanning.substitutionPlan`, calculado com o histórico do NOVO exercício, P3).
    ///
    /// A troca em si passa por `apply(.exerciseSubstituted)`, para que o evento seja o mesmo que
    /// o relógio emite (M3) e chegue aos observadores. A prescrição nova é escrita no contexto
    /// antes do `apply`, e o único `save()` (o do `apply`) grava troca e prescrição juntas: nunca
    /// fica no store o exercício novo com a prescrição do antigo. Se o `apply` lançar (exercício
    /// fora do catálogo ou falha no `save`), `rollback()` descarta a prescrição escrita.
    /// Validações feitas antes de escrever qualquer coisa, para que uma recusa não deixe nada
    /// pela metade:
    /// - sessão inexistente → `sessionNotFound`; fora de `inProgress` → `sessionNotInProgress`;
    /// - exercício da sessão inexistente → `sessionExerciseNotFound`;
    /// - exercício que já tem séries (inclusive aquecimento) → `unsupported`: as séries
    ///   pertencem ao exercício antigo e passariam a contar como histórico do novo.
    ///
    /// Trocar pelo mesmo exercício é no-op (não registra `substitutedFromUUID` apontando para si).
    /// O `id` de `planned` não é usado: vale `sessionExerciseID`.
    func substituteExercise(sessionID: UUID, sessionExerciseID: UUID, with planned: PlannedExercise, now: Date) throws {
        guard let session = try fetchSession(uuid: sessionID) else {
            throw SessionCoordinatorError.sessionNotFound(sessionID)
        }
        try requireInProgress(session)
        let sessionExercise = try findSessionExercise(withID: sessionExerciseID, in: session)
        guard sessionExercise.sets.isEmpty else {
            throw SessionCoordinatorError.unsupported
        }
        if sessionExercise.exerciseUUID == planned.exercise.id {
            return
        }

        // O `apply` mantém a prescrição do original (correto para o evento cru do relógio);
        // aqui ela passa a ser a do substituto, que começa em calibração se nunca foi feito.
        let prescription = planned.prescription
        sessionExercise.prescribedLoad = prescription.load
        sessionExercise.prescribedSets = prescription.sets
        sessionExercise.prescribedRepMin = prescription.repMin
        sessionExercise.prescribedRepMax = prescription.repMax
        sessionExercise.prescribedRIR = prescription.targetRIR
        sessionExercise.restSeconds = prescription.restSeconds
        sessionExercise.noteRaw = prescription.note.rawValue
        sessionExercise.prescribedTargetReps = prescription.targetReps

        // Troca `exerciseUUID`, nome e relação, guarda `substitutedFromUUID` e salva tudo num só
        // `save()`. Lança `exerciseNotFound` antes do `save` se o novo exercício não está no
        // catálogo.
        do {
            try apply(SessionEvent(
                sessionID: sessionID,
                occurredAt: now,
                source: .iphone,
                kind: .exerciseSubstituted(sessionExerciseID: sessionExerciseID, newExerciseID: planned.exercise.id)
            ))
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Só leitura, para o gravador do Saúde revisitar sessões recentes (reconciliação, RF-13/RF-14).
    /// Uma falha de fetch vira lista vazia: reconciliar é melhor esforço e roda de novo depois.
    func completedSessions(startedSince date: Date) -> [WorkoutSessionModel] {
        // `#Predicate` só compara com valores capturados; o `rawValue` vai para um `let`.
        let completed = SessionStatus.completed.rawValue
        let descriptor = FetchDescriptor<WorkoutSessionModel>(
            predicate: #Predicate<WorkoutSessionModel> { $0.statusRaw == completed && $0.startedAt >= date },
            sortBy: [SortDescriptor(\WorkoutSessionModel.startedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Cada leitura cria um stream novo (fan-out): HealthKit e Watch consomem independentes.
    /// Buffer ilimitado para que um consumidor lento nunca perca evento.
    var eventsApplied: AsyncStream<SessionEvent> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: SessionEvent.self,
            bufferingPolicy: .unbounded
        )
        continuations.append(continuation)
        return stream
    }

    // MARK: - Mutações

    private func insertSet(
        in session: WorkoutSessionModel,
        sessionExerciseID: UUID,
        setID: UUID,
        index: Int,
        load: Double,
        reps: Int,
        rir: Int?,
        isWarmup: Bool,
        event: SessionEvent
    ) throws {
        // `SetLogModel.uuid` é `.unique`: inserir de novo faria upsert silencioso (ARCHITECTURE
        // §15). Uma série com esse id, venha de qual evento vier, já está aplicada.
        if try fetchSet(uuid: setID) != nil {
            return
        }
        let sessionExercise = try findSessionExercise(withID: sessionExerciseID, in: session)
        let setLog = SetLogModel(
            uuid: setID,
            index: index,
            load: load,
            reps: reps,
            rir: rir,
            isWarmup: isWarmup,
            completedAt: event.occurredAt,
            sourceRaw: event.source.rawValue,
            updatedAt: event.occurredAt
        )
        modelContext.insert(setLog)
        sessionExercise.sets.append(setLog)
    }

    private func requireInProgress(_ session: WorkoutSessionModel) throws {
        guard session.status == .inProgress else {
            throw SessionCoordinatorError.sessionNotInProgress(session.uuid)
        }
    }

    private func findSessionExercise(withID id: UUID, in session: WorkoutSessionModel) throws -> SessionExerciseModel {
        guard let match = session.exercises.first(where: { $0.uuid == id }) else {
            throw SessionCoordinatorError.sessionExerciseNotFound(id)
        }
        return match
    }

    /// Busca no store (nunca devolve um modelo já apagado) e confere que a série pertence à sessão
    /// do evento: uma série de outra sessão é "não encontrada" aqui.
    private func findSet(withID id: UUID, in session: WorkoutSessionModel) throws -> SetLogModel? {
        guard let setLog = try fetchSet(uuid: id) else {
            return nil
        }
        guard setLog.sessionExercise?.session?.uuid == session.uuid else {
            return nil
        }
        return setLog
    }

    private func publish(_ event: SessionEvent) {
        continuations = continuations.filter { continuation in
            switch continuation.yield(event) {
            case .terminated:
                return false
            default:
                return true
            }
        }
    }

    // MARK: - Fetches

    private func fetchActiveSession() throws -> WorkoutSessionModel? {
        // `#Predicate` só compara com valores capturados; o `rawValue` vai para um `let`.
        let inProgress = SessionStatus.inProgress.rawValue
        var descriptor = FetchDescriptor<WorkoutSessionModel>(
            predicate: #Predicate<WorkoutSessionModel> { $0.statusRaw == inProgress }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchSession(uuid: UUID) throws -> WorkoutSessionModel? {
        var descriptor = FetchDescriptor<WorkoutSessionModel>(
            predicate: #Predicate<WorkoutSessionModel> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchExercise(uuid: UUID) throws -> ExerciseModel? {
        var descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate<ExerciseModel> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchSet(uuid: UUID) throws -> SetLogModel? {
        var descriptor = FetchDescriptor<SetLogModel>(
            predicate: #Predicate<SetLogModel> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
