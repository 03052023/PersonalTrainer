import Foundation

/// The local decision log of the dialogue (SPEC §7.11: "Decisões ficam registradas
/// localmente (log JSON) para auditoria e para não repetir"). The app persists it as
/// JSON (not SwiftData) and passes it to `CoachFeedBuilder.feed`.
public struct CoachLog: Codable, Sendable, Hashable {
    /// Every answer, in the order it was recorded. Never pruned by the core.
    public var entries: [CoachLogEntry]
    /// When the app last ran the periodic review (use `ReviewReport.generatedAt`). The
    /// app sets it when it runs a review, so `ReviewSchedule.isDue` counts the next
    /// interval from there; `record` never changes it.
    public var lastReviewAt: Date?

    public init(entries: [CoachLogEntry] = [], lastReviewAt: Date? = nil) {
        self.entries = entries
        self.lastReviewAt = lastReviewAt
    }

    /// Appends the user's answer to `message`. From then on the message's id is hidden
    /// from the feed; `neverAgain` also silences its `rule` + `itemKey` for good.
    public mutating func record(_ message: CoachMessage, action: CoachAction, at date: Date) {
        entries.append(
            CoachLogEntry(
                messageID: message.id,
                rule: message.rule,
                itemKey: message.itemKey,
                action: action,
                date: date
            )
        )
    }
}

// MARK: - Queries used by the feed

extension CoachLog {
    /// Whether the message with this id was already answered (any action).
    func hasAnswered(messageID: String) -> Bool {
        entries.contains { $0.messageID == messageID }
    }

    /// SPEC §7.11: "Não sugerir mais isto" silences the rule for that item.
    func isSilenced(rule: CoachRule, itemKey: String) -> Bool {
        entries.contains { $0.action == .neverAgain && $0.rule == rule && $0.itemKey == itemKey }
    }

    /// The most recent answer for `rule` + `itemKey`: latest `date`, and for equal dates
    /// the one recorded last, so the result does not depend on how dates tie.
    func latestEntry(rule: CoachRule, itemKey: String) -> CoachLogEntry? {
        var latest: CoachLogEntry?
        for entry in entries where entry.rule == rule && entry.itemKey == itemKey {
            if let current = latest, entry.date < current.date {
                continue
            }
            latest = entry
        }
        return latest
    }
}
