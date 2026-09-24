import Foundation
import Observation
import os
import TrainerCore

/// Estado em memória da sessão ativa (SPEC F2/F3, RF-02..RF-06, RF-10, RF-19, RF-34).
///
/// O estado vem do próprio `WorkoutSessionModel`: `@Model` é `Observable`, então SwiftUI
/// atualiza a tela quando o coordinator grava uma série. Nada aqui escreve no
/// `ModelContext` (AGENTS R4): toda mutação passa por `SessionCoordinating`, que salva
/// imediatamente (RF-06). A tela não usa `@Query` (ARCHITECTURE §15, "re-renderiza").
///
/// Datas vêm sempre do closure `now` injetado (SPEC P11), nunca de `Date()`. O serviço de
/// notificações só entra para pedir permissão na primeira série concluída (AGENTS §7).
/// `planner` e `catalog` só servem ao botão "Trocar" (RF-34): substitutos, lista completa e a
/// prescrição do exercício novo. `traits` diz a medida de cada exercício pelo `slug` (SPEC RF-43),
/// para o rascunho e a prescrição mostrarem segundos ou passos; é o mesmo catálogo que a raiz
/// injeta em `\.exerciseTraits`.
@Observable
@MainActor
final class ActiveSessionViewModel {
    /// Série em edição na `EditSetSheet` (RF-19). É uma cópia de valores: a folha edita a
    /// cópia e só grava ao salvar, pelo coordinator.
    struct SetEdit: Identifiable, Hashable {
        let setID: UUID
        /// Posição 1-based entre as séries do exercício, para o título "Corrigir série 2".
        let number: Int
        var load: Double
        var reps: Int
        var rir: Int?
        let isWarmup: Bool
        let loadIncrement: Double
        let loadUnit: LoadUnit
        let repMin: Int
        let repMax: Int
        /// Medida do exercício (SPEC RF-43): o stepper da correção vira "Segundos" ou "Passos".
        var measure: ExerciseMeasure = .reps

        var id: UUID { setID }
    }

    /// Exposto para `RestTimerView`. Começa a contar ao concluir uma série de trabalho (RF-05).
    let restTimer: RestTimer

    private(set) var session: WorkoutSessionModel?
    private(set) var selectedExerciseID: UUID? = nil
    /// Próxima série do exercício selecionado, pré-preenchida (RF-04). `nil` quando não há
    /// exercício selecionado ou quando ele foi pulado (não há série a registrar).
    var currentDraft: SetDraft? = nil
    var errorMessage: String? = nil
    private(set) var isFinished: Bool = false

    /// `true` enquanto a tela deve perguntar "Registrar com 0 kg?": calibração sem carga
    /// prescrita (SPEC P2) em que o usuário tocou "Concluir série" sem digitar a carga, num
    /// exercício que não é de peso corporal (SPEC P8: carga 0 só vale para `bodyweight`).
    /// Fechar o aviso sem confirmar equivale a `cancelZeroLoadSet()`.
    var needsZeroLoadConfirmation: Bool = false

    /// Folha "Trocar exercício" (RF-34) aberta.
    var isShowingSubstituteSheet: Bool = false
    /// Substitutos do mesmo padrão de movimento, carregados ao abrir a folha.
    private(set) var substituteSuggestions: [ExerciseDefinition] = []
    /// Catálogo não arquivado para "Ver todos os exercícios", sem o exercício atual.
    private(set) var substitutionCatalog: [ExerciseDefinition] = []

    /// Série aberta na folha de correção; `nil` = folha fechada.
    var editingSet: SetEdit? = nil

    private let coordinator: any SessionCoordinating
    private let planner: any SessionPlanning
    private let catalog: any CatalogRepositoring
    private let notifications: any NotificationScheduling
    private let now: () -> Date
    private let traits: ExerciseTraitsCatalog
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "ActiveSessionViewModel"
    )
    /// A permissão de notificação é pedida uma vez por instância, na primeira série concluída
    /// (AGENTS §7: nunca no launch). Estado interno, não de tela.
    @ObservationIgnored private var hasRequestedNotificationAuthorization = false
    /// Erro de uma ação feita dentro de uma folha (trocar, corrigir, apagar). Só vira
    /// `errorMessage` em `sheetDidDismiss()`: um `.alert` pedido enquanto a folha ainda está
    /// fechando pode não aparecer.
    @ObservationIgnored private var deferredErrorMessage: String? = nil

    init(
        sessionID: UUID,
        coordinator: any SessionCoordinating,
        planner: any SessionPlanning,
        catalog: any CatalogRepositoring,
        restTimer: RestTimer,
        notifications: any NotificationScheduling,
        now: @escaping () -> Date,
        traits: ExerciseTraitsCatalog = .empty
    ) {
        self.coordinator = coordinator
        self.planner = planner
        self.catalog = catalog
        self.restTimer = restTimer
        self.notifications = notifications
        self.now = now
        self.traits = traits
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

    /// "Trocar" só vale antes da 1ª série do exercício (RF-34): o histórico de cada exercício é
    /// separado (P3) e o coordinator recusa a troca de um exercício que já tem séries.
    var canSubstituteSelectedExercise: Bool {
        guard !isFinished, session != nil, let exercise = selectedExercise else {
            return false
        }
        return !exercise.wasSkipped && exercise.sets.isEmpty
    }

    /// Texto da prescrição do exercício ("3 × 8–12 · 60 kg · RIR 2"), sempre a partir da
    /// prescrição gravada no snapshot, independente do que o usuário editou na série atual.
    /// Carga prescrita `nil` (SPEC P2) aparece como "—", igual à Home e ao histórico.
    func prescriptionSummary(for exercise: SessionExerciseModel) -> String {
        makeDraft(for: exercise, sortedSets: []).prescriptionSummary
    }

    /// Leitura por voz da mesma prescrição (SPEC RF-41 d): "3 séries de 8 a 12 repetições,
    /// 100 kg, parar com 2 repetições de reserva".
    func prescriptionSpokenText(for exercise: SessionExerciseModel) -> String {
        makeDraft(for: exercise, sortedSets: []).prescriptionSpokenText
    }

    /// Medida do exercício pelo `slug` do catálogo do seed (SPEC RF-43). Personalizado ou sem
    /// relação com o catálogo mede em repetições.
    func measure(for exercise: SessionExerciseModel) -> ExerciseMeasure {
        MeasureText.measure(of: exercise.exercise, in: traits)
    }

    /// Séries de trabalho registradas (SPEC P1) — o "2" de "2/3" nos chips.
    func workingSetCount(of exercise: SessionExerciseModel) -> Int {
        exercise.sets.filter { !$0.isWarmup }.count
    }

    // MARK: - Registrar série

    /// "Concluir série". Na calibração sem carga (SPEC P2) com a carga ainda em 0, pede
    /// confirmação antes de gravar (`needsZeroLoadConfirmation`); nos demais casos grava direto.
    func completeSet() {
        guard session != nil, let exercise = selectedExercise, let draft = currentDraft else {
            return
        }
        if requiresZeroLoadConfirmation(draft: draft, exercise: exercise) {
            needsZeroLoadConfirmation = true
            return
        }
        logCurrentDraft()
    }

    /// "Registrar" no aviso de 0 kg: grava a série como está. Não depende do valor atual de
    /// `needsZeroLoadConfirmation`, porque o SwiftUI pode fechar o aviso antes da ação.
    func confirmZeroLoadSet() {
        needsZeroLoadConfirmation = false
        logCurrentDraft()
    }

    /// Fecha o aviso sem gravar; o rascunho fica como estava para o usuário ajustar a carga.
    func cancelZeroLoadSet() {
        needsZeroLoadConfirmation = false
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

    // MARK: - Trocar exercício (RF-34)

    /// Abre a folha "Trocar": substitutos do planner (mesmo padrão de movimento, até 5) sem os
    /// exercícios que já estão nesta sessão, e o catálogo completo para "Ver todos". Falha ao
    /// carregar uma das listas só deixa essa lista vazia (a folha continua útil com a outra).
    func beginSubstitution() {
        guard canSubstituteSelectedExercise, let exercise = selectedExercise else {
            return
        }
        let inSession = Set(exercises.map(\.exerciseUUID))
        do {
            // RF-34: a folha mostra só os substitutos deste exercício, do mais ao menos parecido,
            // sem o catálogo inteiro; o limite alto cobre todos os candidatos de um padrão.
            substituteSuggestions = try planner.substitutes(for: exercise.exerciseUUID, limit: 20)
                .filter { !inSession.contains($0.id) }
        } catch {
            logger.error("Falha ao buscar substitutos: \(String(describing: error), privacy: .public)")
            substituteSuggestions = []
        }
        do {
            substitutionCatalog = try catalog.allExercises(includeArchived: false)
                .filter { $0.id != exercise.exerciseUUID }
        } catch {
            logger.error("Falha ao ler o catálogo: \(String(describing: error), privacy: .public)")
            substitutionCatalog = []
        }
        isShowingSubstituteSheet = true
    }

    /// Troca o exercício selecionado por `newExercise` só nesta sessão: o planner calcula a
    /// prescrição do novo mantendo o alvo do original, e o coordinator substitui o snapshot.
    /// O novo exercício tem histórico próprio (P3); sem histórico, calibra (P2).
    func substituteSelectedExercise(with newExercise: ExerciseDefinition) {
        guard let session, canSubstituteSelectedExercise, let exercise = selectedExercise else {
            closeSubstitution()
            return
        }
        let timestamp = now()
        let target = substitutionTarget(for: exercise, newExerciseID: newExercise.id)
        do {
            let planned = try planner.substitutionPlan(
                replacing: exercise.uuid,
                target: target,
                newExerciseID: newExercise.id,
                now: timestamp
            )
            try coordinator.substituteExercise(
                sessionID: session.uuid,
                sessionExerciseID: exercise.uuid,
                with: planned,
                now: timestamp
            )
        } catch {
            deferredErrorMessage = message(for: error, fallback: "Não foi possível trocar o exercício.")
            closeSubstitution()
            return
        }
        closeSubstitution()
        refreshDraft()
    }

    func cancelSubstitution() {
        closeSubstitution()
    }

    // MARK: - Corrigir / apagar série (RF-19)

    /// Abre a folha de correção para a série `setID` de qualquer exercício da sessão.
    func beginEditingSet(id setID: UUID) {
        guard !isFinished else {
            return
        }
        for exercise in exercises {
            let sortedSets = exercise.sets.sorted { $0.index < $1.index }
            guard let position = sortedSets.firstIndex(where: { $0.uuid == setID }) else {
                continue
            }
            let setLog = sortedSets[position]
            editingSet = SetEdit(
                setID: setLog.uuid,
                number: position + 1,
                load: setLog.load,
                reps: setLog.reps,
                rir: setLog.rir,
                isWarmup: setLog.isWarmup,
                loadIncrement: exercise.exercise?.loadIncrement ?? 2.5,
                loadUnit: exercise.exercise?.loadUnit ?? .kilograms,
                repMin: exercise.prescribedRepMin,
                repMax: exercise.prescribedRepMax,
                measure: measure(for: exercise)
            )
            return
        }
    }

    /// Grava a correção (evento `setUpdated`) e refaz o rascunho: a próxima série copia a
    /// anterior já corrigida (RF-04).
    func saveEditedSet(_ edit: SetEdit) {
        editingSet = nil
        guard let session else {
            return
        }
        do {
            try coordinator.updateSet(
                sessionID: session.uuid,
                setID: edit.setID,
                load: edit.load,
                reps: edit.reps,
                rir: edit.rir,
                now: now()
            )
        } catch {
            deferredErrorMessage = message(for: error, fallback: "Não foi possível corrigir a série.")
            return
        }
        refreshDraft()
    }

    /// Apaga a série (evento `setDeleted`). O exercício pode voltar a ficar pendente; a
    /// seleção não muda, só o rascunho.
    func deleteSet(id setID: UUID) {
        editingSet = nil
        guard let session else {
            return
        }
        do {
            try coordinator.deleteSet(sessionID: session.uuid, setID: setID, now: now())
        } catch {
            deferredErrorMessage = message(for: error, fallback: "Não foi possível apagar a série.")
            return
        }
        refreshDraft()
    }

    func cancelEditingSet() {
        editingSet = nil
    }

    /// Chamado pelo `onDismiss` das folhas: mostra o erro que aconteceu dentro delas.
    func sheetDidDismiss() {
        guard let deferredErrorMessage else {
            return
        }
        self.deferredErrorMessage = nil
        errorMessage = deferredErrorMessage
    }

    // MARK: - Encerrar

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

    // MARK: - Gravação da série

    /// Grava a série do rascunho atual (RF-03, RF-06), inicia o descanso se for série de
    /// trabalho (RF-05) e prepara a próxima série (RF-04). Se o exercício completou as séries
    /// prescritas, a seleção avança para o próximo exercício pendente.
    private func logCurrentDraft() {
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

    /// SPEC P2 + P8: sem carga prescrita, 0 quase sempre é "esqueci de digitar"; só o peso
    /// corporal puro aceita 0 sem perguntar. Sem catálogo relacionado, pergunta (é inofensivo).
    private func requiresZeroLoadConfirmation(draft: SetDraft, exercise: SessionExerciseModel) -> Bool {
        guard draft.prescribedLoad == nil, draft.load == 0 else {
            return false
        }
        return exercise.exercise?.equipment != .bodyweight
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

    // MARK: - Troca

    private func closeSubstitution() {
        isShowingSubstituteSheet = false
        substituteSuggestions = []
        substitutionCatalog = []
    }

    /// Alvo do exercício original reconstruído do snapshot (RF-34: a troca mantém séries,
    /// faixa, RIR e descanso). `exerciseID` já é o do exercício novo porque o motor copia
    /// `target.exerciseID` para a prescrição; `startingLoad` fica `nil` porque a carga inicial
    /// do original não vale para outro exercício (P3 é por exercício; sem histórico, P2).
    private func substitutionTarget(for exercise: SessionExerciseModel, newExerciseID: UUID) -> ExerciseTarget {
        var targetRIR = exercise.prescribedRIR
        // SPEC P2: calibrar sem carga grava RIR alvo = T + 1. Sem desfazer aqui, um substituto
        // que também calibre sem carga receberia T + 2.
        if exercise.note == .calibrate, exercise.prescribedLoad == nil {
            targetRIR = max(0, targetRIR - 1)
        }
        return ExerciseTarget(
            exerciseID: newExerciseID,
            order: exercise.order,
            sets: exercise.prescribedSets,
            repMin: exercise.prescribedRepMin,
            repMax: exercise.prescribedRepMax,
            targetRIR: targetRIR,
            restSeconds: exercise.restSeconds,
            startingLoad: nil
        )
    }

    // MARK: - Rascunho da série

    private func refreshDraft() {
        guard let exercise = selectedExercise, !exercise.wasSkipped else {
            currentDraft = nil
            return
        }
        let sortedSets = exercise.sets.sorted { $0.index < $1.index }
        currentDraft = makeDraft(for: exercise, sortedSets: sortedSets)
    }

    /// RF-04: a 1ª série vem da prescrição; as seguintes copiam carga/reps/RIR da anterior
    /// (inclusive quando a anterior foi aquecimento: o usuário ajusta no stepper).
    ///
    /// Índice = maior índice gravado + 1 (aquecimento incluído): continua único depois de
    /// apagar uma série do meio (RF-19). O número exibido é a posição, sem lacunas.
    ///
    /// Meta de reps: `prescribedTargetReps` do snapshot quando conhecido (> 0; em `hold` a SPEC
    /// P5 sobe a meta para min(repMax, menor reps + 1)). Sessões gravadas antes do campo existir
    /// têm 0 e caem em `prescribedRepMin`, a meta de P2/P4/P6/P9 e o piso de P5.
    /// Sem `prescribedLoad` (SPEC P2 sem `startingLoad`) a carga começa em 0 e o usuário digita;
    /// `prescribedLoad` segue `nil` no rascunho para o texto da prescrição mostrar "—".
    private func makeDraft(for exercise: SessionExerciseModel, sortedSets: [SetLogModel]) -> SetDraft {
        let targetReps = exercise.prescribedTargetReps > 0 ? exercise.prescribedTargetReps : exercise.prescribedRepMin
        let load: Double
        let reps: Int
        let rir: Int?
        if let previous = sortedSets.last {
            load = previous.load
            reps = previous.reps
            rir = previous.rir
        } else {
            load = exercise.prescribedLoad ?? 0
            reps = targetReps
            rir = exercise.prescribedRIR
        }
        let nextIndex = (sortedSets.map(\.index).max() ?? -1) + 1

        return SetDraft(
            load: load,
            reps: reps,
            rir: rir,
            isWarmup: false,
            setIndex: nextIndex,
            setNumber: sortedSets.count + 1,
            plannedSets: exercise.prescribedSets,
            prescribedLoad: exercise.prescribedLoad,
            loadIncrement: exercise.exercise?.loadIncrement ?? 2.5,
            loadUnit: exercise.exercise?.loadUnit ?? .kilograms,
            repMin: exercise.prescribedRepMin,
            repMax: exercise.prescribedRepMax,
            targetReps: targetReps,
            targetRIR: exercise.prescribedRIR,
            note: exercise.note ?? .hold,
            measure: measure(for: exercise)
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
        case .unsupported:
            return "Esta ação não está disponível agora."
        }
    }
}
