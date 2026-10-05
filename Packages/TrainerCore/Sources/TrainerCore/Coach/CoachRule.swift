import Foundation

/// The rules of the app's dialogue with the user (SPEC §7.11). Since 2.5 the active rules are
/// C1–C3 and C5–C8; C4 was removed (SPEC §7.18 L4).
/// Raw values are persisted in the coach log (`CoachLogEntry.rule`): never rename a case.
public enum CoachRule: String, Codable, CaseIterable, Sendable {
    /// C1: a lighter week was scheduled (SPEC §7.5).
    case deload
    /// C2: suggestions of the periodic review (SPEC §7.8).
    case review
    /// C3: health suggestions (SPEC §7.10).
    case health
    /// C4, removida na 2.5 (SPEC §7.18 L4): o case fica porque o raw value pode estar no log do
    /// diálogo; nunca é emitido nem oferecido.
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
