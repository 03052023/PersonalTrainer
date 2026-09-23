import Foundation
import Observation
import TrainerCore

/// Estado em memória da sessão ativa (SPEC F2/F3, RF-02..RF-06, RF-10).
///
/// O estado vem do próprio `WorkoutSessionModel`: `@Model` é `Observable`, então SwiftUI
/// atualiza a tela quando o coordinator grava uma série. Nada aqui escreve no
/// `ModelContext` (AGENTS R4): toda mutação passa por `SessionCoordinating`, que salva
/// imediatamente (RF-06). A tela não usa `@Query` (ARCHITECTURE §15, "re-renderiza").
///
/// Datas vêm sempre do closure `now` injetado (SPEC P11), nunca de `Date()`. O serviço de
/// notificações só entra para pedir permissão na primeira série concluída (AGENTS §7).
@Observable
@MainActor
final class ActiveSessionViewModel {
    /// Exposto para `RestTimerView`. Começa a contar ao concluir uma série de trabalho (RF-05).
    let restTimer: RestTimer

    private(set) var session: WorkoutSessionModel?
    private(set) var selectedExerciseID: UUID? = nil
    /// Próxima série do exercício selecionado, pré-preenchida (RF-04). `nil` quando não há
    /// exercício selecionado ou quando ele foi pulado (não há série a registrar).
    var currentDraft: SetDraft? = nil
    var errorMessage: String? = nil
    private(set) var isFinished: Bool = false

    private let coordinator: any SessionCoordinating
    private let notifications: any NotificationScheduling
    private let now: () -> Date
    /// A permissão de notificação é pedida uma vez por instância, na primeira série concluída
    /// (AGENTS §7: nunca no launch). Estado interno, não de tela.
    @ObservationIgnored private var hasRequestedNotificationAuthorization = false

    init(
        sessionID: UUID,
        coordinator: any SessionCoordinating,
        restTimer: RestTimer,
        notifications: any NotificationScheduling,
        now: @escaping () -> Date
    ) {
        self.coordinator = coordinator
        self.restTimer = restTimer
        self.notifications = notifications
        self.now = now
        let session = coordinator.session(withID: sessionID)
        self.session = session

        if let session {
            // `status` é `nil` para raw desconhecido; nesse caso não se afirma nada sobre o fim.
            if let status = session.status, status != .inProgress {
                isFinished = true
            }
        } else {
            errorMessage = "Sessão não encontrada."
        }

        selectInitialExercise()
        refreshDraft()
    }

    // MARK: - Estado derivado

    /// Exercícios da sessão ordenados por `order`.
    var exercises: [SessionExerciseModel] {
        (session?.exercises ?? []).sorted { $0.order < $1.order }
    }

    var selectedExercise: SessionExerciseModel? {
        guard let selectedExerciseID else {
            return nil
        }
        return exercises.first { $0.uuid == selectedExerciseID }
    }

    /// Totais da sessão (duração, séries de trabalho, tonelagem). Sem sessão, tudo zero.
    var stats: SessionStats {
        guard let session else {
            return SessionStats(duration: nil, workingSetCount: 0, warmupSetCount: 0, tonnage: 0, exerciseCount: 0)
        }
        let exerciseSets: [[SetResult]] = exercises.map { exercise in
            exercise.sets
                .sorted { $0.index < $1.index }
                .map { HistoryMapper.setResult(from: $0) }
        }
        return SessionStats.compute(
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            exerciseSets: exerciseSets
        )
    }

    /// "Booleano" para o `.alert` de erro: fechar o alerta limpa `errorMessage`.
    var isShowingError: Bool {
        get { errorMessage != nil }
        set {
            if !newValue {
                errorMessage = nil
            }
        }
    }

    /// Texto da prescrição do exercício ("3 × 8–12 · 60 kg · RIR 2"), sempre a partir da
    /// prescrição gravada no snapshot, independente do que o usuário editou na série atual.
    func prescriptionSummary(for exercise: SessionExerciseModel) -> String {
        makeDraft(for: exercise, index: 0, previous: nil).prescriptionSummary
    }

    /// Séries de trabalho registradas (SPEC P1) — o "2" de "2/3" nos chips.
    func workingSetCount(of exercise: SessionExerciseModel) -> Int {
        exercise.sets.filter { !$0.isWarmup }.count
    }

    // MARK: - Ações

    /// Grava a série do rascunho atual (RF-03, RF-06), inicia o descanso se for série de
    /// trabalho (RF-05) e prepara a próxima série (RF-04). Se o exercício completou as séries
    /// prescritas, a seleção avança para o próximo exercício pendente.
    func completeSet() {
        guard let session, let exercise = selectedExercise, let draft = currentDraft else {
            return
        }
        let timestamp = now()
        do {
            try coordinator.logSet(
                sessionID: session.uuid,
                sessionExerciseID: exercise.uuid,
                index: draft.setIndex,
                load: draft.load,
                reps: draft.reps,
                rir: draft.rir,
                isWarmup: draft.isWarmup,
                now: timestamp
            )
        } catch {
            errorMessage = message(for: error, fallback: "Não foi possível registrar a série.")
            return
        }

        requestNotificationAuthorizationIfNeeded()

        // Aquecimento não inicia descanso: o usuário segue direto para a próxima série.
        if !draft.isWarmup, exercise.restSeconds > 0 {
            restTimer.start(seconds: exercise.restSeconds, now: timestamp)
        }

        if !isPending(exercise) {
            selectedExerciseID = nextPendingExercise(after: exercise)?.uuid ?? exercise.uuid
        }
        refreshDraft()
    }

    /// Máquina ocupada (SPEC F3, RF-10): marca o exercício como pulado e avança.
    func skipCurrentExercise() {
        guard let session, let exercise = selectedExercise else {
            return
        }
        do {
            try coordinator.skipExercise(sessionID: session.uuid, sessionExerciseID: exercise.uuid, now: now())
        } catch {
            errorMessage = message(for: error, fallback: "Não foi possível pular o exercício.")
            return
        }
        selectedExerciseID = nextPendingExercise(after: exercise)?.uuid ?? exercise.uuid
        refreshDraft()
    }

    /// Seleção manual pelo chip. Ignora ids que não pertencem à sessão.
    func select(exerciseID: UUID) {
        guard exercises.contains(where: { $0.uuid == exerciseID }) else {
            return
        }
        selectedExerciseID = exerciseID
        refreshDraft()
    }

    /// SPEC F4 / RF-02: `status = completed`. O descanso pendente é cancelado junto com a
    /// notificação (não faz sentido avisar "descanso terminou" depois do treino).
    func finish() {
        guard let session else {
            return
        }
        do {
            try coordinator.finishSession(sessionID: session.uuid, now: now())
        } catch {
            errorMessage = message(for: error, fallback: "Não foi possível finalizar o treino.")
            return
        }
        restTimer.skip()
        isFinished = true
    }

    /// `status = abandoned`; as séries registradas continuam no histórico (SPEC P3/S2).
    func abandon() {
        guard let session else {
            return
        }
        do {
            try coordinator.abandonSession(sessionID: session.uuid, now: now())
        } catch {
            errorMessage = message(for: error, fallback: "Não foi possível abandonar o treino.")
            return
        }
        restTimer.skip()
        isFinished = true
    }

    // MARK: - Seleção

    /// Pendente = não pulado e com menos séries de trabalho que o prescrito (SPEC P1).
    private func isPending(_ exercise: SessionExerciseModel) -> Bool {
        !exercise.wasSkipped && workingSetCount(of: exercise) < exercise.prescribedSets
    }

    /// Primeiro pendente na ordem; se a sessão já está toda feita (ou pulada), o último,
    /// para que ao retomar o usuário caia onde parou.
    private func selectInitialExercise() {
        let all = exercises
        let initial = all.first { isPending($0) } ?? all.last
        selectedExerciseID = initial?.uuid
    }

    /// Próximo pendente depois de `exercise`, dando a volta ao início: quem pulou adiante por
    /// máquina ocupada volta ao exercício que ficou para trás. `nil` se não resta nenhum.
    private func nextPendingExercise(after exercise: SessionExerciseModel) -> SessionExerciseModel? {
        let all = exercises
        guard let position = all.firstIndex(where: { $0.uuid == exercise.uuid }) else {
            return all.first { isPending($0) }
        }
        let following = Array(all[(position + 1)...]) + Array(all[..<position])
        return following.first { isPending($0) }
    }

    // MARK: - Rascunho da série

    private func refreshDraft() {
        guard let exercise = selectedExercise, !exercise.wasSkipped else {
            currentDraft = nil
            return
        }
        let sortedSets = exercise.sets.sorted { $0.index < $1.index }
        // Índice = séries já registradas, aquecimento incluído (é sequencial dentro do exercício).
        currentDraft = makeDraft(for: exercise, index: sortedSets.count, previous: sortedSets.last)
    }

    /// RF-04: a 1ª série vem da prescrição; as seguintes copiam carga/reps/RIR da anterior
    /// (inclusive quando a anterior foi aquecimento: o usuário ajusta no stepper).
    ///
    /// O snapshot não guarda a meta de reps do motor (`ExercisePrescription.targetReps`), só a
    /// faixa; usa-se `prescribedRepMin` como valor inicial e como `targetReps` — é a meta em
    /// `calibrate`/`increase`/`retry`/`returning` (SPEC P2, P4, P6, P9) e o piso em `hold`.
    /// Sem `prescribedLoad` (SPEC P2 sem `startingLoad`) a carga começa em 0 e o usuário digita.
    private func makeDraft(for exercise: SessionExerciseModel, index: Int, previous: SetLogModel?) -> SetDraft {
        let load: Double
        let reps: Int
        let rir: Int?
        if let previous {
            load = previous.load
            reps = previous.reps
            rir = previous.rir
        } else {
            load = exercise.prescribedLoad ?? 0
            reps = exercise.prescribedRepMin
            rir = exercise.prescribedRIR
        }

        return SetDraft(
            load: load,
            reps: reps,
            rir: rir,
            isWarmup: false,
            setIndex: index,
            plannedSets: exercise.prescribedSets,
            loadIncrement: exercise.exercise?.loadIncrement ?? 2.5,
            loadUnit: exercise.exercise?.loadUnit ?? .kilograms,
            repMin: exercise.prescribedRepMin,
            repMax: exercise.prescribedRepMax,
            targetReps: exercise.prescribedRepMin,
            targetRIR: exercise.prescribedRIR,
            note: exercise.note ?? .hold
        )
    }

    // MARK: - Notificações

    /// AGENTS §7: a permissão é pedida na primeira ação que precisa dela — a primeira série
    /// concluída, a partir da qual o timer de descanso passa a agendar avisos (RF-05) —, nunca
    /// no launch. Só depois de a série estar gravada, para o pedido nunca atrasar o registro
    /// (RNF-02). O resultado não muda o fluxo: sem permissão o timer segue em primeiro plano.
    private func requestNotificationAuthorizationIfNeeded() {
        guard !hasRequestedNotificationAuthorization else {
            return
        }
        hasRequestedNotificationAuthorization = true
        let notifications = self.notifications
        Task {
            _ = await notifications.requestAuthorization()
        }
    }

    // MARK: - Erros

    /// Mensagem pt-BR para o `.alert`. Erros do coordinator têm texto próprio; o resto usa o
    /// texto da ação (o `localizedDescription` de um enum Swift não serve para o usuário).
    private func message(for error: any Error, fallback: String) -> String {
        guard let coordinatorError = error as? SessionCoordinatorError else {
            return fallback
        }
        switch coordinatorError {
        case .sessionNotFound:
            return "A sessão não foi encontrada."
        case .sessionNotInProgress:
            return "Esta sessão já foi encerrada."
        case .sessionAlreadyInProgress:
            return "Já existe uma sessão em andamento."
        case .sessionExerciseNotFound:
            return "O exercício não foi encontrado nesta sessão."
        case .setNotFound:
            return "A série não foi encontrada."
        case .exerciseNotFound:
            return "O exercício não existe no catálogo."
        }
    }
}
