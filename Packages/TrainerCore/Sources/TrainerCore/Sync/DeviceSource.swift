import Foundation

/// Which client produced a `SessionEvent`.
///
/// ARCHITECTURE §7 / AR-2: the iPhone UI, the Watch UI and the backup importer
/// all emit the same events; `source` lets the `SessionCoordinator` and the
/// HealthKit invariant (ARCHITECTURE §8: exactly one `HKWorkout` per session)
/// tell them apart without a second write path.
///
/// Raw values are persisted (`WorkoutSessionModel.sourceRaw`, `SetLogModel.sourceRaw`)
/// and travel over WatchConnectivity, so they follow AGENTS §4: stable English
/// raw values, never rename an existing case (add a new one and migrate).
public enum DeviceSource: String, Codable, Sendable, Hashable, CaseIterable {
    case iphone
    case watch
    case importer
}
