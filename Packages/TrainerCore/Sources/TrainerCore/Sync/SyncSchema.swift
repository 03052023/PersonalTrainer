import Foundation

/// Version of the iPhone ↔ Watch wire format (ARCHITECTURE §9, AR-3).
///
/// Bump `currentVersion` whenever an encoded `ActiveSessionSnapshot` or
/// `SessionEvent` changes shape in a way an older receiver cannot decode: a new
/// `SessionEvent.Kind` case, a renamed or retyped key, a new required field.
/// Adding an optional field does not require a bump. Not to be confused with
/// `TrainerCore.version` (the package) or the SwiftData `SchemaVN` (ARCHITECTURE §5).
public enum SyncSchema {
    /// v1 (M0): `ActiveSessionSnapshot { schemaVersion, generatedAt, activeSession?, nextPlan? }`
    /// and the nine `SessionEvent.Kind` cases with a `type` discriminator.
    public static let currentVersion = 1
}
