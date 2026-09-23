import Foundation

@MainActor
protocol HealthProbeServicing {
    var isAvailable: Bool { get }

    func requestReadAccess() async throws
    func latestHeartRate(now: Date) async throws -> HeartRateReading?
}