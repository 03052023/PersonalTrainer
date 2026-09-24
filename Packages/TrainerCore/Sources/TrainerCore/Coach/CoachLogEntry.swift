import Foundation

/// One answer of the user to a coach message, kept in the local decision log for
/// auditing and so the same message is not repeated (SPEC §7.11).
public struct CoachLogEntry: Codable, Sendable, Hashable {
    public let messageID: String
    public let rule: CoachRule
    public let itemKey: String
    public let action: CoachAction
    public let date: Date

    public init(messageID: String, rule: CoachRule, itemKey: String, action: CoachAction, date: Date) {
        self.messageID = messageID
        self.rule = rule
        self.itemKey = itemKey
        self.action = action
        self.date = date
    }
}
