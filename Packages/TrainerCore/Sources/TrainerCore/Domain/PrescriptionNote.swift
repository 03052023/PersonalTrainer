import Foundation

public enum PrescriptionNote: String, Codable, Sendable, Hashable {
    case calibrate
    case increase
    case hold
    case retry
    case decrease
    case returning
    case deload
}
