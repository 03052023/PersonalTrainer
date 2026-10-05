import Foundation

/// Groups worked outside the app that still need rest (SPEC §7.17 X5, §7.3 S6; docs/V24-CONTRACT.md §3.1).
///
/// Built by `OutsideActivities.recoveryLoads(entries:)` from what the person logged, and passed to
/// `FrequencyAwareSelector`: a group in `muscles` counts as "trained" from `start` until `hours` later.
/// Strength activities (cross) keep their groups for 48 h, like S6; a vigorous aerobic activity keeps
/// the legs for 24 h, like A5. Only logged facts: no physiological signal is an input (SPEC P12).
public struct RecoveryLoad: Sendable, Hashable {
    public let start: Date
    public let muscles: Set<MuscleGroup>
    /// Rest window in hours (48 for strength, 24 for vigorous aerobic work).
    public let hours: Double

    public init(start: Date, muscles: Set<MuscleGroup>, hours: Double) {
        self.start = start
        self.muscles = muscles
        self.hours = hours
    }
}
