import Foundation

public enum SessionStatus: String, Codable, Sendable, Hashable {
    case inProgress
    case completed
    case abandoned
}
