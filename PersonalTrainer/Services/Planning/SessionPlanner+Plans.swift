import Foundation
import os
import SwiftData
import TrainerCore

/// Vários planos no planejador (SPEC §7.15 M1–M9, §7.3 S8, §7.16 W2; docs/V23-UI-CONTRACT.md §3.3 e §4.5).
///
/// - Os planos ativos vêm de `activePrograms()`, o principal primeiro (M1).
/// - Com dois planos, cada um tem a própria rotação (S8) e o seletor por frequência (S5–S7) fica desligado;
///   a semana leve e a revisão são só do principal (M2).
/// - A semana ideal é a de `WeeklyFit.fit` (M4, M5), com cada plano rodado até a fase do começo da semana
///   (M3: S2 com as sessões iniciadas antes de segunda 00:00).
/// - As escolhas da semana ficam em `PlannerSettings.weekPreferences` (M9), fora do backup.
///
/// Só lê o banco (AGENTS R4); `now` é sempre parâmetro (SPEC P11).
extension SessionPlanner {
    // MARK: - Planos ativos

    func activeProgramGoals() throws -> [ProgramGoal] {
        try activePrograms().map { $0.goal ?? .hypertrophy }
    }

    func nextPlan(forProgramID programID: UUID, now: Date) throws -> SessionPlan? {
        let programs = try activePrograms()
        guard let index = programs.firstIndex(where: { $0.uuid == programID }) else {
            return nil
        }
        let sessions = try allSessionSummaries()
        return try rotationPlan(
            for: programs[index],
            isPrincipal: index == 0,
            isMultiPlan: programs.count > 1,
            sessions: sessions,
            settings: settings(),
            now: now
        )
    }

    func days(ofProgramID programID: UUID) throws -> [ProgramDayTemplate] {
        guard let program = try activePrograms().first(where: { $0.uuid == programID }) else {
            return []
        }
        return try programTemplate(from: program).days
    }

    // MARK: - Tela Hoje (M6)

    /// Com um plano, a próxima sessão dele, como na 2.2, com "Feito hoje" para o Início (RF-49: "Tudo feito
    /// por hoje." e "Ver o dia"; a tela Hoje com um plano não lê isto). Com dois, as sessões da semana ideal
    /// para o dia de hoje (M6).
    func todayOverview(now: Date) throws -> TodayOverview {
        let programs = try activePrograms()
        guard let principal = programs.first else {
            return TodayOverview.empty
        }
        let sessions = try allSessionSummaries()
        let currentSettings = settings()
        guard programs.count > 1 else {
            guard let plan = try rotationPlan(
                for: principal,
                isPrincipal: true,
                isMultiPlan: false,
                sessions: sessions,
                settings: currentSettings,
                now: now
            ) else {
                return TodayOverview.empty
            }
            return TodayOverview(sessions: [
                TodaySession(
                    plan: plan,
                    goal: principal.goal ?? .hypertrophy,
                    isDoneToday: wasTrainedToday(principal, sessions: sessions, now: now)
                ),
            ])
        }
        return try multiPlanOverview(programs: programs, sessions: sessions, settings: currentSettings, now: now)
    }

    /// SPEC §7.15 M6 com dois planos:
    /// - as sessões de hoje são as da semana ideal para o dia da semana de hoje, na ordem do dia (força antes
    ///   do aeróbico), cada uma a próxima da rotação do seu plano (S8);
    /// - "Feito hoje" quando o plano teve hoje uma sessão concluída ou abandonada com ao menos uma série de
    ///   trabalho;
    /// - sem nenhuma sessão hoje, dia de descanso, com a próxima de cada plano em `otherSessions`;
    /// - se os planos não cabem mais nos dias escolhidos, a próxima do principal, a do outro em
    ///   `otherSessions` e `fitsWeek` falso.
    func multiPlanOverview(
        programs: [ProgramModel],
        sessions: [SessionSummary],
        settings currentSettings: PlannerSettings,
        now: Date
    ) throws -> TodayOverview {
        var nextSessions: [TodaySession] = []
        for (index, program) in programs.enumerated() {
            guard let plan = try rotationPlan(
                for: program,
                isPrincipal: index == 0,
                isMultiPlan: true,
                sessions: sessions,
                settings: currentSettings,
                now: now
            ) else {
                continue
            }
            let isDoneToday = wasTrainedToday(program, sessions: sessions, now: now)
            nextSessions.append(TodaySession(plan: plan, goal: program.goal ?? .hypertrophy, isDoneToday: isDoneToday))
        }

        let preferences = activeWeekPreferences(currentSettings.weekPreferences, programs: programs)
        let fit = try weekFit(programs: programs, preferences: preferences, sessions: sessions, now: now)
        guard let schedule = fit.schedule else {
            return TodayOverview(
                sessions: Array(nextSessions.prefix(1)),
                otherSessions: Array(nextSessions.dropFirst()),
                isRestDay: false,
                fitsWeek: false
            )
        }

        let weekday = PlanWeekday.of(now, calendar: calendar)
        var todaySessions: [TodaySession] = []
        for slot in schedule.slots(on: weekday) {
            guard
                let session = nextSessions.first(where: { $0.plan.programID == slot.programID }),
                !todaySessions.contains(where: { $0.id == session.id })
            else {
                continue
            }
            todaySessions.append(session)
        }
        let otherSessions = nextSessions.filter { session in
            !todaySessions.contains { $0.id == session.id }
        }
        return TodayOverview(
            sessions: todaySessions,
            otherSessions: otherSessions,
            isRestDay: todaySessions.isEmpty,
            fitsWeek: true
        )
    }

    /// "Feito hoje" (M6, RF-49): hoje, no calendário do planejador, houve uma sessão concluída ou abandonada
    /// com ao menos uma série de trabalho num dia de `program`.
    func wasTrainedToday(_ program: ProgramModel, sessions: [SessionSummary], now: Date) -> Bool {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? startOfToday.addingTimeInterval(86_400)
        let dayIDs = Set(program.days.map { $0.uuid })
        return sessions.contains { session in
            dayIDs.contains(session.programDayID)
                && session.status != .inProgress
                && session.workingSetCount >= 1
                && session.startedAt >= startOfToday
                && session.startedAt < startOfTomorrow
        }
    }

    // MARK: - Semana (M4, M5, M9)

    /// A semana ideal dos dois planos ativos, com as escolhas gravadas; `nil` com um plano só ou quando os
    /// planos não cabem.
    func weekSchedule(now: Date) throws -> WeekSchedule? {
        let programs = try activePrograms()
        guard programs.count > 1 else {
            return nil
        }
        let preferences = activeWeekPreferences(settings().weekPreferences, programs: programs)
        let sessions = try allSessionSummaries()
        return try weekFit(programs: programs, preferences: preferences, sessions: sessions, now: now).schedule
    }

    /// As escolhas gravadas (M9), sem os ids de planos que não estão ativos. Numa falha de leitura dos
    /// planos, as escolhas como estão.
    func weekPreferences() -> WeekPreferences {
        let stored = settings().weekPreferences
        do {
            return activeWeekPreferences(stored, programs: try activePrograms())
        } catch {
            let reason = String(describing: error)
            logger.error("Planos ativos indisponíveis para as escolhas da semana: \(reason, privacy: .public)")
            return stored
        }
    }

    /// Grava como está, com os ids de planos ainda inativos: o fluxo de adicionar grava as escolhas antes
    /// de ativar o segundo plano (docs/V23-UI-CONTRACT.md §4.6).
    func saveWeekPreferences(_ preferences: WeekPreferences) throws {
        try storeWeekPreferences(preferences)
        logger.info("Escolhas da semana gravadas.")
    }

    /// O encaixe de `programIDs` (ativos ou não, como o plano que a pessoa quer acrescentar) com
    /// `preferences`, sem gravar nada. Ids que não existem ficam de fora (com log).
    func fitCheck(programIDs: [UUID], preferences: WeekPreferences, now: Date) throws -> FitResult {
        var programs: [ProgramModel] = []
        for programID in programIDs where !programs.contains(where: { $0.uuid == programID }) {
            guard let program = try fetchProgram(uuid: programID) else {
                logger.error("Programa \(programID.uuidString, privacy: .public) fora do encaixe: não existe.")
                continue
            }
            programs.append(program)
        }
        let ordered = programs.sorted { lhs, rhs in SessionPlanner.comesFirst(lhs, rhs) }
        let cleaned = SessionPlanner.preferences(preferences, keepingSessionsOf: Set(ordered.map { $0.uuid }))
        let sessions = try allSessionSummaries()
        return try weekFit(programs: ordered, preferences: cleaned, sessions: sessions, now: now)
    }

    // MARK: - Metas da semana (W2)

    /// Um `PlanWeekProgress` por plano ativo, na ordem de M1: as sessões `completed` com ao menos uma série
    /// de trabalho, iniciadas na semana de §7.4 (começo da semana do `UserSettingsModel`), em dias daquele
    /// plano, e as sessões por semana dele (M3).
    func planWeekProgress(now: Date) throws -> [PlanWeekProgress] {
        let programs = try activePrograms()
        guard !programs.isEmpty else {
            return []
        }
        let sessions = try allSessionSummaries()
        let week = try weekSettings()
        let interval = WeeklyFrequency.weekInterval(
            containing: now,
            weekStartsOnMonday: week.startsOnMonday,
            calendar: calendar
        )
        let preferences = activeWeekPreferences(settings().weekPreferences, programs: programs)
        var progress: [PlanWeekProgress] = []
        for program in programs {
            let fullTemplate = try programTemplate(from: program)
            let template = SessionPlanner.trainableTemplate(fullTemplate)
            let dayIDs = Set(program.days.map { $0.uuid })
            let completed = sessions.filter { session in
                session.status == .completed
                    && session.workingSetCount >= 1
                    && dayIDs.contains(session.programDayID)
                    && session.startedAt >= interval.start
                    && session.startedAt < interval.end
            }.count
            progress.append(PlanWeekProgress(
                programID: program.uuid,
                goal: program.goal ?? .hypertrophy,
                completed: completed,
                perWeek: SessionPlanner.sessionsPerWeek(of: template, preferences: preferences)
            ))
        }
        return progress
    }

    /// SPEC §7.4 e §7.16 W2: as sessões concluídas de todos os planos, com as metas por grupo e o começo da
    /// semana do `UserSettingsModel`, no calendário do planejador.
    func weeklyFrequency(now: Date) throws -> WeeklyFrequencyReport {
        let week = try weekSettings()
        let sessions = try completedSessionSummaries()
        return WeeklyFrequency.report(
            sessions: sessions,
            targets: week.targets,
            now: now,
            weekStartsOnMonday: week.startsOnMonday,
            calendar: calendar
        )
    }

    // MARK: - Apoio do encaixe

    /// `WeeklyFit.fit` com a demanda de cada plano rodada até a fase do começo da semana (M3). A semana do
    /// encaixe começa sempre na segunda (M4).
    func weekFit(
        programs: [ProgramModel],
        preferences: WeekPreferences,
        sessions: [SessionSummary],
        now: Date
    ) throws -> FitResult {
        let weekStart = WeeklyFrequency.weekInterval(containing: now, weekStartsOnMonday: true, calendar: calendar).start
        var demands: [PlanDemand] = []
        for program in programs {
            let demand = try phasedDemand(of: program, preferences: preferences, sessions: sessions, weekStart: weekStart)
            demands.append(demand)
        }
        return WeeklyFit.fit(demands, preferences: preferences)
    }

    /// SPEC §7.15 M3: a demanda de `program` (os dias com exercícios, o catálogo e a duração estimada de cada
    /// dia), começando pela sessão que a rotação dele (S2, só com as sessões dos dias dele, S8) daria na
    /// segunda 00:00.
    func phasedDemand(
        of program: ProgramModel,
        preferences: WeekPreferences,
        sessions: [SessionSummary],
        weekStart: Date
    ) throws -> PlanDemand {
        let fullTemplate = try programTemplate(from: program)
        let template = SessionPlanner.trainableTemplate(fullTemplate)
        let catalog = try exerciseCatalog(of: program)
        let demand = PlanDemand.from(
            program: template,
            exercises: catalog,
            sessionsPerWeek: preferences.sessionsPerWeek[template.id],
            minutesPerDay: estimatedMinutes(of: template, exercises: catalog)
        )
        let dayIDs = Set(fullTemplate.days.map { $0.id })
        let beforeWeek = sessions.filter { $0.startedAt < weekStart && dayIDs.contains($0.programDayID) }
        guard let phase = selector.nextDay(program: template, recentSessions: beforeWeek, now: weekStart) else {
            return demand
        }
        return demand.startingAt(programDayID: phase.id)
    }

    /// Os exercícios de `program` por `ExerciseDefinition.id`. Relação anulada é store corrompido
    /// (ARCHITECTURE §5) e lança `PlanningError.exerciseNotFound`, como em `programSnapshot`.
    func exerciseCatalog(of program: ProgramModel) throws -> [UUID: ExerciseDefinition] {
        var catalog: [UUID: ExerciseDefinition] = [:]
        for day in program.days {
            for programExercise in day.exercises {
                guard let model = programExercise.exercise else {
                    throw PlanningError.exerciseNotFound(programExercise.uuid)
                }
                if catalog[model.uuid] == nil {
                    catalog[model.uuid] = try ExerciseMapper.definition(from: model)
                }
            }
        }
        return catalog
    }

    /// A duração estimada de cada dia (`SessionDurationEstimate`), sobre o alvo do programa: é para textos
    /// como "Cardio leve 25 min" e não entra no encaixe.
    func estimatedMinutes(of template: ProgramTemplate, exercises: [UUID: ExerciseDefinition]) -> [UUID: Int] {
        var minutes: [UUID: Int] = [:]
        for day in template.days {
            var planned: [PlannedExercise] = []
            for target in day.exercises {
                guard let exercise = exercises[target.exerciseID] else {
                    continue
                }
                let prescription = ExercisePrescription(
                    exerciseID: exercise.id,
                    load: target.startingLoad,
                    sets: target.sets,
                    repMin: target.repMin,
                    repMax: target.repMax,
                    targetReps: target.repMin,
                    targetRIR: target.targetRIR,
                    restSeconds: target.restSeconds,
                    note: .calibrate
                )
                planned.append(PlannedExercise(id: target.id, exercise: exercise, target: target, prescription: prescription))
            }
            minutes[day.id] = SessionDurationEstimate.minutes(for: planned, traits: traits)
        }
        return minutes
    }

    /// SPEC §7.15 M9: ids de planos que não estão ativos são ignorados.
    func activeWeekPreferences(_ preferences: WeekPreferences, programs: [ProgramModel]) -> WeekPreferences {
        SessionPlanner.preferences(preferences, keepingSessionsOf: Set(programs.map { $0.uuid }))
    }

    /// `preferences` só com o "Menos sessões" dos planos `ids`.
    nonisolated static func preferences(
        _ preferences: WeekPreferences,
        keepingSessionsOf ids: Set<UUID>
    ) -> WeekPreferences {
        var result = preferences
        result.sessionsPerWeek = preferences.sessionsPerWeek.filter { ids.contains($0.key) }
        return result
    }

    /// SPEC §7.15 M3: a de "Menos sessões" ou o número de dias (com exercícios), limitada a 1…dias; 0 num
    /// plano sem dias. A mesma conta de `PlanDemand.from`.
    nonisolated static func sessionsPerWeek(of template: ProgramTemplate, preferences: WeekPreferences) -> Int {
        let count = template.days.count
        guard count > 0 else {
            return 0
        }
        let wanted = preferences.sessionsPerWeek[template.id] ?? count
        return min(max(wanted, 1), count)
    }

    /// Inclui inativos: o encaixe confere também o plano que a pessoa quer acrescentar.
    func fetchProgram(uuid: UUID) throws -> ProgramModel? {
        var descriptor = FetchDescriptor<ProgramModel>(
            predicate: #Predicate<ProgramModel> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
