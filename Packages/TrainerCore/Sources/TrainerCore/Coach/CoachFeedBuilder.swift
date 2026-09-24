import Foundation

/// Builds the messages of the app's dialogue with the user (SPEC §7.11 C1–C8).
///
/// Pure function of its input, the decision log, `now` and the calendar (SPEC §7.7,
/// AGENTS R3): no clock, no randomness, no generated text. Every rule proposes at most
/// what it has to say today; then
/// - a message whose `id` is already in the log (answered with any action) is dropped:
///   the period inside the id decides when the same rule may speak again;
/// - a message whose `rule` + `itemKey` got "Não sugerir mais isto" is dropped for good;
/// - the rest is sorted by `priority`, then `id`, so the order never depends on the
///   order of the input.
public enum CoachFeedBuilder: Sendable {
    /// Priority bands (lower = more important). The installation expiry comes first
    /// because an expired app does not open at all; then the lighter week, which changes
    /// the next sessions on its own. Rules with several messages add their position
    /// (at most `bandWidth − 1`) to the band.
    enum Priority {
        static let bandWidth = 100
        static let installExpiry = 0
        static let deload = 100
        static let comeback = 200
        static let review = 300
        static let personalRecord = 400
        static let health = 500
        static let backup = 600
        static let longevity = 700

        static func within(_ band: Int, offset: Int) -> Int {
            band + min(max(offset, 0), bandWidth - 1)
        }
    }

    /// The messages to show now, most important first (see the type's documentation).
    public static func feed(input: CoachInput, log: CoachLog, now: Date, calendar: Calendar) -> [CoachMessage] {
        var candidates: [CoachMessage] = []
        if let message = installExpiryMessage(expiry: input.provisioningExpiry, now: now, calendar: calendar) {
            candidates.append(message)
        }
        if let message = deloadMessage(state: input.deload, calendar: calendar) {
            candidates.append(message)
        }
        if let message = comebackMessage(
            lastSessionStart: input.lastSessionStart,
            nextDayName: input.nextDayName,
            now: now,
            calendar: calendar
        ) {
            candidates.append(message)
        }
        candidates += reviewMessages(report: input.review, deload: input.deload)
        candidates += personalRecordMessages(
            records: input.personalRecords,
            names: input.exerciseNames,
            units: input.loadUnits
        )
        candidates += healthMessages(suggestions: input.healthSuggestions, log: log, now: now, calendar: calendar)
        if let message = backupMessage(
            lastBackupAt: input.lastBackupAt,
            completedSessionCount: input.completedSessionCount,
            now: now,
            calendar: calendar
        ) {
            candidates.append(message)
        }
        candidates += longevityMessages(
            goal: input.goal,
            done: input.longevityDoneThisWeek,
            now: now,
            calendar: calendar
        )

        // Duplicated input (the same suggestion or record twice) yields one message: the
        // first one produced, before sorting, so the choice is deterministic.
        var seen = Set<String>()
        let visible = candidates.filter { message in
            guard seen.insert(message.id).inserted else {
                return false
            }
            return !log.hasAnswered(messageID: message.id)
                && !log.isSilenced(rule: message.rule, itemKey: message.itemKey)
        }
        return visible.sorted { lhs, rhs in
            lhs.priority != rhs.priority ? lhs.priority < rhs.priority : lhs.id < rhs.id
        }
    }
}
