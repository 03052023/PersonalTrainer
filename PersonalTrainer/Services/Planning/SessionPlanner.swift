import Foundation
import os
import SwiftData
import TrainerCore

/// Implementação de `SessionPlanning` (T1.2, M4). Orquestra o motor de `TrainerCore` sobre o
/// `ModelContext` (ARCHITECTURE §6): escolhe o dia com a rotação (S1–S2) ou com o
/// `FrequencyAwareSelector` (S5–S7), busca o histórico de cada exercício, pede a prescrição ao
/// `ProgressionRule` e, em semana leve (`DeloadScheduler`, SPEC §7.5), troca cada prescrição pela
/// de `DeloadPolicy`. Só lê o banco; as escritas são delegadas: iniciar a sessão ao
/// `SessionCoordinating` (ARCHITECTURE §7, AR-2) e as decisões de semana leve ao
/// `DeloadDecisionsStoring`.
///
/// Roda no `MainActor` porque lê `@Model` (ARCHITECTURE §10). `now` é sempre parâmetro; nenhum
/// `Date()` aqui (SPEC P11). SPEC S3 (retomar sessão em andamento) é de quem chama, conforme o
/// contrato de `SessionPlanning`.
@MainActor
final class SessionPlanner: SessionPlanning {
    private let modelContext: ModelContext
    private let coordinator: any SessionCoordinating
    private let progression: any ProgressionRule
    /// Seletor da sequência (SPEC S2), usado quando o seletor por frequência está desligado.
    private let selector: any WorkoutSelector
    private let deloadDecisions: any DeloadDecisionsStoring
    /// Lido a cada plano: mudar o Ajustes vale já no próximo `nextPlan`.
    private let settings: () -> PlannerSettings
    /// Calendário e fuso da semana de treino (SPEC §7.4), para S5–S7.
    private let calendar: Calendar
    /// AGENTS §4: `subsystem` = bundle id, `category` = nome do serviço.
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "SessionPlanner"
    )

    /// - Parameters:
    ///   - deloadDecisions: o app passa `LiveDeloadDecisionsStore()`. O padrão em memória existe
    ///     para testes e previews (AGENTS R9); com ele, "Fazer semana leve agora" e "Seguir
    ///     normal" não sobrevivem a um relançamento.
    ///   - settings: padrão lê `UserDefaults.standard` a cada chamada.
    ///   - calendar: padrão acompanha o fuso e o calendário do aparelho.
    init(
        modelContext: ModelContext,
        coordinator: any SessionCoordinating,
        progression: any ProgressionRule = DoubleProgressionRule(),
        selector: any WorkoutSelector = RotationSelector(),
        deloadDecisions: any DeloadDecisionsStoring = FakeDeloadDecisionsStore(),
        settings: @escaping () -> PlannerSettings = { PlannerSettings.load(from: .standard) },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.modelContext = modelContext
        self.coordinator = coordinator
        self.progression = progression
        self.selector = selector
        self.deloadDecisions = deloadDecisions
        self.settings = settings
        self.calendar = calendar
    }

    // MARK: - SessionPlanning

    func nextPlan(now: Date) throws -> SessionPlan? {
        guard let program = try activeProgram() else {
            return nil
        }
        let snapshot = try programSnapshot(of: program, now: now)
        guard !snapshot.template.days.isEmpty else {
            return nil
        }

        // SPEC S2: todas as sessões entram, inclusive as de dias que já não existem no programa;
        // os seletores tratam esse caso e ignoram `inProgress` sozinhos (SPEC S3).
        let sessions = try allSessionSummaries()
        let currentSettings = settings()
        guard let choice = try chooseNextDay(
            snapshot: snapshot,
            sessions: sessions,
            settings: currentSettings,
            now: now
        ) else {
            return nil
        }

        let deload = deloadStatus(snapshot: snapshot, sessions: sessions, settings: currentSettings, now: now)
        // CA4-5: a semana leve é o que mais muda o treino, então é ela que a Home explica.
        let reason = deload.planReason ?? choice.reason
        return makePlan(snapshot: snapshot, day: choice.day, deload: deload, reason: reason, now: now)
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        guard
            let program = try activeProgram(),
            program.days.contains(where: { $0.uuid == dayID })
        else {
            return nil
        }
        let snapshot = try programSnapshot(of: program, now: now)
        guard let day = snapshot.template.days.first(where: { $0.id == dayID }) else {
            return nil
        }
        // SPEC S4 + §7.5: o dia é da pessoa, mas uma semana leve programada ou em andamento vale
        // para qualquer dia, senão trocar de dia na Home driblaria o descanso.
        let sessions = try allSessionSummaries()
        let deload = deloadStatus(snapshot: snapshot, sessions: sessions, settings: settings(), now: now)
        return makePlan(snapshot: snapshot, day: day, deload: deload, reason: .manual, now: now)
    }

    func startSession(from plan: SessionPlan, now: Date) throws -> UUID {
        // RF-02: no máximo uma sessão em andamento. O coordinator repete a checagem, mas o erro
        // daqui é o do contrato de planejamento (`PlanningError`), que a Home entende.
        if let active = coordinator.activeSession {
            throw PlanningError.sessionAlreadyInProgress(active.uuid)
        }
        return try coordinator.startSession(plan: plan, now: now, source: .iphone)
    }

    // MARK: - SessionPlanning (M2)

    /// Dias do programa ativo para o seletor manual da Home (T2.14, SPEC S4). O mapper já
    /// ordena por `order` (SPEC S1). Relação de catálogo anulada lança
    /// `PlanningError.exerciseNotFound`, como em `nextPlan`.
    func activeProgramDays() throws -> [ProgramDayTemplate] {
        guard let program = try activeProgram() else {
            return []
        }
        return try programTemplate(from: program).days
    }

    /// SPEC §7.9: `goalRaw` desconhecido (versão futura, store editado) vale como hipertrofia,
    /// o mesmo padrão de `ProgramTemplate.effectiveGoal`.
    func activeProgramGoal() throws -> ProgramGoal? {
        guard let program = try activeProgram() else {
            return nil
        }
        return program.goal ?? .hypertrophy
    }

    /// RF-34: mantém do alvo original séries, faixa, RIR, descanso, ordem e `id`; o motor roda
    /// com o histórico do NOVO exercício (P3 é por exercício).
    ///
    /// `startingLoad` só é mantido quando se volta ao próprio exercício do alvo: a carga inicial
    /// de um supino com barra não serve para halteres, e com ela o P2 prescreveria essa carga em
    /// vez de deixar o usuário calibrar. `exerciseID` passa a ser o do substituto, porque o
    /// motor o copia para `ExercisePrescription.exerciseID`.
    ///
    /// SPEC §7.5: se o exercício trocado pertence a uma sessão de semana leve, o substituto
    /// também recebe a prescrição de semana leve; a sessão inteira é leve.
    func substitutionPlan(
        replacing sessionExerciseID: UUID,
        target: ExerciseTarget,
        newExerciseID: UUID,
        now: Date
    ) throws -> PlannedExercise {
        guard let exerciseModel = try fetchExercise(uuid: newExerciseID) else {
            throw PlanningError.exerciseNotFound(newExerciseID)
        }
        let exercise = try ExerciseMapper.definition(from: exerciseModel)
        let substituteTarget = ExerciseTarget(
            id: target.id,
            exerciseID: exercise.id,
            order: target.order,
            sets: target.sets,
            repMin: target.repMin,
            repMax: target.repMax,
            targetRIR: target.targetRIR,
            restSeconds: target.restSeconds,
            startingLoad: exercise.id == target.exerciseID ? target.startingLoad : nil
        )
        let entries = try history(forExerciseUUID: exercise.id)
        let normal = progression.prescribe(
            target: substituteTarget,
            exercise: exercise,
            history: entries,
            now: now
        )
        let prescription = try isInDeloadSession(sessionExerciseID: sessionExerciseID)
            ? SessionPlanner.deloadPrescription(from: normal, exercise: exercise)
            : normal
        // Mesmo id do exercício substituído: o coordinator reescreve o snapshot existente.
        return PlannedExercise(
            id: sessionExerciseID,
            exercise: exercise,
            target: substituteTarget,
            prescription: prescription
        )
    }

    /// RF-34: candidatos do catálogo não arquivado, ranqueados por `ExerciseSubstitution`. O
    /// próprio exercício é excluído. Vazio se ele não tem padrão de movimento (contrato de
    /// `SessionPlanning`) ou se `limit <= 0`. O exercício de origem pode estar arquivado (ainda
    /// está no programa ou na sessão); só os candidatos precisam estar visíveis.
    func substitutes(for exerciseID: UUID, limit: Int) throws -> [ExerciseDefinition] {
        guard let exerciseModel = try fetchExercise(uuid: exerciseID) else {
            throw PlanningError.exerciseNotFound(exerciseID)
        }
        let exercise = try ExerciseMapper.definition(from: exerciseModel)
        guard exercise.movementPattern != nil, limit > 0 else {
            return []
        }
        let catalog = try visibleCatalog()
        return ExerciseSubstitution.candidates(
            for: exercise,
            in: catalog,
            excluding: [exerciseID],
            limit: limit
        )
    }

    // MARK: - SessionPlanning (M4)

    func deloadStatus(now: Date) throws -> DeloadStatus {
        guard let program = try activeProgram() else {
            return .inactive
        }
        let snapshot = try programSnapshot(of: program, now: now)
        guard !snapshot.template.days.isEmpty else {
            return .inactive
        }
        let sessions = try allSessionSummaries()
        return deloadStatus(snapshot: snapshot, sessions: sessions, settings: settings(), now: now)
    }

    func requestDeload(now: Date) throws {
        let status = try deloadStatus(now: now)
        guard case .inactive = status else {
            // Já há semana leve programada ou em andamento. Regravar a data de um pedido que
            // espera mudaria o `since` da mensagem C1 e a faria voltar (docs/V2-FINAL-CONTRACT.md
            // §2); um pedido durante a passagem, que nenhuma sessão leve posterior atenderia,
            // emendaria uma segunda semana leve logo depois da atual.
            logger.info("Pedido de semana leve ignorado: já há uma programada ou em andamento.")
            return
        }
        var decisions = deloadDecisions.load()
        decisions.manualRequestedAt = now
        try deloadDecisions.save(decisions)
        logger.info("Semana leve pedida pela pessoa.")
    }

    func dismissDeload(now: Date) throws {
        let status = try deloadStatus(now: now)
        guard case .pending = status else {
            // Passagem em andamento não se desfaz, e sem semana leve não há o que dispensar
            // (docs/V2-FINAL-CONTRACT.md §2, ajustes da onda 2).
            logger.info("\"Seguir normal\" ignorado: não há semana leve programada.")
            return
        }
        var decisions = deloadDecisions.load()
        decisions.dismissedAt = now
        // `DeloadScheduler` não deixa `dismissedAt` cancelar um pedido manual; sem limpar o
        // pedido, "Seguir normal" numa semana leve pedida à mão não teria efeito.
        decisions.manualRequestedAt = nil
        try deloadDecisions.save(decisions)
        logger.info("Semana leve dispensada pela pessoa.")
    }

    func completedSessionSummaries() throws -> [SessionSummary] {
        try allSessionSummaries()
            .filter { $0.status == .completed }
            .sorted(by: SessionPlanner.isChronological)
    }

    /// SPEC P3/P9: concluídas e abandonadas, como o histórico do motor; `inProgress` fica fora.
    func finishedSessionSummaries() throws -> [SessionSummary] {
        try allSessionSummaries()
            .filter { $0.status == .completed || $0.status == .abandoned }
            .sorted(by: SessionPlanner.isChronological)
    }

    /// SPEC §7.8 sobre o programa ativo:
    /// - uma entrada por exercício do programa (`ProgramExerciseModel`), com o histórico do
    ///   exercício (sessões concluídas ou abandonadas, P3);
    /// - `sessions`: só as dos dias do programa ativo (R4); `programStartDate` é a mais antiga
    ///   delas com ≥ 1 série de trabalho, concluída ou abandonada;
    /// - `currentPrescriptions`: as de hoje. Em semana leve, as de SPEC §7.5 (nota `deload`),
    ///   o que faz a revisão não sugerir outra semana leve em cima da programada;
    /// - volume alvo do objetivo (SPEC §7.9) e início da semana do `UserSettingsModel`.
    func reviewInput(now: Date, recovery: RecoveryContext) throws -> ReviewInput? {
        guard let program = try activeProgram() else {
            return nil
        }
        let snapshot = try programSnapshot(of: program, now: now)
        let template = snapshot.template
        guard !template.days.isEmpty else {
            return nil
        }

        let sessions = try allSessionSummaries()
        let dayIDs = Set(template.days.map { $0.id })
        let programSessions = sessions.filter { dayIDs.contains($0.programDayID) }
        let programStartDate = programSessions
            .filter { $0.status != .inProgress && $0.workingSetCount >= 1 }
            .map { $0.startedAt }
            .min()

        let deload = deloadStatus(snapshot: snapshot, sessions: sessions, settings: settings(), now: now)
        let plansDeload = deload.plansDeload
        let prescriptions = snapshot.slots.map { slot in
            plansDeload ? SessionPlanner.deloadPrescription(from: slot.normal, exercise: slot.exercise) : slot.normal
        }
        let exercises = snapshot.slots.map { slot in
            ExerciseReviewInput(
                exercise: slot.exercise,
                targetID: slot.target.id,
                dayID: slot.dayID,
                sets: slot.target.sets,
                repMin: slot.target.repMin,
                repMax: slot.target.repMax,
                history: snapshot.histories[slot.exercise.id] ?? []
            )
        }
        let week = try weekSettings()

        return ReviewInput(
            programID: template.id,
            programName: template.name,
            programDayCount: template.days.count,
            programStartDate: programStartDate,
            exercises: exercises,
            sessions: programSessions,
            weeklySetTarget: template.effectiveGoal.defaults.weeklySetsPerMuscle,
            currentPrescriptions: prescriptions,
            recovery: recovery,
            weekStartsOnMonday: week.startsOnMonday
        )
    }
}

// MARK: - Programa ativo já calculado

private extension SessionPlanner {
    /// Um exercício do programa ativo com a prescrição normal de hoje (sem semana leve).
    struct ProgramSlot {
        let dayID: UUID
        let exercise: ExerciseDefinition
        let target: ExerciseTarget
        let normal: ExercisePrescription
    }

    /// O programa ativo com tudo o que plano, semana leve e revisão leem, calculado uma vez por
    /// chamada pública.
    struct ProgramSnapshot {
        let template: ProgramTemplate
        /// Um por `ProgramExerciseModel`: dias em `order`, exercícios em `order` dentro do dia.
        let slots: [ProgramSlot]
        /// Histórico por `ExerciseDefinition.id`, como o motor o recebe (P3).
        let histories: [UUID: [ExerciseHistoryEntry]]
    }

    /// Dia escolhido pelo seletor e o motivo, antes de considerar a semana leve.
    struct DayChoice {
        let day: ProgramDayTemplate
        let reason: PlanReason
    }

    /// Metas por grupo e início da semana gravados pelo usuário (SPEC §7.4).
    struct WeekSettings {
        let targets: [MuscleGroup: Int]
        let startsOnMonday: Bool
    }

    /// Relação de catálogo anulada lança `PlanningError.exerciseNotFound` com o id do
    /// `ProgramExerciseModel` (via `programTemplate`), em qualquer dia do programa: a semana leve
    /// (SPEC §7.5 a) e a revisão leem o programa inteiro, então um store corrompido falha igual
    /// em `nextPlan`, `plan(forDayID:)`, `deloadStatus` e `reviewInput`.
    func programSnapshot(of program: ProgramModel, now: Date) throws -> ProgramSnapshot {
        let template = try programTemplate(from: program)
        var slots: [ProgramSlot] = []
        var histories: [UUID: [ExerciseHistoryEntry]] = [:]

        for day in program.days.sorted(by: { $0.order < $1.order }) {
            for programExercise in day.exercises.sorted(by: { $0.order < $1.order }) {
                guard let exerciseModel = programExercise.exercise else {
                    // O catálogo nunca é apagado (ARCHITECTURE §5); relação nula é store corrompido.
                    throw PlanningError.exerciseNotFound(programExercise.uuid)
                }
                let exercise = try ExerciseMapper.definition(from: exerciseModel)
                let target = try ProgramMapper.target(from: programExercise)
                // O mesmo exercício pode estar em dois dias; o histórico é buscado uma vez só.
                let entries: [ExerciseHistoryEntry]
                if let cached = histories[exercise.id] {
                    entries = cached
                } else {
                    entries = try history(forExerciseUUID: exercise.id)
                    histories[exercise.id] = entries
                }
                let normal = progression.prescribe(
                    target: target,
                    exercise: exercise,
                    history: entries,
                    now: now
                )
                slots.append(ProgramSlot(dayID: day.uuid, exercise: exercise, target: target, normal: normal))
            }
        }
        return ProgramSnapshot(template: template, slots: slots, histories: histories)
    }

    /// SPEC §7.5 com o rearme e as decisões da pessoa, derivado do histórico a cada chamada
    /// (ARCHITECTURE ADR 003). Uma prescrição por exercício do programa, como em §7.5 (a).
    func deloadStatus(
        snapshot: ProgramSnapshot,
        sessions: [SessionSummary],
        settings: PlannerSettings,
        now: Date
    ) -> DeloadStatus {
        DeloadScheduler.status(
            normalPrescriptions: snapshot.slots.map { $0.normal },
            histories: snapshot.histories,
            sessions: sessions,
            programDayCount: snapshot.template.days.count,
            decisions: deloadDecisions.load(),
            weeksBetweenDeloads: settings.deloadWeeks,
            now: now
        )
    }
}

// MARK: - Escolha do dia (SPEC S1–S2, S5–S7)

private extension SessionPlanner {
    /// Rotação por padrão; com o seletor por frequência ligado (RF-39), `FrequencyAwareSelector`
    /// com os grupos primários de cada dia e as metas do `UserSettingsModel`.
    func chooseNextDay(
        snapshot: ProgramSnapshot,
        sessions: [SessionSummary],
        settings: PlannerSettings,
        now: Date
    ) throws -> DayChoice? {
        let template = SessionPlanner.trainableTemplate(snapshot.template)
        guard settings.usesFrequencySelector(programDayCount: template.days.count) else {
            guard let day = selector.nextDay(program: template, recentSessions: sessions, now: now) else {
                return nil
            }
            return DayChoice(day: day, reason: .rotation)
        }

        let week = try weekSettings()
        // SPEC S5: "grupos primários do dia" = primários dos exercícios do programa naquele dia.
        var dayMuscles: [UUID: Set<MuscleGroup>] = [:]
        for slot in snapshot.slots {
            dayMuscles[slot.dayID, default: []].formUnion(slot.exercise.primaryMuscles)
        }
        let frequencySelector = FrequencyAwareSelector(
            weeklyTargets: week.targets,
            calendar: calendar,
            weekStartsOnMonday: week.startsOnMonday,
            dayMuscles: dayMuscles
        )
        guard let day = frequencySelector.nextDay(program: template, recentSessions: sessions, now: now) else {
            return nil
        }
        let reason = frequencyReason(
            muscles: dayMuscles[day.id] ?? [],
            sessions: sessions,
            week: week,
            now: now
        ) ?? .rotation
        return DayChoice(day: day, reason: reason)
    }

    /// RF-33/RF-36: um dia sem exercícios (recém-acrescentado no editor) fica fora da escolha
    /// automática. Uma sessão vazia não move a rotação (S2 pede ≥ 1 série de trabalho), então a
    /// Home voltaria a propor o mesmo dia. Escolhido à mão (S4) ele ainda abre. Se nenhum dia tem
    /// exercícios, vale o programa inteiro.
    nonisolated static func trainableTemplate(_ template: ProgramTemplate) -> ProgramTemplate {
        let trainable = template.days.filter { !$0.exercises.isEmpty }
        guard !trainable.isEmpty, trainable.count < template.days.count else {
            return template
        }
        return ProgramTemplate(
            id: template.id,
            name: template.name,
            days: trainable,
            isActive: template.isActive,
            goal: template.goal,
            summary: template.summary
        )
    }

    /// CA4-5: o grupo do dia mais longe da meta semanal, com a mesma conta do painel "Esta
    /// semana" (`WeeklyFrequency.report`, SPEC §7.4). Empate de diferença fica com o primeiro de
    /// `MuscleGroup.allCases`, a ordem das entradas do relatório. `nil` se nenhum grupo do dia
    /// está abaixo da meta: o dia saiu da ordem da rotação (S7) e o motivo é `.rotation`.
    func frequencyReason(
        muscles: Set<MuscleGroup>,
        sessions: [SessionSummary],
        week: WeekSettings,
        now: Date
    ) -> PlanReason? {
        let report = WeeklyFrequency.report(
            sessions: sessions,
            targets: week.targets,
            now: now,
            weekStartsOnMonday: week.startsOnMonday,
            calendar: calendar
        )
        var best: WeeklyFrequencyEntry?
        for entry in report.entries where muscles.contains(entry.muscle) && entry.completed < entry.target {
            if let current = best, current.target - current.completed >= entry.target - entry.completed {
                continue
            }
            best = entry
        }
        guard let best else {
            return nil
        }
        return PlanReason.frequency(muscle: best.muscle, done: best.completed, target: best.target)
    }

    /// Linha única de `UserSettingsModel` (ARCHITECTURE §5); se houver mais de uma, a escolha é
    /// determinística, como no painel da Home. Sem linha: metas padrão (2×) e semana na segunda.
    func weekSettings() throws -> WeekSettings {
        let rows = try modelContext.fetch(FetchDescriptor<UserSettingsModel>())
        let row = rows.min { $0.uuid.uuidString < $1.uuid.uuidString }
        return WeekSettings(
            targets: row?.weeklyTargets ?? [:],
            startsOnMonday: row?.weekStartsOnMonday ?? true
        )
    }
}

// MARK: - Montagem do plano

private extension SessionPlanner {
    /// Uma prescrição por exercício do dia, na ordem de `order` (SPEC RF-01). Nada é gravado: o
    /// plano é um DTO que `SessionCoordinating.startSession` transforma em snapshots
    /// (ARCHITECTURE §5, decisão 3).
    func makePlan(
        snapshot: ProgramSnapshot,
        day: ProgramDayTemplate,
        deload: DeloadStatus,
        reason: PlanReason,
        now: Date
    ) -> SessionPlan {
        let plansDeload = deload.plansDeload
        let planned = snapshot.slots
            .filter { $0.dayID == day.id }
            .map { slot in
                PlannedExercise(
                    id: UUID(),
                    exercise: slot.exercise,
                    target: slot.target,
                    prescription: plansDeload
                        ? SessionPlanner.deloadPrescription(from: slot.normal, exercise: slot.exercise)
                        : slot.normal
                )
            }

        return SessionPlan(
            programID: snapshot.template.id,
            programName: snapshot.template.name,
            programDayID: day.id,
            programDayName: day.name,
            exercises: planned,
            generatedAt: now,
            isDeload: plansDeload,
            reason: reason
        )
    }

    /// SPEC §7.5 sobre a prescrição normal do dia (C), com o mínimo de P8.
    nonisolated static func deloadPrescription(
        from normal: ExercisePrescription,
        exercise: ExerciseDefinition
    ) -> ExercisePrescription {
        DeloadPolicy.deloadPrescription(
            from: normal,
            loadIncrement: exercise.loadIncrement,
            isBodyweight: exercise.equipment == .bodyweight
        )
    }
}

// MARK: - Leitura do banco

private extension SessionPlanner {
    /// Programa com `isActive == true`. Deveria haver só um; se houver mais (store editado à mão
    /// ou bug de repositório), vale o mais antigo, com desempate por `uuid` para ser
    /// determinístico (SPEC P11). Ordenação em memória: são um ou dois registros.
    func activeProgram() throws -> ProgramModel? {
        let descriptor = FetchDescriptor<ProgramModel>(
            predicate: #Predicate<ProgramModel> { $0.isActive == true }
        )
        let activePrograms = try modelContext.fetch(descriptor)
        return activePrograms.min { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.uuid.uuidString < rhs.uuid.uuidString
        }
    }

    /// `ProgramMapper.template` lança `MappingError.missingExercise` para relação anulada; aqui
    /// vira `PlanningError.exerciseNotFound` para que todos os caminhos falhem com o mesmo erro
    /// diante do mesmo store corrompido (ver `programSnapshot`).
    func programTemplate(from program: ProgramModel) throws -> ProgramTemplate {
        do {
            return try ProgramMapper.template(from: program)
        } catch MappingError.missingExercise(let programExerciseUUID) {
            throw PlanningError.exerciseNotFound(programExerciseUUID)
        }
    }

    /// Todas as sessões, em qualquer status, como os seletores (SPEC S2, S5–S7), o
    /// `DeloadScheduler` (SPEC §7.5, com `isDeload`) e a revisão as leem.
    func allSessionSummaries() throws -> [SessionSummary] {
        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSessionModel>())
        return try sessions.map { try SessionSummaryMapper.summary(from: $0) }
    }

    /// Da mais antiga para a mais recente; empate de `startedAt` pelo `id` (SPEC P11).
    nonisolated static func isChronological(_ lhs: SessionSummary, _ rhs: SessionSummary) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Histórico de UM exercício (ARCHITECTURE §6): o filtro por `exerciseUUID` é feito no banco;
    /// o mapper refiltra por status (`completed`/`abandoned`, SPEC P3) e ordena.
    func history(forExerciseUUID exerciseUUID: UUID) throws -> [ExerciseHistoryEntry] {
        let uuid = exerciseUUID
        let descriptor = FetchDescriptor<SessionExerciseModel>(
            predicate: #Predicate<SessionExerciseModel> { $0.exerciseUUID == uuid }
        )
        let sessionExercises = try modelContext.fetch(descriptor)
        return try HistoryMapper.historyEntries(from: sessionExercises, exerciseUUID: uuid)
    }

    /// `true` quando o exercício de sessão `sessionExerciseID` existe e a sessão dele é de
    /// semana leve. Um id que não está no banco (plano ainda não iniciado) conta como normal.
    func isInDeloadSession(sessionExerciseID: UUID) throws -> Bool {
        let uuid = sessionExerciseID
        var descriptor = FetchDescriptor<SessionExerciseModel>(
            predicate: #Predicate<SessionExerciseModel> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.session?.isDeload ?? false
    }

    /// Inclui arquivados: quem chama decide se isso importa.
    func fetchExercise(uuid: UUID) throws -> ExerciseModel? {
        var descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate<ExerciseModel> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    /// Catálogo não arquivado, ordenado por `slug` para que a entrada do ranqueamento seja
    /// determinística (SPEC P11). Um exercício com raw value inválido é pulado e logado: é
    /// uma lista de sugestões, e um registro corrompido não deve esconder os outros.
    func visibleCatalog() throws -> [ExerciseDefinition] {
        let descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate<ExerciseModel> { $0.isArchived == false }
        )
        let models = try modelContext.fetch(descriptor)
        var definitions: [ExerciseDefinition] = []
        definitions.reserveCapacity(models.count)
        for model in models {
            do {
                definitions.append(try ExerciseMapper.definition(from: model))
            } catch {
                let slug = model.slug
                let reason = String(describing: error)
                logger.error("Exercício \(slug, privacy: .public) fora dos substitutos: \(reason, privacy: .public)")
            }
        }
        return definitions.sorted { $0.slug < $1.slug }
    }
}

// MARK: - Semana leve no plano

private extension DeloadStatus {
    /// SPEC §7.5: `pending` e `active` pedem as prescrições de semana leve no próximo plano.
    var plansDeload: Bool {
        switch self {
        case .inactive:
            return false
        case .pending, .active:
            return true
        }
    }

    /// CA4-5: o gatilho enquanto a semana leve está programada; `nil` durante a passagem.
    var planReason: PlanReason? {
        switch self {
        case .inactive:
            return nil
        case .pending(let trigger):
            return .deload(trigger)
        case .active:
            return .deload(nil)
        }
    }
}
