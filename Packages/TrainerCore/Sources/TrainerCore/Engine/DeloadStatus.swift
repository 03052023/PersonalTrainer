import Foundation

/// Where the deload week of SPEC §7.5 stands for the next plan, as
/// `DeloadScheduler` derives it from the history. Never persisted: it is
/// recomputed on every call (ARCHITECTURE ADR 003).
///
/// `pending` and `active` both mean "plan the next session with
/// `DeloadPolicy.deloadPrescription(from:loadIncrement:isBodyweight:)`".
public enum DeloadStatus: Sendable, Hashable {
    /// No deload: the next plan uses the normal prescriptions.
    case inactive
    /// The next plan must be a deload; no deload session has started yet.
    /// `trigger` is the reason the C1 message shows (SPEC §7.11).
    case pending(trigger: DeloadTrigger)
    /// A deload pass is running since `start`, the `startedAt` of its first
    /// deload session. It ends once `DeloadPolicy.isDeloadActive` says the pass
    /// of the rotation is complete.
    case active(start: Date)
}
