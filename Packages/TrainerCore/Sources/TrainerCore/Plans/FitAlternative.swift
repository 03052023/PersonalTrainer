import Foundation

/// Uma saída quando os planos não cabem (SPEC §7.15 M5): as mudanças, as preferências que resultam delas e a
/// semana que fica.
public struct FitAlternative: Sendable, Hashable {
    public let changes: [FitChange]
    public let preferences: WeekPreferences
    public let schedule: WeekSchedule

    public init(changes: [FitChange], preferences: WeekPreferences, schedule: WeekSchedule) {
        self.changes = changes
        self.preferences = preferences
        self.schedule = schedule
    }
}
