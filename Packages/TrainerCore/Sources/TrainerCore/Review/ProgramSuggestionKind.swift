import Foundation

/// What a periodic-review suggestion proposes (SPEC §7.8 R5, §7.11 C2).
/// Raw values are persisted in the decision log: never rename a case.
public enum ProgramSuggestionKind: String, Codable, Sendable, Hashable, CaseIterable {
    case deload
    case addSets
    case removeSets
    case swapExercise
    case changeRepRange
    case reduceDays
    case switchProgram

    /// SPEC R7: fixed presentation order — protect recovery first, then frequency, then
    /// volume, then exercise-level changes, and the optional program switch last.
    var reviewRank: Int {
        switch self {
        case .deload: return 0
        case .reduceDays: return 1
        case .removeSets: return 2
        case .addSets: return 3
        case .changeRepRange: return 4
        case .swapExercise: return 5
        case .switchProgram: return 6
        }
    }
}
