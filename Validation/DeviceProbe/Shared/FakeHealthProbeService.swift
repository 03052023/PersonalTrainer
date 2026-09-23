import Foundation

@MainActor
final class FakeHealthProbeService: HealthProbeServicing {
    enum Scenario {
        case sample
        case empty
        case unavailable
        case authorizationFailure
        case readFailure
    }

    private let scenario: Scenario

    init(scenario: Scenario = .sample) {
        self.scenario = scenario
    }

    var isAvailable: Bool {
        if case .unavailable = scenario { return false }
        return true
    }

    func requestReadAccess() async throws {
        if case .authorizationFailure = scenario {
            throw HealthProbeError.authorizationFailed(code: nil)
        }
        if !isAvailable {
            throw HealthProbeError.unavailable
        }
    }

    func latestHeartRate(now: Date) async throws -> HeartRateReading? {
        switch scenario {
        case .sample:
            return HeartRateReading(
                beatsPerMinute: 76,
                sampledAt: now.addingTimeInterval(-90)
            )
        case .empty, .authorizationFailure:
            return nil
        case .unavailable:
            throw HealthProbeError.unavailable
        case .readFailure:
            throw HealthProbeError.readFailed(code: nil)
        }
    }
}