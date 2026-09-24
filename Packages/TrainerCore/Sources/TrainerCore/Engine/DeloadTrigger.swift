import Foundation

/// Why a deload week was scheduled (SPEC §7.5 triggers, shown by the C1 message of
/// SPEC §7.11). Raw values are persisted in the decision log: never rename a case.
public enum DeloadTrigger: String, Codable, CaseIterable, Sendable, Hashable {
    /// SPEC §7.5 (a): ≥ 50 % of the current prescriptions carry the `decrease` note.
    case manyDecreases
    /// SPEC §7.5 (b): N weeks (default 6) since the last deload or the first session.
    case scheduled
    /// SPEC §7.5 (c): the user asked for it. Never produced by `DeloadPolicy.trigger`.
    case manual
}
