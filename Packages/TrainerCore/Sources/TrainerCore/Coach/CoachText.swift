import Foundation

/// Periods and numbers inside the coach texts and ids. Formatted by hand, never with a
/// locale-dependent formatter, so the same input reads the same on the iPhone, on the CI
/// Linux runner and in the tests (SPEC §7.7).
enum CoachText {
    /// `calendar`'s time zone on the Gregorian calendar: labels are always Gregorian
    /// digits, whatever calendar the user picked.
    static func gregorian(like calendar: Calendar) -> Calendar {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        return gregorian
    }

    /// Local day of `date`, e.g. "2026-09-23": the daily period of message ids.
    static func day(_ date: Date, calendar: Calendar) -> String {
        let components = gregorian(like: calendar).dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        return "\(padded(year, digits: 4))-\(padded(components.month ?? 0, digits: 2))-\(padded(components.day ?? 0, digits: 2))"
    }

    /// ISO 8601 week of `date`, e.g. "2026-W39": the weekly period of message ids, the same
    /// label the periodic review puts in its suggestion ids.
    static func week(_ date: Date, calendar: Calendar) -> String {
        ProgramReviewer.isoWeekLabel(for: date, calendar: calendar)
    }

    /// Local day, month and time for a sentence, e.g. "25/09 às 23:00".
    static func dayMonthTime(_ date: Date, calendar: Calendar) -> String {
        let components = gregorian(like: calendar).dateComponents([.month, .day, .hour, .minute], from: date)
        let dayMonth = "\(padded(components.day ?? 0, digits: 2))/\(padded(components.month ?? 0, digits: 2))"
        let time = "\(padded(components.hour ?? 0, digits: 2)):\(padded(components.minute ?? 0, digits: 2))"
        return "\(dayMonth) às \(time)"
    }

    /// Canonical decimal for ids, with a dot and at most two decimals: 102.5 → "102.5",
    /// 100 → "100", 12.25 → "12.25".
    static func idNumber(_ value: Double) -> String {
        let hundredths = HealthMath.roundedInt(value * 100)
        let magnitude = hundredths.magnitude
        let sign = hundredths < 0 ? "-" : ""
        let whole = magnitude / 100
        let fraction = magnitude % 100
        if fraction == 0 {
            return "\(sign)\(whole)"
        }
        if fraction % 10 == 0 {
            return "\(sign)\(whole).\(fraction / 10)"
        }
        return "\(sign)\(whole).\(fraction < 10 ? "0" : "")\(fraction)"
    }

    /// "1 dia", "9 dias".
    static func days(_ value: Int) -> String {
        HealthText.count(value, singular: "dia", plural: "dias")
    }

    /// `value` with leading zeros up to `digits` characters (negative values keep the sign).
    static func padded(_ value: Int, digits: Int) -> String {
        let text = String(value.magnitude)
        let zeros = String(repeating: "0", count: max(0, digits - text.count))
        return (value < 0 ? "-" : "") + zeros + text
    }
}
