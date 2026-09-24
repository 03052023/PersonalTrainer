import Foundation

/// One suggestion of the periodic review (SPEC §7.8 R5, §7.11 C2).
///
/// The user accepts or declines it; nothing changes on its own (SPEC §7.8). Every
/// suggestion carries the rule that produced it and a one-sentence reason with the
/// numbers behind it (SPEC R5, R7). Texts are fixed pt-BR templates, never generated.
public struct ProgramSuggestion: Identifiable, Codable, Sendable, Hashable {
    /// Stable, deterministic key: `<kind>:<scope>:<ISO week of the review>`, e.g.
    /// `addSets:chest:<targetID>:2026-W39` or `deload:2026-W39`. The same history reviewed
    /// twice in the same week yields the same ids (SPEC R7), so the decision log can
    /// recognise a suggestion it already showed.
    public let id: String
    public let kind: ProgramSuggestionKind
    /// SPEC rule that generated the suggestion: "R1" … "R5".
    public let rule: String
    /// Short pt-BR title, free of gym jargon (SPEC decision 15).
    public let title: String
    /// One pt-BR sentence with the numbers that produced the suggestion (SPEC R5).
    public let reason: String
    /// `ExerciseTarget.id`s the suggestion changes; empty for program-level suggestions
    /// (deload, fewer days, switching programs).
    public let targetIDs: [UUID]
    /// Muscle group behind a volume suggestion (SPEC R3); `nil` otherwise.
    public let muscle: MuscleGroup?
    /// New absolute `sets` value for every target in `targetIDs` (addSets/removeSets).
    /// Absolute rather than a delta so applying the same suggestion twice is harmless.
    public let proposedSets: Int?
    /// New rep range for every target in `targetIDs` (changeRepRange).
    public let proposedRepRange: ClosedRange<Int>?
    public let strength: SuggestionStrength
    /// Key in the reference catalog behind the "Por quê?" button (SPEC RF-32), e.g.
    /// `topic.volume`, `topic.frequency`, `topic.substitution`, `rule.D`.
    public let referenceTopic: String

    public init(
        id: String,
        kind: ProgramSuggestionKind,
        rule: String,
        title: String,
        reason: String,
        targetIDs: [UUID] = [],
        muscle: MuscleGroup? = nil,
        proposedSets: Int? = nil,
        proposedRepRange: ClosedRange<Int>? = nil,
        strength: SuggestionStrength = .recommended,
        referenceTopic: String
    ) {
        self.id = id
        self.kind = kind
        self.rule = rule
        self.title = title
        self.reason = reason
        self.targetIDs = targetIDs
        self.muscle = muscle
        self.proposedSets = proposedSets
        self.proposedRepRange = proposedRepRange
        self.strength = strength
        self.referenceTopic = referenceTopic
    }

    /// SPEC R6: recovery trends only change how strongly a suggestion is backed and
    /// explain why; kind, targets and proposed values stay as R1–R5 produced them.
    func modulated(to strength: SuggestionStrength, adding sentence: String) -> ProgramSuggestion {
        ProgramSuggestion(
            id: id,
            kind: kind,
            rule: rule,
            title: title,
            reason: reason + " " + sentence,
            targetIDs: targetIDs,
            muscle: muscle,
            proposedSets: proposedSets,
            proposedRepRange: proposedRepRange,
            strength: strength,
            referenceTopic: referenceTopic
        )
    }
}
