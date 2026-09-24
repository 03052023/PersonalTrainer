import Foundation

/// Fixed pt-BR pieces of the review texts (AGENTS §4: UI text in pt-BR, fixed in code;
/// SPEC R7: no generated text). Numbers are formatted here, not by a locale-dependent
/// formatter, so the same report reads the same on every device.
enum ReviewText {
    /// `8` → "8", `8.25` → "8,3" (one decimal, pt-BR comma, halves away from zero).
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let tenths = (abs(value) * 10).rounded(.toNearestOrAwayFromZero)
        guard tenths < 1e15 else { return value < 0 ? "-∞" : "∞" }
        let whole = Int(tenths) / 10
        let fraction = Int(tenths) % 10
        let sign = value < 0 && tenths > 0 ? "-" : ""
        return fraction == 0 ? "\(sign)\(whole)" : "\(sign)\(whole),\(fraction)"
    }

    /// `part / total` as a whole percentage: 4 of 10 → "40%".
    static func percent(_ part: Int, of total: Int) -> String {
        guard total > 0 else { return "0%" }
        let value = (Double(part) / Double(total) * 100).rounded(.toNearestOrAwayFromZero)
        return "\(Int(value))%"
    }

    /// `1` → "1 semana", `3` → "3 semanas".
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }

    /// Estimated 1RM with the load unit when it is meaningful as a weight.
    static func estimate(_ e1rm: Double, unit: LoadUnit) -> String {
        switch unit {
        case .kilograms: return "\(number(e1rm)) kg"
        case .plates, .level: return number(e1rm)
        }
    }

    /// Lower-case group name for use inside a sentence (SPEC §7.4 list).
    static func muscleName(_ muscle: MuscleGroup) -> String {
        switch muscle {
        case .chest: return "peito"
        case .back: return "costas"
        case .shoulders: return "ombros"
        case .biceps: return "bíceps"
        case .triceps: return "tríceps"
        case .quads: return "quadríceps"
        case .hamstrings: return "posteriores da coxa"
        case .glutes: return "glúteos"
        case .calves: return "panturrilhas"
        case .core: return "abdômen e lombar"
        }
    }

    static func capitalizingFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
