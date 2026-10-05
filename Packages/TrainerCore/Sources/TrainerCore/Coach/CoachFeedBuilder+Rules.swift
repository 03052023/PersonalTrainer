import Foundation

/// One builder per active rule of SPEC §7.11 (C4 was removed in 2.5, SPEC §7.18 L4). Each
/// returns what the rule would say now, before the decision log filters answered and
/// silenced messages (except C3, whose cadence depends on the last answer and not only on
/// the id's period).
extension CoachFeedBuilder {
    /// C5: calendar days without a session before the welcome back ("≥ 6 dias").
    static let comebackDays = 6
    /// C5 / SPEC P9: elapsed pause after which the loads come back reduced (strictly more).
    static let reducedLoadPause: TimeInterval = 21 * 86_400
    /// C3: calendar days one kind waits after "Entendi" ("no máximo 1 por tipo a cada 3 dias").
    static let healthCooldownDays = 3
    /// C3: calendar days one kind waits after "Lembrar amanhã".
    static let healthRemindDays = 1
    /// C7: calendar days after which a backup is old ("há ≥ 14 dias").
    static let backupStaleDays = 14
    /// C7: completed sessions that make a first backup worth it ("nunca, com ≥ 5 sessões").
    static let backupFirstSessions = 5

    // MARK: - C1 Deload

    /// C1: announces a scheduled lighter week once per scheduling (`deload:<day of since>`).
    /// Nothing while it runs: the Home card shows it as part of the plan (DESIGN §9).
    ///
    /// Since 2.4 (TASKS B11) the reason opens with the numbers of the trigger when `detail`
    /// explains this same trigger; without it, and for the manual request, the sentence has
    /// no numbers, as before.
    static func deloadMessage(
        state: CoachDeloadState,
        detail: DeloadTriggerDetail? = nil,
        calendar: Calendar
    ) -> CoachMessage? {
        guard case let .scheduled(trigger, since) = state else {
            return nil
        }
        // SPEC §7.5 content: ⌈S × 0,6⌉ sets and round↓(C × 0,85) for one pass of the rotation.
        let content = "nas próximas sessões, uma de cada dia do programa, você fará cerca de 60% das séries "
            + "com cargas 15% menores, para o corpo se recuperar."
        let matchingDetail = (detail?.trigger == trigger) ? detail : nil
        let reason = deloadOpening(trigger: trigger, detail: matchingDetail) + content
        return CoachMessage(
            id: "deload:\(CoachText.day(since, calendar: calendar))",
            rule: .deload,
            itemKey: trigger.rawValue,
            title: "Semana mais leve programada",
            reason: reason,
            referenceTopic: "rule.D",
            actions: [.ok, .keepNormal],
            priority: Priority.deload,
            highlightsOnLaunch: true
        )
    }

    /// C1: the first half of the reason, up to the "; " before the content.
    ///
    /// - (a) "Em 4 de 7 exercícios a carga precisou baixar; " (the noun follows the total:
    ///   "1 de 1 exercício");
    /// - (b) "Já são 6 semanas desde a última semana leve; " or "… desde a primeira sessão; "
    ///   ("Já faz 1 semana …" in the singular);
    /// - without usable numbers, or for the manual request, the 2.3 sentence.
    static func deloadOpening(trigger: DeloadTrigger, detail: DeloadTriggerDetail?) -> String {
        switch trigger {
        case .manyDecreases:
            if let detail, detail.decreasedExercises > 0, detail.countedExercises >= detail.decreasedExercises {
                let total = HealthText.count(detail.countedExercises, singular: "exercício", plural: "exercícios")
                return "Em \(HealthText.integer(detail.decreasedExercises)) de \(total) a carga precisou baixar; "
            }
            return "Em metade ou mais dos exercícios a carga precisou baixar; "
        case .scheduled:
            if let detail, detail.weeksSinceAnchor >= 1 {
                let weeks = HealthText.count(detail.weeksSinceAnchor, singular: "semana", plural: "semanas")
                let opening = detail.weeksSinceAnchor == 1 ? "Já faz" : "Já são"
                let anchor = detail.anchorIsLastDeload ? "desde a última semana leve" : "desde a primeira sessão"
                return "\(opening) \(weeks) \(anchor); "
            }
            return "Chegou a semana leve programada no seu plano; "
        case .manual:
            return "Você pediu uma semana mais leve; "
        }
    }

    // MARK: - C2 Periodic review

    /// C2: one message per suggestion of the current review, in the report's order
    /// (SPEC R7). The id carries the review's ISO week, so "Agora não" waits for the next
    /// review; the item key drops the week, so "Não sugerir mais isto" outlives it.
    static func reviewMessages(report: ReviewReport?, deload: CoachDeloadState) -> [CoachMessage] {
        guard let report else {
            return []
        }
        // SPEC R5: a deload is "não sugerido com um deload em andamento"; while one is
        // scheduled or running, C1 already speaks for it.
        let deloadPlanned: Bool
        switch deload {
        case .none: deloadPlanned = false
        case .scheduled, .running: deloadPlanned = true
        }
        var messages: [CoachMessage] = []
        for suggestion in report.suggestions {
            if deloadPlanned && suggestion.kind == .deload {
                continue
            }
            messages.append(
                CoachMessage(
                    id: "review:\(suggestion.id)",
                    rule: .review,
                    itemKey: reviewItemKey(suggestionID: suggestion.id),
                    title: suggestion.title,
                    reason: suggestion.reason,
                    referenceTopic: suggestion.referenceTopic,
                    actions: [.apply, .notNow, .neverAgain],
                    priority: Priority.within(Priority.review, offset: messages.count),
                    highlightsOnLaunch: true,
                    suggestionID: suggestion.id
                )
            )
        }
        return messages
    }

    /// The suggestion id without its trailing ISO week: `addSets:chest:<id>:2026-W39` →
    /// `addSets:chest:<id>`, `deload:2026-W39` → `deload`. Other ids stay whole.
    static func reviewItemKey(suggestionID id: String) -> String {
        guard let colon = id.lastIndex(of: ":") else {
            return id
        }
        let suffix = id[id.index(after: colon)...]
        return isISOWeekLabel(suffix) ? String(id[..<colon]) : id
    }

    /// "YYYY-Www" with ASCII digits, as `ProgramReviewer.isoWeekLabel` writes it.
    static func isISOWeekLabel(_ text: Substring) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return false
        }
        let year = parts[0]
        let week = parts[1]
        return year.count == 4
            && year.allSatisfy(isASCIIDigit)
            && week.count == 3
            && week.first == "W"
            && week.dropFirst().allSatisfy(isASCIIDigit)
    }

    static func isASCIIDigit(_ character: Character) -> Bool {
        character >= "0" && character <= "9"
    }

    // MARK: - C3 Health

    /// C3: one message per kind of health suggestion (the first of each kind). After
    /// "Entendi" the kind waits 3 calendar days; after "Lembrar amanhã", until the next
    /// day. The id carries today, so an answer given today hides it for the rest of it.
    static func healthMessages(
        suggestions: [HealthSuggestion],
        log: CoachLog,
        now: Date,
        calendar: Calendar
    ) -> [CoachMessage] {
        let today = CoachText.day(now, calendar: calendar)
        var seenKinds = Set<HealthSuggestionKind>()
        var messages: [CoachMessage] = []
        for suggestion in suggestions {
            guard seenKinds.insert(suggestion.kind).inserted else {
                continue
            }
            let key = suggestion.kind.rawValue
            if let last = log.latestEntry(rule: .health, itemKey: key) {
                let wait = last.action == .remindTomorrow ? healthRemindDays : healthCooldownDays
                // A last answer dated after `now` (clock skew) keeps the kind quiet.
                guard HealthDays.daysBetween(last.date, now, calendar: calendar) >= wait else {
                    continue
                }
            }
            let rank = HealthSuggestionKind.allCases.firstIndex(of: suggestion.kind) ?? 0
            messages.append(
                CoachMessage(
                    id: "health:\(key):\(today)",
                    rule: .health,
                    itemKey: key,
                    title: suggestion.title,
                    reason: suggestion.detail,
                    referenceTopic: suggestion.referenceTopic,
                    actions: [.understood, .remindTomorrow],
                    priority: Priority.within(Priority.health, offset: rank),
                    highlightsOnLaunch: false
                )
            )
        }
        return messages
    }

    // MARK: - C5 Comeback

    /// C5: welcome back after ≥ 6 calendar days without a session. When the pause is
    /// longer than 21 days (SPEC P9, the same elapsed-time test as the engine) it adds
    /// that the loads come back reduced, under a new id so the warning is seen even if
    /// the plain welcome was already answered.
    static func comebackMessage(
        lastSessionStart: Date?,
        nextDayName: String?,
        now: Date,
        calendar: Calendar
    ) -> CoachMessage? {
        guard let last = lastSessionStart else {
            return nil
        }
        let days = HealthDays.daysBetween(last, now, calendar: calendar)
        guard days >= comebackDays else {
            return nil
        }
        let reduced = now.timeIntervalSince(last) > reducedLoadPause
        // Owner notes item 16: the notice states the fact and what to do, with no effect phrase.
        var sentences = ["Sua última sessão foi há \(CoachText.days(days))."]
        if let name = nextDayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            sentences.append("Hoje o plano é \(name).")
        }
        if reduced {
            sentences.append("Como faz mais de 21 dias, as cargas vêm cerca de 10% menores para você retomar com calma.")
        }
        let lastDay = CoachText.day(last, calendar: calendar)
        return CoachMessage(
            id: reduced ? "comeback:\(lastDay):reduced" : "comeback:\(lastDay)",
            rule: .comeback,
            itemKey: "comeback",
            title: "Bom te ver de volta",
            reason: sentences.joined(separator: " "),
            referenceTopic: "rule.P9",
            actions: [.start],
            priority: Priority.comeback,
            highlightsOnLaunch: true
        )
    }

    // MARK: - C6 Personal record

    /// C6: one message per new best estimated 1RM of the last completed session, sorted by
    /// exercise id. The id carries the set that made the mark: a later mark of the same
    /// exercise is a new message.
    static func personalRecordMessages(
        records: [PersonalRecord],
        names: [UUID: String],
        units: [UUID: LoadUnit]
    ) -> [CoachMessage] {
        let sorted = records.sorted { lhs, rhs in
            if lhs.exerciseID != rhs.exerciseID {
                return lhs.exerciseID.uuidString < rhs.exerciseID.uuidString
            }
            if lhs.load != rhs.load { return lhs.load > rhs.load }
            if lhs.reps != rhs.reps { return lhs.reps > rhs.reps }
            return (lhs.previousBest ?? 0) < (rhs.previousBest ?? 0)
        }
        var messages: [CoachMessage] = []
        for record in sorted {
            let exercise = record.exerciseID.uuidString
            let unit = units[record.exerciseID] ?? .kilograms
            let trimmedName = names[record.exerciseID]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = trimmedName.isEmpty ? "Exercício" : trimmedName
            let repetitions = record.reps == 1 ? "1 repetição" : "\(record.reps) repetições"
            let set = "\(ReviewText.estimate(record.load, unit: unit)) × \(repetitions)"
            let estimate = ReviewText.estimate(record.e1rm, unit: unit)
            let reason: String
            if let previous = record.previousBest {
                reason = "\(name): \(set); sua força estimada para 1 repetição subiu de "
                    + "\(ReviewText.estimate(previous, unit: unit)) para \(estimate)."
            } else {
                reason = "\(name): \(set); sua força estimada para 1 repetição chegou a \(estimate)."
            }
            messages.append(
                CoachMessage(
                    id: "record:\(exercise):\(CoachText.idNumber(record.load))x\(record.reps)",
                    rule: .personalRecord,
                    itemKey: exercise,
                    title: "Nova melhor marca",
                    reason: reason,
                    referenceTopic: "topic.e1rm",
                    actions: [.seeProgress],
                    priority: Priority.within(Priority.personalRecord, offset: messages.count),
                    highlightsOnLaunch: false,
                    suggestionID: exercise
                )
            )
        }
        return messages
    }

    // MARK: - C7 Backup

    /// C7: backup older than 14 calendar days, or never made with ≥ 5 completed sessions.
    /// At most one per ISO week: the id carries the week.
    static func backupMessage(
        lastBackupAt: Date?,
        completedSessionCount: Int,
        now: Date,
        calendar: Calendar
    ) -> CoachMessage? {
        let reason: String
        if let lastBackupAt {
            let days = HealthDays.daysBetween(lastBackupAt, now, calendar: calendar)
            guard days >= backupStaleDays else {
                return nil
            }
            reason = "Seu último backup foi há \(CoachText.days(days)); "
                + "um backup novo guarda também as sessões feitas desde então."
        } else {
            guard completedSessionCount >= backupFirstSessions else {
                return nil
            }
            reason = "Você já tem \(HealthText.integer(completedSessionCount)) sessões registradas e ainda "
                + "nenhum backup; um backup guarda seu histórico se o app precisar ser reinstalado."
        }
        return CoachMessage(
            id: "backup:\(CoachText.week(now, calendar: calendar))",
            rule: .backup,
            itemKey: "backup",
            title: "Faça um backup do seu histórico",
            reason: reason,
            referenceTopic: nil,
            actions: [.backupNow, .later],
            priority: Priority.backup,
            highlightsOnLaunch: false
        )
    }

    // MARK: - C8 Longevity

    /// C8: with the Longevity goal, one light reminder per block (balance, mobility) not
    /// marked this week. At most one per ISO week and block: the id carries both.
    static func longevityMessages(
        goal: ProgramGoal?,
        done: Set<String>,
        now: Date,
        calendar: Calendar
    ) -> [CoachMessage] {
        guard goal == .longevity else {
            return []
        }
        let week = CoachText.week(now, calendar: calendar)
        let blocks: [(key: String, title: String, reason: String)] = [
            (
                key: CoachInput.balanceKey,
                title: "Equilíbrio: 5 a 10 minutos",
                reason: "Você ainda não marcou equilíbrio nesta semana; a meta é de 2 a 3 vezes por semana, "
                    + "com rotinas curtas como ficar num pé só ou andar em linha reta."
            ),
            (
                key: CoachInput.mobilityKey,
                title: "Mobilidade: 5 a 10 minutos",
                reason: "Você ainda não marcou mobilidade nesta semana; a meta é de 2 a 3 vezes por semana, "
                    + "com 5 a 10 minutos de movimentos amplos e alongamentos."
            ),
        ]
        var messages: [CoachMessage] = []
        for (offset, block) in blocks.enumerated() where !done.contains(block.key) {
            messages.append(
                CoachMessage(
                    id: "longevity:\(block.key):\(week)",
                    rule: .longevity,
                    itemKey: block.key,
                    title: block.title,
                    reason: block.reason,
                    referenceTopic: ProgramGoal.longevity.referenceTopic,
                    actions: [.done, .skip],
                    priority: Priority.within(Priority.longevity, offset: offset),
                    highlightsOnLaunch: false
                )
            )
        }
        return messages
    }
}
