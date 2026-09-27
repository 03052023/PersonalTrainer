import Foundation
import Observation
import os
import TrainerCore

/// Estado da ficha da sessão (SPEC RF-44, RF-04, RF-46, RF-10, RF-19, RF-34; docs/V22-CONTRACT.md
/// §3.1).
///
/// A ficha mostra todos os exercícios; cada toque grava pelo `SessionCoordinating` (AGENTS R4),
/// que salva na hora (RF-06): a bolinha vazia grava uma série com a meta de hoje (`markSet`),
/// "Feito" grava as séries que faltam (`markExerciseDone`) e "Marcar como feitos, como previsto"
/// faz o mesmo em cada pendente que tem carga (`markRemainingAsPrescribed`). Toda série nova grava
/// `rir = nil` e `isWarmup = false` (SPEC RF-03, RF-41, decisão 18); a correção de uma série
/// regrava o `rir` que ela já tinha.
///
/// O estado vem do próprio `WorkoutSessionModel`: `@Model` é `Observable`, então a tela se
/// atualiza quando o coordinator grava. Só a carga digitada no teclado fica em memória
/// (`setWorkingLoad`, P10): ela não é dado de treino até uma bolinha ser marcada.
///
/// Datas vêm sempre do closure `now` injetado (SPEC P11), nunca de `Date()`. O serviço de
/// notificações só entra para pedir permissão na primeira série gravada (AGENTS §7).
@Observable
@MainActor
final class ActiveSessionViewModel {
    /// Série aberta em "Corrigir série" (RF-19). Cópia de valores: a folha edita a cópia e só grava
    /// ao salvar, pelo coordinator.
    struct SetEdit: Identifiable, Hashable {
        let setID: UUID
        /// Posição 1-based entre as séries de trabalho do exercício ("Corrigir série 2").
        let number: Int
        var load: Double
        var reps: Int
        /// RIR já gravado na série. Não aparece na folha; salvar regrava o mesmo valor
        /// (SPEC RF-41; contrato V22 §1.5).
        let rir: Int?
        let loadIncrement: Double
        let loadUnit: LoadUnit
        let repMin: Int
        let repMax: Int
        /// Medida do exercício (SPEC RF-43): o stepper vira "Segundos" ou "Passos".
        var measure: ExerciseMeasure = .reps
        /// Peso do corpo (SPEC RF-46): o stepper de carga vira "Carga extra".
        var isBodyweight: Bool = false
        /// "Agachamento livre · previsto: 3 repetições · 62,5 kg"; vazio nos previews.
        var plannedLine: String = ""

        var id: UUID { setID }
    }

    /// Exposto para `RestTimerView`. Começa a contar quando uma bolinha é marcada (RF-05).
    let restTimer: RestTimer

    private(set) var session: WorkoutSessionModel?
    var errorMessage: String? = nil
    private(set) var isFinished: Bool = false
    /// Quantas marcações deram certo: gatilho do `.sensoryFeedback(.success)` (DESIGN §10).
    private(set) var markCount: Int = 0

    /// Folha "Trocar exercício" (RF-34) aberta.
    var isShowingSubstituteSheet: Bool = false
    /// Substitutos do mesmo padrão de movimento, carregados ao abrir a folha.
    private(set) var substituteSuggestions: [ExerciseDefinition] = []
    /// Exercício que a folha "Trocar" vai substituir.
    private(set) var substitutingExerciseID: UUID? = nil

    /// Série aberta na folha de correção; `nil` = folha fechada.
    var editingSet: SetEdit? = nil

    /// Carga digitada no teclado, por `SessionExerciseModel.uuid` (SPEC RF-04, P10). Só memória.
    private var chosenLoads: [UUID: Double] = [:]
    /// Exercício cuja bolinha iniciou o descanso atual: base do "A seguir" do descanso.
    private var restSourceExerciseID: UUID? = nil

    private let coordinator: any SessionCoordinating
    private let planner: any SessionPlanning
    private let notifications: any NotificationScheduling
    private let now: () -> Date
    private let traits: ExerciseTraitsCatalog
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "ActiveSessionViewModel"
    )
    /// A permissão de notificação é pedida uma vez por instância, na primeira série gravada
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
        restTimer: RestTimer,
        notifications: any NotificationScheduling,
        now: @escaping () -> Date,
        traits: ExerciseTraitsCatalog = .empty
    ) {
        self.coordinator = coordinator
        self.planner = planner
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
    }

    // MARK: - Estado derivado

    /// Exercícios da sessão ordenados por `order`.
    var exercises: [SessionExerciseModel] {
        (session?.exercises ?? []).sorted { $0.order < $1.order }
    }

    /// Totais da sessão (duração, séries de trabalho, exercícios feitos). Sem sessão, tudo zero.
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

    /// Sessão aberta para marcar: carregada, em andamento e não encerrada nesta tela.
    var isOpen: Bool {
        guard let session, !isFinished else {
            return false
        }
        return session.status == .inProgress
    }

    /// Exercícios não pulados com menos séries de trabalho que o prescrito (SPEC P1), na ordem.
    var pendingExercises: [SessionExerciseModel] {
        exercises.filter { isPending($0) }
    }

    /// O exercício "atual" da ficha: o primeiro pendente, com borda `accent` (SPEC RF-44 a).
    var currentExerciseID: UUID? {
        exercises.first { isPending($0) }?.uuid
    }

    /// Medida do exercício pelo `slug` do catálogo do seed (SPEC RF-43). Personalizado ou sem
    /// relação com o catálogo mede em repetições.
    func measure(for exercise: SessionExerciseModel) -> ExerciseMeasure {
        MeasureText.measure(of: exercise.exercise, in: traits)
    }

    /// Séries de trabalho (SPEC P1), na ordem de `index`. Aquecimentos antigos ficam de fora.
    func workingSets(of exercise: SessionExerciseModel) -> [SetLogModel] {
        exercise.sets
            .filter { !$0.isWarmup }
            .sorted { $0.index < $1.index }
    }

    func workingSetCount(of exercise: SessionExerciseModel) -> Int {
        exercise.sets.filter { !$0.isWarmup }.count
    }

    /// Pendente = não pulado e com menos séries de trabalho que o prescrito (SPEC P1).
    func isPending(_ exercise: SessionExerciseModel) -> Bool {
        !exercise.wasSkipped && workingSetCount(of: exercise) < exercise.prescribedSets
    }

    /// Feito = não pulado e com todas as séries prescritas (a linha compacta da ficha).
    func isDone(_ exercise: SessionExerciseModel) -> Bool {
        !exercise.wasSkipped && !isPending(exercise)
    }

    /// Peso do corpo (SPEC RF-46, P8). Sem catálogo relacionado, trata como exercício com carga.
    func isBodyweight(_ exercise: SessionExerciseModel) -> Bool {
        exercise.exercise?.equipment == .bodyweight
    }

    // MARK: - Meta e carga de hoje (SPEC RF-04, RF-44, RF-46)

    /// Meta de repetições (ou segundos, passos) de hoje: o que cada bolinha grava (RF-04).
    func goal(for exercise: SessionExerciseModel) -> Int {
        TodayTargetText.goal(targetReps: exercise.prescribedTargetReps, repMin: exercise.prescribedRepMin)
    }

    /// A carga que a próxima bolinha grava (RF-04): a escolhida no teclado; senão, a da última
    /// série de trabalho deste exercício nesta sessão; senão, a prescrita; em peso do corpo sem
    /// nada disso, 0 (P8). `nil` = primeira vez com carga, ainda sem carga (P2): não dá para marcar.
    func workingLoad(for exercise: SessionExerciseModel) -> Double? {
        if let chosen = chosenLoads[exercise.uuid] {
            return chosen
        }
        if let last = workingSets(of: exercise).last {
            return last.load
        }
        if let prescribed = exercise.prescribedLoad {
            return prescribed
        }
        return isBodyweight(exercise) ? 0 : nil
    }

    /// Como a carga aparece na ficha, já com a carga escolhida (RF-46): peso do corpo sem carga
    /// não mostra nada; primeira vez sem carga, "escolha a carga".
    func loadDisplay(for exercise: SessionExerciseModel) -> TodayTargetText.LoadDisplay {
        TodayTargetText.loadDisplay(
            load: workingLoad(for: exercise),
            unit: loadUnit(of: exercise),
            equipment: exercise.exercise?.equipment
        )
    }

    /// Unidade da carga do exercício; sem catálogo relacionado, kg.
    func loadUnit(of exercise: SessionExerciseModel) -> LoadUnit {
        exercise.exercise?.loadUnit ?? .kilograms
    }

    /// Carga digitada no teclado para o exercício, se houver.
    func chosenLoad(for sessionExerciseID: UUID) -> Double? {
        chosenLoads[sessionExerciseID]
    }

    /// Primeira vez com carga (SPEC RF-44 c): sem carga prescrita (P2), não é peso do corpo e ainda
    /// sem nenhuma série de trabalho. A ficha mostra a dica e o campo de carga no lugar da meta.
    func isFirstTimeWithLoad(_ exercise: SessionExerciseModel) -> Bool {
        exercise.prescribedLoad == nil && !isBodyweight(exercise) && workingSets(of: exercise).isEmpty
    }

    /// Falta escolher a carga (RF-44 c): primeira vez sem carga, não é peso do corpo, e nenhuma
    /// carga maior que 0 escolhida ou já gravada neste exercício.
    func needsLoadChoice(_ exercise: SessionExerciseModel) -> Bool {
        guard exercise.prescribedLoad == nil, !isBodyweight(exercise) else {
            return false
        }
        guard let load = workingLoad(for: exercise) else {
            return true
        }
        return load <= 0
    }

    /// Bolinhas e "Feito" funcionam: sessão aberta, exercício não pulado e com carga (RF-44 c).
    func canMark(_ exercise: SessionExerciseModel) -> Bool {
        isOpen && !exercise.wasSkipped && !needsLoadChoice(exercise)
    }

    /// Teclado da carga (RF-44 b, P10): vale para as próximas bolinhas do exercício, sem gravar
    /// nada. Aceita de 0 (só peso do corpo, carga extra) ou mais de 0 até 1.000; fora disso, a
    /// escolha é desfeita e a ficha volta à carga de antes.
    func setWorkingLoad(_ load: Double, for sessionExerciseID: UUID) {
        guard let exercise = findExercise(id: sessionExerciseID) else {
            return
        }
        if SessionSheetText.isValidLoad(load, allowsZero: isBodyweight(exercise)) {
            chosenLoads[sessionExerciseID] = load
        } else {
            chosenLoads[sessionExerciseID] = nil
        }
    }

    /// Campo de carga apagado: volta à carga de antes (última série ou prescrita).
    func clearWorkingLoad(for sessionExerciseID: UUID) {
        chosenLoads[sessionExerciseID] = nil
    }

    // MARK: - Marcar (SPEC RF-44 b)

    /// Bolinha vazia: grava 1 série com a meta de hoje e a carga de `workingLoad`, `rir = nil`,
    /// `isWarmup = false`, e inicia o descanso do exercício (RF-05). Só com série faltando.
    func markSet(sessionExerciseID: UUID) {
        guard
            let session,
            let exercise = findExercise(id: sessionExerciseID),
            canMark(exercise),
            isPending(exercise)
        else {
            return
        }
        let timestamp = now()
        guard logPrescribedSet(for: exercise, sessionID: session.uuid, now: timestamp) else {
            return
        }
        markCount += 1
        requestNotificationAuthorizationIfNeeded()
        if exercise.restSeconds > 0 {
            restSourceExerciseID = exercise.uuid
            restTimer.start(seconds: exercise.restSeconds, now: timestamp)
        }
    }

    /// "Feito": uma série como a da bolinha para cada série que falta até `prescribedSets`. Nada
    /// se o exercício já está completo. Não inicia descanso (o exercício acabou).
    func markExerciseDone(sessionExerciseID: UUID) {
        guard
            let session,
            let exercise = findExercise(id: sessionExerciseID),
            canMark(exercise)
        else {
            return
        }
        let missing = exercise.prescribedSets - workingSetCount(of: exercise)
        guard missing > 0 else {
            return
        }
        let timestamp = now()
        var logged = 0
        for _ in 0..<missing {
            guard logPrescribedSet(for: exercise, sessionID: session.uuid, now: timestamp) else {
                break
            }
            logged += 1
        }
        guard logged > 0 else {
            return
        }
        markCount += 1
        requestNotificationAuthorizationIfNeeded()
    }

    /// "Marcar como feitos, como previsto" (RF-44 e): "Feito" em cada pendente que dá para marcar;
    /// os de primeira vez sem carga ficam de fora, e os pulados não são pendentes.
    func markRemainingAsPrescribed() {
        for exercise in pendingExercises where canMark(exercise) {
            markExerciseDone(sessionExerciseID: exercise.uuid)
        }
    }

    /// "A seguir" do descanso (RF-44 f): a próxima série do exercício que iniciou o descanso; se
    /// ele acabou, o próximo pendente; sem nenhum, "Tudo marcado". `nil` sem descanso marcado.
    var restNextUpText: String? {
        guard let sourceID = restSourceExerciseID, let source = findExercise(id: sourceID) else {
            return nil
        }
        if isPending(source) {
            return SessionSheetText.nextSet(number: workingSetCount(of: source) + 1, exerciseName: source.exerciseName)
        }
        if let next = nextPendingExercise(after: source) {
            return SessionSheetText.nextExercise(next.exerciseName)
        }
        return SessionSheetText.allMarked
    }

    // MARK: - Informações, pular e trocar (SPEC RF-47, RF-10, RF-34)

    /// Conteúdo da folha "Informações do exercício", a partir do snapshot. "Da última vez" vem do
    /// planner; uma falha só esconde essa seção (fica no log).
    func infoContent(for exercise: SessionExerciseModel) -> ExerciseInfoContent {
        let lastSession: ExerciseLastSession?
        do {
            lastSession = try planner.lastSession(forExerciseID: exercise.exerciseUUID)
        } catch {
            logger.error("Falha ao ler a última sessão do exercício: \(String(describing: error), privacy: .public)")
            lastSession = nil
        }
        return ExerciseInfoContent(sessionExercise: exercise, measure: measure(for: exercise), lastSession: lastSession)
    }

    /// "Pular" da folha de informações: vale enquanto a sessão está aberta e o exercício não foi pulado.
    func canSkip(_ exercise: SessionExerciseModel) -> Bool {
        isOpen && !exercise.wasSkipped
    }

    /// Máquina ocupada (SPEC F3, RF-10): marca o exercício como pulado. A própria folha de
    /// informações já é a confirmação. Séries já feitas são mantidas.
    func skip(sessionExerciseID: UUID) {
        guard let session, let exercise = findExercise(id: sessionExerciseID), canSkip(exercise) else {
            return
        }
        do {
            try coordinator.skipExercise(sessionID: session.uuid, sessionExerciseID: exercise.uuid, now: now())
        } catch {
            errorMessage = message(for: error, fallback: "Não foi possível pular o exercício.")
        }
    }

    /// "Trocar" só vale antes da 1ª série do exercício (RF-34): o histórico de cada exercício é
    /// separado (P3) e o coordinator recusa a troca de um exercício que já tem séries.
    func canSubstitute(_ exercise: SessionExerciseModel) -> Bool {
        isOpen && !exercise.wasSkipped && exercise.sets.isEmpty
    }

    /// Nome do exercício na folha "Trocar".
    var substitutingExerciseName: String {
        guard let substitutingExerciseID, let exercise = findExercise(id: substitutingExerciseID) else {
            return ""
        }
        return exercise.exerciseName
    }

    /// Abre a folha "Trocar": substitutos do planner (mesmo padrão de movimento) sem os
    /// exercícios que já estão nesta sessão. Falha ao carregar só deixa a lista vazia.
    func beginSubstitution(sessionExerciseID: UUID) {
        guard let exercise = findExercise(id: sessionExerciseID), canSubstitute(exercise) else {
            return
        }
        let inSession = Set(exercises.map(\.exerciseUUID))
        do {
            // RF-34: só os substitutos deste exercício, do mais ao menos parecido; o limite alto
            // cobre todos os candidatos de um padrão.
            substituteSuggestions = try planner.substitutes(for: exercise.exerciseUUID, limit: 20)
                .filter { !inSession.contains($0.id) }
        } catch {
            logger.error("Falha ao buscar substitutos: \(String(describing: error), privacy: .public)")
            substituteSuggestions = []
        }
        substitutingExerciseID = exercise.uuid
        isShowingSubstituteSheet = true
    }

    /// Troca o exercício da folha por `newExercise` só nesta sessão: o planner calcula a
    /// prescrição do novo mantendo o alvo do original, e o coordinator substitui o snapshot.
    /// O novo exercício tem histórico próprio (P3); sem histórico, é primeira vez (P2).
    func substituteSelectedExercise(with newExercise: ExerciseDefinition) {
        guard
            let session,
            let substitutingExerciseID,
            let exercise = findExercise(id: substitutingExerciseID),
            canSubstitute(exercise)
        else {
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
        // A carga digitada era do exercício antigo.
        chosenLoads[exercise.uuid] = nil
        closeSubstitution()
    }

    func cancelSubstitution() {
        closeSubstitution()
    }

    // MARK: - Corrigir / apagar série (RF-19)

    /// Abre "Corrigir série" para a série `setID` de qualquer exercício da sessão.
    func beginEditingSet(id setID: UUID) {
        guard isOpen else {
            return
        }
        for exercise in exercises {
            guard let setLog = exercise.sets.first(where: { $0.uuid == setID }) else {
                continue
            }
            // Posição entre as séries do mesmo tipo: as bolinhas só mostram as de trabalho.
            let siblings: [SetLogModel] = setLog.isWarmup
                ? exercise.sets.sorted(by: { $0.index < $1.index })
                : workingSets(of: exercise)
            let position = siblings.firstIndex(where: { $0.uuid == setID }) ?? 0
            let headline = TodayTargetText.headline(
                goal: goal(for: exercise),
                measure: measure(for: exercise),
                load: loadDisplay(for: exercise)
            )
            editingSet = SetEdit(
                setID: setLog.uuid,
                number: position + 1,
                load: setLog.load,
                reps: setLog.reps,
                rir: setLog.rir,
                loadIncrement: exercise.exercise?.loadIncrement ?? 2.5,
                loadUnit: loadUnit(of: exercise),
                repMin: exercise.prescribedRepMin,
                repMax: exercise.prescribedRepMax,
                measure: measure(for: exercise),
                isBodyweight: isBodyweight(exercise),
                plannedLine: SessionSheetText.plannedLine(exerciseName: exercise.exerciseName, headline: headline)
            )
            return
        }
    }

    /// Grava a correção (evento `setUpdated`) com o `rir` que a série já tinha. A próxima bolinha
    /// passa a copiar a carga corrigida, se ela for a última série (RF-04).
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
        }
    }

    /// Apaga a série (evento `setDeleted`). O exercício volta a ficar pendente.
    func deleteSet(id setID: UUID) {
        editingSet = nil
        guard let session else {
            return
        }
        do {
            try coordinator.deleteSet(sessionID: session.uuid, setID: setID, now: now())
        } catch {
            deferredErrorMessage = message(for: error, fallback: "Não foi possível apagar a série.")
        }
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

    // MARK: - Concluir (SPEC RF-44 e, F4)

    /// "Concluir": sem pendentes, conclui direto (`.finished`); com pendentes, devolve os nomes
    /// para a tela perguntar uma vez, e não grava nada.
    func requestFinish() -> SessionFinishRequest {
        let pending = pendingExercises
        guard !pending.isEmpty else {
            finish()
            return .finished
        }
        let hasAnySet = exercises.contains { workingSetCount(of: $0) > 0 }
        return .needsConfirmation(pendingNames: pending.map(\.exerciseName), hasAnySet: hasAnySet)
    }

    /// SPEC F4 / RF-02: `status = completed`. O descanso pendente é cancelado junto com a
    /// notificação (não faz sentido avisar "descanso terminou" depois da sessão).
    func finish() {
        guard let session else {
            return
        }
        do {
            try coordinator.finishSession(sessionID: session.uuid, now: now())
        } catch {
            errorMessage = message(for: error, fallback: "Não foi possível concluir a sessão.")
            return
        }
        restTimer.skip()
        isFinished = true
    }

    /// "Sair sem registrar": `status = abandoned`. Séries que existirem continuam no histórico
    /// (SPEC P3/S2).
    func abandon() {
        guard let session else {
            return
        }
        do {
            try coordinator.abandonSession(sessionID: session.uuid, now: now())
        } catch {
            errorMessage = message(for: error, fallback: "Não foi possível encerrar a sessão.")
            return
        }
        restTimer.skip()
        isFinished = true
    }

    // MARK: - Resumo (SPEC RF-44 h)

    /// Objetivo do programa ativo, para a flor do resumo. Falha → sem pétala preenchida (log).
    func activeGoal() -> ProgramGoal? {
        do {
            return try planner.activeProgramGoal()
        } catch {
            logger.error("Falha ao ler o objetivo ativo: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Nome do dia da próxima sessão ("Dia B — …"). Falha → a linha some do resumo (log).
    func nextSessionName() -> String? {
        do {
            return try planner.nextPlan(now: now())?.programDayName
        } catch {
            logger.error("Falha ao calcular a próxima sessão: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // MARK: - Privado

    private func findExercise(id: UUID) -> SessionExerciseModel? {
        exercises.first { $0.uuid == id }
    }

    /// Grava uma série como prevista (RF-04, RF-44 b). `index` = maior índice gravado + 1
    /// (aquecimentos antigos incluídos), único mesmo depois de apagar uma série do meio (RF-19).
    private func logPrescribedSet(for exercise: SessionExerciseModel, sessionID: UUID, now timestamp: Date) -> Bool {
        let index = (exercise.sets.map(\.index).max() ?? -1) + 1
        do {
            try coordinator.logSet(
                sessionID: sessionID,
                sessionExerciseID: exercise.uuid,
                index: index,
                load: workingLoad(for: exercise) ?? 0,
                reps: goal(for: exercise),
                rir: nil,
                isWarmup: false,
                now: timestamp
            )
            return true
        } catch {
            errorMessage = message(for: error, fallback: "Não foi possível registrar a série.")
            return false
        }
    }

    /// Próximo pendente depois de `exercise`, dando a volta ao início. `nil` se não resta nenhum.
    private func nextPendingExercise(after exercise: SessionExerciseModel) -> SessionExerciseModel? {
        let all = exercises
        guard let position = all.firstIndex(where: { $0.uuid == exercise.uuid }) else {
            return all.first { isPending($0) }
        }
        let following = Array(all[(position + 1)...]) + Array(all[..<position])
        return following.first { isPending($0) }
    }

    private func closeSubstitution() {
        isShowingSubstituteSheet = false
        substituteSuggestions = []
        substitutingExerciseID = nil
    }

    /// Alvo do exercício original reconstruído do snapshot (RF-34: a troca mantém séries, faixa,
    /// RIR e descanso). `exerciseID` já é o do exercício novo porque o motor copia
    /// `target.exerciseID` para a prescrição; `startingLoad` fica `nil` porque a carga inicial do
    /// original não vale para outro exercício (P3 é por exercício; sem histórico, P2).
    private func substitutionTarget(for exercise: SessionExerciseModel, newExerciseID: UUID) -> ExerciseTarget {
        var targetRIR = exercise.prescribedRIR
        // SPEC P2: primeira vez sem carga grava RIR alvo = T + 1. Sem desfazer aqui, um substituto
        // que também comece sem carga receberia T + 2.
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

    /// AGENTS §7: a permissão é pedida na primeira ação que precisa dela — a primeira série
    /// gravada, a partir da qual o timer de descanso passa a agendar avisos (RF-05) —, nunca no
    /// launch. Só depois de a série estar gravada, para o pedido nunca atrasar o registro
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
