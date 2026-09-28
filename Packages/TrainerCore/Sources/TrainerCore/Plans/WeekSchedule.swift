import Foundation

/// A semana ideal com os planos encaixados (SPEC §7.15 M4; docs/V23-UI-CONTRACT.md §3.1).
public struct WeekSchedule: Sendable, Hashable {
    /// Ordenadas por dia e, dentro do dia, por `orderInDay`.
    public let slots: [PlannedSlot]
    public let notes: [FitNote]

    public init(slots: [PlannedSlot], notes: [FitNote] = []) {
        self.slots = slots.sorted { lhs, rhs in
            if lhs.weekday != rhs.weekday {
                return lhs.weekday < rhs.weekday
            }
            return lhs.orderInDay < rhs.orderInDay
        }
        self.notes = notes
    }

    public static let empty = WeekSchedule(slots: [])

    /// As sessões de um dia, na ordem do dia.
    public func slots(on weekday: PlanWeekday) -> [PlannedSlot] {
        slots.filter { $0.weekday == weekday }
    }

    /// Os dias sem nenhuma sessão.
    public var restDays: [PlanWeekday] {
        PlanWeekday.allCases.filter { day in !slots.contains { $0.weekday == day } }
    }
}
