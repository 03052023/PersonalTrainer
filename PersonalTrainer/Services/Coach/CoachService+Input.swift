import Foundation
import os
import TrainerCore

/// Montagem do `CoachInput` (contrato V2-FINAL §2.3). Cada fonte falha sozinha: um erro de
/// leitura é logado e vira "sem dado" naquela regra, sem esconder o resto do feed.
extension CoachService {
    func makeInput(log: inout CoachLog, now: Date) -> CoachInput {
        let sessions = loadSessions()
        // SPEC P9 / C5: a pausa conta da última sessão com ≥ 1 série de trabalho, deload incluído
        // (concluída ou abandonada, como o histórico do motor, SPEC P3).
        let trainedSessions = sessions.filter { $0.status != .inProgress && $0.workingSetCount > 0 }
        let trainedStarts = trainedSessions.map(\.startedAt)
        // SPEC §7.15 M2: com dois planos, o C5 olha o principal, com as sessões dos dias dele.
        let principal = comebackPrincipal()
        let lastSessionStart = comebackStart(trainedSessions, principal: principal)
        let reviewInput = loadReviewInput(now: now)
        rememberTargets(from: reviewInput)
        let exercises = exerciseCatalog(from: reviewInput)
        let deload = deloadState(sessions: sessions, now: now)
        let deloadDetail = deloadTriggerDetail(for: deload, now: now)
        let review = relevantReview(
            currentReview(log: &log, input: reviewInput, firstSessionAt: trainedStarts.min(), now: now),
            activeProgramID: reviewInput?.programID
        )
        let records = personalRecords(sessions: sessions, reviewInput: reviewInput)
        let nextDay = nextDayName(lastSessionStart: lastSessionStart, principalID: principal?.id, now: now)
        let completedCount = sessions.filter { $0.status == .completed }.count
        // SPEC C8, §7.17 X6: o bloco já registrado nesta semana em "Fora do app" também está feito, e o
        // lembrete some (sem isso, um "Feito" a mais gravaria a mesma vez duas vezes).
        let longevityDone = longevityMarks(in: log, now: now).union(registeredLongevity(now: now))

        return CoachInput(
            deload: deload,
            review: review,
            healthSuggestions: lastHealthSuggestions,
            lastSessionStart: lastSessionStart,
            nextDayName: nextDay,
            personalRecords: records,
            exerciseNames: exercises.mapValues { $0.name },
            loadUnits: exercises.mapValues { $0.loadUnit },
            lastBackupAt: lastBackupAt,
            completedSessionCount: completedCount,
            goal: reminderGoal(),
            longevityDoneThisWeek: longevityDone,
            deloadDetail: deloadDetail
        )
    }

    /// O objetivo que o `CoachInput` recebe. Só o C8 o lê, e desde a 2.3 ele vale quando qualquer plano
    /// ativo é de Longevidade, principal ou não (SPEC §7.15 M2). Fora disso, o objetivo do principal.
    func reminderGoal() -> ProgramGoal? {
        do {
            if try planner.activeProgramGoals().contains(.longevity) {
                return .longevity
            }
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Objetivos dos planos ativos indisponíveis: \(reason, privacy: .public)")
        }
        return activeGoal()
    }

    // MARK: - Fontes

    /// Concluídas e abandonadas (SPEC P3/P9); as regras que pedem só as concluídas (C6, C7)
    /// filtram por `status`.
    func loadSessions() -> [SessionSummary] {
        do {
            return try planner.finishedSessionSummaries()
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Sessões indisponíveis para o diálogo: \(reason, privacy: .public)")
            return []
        }
    }

    func loadReviewInput(now: Date) -> ReviewInput? {
        do {
            return try planner.reviewInput(now: now, recovery: lastRecovery)
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Entrada da revisão indisponível: \(reason, privacy: .public)")
            return nil
        }
    }

    func activeGoal() -> ProgramGoal? {
        do {
            return try planner.activeProgramGoal()
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Objetivo do programa ativo indisponível: \(reason, privacy: .public)")
            return nil
        }
    }

    /// C7: gravada pelo Ajustes depois de exportar backup (contrato V2-FINAL §2).
    var lastBackupAt: Date? {
        guard defaults.object(forKey: DefaultsKey.lastBackupAt) != nil else {
            return nil
        }
        return Date(timeIntervalSince1970: defaults.double(forKey: DefaultsKey.lastBackupAt))
    }

    /// Exercícios do programa ativo, por `ExerciseDefinition.id` (nomes e unidades do C6).
    func exerciseCatalog(from input: ReviewInput?) -> [UUID: ExerciseDefinition] {
        var catalog: [UUID: ExerciseDefinition] = [:]
        for slot in input?.exercises ?? [] {
            catalog[slot.exercise.id] = slot.exercise
        }
        return catalog
    }

    /// Guarda o exercício de cada alvo, para descrever e aplicar sugestões do C2.
    func rememberTargets(from input: ReviewInput?) {
        var exercises: [UUID: ExerciseDefinition] = [:]
        for slot in input?.exercises ?? [] {
            exercises[slot.targetID] = slot.exercise
        }
        targetExercises = exercises
    }

    // MARK: - C1 Semana leve

    /// O status do planejador, com um `since` estável enquanto a semana leve estiver pendente
    /// (contrato V2-FINAL §2, ajustes da onda 2): sem isso o id `deload:<dia>` mudaria todo dia e
    /// a mensagem voltaria depois de respondida. Numa falha de leitura, nada é apagado.
    func deloadState(sessions: [SessionSummary], now: Date) -> CoachDeloadState {
        let status: DeloadStatus
        do {
            status = try planner.deloadStatus(now: now)
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Status da semana leve indisponível: \(reason, privacy: .public)")
            return .none
        }
        switch status {
        case .inactive:
            clearPendingDeload()
            return .none
        case .active(let start):
            clearPendingDeload()
            return .running(start: start)
        case .pending(let trigger):
            return .scheduled(trigger: trigger, since: pendingSince(trigger: trigger, sessions: sessions, now: now))
        }
    }

    /// `coachPendingDeloadSince` gravado na primeira vez que o pendente aparece. Começa de novo
    /// quando:
    /// - o pendente vira pedido manual (contrato: no manual, `since = manualRequestedAt`; o
    ///   pedido acabou de acontecer, e `now` é o instante mais próximo disponível aqui);
    /// - uma sessão de deload começou depois do `since` guardado: esse era de uma semana leve
    ///   anterior que o app não viu terminar.
    func pendingSince(trigger: DeloadTrigger, sessions: [SessionSummary], now: Date) -> Date {
        if let since = storedPendingSince {
            let storedTrigger = defaults.string(forKey: DefaultsKey.pendingDeloadTrigger)
                .flatMap { DeloadTrigger(rawValue: $0) }
            let becameManual = trigger == .manual && storedTrigger != .manual
            let isStale = sessions.contains { $0.isDeload && $0.startedAt >= since }
            if !becameManual && !isStale {
                if storedTrigger != trigger {
                    defaults.set(trigger.rawValue, forKey: DefaultsKey.pendingDeloadTrigger)
                }
                return since
            }
        }
        markPendingDeload(since: now, trigger: trigger)
        return now
    }

    /// Os números do C1 (SPEC §7.11 C1, achado B11 da 2.1): só com a semana leve programada, que é
    /// quando o planejador pode tê-los (`SessionPlanning.deloadTriggerDetail` devolve `nil` fora de
    /// `.pending`). Assim o diálogo não recalcula o programa à toa em cada atualização. Numa falha de
    /// leitura, `nil` com log: o C1 fica com o texto sem números.
    func deloadTriggerDetail(for state: CoachDeloadState, now: Date) -> DeloadTriggerDetail? {
        guard case .scheduled = state else {
            return nil
        }
        do {
            return try planner.deloadTriggerDetail(now: now)
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Números da semana leve indisponíveis: \(reason, privacy: .public)")
            return nil
        }
    }

    var storedPendingSince: Date? {
        guard defaults.object(forKey: DefaultsKey.pendingDeloadSince) != nil else {
            return nil
        }
        return Date(timeIntervalSince1970: defaults.double(forKey: DefaultsKey.pendingDeloadSince))
    }

    func markPendingDeload(since: Date, trigger: DeloadTrigger) {
        defaults.set(since.timeIntervalSince1970, forKey: DefaultsKey.pendingDeloadSince)
        defaults.set(trigger.rawValue, forKey: DefaultsKey.pendingDeloadTrigger)
    }

    func clearPendingDeload() {
        defaults.removeObject(forKey: DefaultsKey.pendingDeloadSince)
        defaults.removeObject(forKey: DefaultsKey.pendingDeloadTrigger)
    }

    // MARK: - C2 Revisão periódica

    /// Roda `ProgramReviewer` quando `ReviewSchedule.isDue` e guarda o relatório e
    /// `lastReviewAt`; fora disso, devolve o relatório guardado (contrato V2-FINAL §2). O log
    /// esconde o que já foi respondido.
    func currentReview(log: inout CoachLog, input: ReviewInput?, firstSessionAt: Date?, now: Date) -> ReviewReport? {
        if let input,
           ReviewSchedule.isDue(lastReviewAt: log.lastReviewAt, firstSessionAt: firstSessionAt, now: now) {
            let report = ProgramReviewer.review(input: input, now: now, calendar: calendar)
            review = report
            didLoadReview = true
            defaults.set(input.programID.uuidString, forKey: DefaultsKey.lastReviewProgramID)
            do {
                // O relatório primeiro: com `lastReviewAt` gravado e o relatório não, as
                // sugestões sumiriam até a próxima revisão. Na falha, a revisão roda de novo.
                try logStore.saveLastReview(report)
                log.lastReviewAt = report.generatedAt
                try logStore.save(log)
            } catch {
                let reason = String(describing: error)
                Self.logger.error("Revisão periódica não foi gravada: \(reason, privacy: .public)")
            }
            return report
        }
        if !didLoadReview {
            review = logStore.loadLastReview()
            didLoadReview = true
        }
        return review
    }

    /// O relatório guardado só com o que ainda vale para o programa ativo: ele fica até a próxima
    /// revisão, e o programa pode ter sido editado ou trocado nesse meio-tempo.
    /// - Sugestão por exercício: só se todos os alvos ainda estão no programa ativo, senão
    ///   "Aplicar" só daria erro (a mesma conferência de `activeTargets`).
    /// - Sugestão do programa inteiro (semana leve, menos dias, trocar de programa): só se a
    ///   revisão foi feita sobre o programa ativo. Sem a marca do programa revisado, vale.
    /// Numa falha de leitura dos programas, o relatório segue como está; "Aplicar" confere de novo.
    func relevantReview(_ report: ReviewReport?, activeProgramID: UUID?) -> ReviewReport? {
        guard let report else {
            return nil
        }
        let activeTargetIDs: Set<UUID>
        do {
            let targets = try programs.allPrograms()
                .filter { $0.isActive }
                .flatMap { $0.days }
                .flatMap { $0.exercises }
            activeTargetIDs = Set(targets.map { $0.id })
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Programas indisponíveis para conferir a revisão: \(reason, privacy: .public)")
            return report
        }
        let reviewedProgramID = defaults.string(forKey: DefaultsKey.lastReviewProgramID)
            .flatMap { UUID(uuidString: $0) }
        let isSameProgram = reviewedProgramID == nil || reviewedProgramID == activeProgramID
        let kept = report.suggestions.filter { suggestion in
            if suggestion.targetIDs.isEmpty {
                return isSameProgram
            }
            return suggestion.targetIDs.allSatisfy { activeTargetIDs.contains($0) }
        }
        guard kept.count != report.suggestions.count else {
            return report
        }
        return ReviewReport(
            generatedAt: report.generatedAt,
            stagnantExerciseIDs: report.stagnantExerciseIDs,
            fatigueHigh: report.fatigueHigh,
            weeklySetsByMuscle: report.weeklySetsByMuscle,
            adherence: report.adherence,
            suggestions: kept
        )
    }

    // MARK: - C5 Retomada

    /// O plano principal quando há dois planos ativos (SPEC §7.15 M1, M2): é ele que o C5 olha. `nil` com um
    /// plano só, que segue o C5 de sempre, com todas as sessões. Numa falha de leitura dos programas, `nil`
    /// (com log): o C5 de sempre é o melhor que dá para fazer.
    func comebackPrincipal() -> ProgramTemplate? {
        do {
            let actives = try programs.allPrograms().filter { $0.isActive }
            guard actives.count > 1 else {
                return nil
            }
            return ActivePlanOrder.sorted(actives).first
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Programas indisponíveis para o C5: \(reason, privacy: .public)")
            return nil
        }
    }

    /// A pausa do C5 conta da última sessão com série de trabalho (SPEC P9). Com dois planos, só as dos dias
    /// do principal (M2): o cardio de ontem não apaga uma semana sem a força, cujas cargas P9 reduz.
    func comebackStart(_ trainedSessions: [SessionSummary], principal: ProgramTemplate?) -> Date? {
        guard let principal else {
            return trainedSessions.map(\.startedAt).max()
        }
        let dayIDs = Set(principal.days.map(\.id))
        return trainedSessions
            .filter { dayIDs.contains($0.programDayID) }
            .map(\.startedAt)
            .max()
    }

    /// O próximo dia da rotação, só quando o C5 pode falar (evita calcular o plano à toa). Com dois planos,
    /// o próximo do principal (SPEC §7.15 M2, S8); com um, o `nextPlan(now:)` de sempre.
    func nextDayName(lastSessionStart: Date?, principalID: UUID?, now: Date) -> String? {
        guard let lastSessionStart, calendarDays(from: lastSessionStart, to: now) >= Self.comebackDays else {
            return nil
        }
        do {
            if let principalID {
                return try planner.nextPlan(forProgramID: principalID, now: now)?.programDayName
            }
            return try planner.nextPlan(now: now)?.programDayName
        } catch {
            let reason = String(describing: error)
            Self.logger.error("Próximo dia indisponível para o C5: \(reason, privacy: .public)")
            return nil
        }
    }

    /// Dias de calendário entre as datas, no fuso do `calendar`.
    func calendarDays(from start: Date, to end: Date) -> Int {
        let components = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: start),
            to: calendar.startOfDay(for: end)
        )
        return components.day ?? 0
    }

    // MARK: - C6 Melhor marca

    /// Melhores marcas da última sessão concluída (`PersonalRecordDetector`), com os históricos
    /// dos exercícios do programa ativo que o planejador já monta para a revisão. Só os medidos em
    /// repetições (SPEC RF-43): o 1RM estimado (Epley) sobre segundos ou passos não é força, e a
    /// mensagem falaria em "repetições" de uma prancha ou de uma carregada, contra o "Ver evolução",
    /// que nesses casos mostra só a carga.
    func personalRecords(sessions: [SessionSummary], reviewInput: ReviewInput?) -> [PersonalRecord] {
        guard let reviewInput else {
            return []
        }
        let completed = sessions.filter { $0.status == .completed && $0.workingSetCount > 0 }
        let latest = completed.max { lhs, rhs in
            if lhs.startedAt != rhs.startedAt {
                return lhs.startedAt < rhs.startedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        guard let latest else {
            return []
        }
        var histories: [UUID: [ExerciseHistoryEntry]] = [:]
        for slot in reviewInput.exercises where traits.traits(for: slot.exercise).measure == .reps {
            // O mesmo exercício em dois alvos traz o mesmo histórico; o detector descarta
            // entradas repetidas.
            histories[slot.exercise.id, default: []] += slot.history
        }
        return PersonalRecordDetector.newRecords(latestSessionID: latest.id, histories: histories)
    }

    // MARK: - C8 Longevidade

    /// Blocos marcados como "Feito" nesta semana ISO (o mesmo período do id da mensagem C8).
    func longevityMarks(in log: CoachLog, now: Date) -> Set<String> {
        longevityMarks(in: log, now: now, markedBefore: nil)
    }

    /// SPEC §7.16 W2.6: as marcas que valem 1 nas Metas, só as de antes do primeiro "Feito" que gravou um
    /// registro (2.4). Desde ele, cada "Feito" existe como registro nas atividades, e apagar o registro
    /// desfaz a vez.
    func legacyLongevityMarks(in log: CoachLog, now: Date) -> Set<String> {
        let since = defaults.object(forKey: DefaultsKey.longevityEntriesSince) as? Date
        return longevityMarks(in: log, now: now, markedBefore: since)
    }

    /// SPEC §7.17 X6: os blocos com algum registro de equilíbrio ou de mobilidade na semana de `now`, de
    /// segunda a domingo (o mesmo período da semana ISO do C8).
    func registeredLongevity(now: Date) -> Set<String> {
        let week = WeeklyFrequency.weekInterval(containing: now, weekStartsOnMonday: true, calendar: calendar)
        let counts = OutsideActivities.longevityCounts(entries: activities.load().entries, week: week)
        return Set(counts.filter { $0.value > 0 }.map(\.key))
    }

    private func longevityMarks(in log: CoachLog, now: Date, markedBefore limit: Date?) -> Set<String> {
        let week = Self.isoWeekLabel(for: now, calendar: calendar)
        var done = Set<String>()
        for entry in log.entries where entry.rule == .longevity && entry.action == .done {
            if let limit, entry.date >= limit {
                continue
            }
            if Self.isoWeekLabel(for: entry.date, calendar: calendar) == week {
                done.insert(entry.itemKey)
            }
        }
        return done
    }

    /// "2026-W39": semana ISO 8601 no fuso do `calendar`, igual à do `CoachFeedBuilder`
    /// (`ProgramReviewer.isoWeekLabel`, interno ao core).
    static func isoWeekLabel(for date: Date, calendar: Calendar) -> String {
        var iso = Calendar(identifier: .gregorian)
        iso.timeZone = calendar.timeZone
        iso.firstWeekday = 2
        iso.minimumDaysInFirstWeek = 4
        let components = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return "\(year)-W\(week < 10 ? "0" : "")\(week)"
    }
}
