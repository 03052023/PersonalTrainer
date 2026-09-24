import Foundation
import os
import TrainerCore

/// Leva cada sessão finalizada para o app Saúde (ARCHITECTURE §8; T2.1, T2.2; SPEC RF-13, RF-14):
/// observa `coordinator.eventsApplied` e, em `sessionFinished`, vincula o treino de força que outro
/// app já gravou (tipicamente o app Exercício do Watch) ou grava um `HKWorkout` novo, lê o resumo de
/// FC do intervalo e guarda tudo na sessão com um `SessionEvent.heartRateSummary` aplicado pelo
/// coordinator (o único caminho de escrita, ARCHITECTURE §7).
///
/// - Invariante "um `HKWorkout` por sessão": `WorkoutSessionModel.hkWorkoutUUID` é a trava. Sessão
///   que já tem UUID nunca ganha um treino gravado de novo, e o evento aplicado grava o UUID do treino.
/// - Antes de aplicar o evento, a sessão é relida: se ela foi apagada ou se outro escritor preencheu a
///   trava durante os `await`, nada é gravado por cima (o coordinator também nunca apaga dados com um
///   evento sem valores).
/// - Reconciliação (`reconcileRecentSessions(now:)`): no fim da sessão o treino do app Exercício pode
///   ainda não existir (o usuário encerra o relógio depois) e as amostras de FC chegam ao iPhone em
///   lotes. A cada volta do app ao primeiro plano, as sessões recentes são revisitadas: o treino do
///   iPhone que virou duplicata é apagado e o do relógio vinculado, e a FC é relida.
/// - Nada aqui interrompe a sessão (AGENTS §4): toda falha do HealthKit só vai para o log e o app
///   segue mostrando "FC indisponível" (ARCHITECTURE §15).
/// - Autorização só na primeira sessão finalizada, nunca no launch (AGENTS §7): a reconciliação nunca
///   pede autorização, só usa a que já foi dada neste processo. Só um pedido bem sucedido fica
///   memorizado; depois de uma recusa o app pergunta de novo na sessão seguinte (o sistema não reabre
///   o diálogo, mas assim uma permissão dada em Ajustes passa a valer).
/// - Sem escrita autorizada, ainda vincula o treino de outro app e lê a FC: o status de leitura é
///   opaco e pode estar liberado mesmo com a escrita negada.
/// - `averageBPM`/`maxBPM` iguais a 0 no evento significam "sem FC": o evento não tem opcionais para
///   FC, e o UUID do treino precisa ser gravado mesmo sem amostras. O coordinator guarda `nil`.
///
/// A sessão da M2 é sempre do iPhone; a trava para sessões com `source == .watch` (o relógio grava o
/// próprio treino) é T3.8.
@MainActor
final class HealthKitWorkoutRecorder {
    /// Janela da reconciliação, contada a partir do início da sessão. 48 h cobrem quem treina à
    /// noite e só volta ao app na noite seguinte.
    static let reconciliationWindow: TimeInterval = 48 * 3_600

    private let healthKit: any HealthKitServicing
    private let coordinator: any SessionCoordinating
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer", category: "HealthKit")
    private var listener: Task<Void, Never>?
    /// Em memória de propósito: o sistema lembra a resposta do usuário, e pedir de novo a cada
    /// launch não mostra diálogo nenhum.
    private var hasWriteAuthorization = false
    /// Sessões com uma passada em andamento (fim de sessão ou reconciliação). As duas passadas
    /// intercalam nos `await`; sem isto, as duas poderiam gravar um treino para a mesma sessão.
    private var sessionsInFlight: Set<UUID> = []
    private var isReconciling = false

    init(healthKit: any HealthKitServicing, coordinator: any SessionCoordinating) {
        self.healthKit = healthKit
        self.coordinator = coordinator
    }

    /// Passa a observar o coordinator. Chamar de novo sem `stop()` não cria um segundo observador
    /// (dois observadores gravariam dois treinos para a mesma sessão).
    func start() {
        guard listener == nil else {
            return
        }
        // Assina já, de forma síncrona: um `sessionFinished` publicado antes de a `Task` começar a
        // rodar fica no buffer do stream em vez de se perder.
        let events = coordinator.eventsApplied
        listener = Task { [weak self] in
            for await event in events {
                guard let self else {
                    return
                }
                await self.process(event)
            }
        }
    }

    /// Para de observar. Um processamento em andamento termina; eventos seguintes são ignorados.
    func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Trata um evento aplicado. Só `sessionFinished` interessa: sessão abandonada não vai para o
    /// Saúde (RF-13 fala em "ao finalizar"). Interno, e não privado, para os testes aguardarem o
    /// processamento sem depender de tempo; em produção só o laço de `start()` chama.
    func process(_ event: SessionEvent) async {
        guard case .sessionFinished(let endedAt) = event.kind else {
            return
        }
        await recordFinishedSession(id: event.sessionID, endedAt: endedAt, mayRequestAuthorization: true)
    }

    /// Revisita as sessões concluídas que começaram até `reconciliationWindow` antes de `now`
    /// (RF-13, RF-14; CA2-1, CA2-2). Chamado quando o app volta ao primeiro plano; uma passada por
    /// vez, e chamadas durante uma passada são ignoradas. Para cada sessão:
    /// - sem treino vinculado: refaz o fluxo do fim de sessão (vincular o treino do relógio, ou gravar
    ///   o próprio se a escrita já foi autorizada neste processo) sem pedir autorização;
    /// - com treino vinculado: se agora existe um treino de outro app cobrindo a sessão e ele não é o
    ///   vinculado, apaga o treino deste app (só esse pode ser apagado) e vincula o do relógio;
    /// - relê a FC e só aplica um evento quando algo mudou (vínculo novo ou FC diferente da guardada).
    func reconcileRecentSessions(now: Date) async {
        guard healthKit.isAvailable, !isReconciling else {
            return
        }
        isReconciling = true
        defer { isReconciling = false }

        // Copia antes de qualquer `await`: os modelos podem ser apagados enquanto o HealthKit responde.
        let since = now.addingTimeInterval(-Self.reconciliationWindow)
        let snapshots = coordinator.completedSessions(startedSince: since).compactMap { SessionSnapshot(session: $0) }
        for snapshot in snapshots {
            await reconcile(snapshot)
        }
    }

    // MARK: - Fluxo

    /// O que a reconciliação precisa da sessão, copiado do modelo antes dos `await`.
    private struct SessionSnapshot {
        let id: UUID
        let startedAt: Date
        let endedAt: Date
        let hkWorkoutUUID: UUID?
        let averageBPM: Double?
        let maxBPM: Double?

        init?(session: WorkoutSessionModel) {
            guard let endedAt = session.endedAt, endedAt > session.startedAt else {
                return nil
            }
            self.id = session.uuid
            self.startedAt = session.startedAt
            self.endedAt = endedAt
            self.hkWorkoutUUID = session.hkWorkoutUUID
            self.averageBPM = session.avgHeartRate
            self.maxBPM = session.maxHeartRate
        }
    }

    private func recordFinishedSession(id sessionID: UUID, endedAt: Date, mayRequestAuthorization: Bool) async {
        guard let session = coordinator.session(withID: sessionID) else {
            logger.error("Sessão \(sessionID.uuidString, privacy: .public) não encontrada; nada enviado ao Saúde.")
            return
        }
        guard session.hkWorkoutUUID == nil else {
            return
        }
        guard healthKit.isAvailable, !sessionsInFlight.contains(sessionID) else {
            return
        }
        // Copia antes de qualquer `await`: o modelo pode ser apagado enquanto o HealthKit responde.
        let startedAt = session.startedAt
        let storedAverage = session.avgHeartRate
        let storedMax = session.maxHeartRate
        guard endedAt > startedAt else {
            logger.error("Sessão \(sessionID.uuidString, privacy: .public) termina antes de começar; nada enviado ao Saúde.")
            return
        }
        sessionsInFlight.insert(sessionID)
        defer { sessionsInFlight.remove(sessionID) }

        let canWrite: Bool
        if mayRequestAuthorization {
            canWrite = await ensureWriteAuthorization()
        } else {
            canWrite = hasWriteAuthorization
        }

        let lookup = await lookUpOverlappingWorkout(start: startedAt, end: endedAt)
        var workoutUUID: UUID?
        switch lookup {
        case .linked(let linkedUUID):
            // RF-13: o treino do app Exercício já está no Saúde; vincula em vez de duplicar.
            workoutUUID = linkedUUID
        case .notFound:
            if canWrite, !lockWasTakenMeanwhile(sessionID: sessionID) {
                workoutUUID = await saveWorkout(start: startedAt, end: endedAt, sessionID: sessionID)
            }
        case .failed:
            // Sem saber se já existe treino de outro app, gravar arriscaria duplicar (RF-13).
            break
        }

        let summary = await readHeartRate(start: startedAt, end: endedAt)
        let heartRateChanged = Self.heartRateDiffers(summary, averageBPM: storedAverage, maxBPM: storedMax)
        guard workoutUUID != nil || heartRateChanged else {
            return
        }
        // A sessão pode ter sido apagada, ou vinculada por outro escritor, durante os `await`.
        guard let current = coordinator.session(withID: sessionID) else {
            if workoutUUID != nil {
                logger.notice("Sessão \(sessionID.uuidString, privacy: .public) apagada enquanto o Saúde respondia; o treino no Saúde fica com o usuário.")
            }
            return
        }
        guard current.hkWorkoutUUID == nil else {
            return
        }
        apply(summary: summary, workoutUUID: workoutUUID, sessionID: sessionID, endedAt: endedAt)
    }

    private func reconcile(_ snapshot: SessionSnapshot) async {
        guard let linkedWorkout = snapshot.hkWorkoutUUID else {
            await recordFinishedSession(id: snapshot.id, endedAt: snapshot.endedAt, mayRequestAuthorization: false)
            return
        }
        guard !sessionsInFlight.contains(snapshot.id) else {
            return
        }
        sessionsInFlight.insert(snapshot.id)
        defer { sessionsInFlight.remove(snapshot.id) }

        // RF-13: o treino do relógio pode ter chegado depois do fim da sessão, quando o iPhone já
        // tinha gravado o próprio. `findOverlappingStrengthWorkout` ignora treinos deste app, então um
        // resultado diferente do vinculado quer dizer que o vinculado é o do iPhone (ou um treino de
        // outro app com sobreposição menor).
        var workoutUUID = linkedWorkout
        let lookup = await lookUpOverlappingWorkout(start: snapshot.startedAt, end: snapshot.endedAt)
        if case .linked(let foreignWorkout) = lookup, foreignWorkout != linkedWorkout {
            let removed = await removeOwnWorkout(sessionID: snapshot.id)
            if removed {
                workoutUUID = foreignWorkout
            }
        }

        let summary = await readHeartRate(start: snapshot.startedAt, end: snapshot.endedAt)
        let relinked = workoutUUID != linkedWorkout
        let heartRateChanged = Self.heartRateDiffers(summary, averageBPM: snapshot.averageBPM, maxBPM: snapshot.maxBPM)
        guard relinked || heartRateChanged else {
            return
        }
        // Outro escritor pode ter mudado a sessão durante os `await` (ex.: exclusão pelo Histórico).
        guard let current = coordinator.session(withID: snapshot.id), current.hkWorkoutUUID == linkedWorkout else {
            return
        }
        apply(summary: summary, workoutUUID: workoutUUID, sessionID: snapshot.id, endedAt: snapshot.endedAt)
    }

    // MARK: - Passos (cada falha só loga)

    private enum OverlapLookup {
        case linked(UUID)
        case notFound
        case failed
    }

    private func ensureWriteAuthorization() async -> Bool {
        if hasWriteAuthorization {
            return true
        }
        do {
            try await healthKit.requestAuthorization()
            hasWriteAuthorization = true
            return true
        } catch {
            logger.notice("Sem autorização para gravar treinos no Saúde: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func lookUpOverlappingWorkout(start: Date, end: Date) async -> OverlapLookup {
        do {
            if let linkedUUID = try await healthKit.findOverlappingStrengthWorkout(start: start, end: end) {
                return .linked(linkedUUID)
            }
            return .notFound
        } catch {
            logger.error("Falha ao procurar treino sobreposto no Saúde: \(String(describing: error), privacy: .public)")
            return .failed
        }
    }

    /// A trava pode ter sido preenchida durante os `await` anteriores (ex.: resumo do relógio na M3).
    /// Sessão apagada conta como trava tomada: não há mais para quem gravar o treino.
    private func lockWasTakenMeanwhile(sessionID: UUID) -> Bool {
        guard let session = coordinator.session(withID: sessionID) else {
            return true
        }
        return session.hkWorkoutUUID != nil
    }

    private func saveWorkout(start: Date, end: Date, sessionID: UUID) async -> UUID? {
        do {
            return try await healthKit.saveStrengthWorkout(start: start, end: end, sessionUUID: sessionID)
        } catch {
            logger.error("Falha ao gravar treino no Saúde: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// `true` quando nenhum treino deste app sobrou para a sessão no Saúde.
    private func removeOwnWorkout(sessionID: UUID) async -> Bool {
        do {
            try await healthKit.removeOwnStrengthWorkout(sessionUUID: sessionID)
            return true
        } catch {
            logger.error("Falha ao apagar o treino duplicado do iPhone no Saúde: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func readHeartRate(start: Date, end: Date) async -> HeartRateSummary? {
        do {
            return try await healthKit.heartRateSummary(start: start, end: end)
        } catch {
            logger.error("Falha ao ler FC no Saúde: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// `true` quando `summary` traz FC e ela difere da que a sessão guarda: evita aplicar o mesmo
    /// resumo de novo a cada reconciliação.
    private static func heartRateDiffers(_ summary: HeartRateSummary?, averageBPM: Double?, maxBPM: Double?) -> Bool {
        guard let summary, summary.averageBPM > 0 else {
            return false
        }
        return summary.averageBPM != averageBPM || summary.maxBPM != maxBPM
    }

    /// FC só para exibição (SPEC P12, AGENTS R2): o evento guarda média/máxima na sessão e nada
    /// disso chega ao motor. `occurredAt` é o fim da sessão, o instante a que o resumo se refere,
    /// o que também evita ler o relógio do sistema aqui.
    private func apply(summary: HeartRateSummary?, workoutUUID: UUID?, sessionID: UUID, endedAt: Date) {
        let event = SessionEvent(
            sessionID: sessionID,
            occurredAt: endedAt,
            source: .iphone,
            kind: .heartRateSummary(
                averageBPM: summary?.averageBPM ?? 0,
                maxBPM: summary?.maxBPM ?? 0,
                hkWorkoutUUID: workoutUUID
            )
        )
        do {
            try coordinator.apply(event)
        } catch {
            logger.error("Falha ao guardar o resumo do Saúde na sessão: \(String(describing: error), privacy: .public)")
        }
    }
}
