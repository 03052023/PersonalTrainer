import Foundation
import os
import SwiftData
import TrainerCore

/// Implementação de `SessionPlanning` (T1.2). Orquestra o motor de `TrainerCore` sobre o
/// `ModelContext` (ARCHITECTURE §6): escolhe o dia com o `WorkoutSelector`, busca o histórico
/// de cada exercício e pede a prescrição ao `ProgressionRule`. Só lê o banco; a única escrita
/// (iniciar a sessão) é delegada ao `SessionCoordinating` (ARCHITECTURE §7, AR-2).
///
/// Roda no `MainActor` porque lê `@Model` (ARCHITECTURE §10). `now` é sempre parâmetro; nenhum
/// `Date()` aqui (SPEC P11). SPEC S3 (retomar sessão em andamento) é de quem chama, conforme o
/// contrato de `SessionPlanning`.
@MainActor
final class SessionPlanner: SessionPlanning {
    private let modelContext: ModelContext
    private let coordinator: any SessionCoordinating
    private let progression: any ProgressionRule
    private let selector: any WorkoutSelector
    /// AGENTS §4: `subsystem` = bundle id, `category` = nome do serviço.
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "SessionPlanner"
    )

    init(
        modelContext: ModelContext,
        coordinator: any SessionCoordinating,
        progression: any ProgressionRule = DoubleProgressionRule(),
        selector: any WorkoutSelector = RotationSelector()
    ) {
        self.modelContext = modelContext
        self.coordinator = coordinator
        self.progression = progression
        self.selector = selector
    }

    // MARK: - SessionPlanning

    func nextPlan(now: Date) throws -> SessionPlan? {
        guard let program = try activeProgram() else {
            return nil
        }
        let template = try programTemplate(from: program)
        guard !template.days.isEmpty else {
            return nil
        }

        // SPEC S2: todas as sessões entram, inclusive as de dias que já não existem no programa;
        // o seletor trata esse caso (reinicia em D1) e ignora `inProgress` sozinho (SPEC S3).
        let recentSessions = try recentSessionSummaries()
        guard
            let nextDay = selector.nextDay(program: template, recentSessions: recentSessions, now: now),
            let day = program.days.first(where: { $0.uuid == nextDay.id })
        else {
            return nil
        }
        return try buildPlan(program: program, day: day, now: now)
    }

    func plan(forDayID dayID: UUID, now: Date) throws -> SessionPlan? {
        guard
            let program = try activeProgram(),
            let day = program.days.first(where: { $0.uuid == dayID })
        else {
            return nil
        }
        return try buildPlan(program: program, day: day, now: now)
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
        let prescription = progression.prescribe(
            target: substituteTarget,
            exercise: exercise,
            history: entries,
            now: now
        )
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
    /// vira `PlanningError.exerciseNotFound` para que `nextPlan` e `plan(forDayID:)` falhem com o
    /// mesmo erro diante do mesmo store corrompido (ver `buildPlan`).
    func programTemplate(from program: ProgramModel) throws -> ProgramTemplate {
        do {
            return try ProgramMapper.template(from: program)
        } catch MappingError.missingExercise(let programExerciseUUID) {
            throw PlanningError.exerciseNotFound(programExerciseUUID)
        }
    }

    /// Entrada do seletor (SPEC S2). Sem catálogo auxiliar: a relação `exercise` só é anulada se o
    /// catálogo for apagado, o que o esquema não permite (ARCHITECTURE §5), e a rotação v1 não lê
    /// `primaryMusclesTrained`.
    func recentSessionSummaries() throws -> [SessionSummary] {
        let sessions = try modelContext.fetch(FetchDescriptor<WorkoutSessionModel>())
        return try sessions.map { try SessionSummaryMapper.summary(from: $0) }
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

// MARK: - Montagem do plano

private extension SessionPlanner {
    /// Uma prescrição por `ProgramExerciseModel` do dia, na ordem de `order` (SPEC RF-01).
    /// Nada é gravado: o plano é um DTO que `SessionCoordinating.startSession` transforma em
    /// snapshots (ARCHITECTURE §5, decisão 3).
    func buildPlan(program: ProgramModel, day: ProgramDayModel, now: Date) throws -> SessionPlan {
        let programExercises = day.exercises.sorted { $0.order < $1.order }
        var planned: [PlannedExercise] = []
        planned.reserveCapacity(programExercises.count)

        for programExercise in programExercises {
            guard let exerciseModel = programExercise.exercise else {
                // O catálogo nunca é apagado (ARCHITECTURE §5); relação nula é store corrompido.
                throw PlanningError.exerciseNotFound(programExercise.uuid)
            }
            let exercise = try ExerciseMapper.definition(from: exerciseModel)
            let target = try ProgramMapper.target(from: programExercise)
            let entries = try history(forExerciseUUID: exercise.id)
            let prescription = progression.prescribe(
                target: target,
                exercise: exercise,
                history: entries,
                now: now
            )
            planned.append(
                PlannedExercise(
                    id: UUID(),
                    exercise: exercise,
                    target: target,
                    prescription: prescription
                )
            )
        }

        return SessionPlan(
            programID: program.uuid,
            programName: program.name,
            programDayID: day.uuid,
            programDayName: day.name,
            exercises: planned,
            generatedAt: now
        )
    }
}
