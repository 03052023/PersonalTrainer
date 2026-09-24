import Foundation

/// The deload status as the coach sees it (SPEC §7.11 C1). The app computes it with
/// `DeloadScheduler` and passes it in; the coach never evaluates the triggers itself.
public enum CoachDeloadState: Sendable, Hashable {
    /// No lighter week scheduled or running.
    case none
    /// The next sessions will be a lighter week (SPEC §7.5), none of them started yet.
    ///
    /// `since` identifies this scheduling and becomes the period of the C1 message id
    /// (`deload:<day of since>`), so it must stay the same while the same deload is
    /// pending: for example the instant the app first saw the pending status, or
    /// `DeloadDecisions.manualRequestedAt` for a manual request. Passing `now` would
    /// show the message again every day after the user answered it.
    case scheduled(trigger: DeloadTrigger, since: Date)
    /// The lighter week is running since `start` (first deload session). C1 stays quiet:
    /// the Home card already shows the lighter week as part of the plan (DESIGN §9).
    case running(start: Date)
}
