import Foundation

/// Dia da semana do encaixe de planos (SPEC §7.15; docs/V23-UI-CONTRACT.md §3.1). A semana começa na
/// segunda, como a de §7.4: `monday` = 0 … `sunday` = 6. O raw value é gravado nas preferências da
/// semana (`WeekPreferences`): nunca renomear nem renumerar um case.
public enum PlanWeekday: Int, Codable, Sendable, Hashable, CaseIterable, Comparable {
    case monday = 0
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    public static func < (lhs: PlanWeekday, rhs: PlanWeekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Rótulo curto em pt-BR para chips e para a semana ("Seg", "Ter" …).
    public var shortName: String {
        switch self {
        case .monday: return "Seg"
        case .tuesday: return "Ter"
        case .wednesday: return "Qua"
        case .thursday: return "Qui"
        case .friday: return "Sex"
        case .saturday: return "Sáb"
        case .sunday: return "Dom"
        }
    }

    /// Nome em pt-BR, em minúsculas, para frases ("na segunda").
    public var name: String {
        switch self {
        case .monday: return "segunda"
        case .tuesday: return "terça"
        case .wednesday: return "quarta"
        case .thursday: return "quinta"
        case .friday: return "sexta"
        case .saturday: return "sábado"
        case .sunday: return "domingo"
        }
    }

    /// O dia seguinte numa semana que se repete (domingo → segunda).
    public var next: PlanWeekday {
        PlanWeekday(rawValue: (rawValue + 1) % 7) ?? .monday
    }

    /// Distância em dias numa semana que se repete, de 0 a 3 (domingo e segunda estão a 1 dia).
    /// É a base dos 48 h de S6 no encaixe (SPEC §7.15 M4).
    public func distance(to other: PlanWeekday) -> Int {
        let difference = abs(rawValue - other.rawValue)
        return min(difference, 7 - difference)
    }

    /// Dia da semana de `date` no `calendar` da pessoa (fuso de §7.4). `Calendar.weekday` vai de
    /// 1 = domingo a 7 = sábado; aqui a semana começa na segunda.
    public static func of(_ date: Date, calendar: Calendar) -> PlanWeekday {
        let weekday = calendar.component(.weekday, from: date)
        return PlanWeekday(rawValue: (weekday + 5) % 7) ?? .monday
    }
}
