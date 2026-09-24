import Foundation

/// How strongly the app backs a suggestion (SPEC §7.8 R6: recovery trends can turn a
/// suggestion "opcional"). Raw values are persisted in the decision log.
public enum SuggestionStrength: String, Codable, Sendable, Hashable {
    case recommended
    case optional
}
