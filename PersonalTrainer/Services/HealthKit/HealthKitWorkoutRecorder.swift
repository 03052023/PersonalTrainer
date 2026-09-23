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
///   que já tem UUID nunca é processada de novo, e o evento aplicado grava o UUID do treino.
/// - Nada aqui interrompe a sessão (AGENTS §4): toda falha do HealthKit só vai para o log e o app
///   segue mostrando "FC indisponível" (ARCHITECTURE §15).
/// - Autorização só na primeira sessão finalizada, nunca no launch (AGENTS §7). Só um pedido bem
///   sucedido fica memorizado; depois de uma recusa o app pergunta de novo na sessão seguinte (o
///   sistema não reabre o diálogo, mas assim uma permissão dada em Ajustes passa a valer).
/// - Sem escrita autorizada, ainda vincula o treino de outro app e lê a FC: o status de leitura é
///   opaco e pode estar liberado mesmo com a escrita negada.
/// - `averageBPM`/`maxBPM` iguais a 0 no evento significam "sem FC": o evento não tem opcionais para
///   FC, e o UUID do treino precisa ser gravado mesmo sem amostras.
///
/// A sessão da M2 é sempre do iPhone; a trava para sessões com `source == .watch` (o relógio grava o
/// próprio treino) é T3.8.
@MainActor
final class HealthKitWorkoutRecorder {
    private let healthKit: any HealthKitServicing
    private let coordinator: any SessionCoordinating
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer", category: "HealthKit")
    private var listener: Task<Void, Never>?
    /// Em memória de propósito: o sistema lembra a resposta do usuário, e pedir de novo a cada
    /// launch não mostra diálogo nenhum.
    private var hasWriteAuthorization = false

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
        await recordFinishedSession(id: event.sessionID, endedAt: endedAt)
    }

    // MARK: - Fluxo

    private func recordFinishedSession(id sessionID: UUID, endedAt: Date) async {
        guard let session = coordinator.session(withID: sessionID) else {
            logger.error("Sessão \(sessionID.uuidString, privacy: .public) não encontrada; nada enviado ao Saúde.")
            return
        }
        guard session.hkWorkoutUUID == nil else {
            return
        }
        guard healthKit.isAvailable else {
            return
        }
        // Copia antes de qualquer `await`: o modelo pode ser apagado enquanto o HealthKit responde.
        let startedAt = session.startedAt
        guard endedAt > startedAt else {
            logger.error("Sessão \(sessionID.uuidString, privacy: .public) termina antes de começar; nada enviado ao Saúde.")
            return
        }

        let canWrite = await ensureWriteAuthorization()

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
        guard workoutUUID != nil || summary != nil else {
            return
        }
        apply(summary: summary, workoutUUID: workoutUUID, sessionID: sessionID, endedAt: endedAt)
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
    private func lockWasTakenMeanwhile(sessionID: UUID) -> Bool {
        coordinator.session(withID: sessionID)?.hkWorkoutUUID != nil
    }

    private func saveWorkout(start: Date, end: Date, sessionID: UUID) async -> UUID? {
        do {
            return try await healthKit.saveStrengthWorkout(start: start, end: end, sessionUUID: sessionID)
        } catch {
            logger.error("Falha ao gravar treino no Saúde: \(String(describing: error), privacy: .public)")
            return nil
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
