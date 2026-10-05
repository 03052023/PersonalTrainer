import Foundation
import os
import TrainerCore

/// Junta o que o pedido de avaliação precisa (SPEC §7.18 L3) e decide pela `RatingPromptPolicy`:
/// - do `RatingPromptStoring`: se o app veio da loja, a versão atual e o último pedido;
/// - do `SessionPlanning`: o histórico (`finishedSessionSummaries()`), de onde saem a primeira sessão
///   concluída, a contagem e como terminou a sessão que acabou de fechar;
/// - do `HealthKitWorkoutRecorder` (opcional; sem ele, vale "nada a gravar no Saúde"): como terminou a ida
///   ao Saúde.
///
/// Quando a regra deixa, chama a caixa do sistema (recebida de fora: só a view tem o `requestReview`) e grava
/// a versão e a data do pedido. Uma falha ao ler o histórico vale "não pede", com log. Nada aqui escreve no
/// `ModelContext` (AGENTS R4).
@MainActor
final class RatingPromptGate {
    private let store: any RatingPromptStoring
    private let planner: any SessionPlanning
    private let recorder: HealthKitWorkoutRecorder?
    /// AGENTS §4: `subsystem` = bundle id, `category` = nome do serviço.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer", category: "RatingPrompt")

    init(store: any RatingPromptStoring, planner: any SessionPlanning, recorder: HealthKitWorkoutRecorder?) {
        self.store = store
        self.planner = planner
        self.recorder = recorder
    }

    /// `false` fora da loja: quem chama nem precisa esperar o Saúde.
    var isStoreInstall: Bool {
        store.isStoreInstall
    }

    /// Como terminou a ida da sessão ao Saúde. Sem gravador (previews, testes, store que não abriu), nada é
    /// gravado no Saúde, então vale `notAttempted`.
    func healthOutcome(for sessionID: UUID) -> HealthRecordOutcome {
        recorder?.healthOutcome(for: sessionID) ?? .notAttempted
    }

    /// A entrada da `RatingPromptPolicy` para a sessão `sessionID`, que acabou de terminar; `nil` quando o
    /// histórico não pôde ser lido.
    func input(forSessionID sessionID: UUID, healthOutcome: HealthRecordOutcome) -> RatingPromptInput? {
        let sessions: [SessionSummary]
        do {
            sessions = try planner.finishedSessionSummaries()
        } catch {
            logger.error("Histórico ilegível; sem pedido de avaliação: \(String(describing: error), privacy: .public)")
            return nil
        }
        let last = store.lastRequest()
        return RatingPromptInput(
            firstCompletedSessionStart: RatingPromptPolicy.firstCompletedSessionStart(in: sessions),
            completedSessionCount: RatingPromptPolicy.completedSessionCount(in: sessions),
            sessionEnding: Self.sessionEnding(of: sessionID, in: sessions, healthOutcome: healthOutcome),
            currentVersion: store.currentVersion,
            lastRequestVersion: last?.version,
            lastRequestAt: last?.date,
            isStoreInstall: store.isStoreInstall
        )
    }

    /// L3 (c): a sessão concluída, com ao menos uma série de trabalho, e o Saúde sem falha. Abandonada (ou
    /// encerrada sem nenhuma série) é `abandoned`; sessão fora do histórico, Saúde com erro ou ainda sem
    /// resposta é `failed`. Sem o app Saúde ou sem permissão de gravar não é erro.
    static func sessionEnding(
        of sessionID: UUID,
        in sessions: [SessionSummary],
        healthOutcome: HealthRecordOutcome
    ) -> RatingSessionEnding {
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            return .failed
        }
        switch session.status {
        case .abandoned:
            return .abandoned
        case .inProgress:
            return .failed
        case .completed:
            guard RatingPromptPolicy.countsAsCompleted(session) else {
                return .abandoned
            }
        }
        switch healthOutcome {
        case .saved, .notAttempted:
            return .completed
        case .pending, .failed:
            return .failed
        }
    }

    /// Quando a L3 deixa, chama `request` (a caixa do sistema) e grava a versão atual e `now` como o último
    /// pedido. Devolve se pediu. `healthOutcome` é o resultado do Saúde depois da espera de quem chama.
    @discardableResult
    func requestIfAllowed(
        sessionID: UUID,
        healthOutcome: HealthRecordOutcome,
        now: Date,
        request: () -> Void
    ) -> Bool {
        guard store.isStoreInstall else {
            return false
        }
        guard let input = input(forSessionID: sessionID, healthOutcome: healthOutcome),
              RatingPromptPolicy.shouldRequest(input, now: now)
        else {
            return false
        }
        let version = store.currentVersion
        request()
        store.recordRequest(RatingPromptRecord(version: version, date: now))
        logger.info("Pedido de avaliação feito na versão \(version, privacy: .public).")
        return true
    }
}
