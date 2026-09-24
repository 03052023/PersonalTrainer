import Foundation

/// One message of the app's dialogue with the user (SPEC §7.11): a title, one reason
/// with the numbers behind it, the "Por quê?" reference and the possible answers.
/// Texts are fixed pt-BR templates in DESIGN §6's voice, never generated (ADR 012).
public struct CoachMessage: Identifiable, Codable, Sendable, Hashable {
    /// Stable id that carries the message's period, e.g. `deload:2026-09-21`,
    /// `health:updateVo2Max:2026-09-23`, `expiry:2026-09-30:2026-09-28`,
    /// `backup:2026-W39`. An answered id never shows again; a new period means a new id.
    public let id: String
    public let rule: CoachRule
    /// What "Não sugerir mais isto" silences, together with `rule`. It does not carry the
    /// period, e.g. `addSets:chest:<targetID>` for a C2 suggestion or the exercise id for C6.
    public let itemKey: String
    /// Short pt-BR title, free of gym jargon (DESIGN §6).
    public let title: String
    /// pt-BR reason with the numbers that produced the message (SPEC §7.11).
    public let reason: String
    /// Key in `references.v1.json` behind "Por quê?", or `nil` (C4 and C7).
    public let referenceTopic: String?
    /// Answers offered, in display order.
    public let actions: [CoachAction]
    /// Lower is more important. C4 and C1 come first.
    public let priority: Int
    /// Show on opening the app, not only in the Home section (SPEC §7.11: "se houver
    /// algo novo e importante"): C4, C1, C5 and C2.
    public let highlightsOnLaunch: Bool
    /// C2: the `ProgramSuggestion.id` to apply; C6: the exercise id (`uuidString`) whose
    /// progress to show; `nil` for the other rules.
    public let suggestionID: String?

    public init(
        id: String,
        rule: CoachRule,
        itemKey: String,
        title: String,
        reason: String,
        referenceTopic: String?,
        actions: [CoachAction],
        priority: Int,
        highlightsOnLaunch: Bool,
        suggestionID: String? = nil
    ) {
        self.id = id
        self.rule = rule
        self.itemKey = itemKey
        self.title = title
        self.reason = reason
        self.referenceTopic = referenceTopic
        self.actions = actions
        self.priority = priority
        self.highlightsOnLaunch = highlightsOnLaunch
        self.suggestionID = suggestionID
    }
}
