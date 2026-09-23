enum HealthProbeError: Error, Sendable, Equatable {
    case unavailable
    case authorizationFailed(code: Int?)
    case readFailed(code: Int?)
    case unexpected
}