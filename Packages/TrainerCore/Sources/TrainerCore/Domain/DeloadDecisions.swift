import Foundation

/// The user's two decisions about the deload week (SPEC §7.5 (c) and §7.11 C1).
///
/// The app keeps this value as a small JSON file, not in SwiftData: it is the only
/// deload state that cannot be derived from the history (ARCHITECTURE ADR 003), and
/// `DeloadScheduler` reads it on every plan. Both fields are optional, so a file
/// written before a field existed still decodes (missing keys become `nil`).
public struct DeloadDecisions: Codable, Sendable, Hashable {
    /// SPEC §7.5 (c): when the user asked for a light week now ("Fazer semana leve
    /// agora"). It is answered once a deload session starts at or after this
    /// instant. `DeloadScheduler` never clears it; to undo a manual request the app
    /// sets it back to `nil` (`dismissedAt` does not cancel it).
    public var manualRequestedAt: Date?

    /// SPEC §7.11 C1 "Seguir normal": when the user declined a scheduled deload.
    /// It postpones the automatic triggers only: (a) ignores reductions that come
    /// from sessions up to this instant, and (b) counts its N weeks from here when
    /// this is more recent than the start of the last deload.
    public var dismissedAt: Date?

    public init(manualRequestedAt: Date? = nil, dismissedAt: Date? = nil) {
        self.manualRequestedAt = manualRequestedAt
        self.dismissedAt = dismissedAt
    }
}
