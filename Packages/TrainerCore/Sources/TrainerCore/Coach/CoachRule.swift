import Foundation

/// The eight rules of the app's dialogue with the user (SPEC §7.11 C1–C8).
/// Raw values are persisted in the coach log (`CoachLogEntry.rule`): never rename a case.
public enum CoachRule: String, Codable, CaseIterable, Sendable {
    /// C1: a lighter week was scheduled (SPEC §7.5).
    case deload
    /// C2: suggestions of the periodic review (SPEC §7.8).
    case review
    /// C3: health suggestions (SPEC §7.10).
    case health
    /// C4: the installation (provisioning profile) is about to expire.
    case installExpiry
    /// C5: welcome back after ≥ 6 days without a session (SPEC P9 after 21 days).
    case comeback
    /// C6: new best estimated 1RM of an exercise (Epley, SPEC R1).
    case personalRecord
    /// C7: backup reminder.
    case backup
    /// C8: balance and mobility reminders of the Longevity goal (SPEC §7.9).
    case longevity
}
