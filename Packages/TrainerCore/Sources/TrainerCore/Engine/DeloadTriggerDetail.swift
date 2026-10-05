import Foundation

/// The numbers behind a scheduled lighter week, for the C1 reason (SPEC §7.11 C1 with numbers, TASKS
/// B11; docs/V24-CONTRACT.md §3.1). Computed by `DeloadScheduler.triggerDetail`, with the same re-arm
/// rule as `DeloadScheduler.status` (SPEC §7.5).
public struct DeloadTriggerDetail: Sendable, Hashable {
    /// The trigger the numbers explain: `.manyDecreases` or `.scheduled` (`.manual` has no numbers).
    public let trigger: DeloadTrigger
    /// (a): exercises whose current prescription carries `decrease` after the re-arm.
    public let decreasedExercises: Int
    /// (a): exercises counted for (a) (every prescription but `calibrate`).
    public let countedExercises: Int
    /// (b): whole weeks (7 × 24 h) since the instant the C1 text names: the start of the last lighter
    /// week or, when there was never one, the first session. A "Seguir normal" postpones (b) but is not
    /// that instant, so after one this can be larger than N (the sentence stays true).
    public let weeksSinceAnchor: Int
    /// (b): `false` when the anchor is the first session (there was never a lighter week).
    public let anchorIsLastDeload: Bool
    /// (b): SPEC §7.5 N.
    public let weeksBetweenDeloads: Int

    public init(
        trigger: DeloadTrigger,
        decreasedExercises: Int = 0,
        countedExercises: Int = 0,
        weeksSinceAnchor: Int = 0,
        anchorIsLastDeload: Bool = false,
        weeksBetweenDeloads: Int = DeloadPolicy.defaultWeeksBetweenDeloads
    ) {
        self.trigger = trigger
        self.decreasedExercises = decreasedExercises
        self.countedExercises = countedExercises
        self.weeksSinceAnchor = weeksSinceAnchor
        self.anchorIsLastDeload = anchorIsLastDeload
        self.weeksBetweenDeloads = weeksBetweenDeloads
    }
}
