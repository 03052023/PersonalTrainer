import Foundation
import Observation

@Observable
@MainActor
final class HealthProbeModel {
    enum Phase: Equatable {
        case idle
        case loading
        case reading(HeartRateReading)
        case empty
        case unavailable
        case failed(HealthProbeError)
    }

    private let service: any HealthProbeServicing
    private(set) var phase: Phase
    private(set) var hasRequestedAccess = false

    init(service: any HealthProbeServicing) {
        self.service = service
        self.phase = service.isAvailable ? .idle : .unavailable
    }

    var isLoading: Bool {
        phase == .loading
    }

    func read(now: Date) async {
        guard !isLoading else { return }
        guard service.isAvailable else {
            phase = .unavailable
            return
        }

        phase = .loading
        do {
            try await service.requestReadAccess()
            hasRequestedAccess = true
            if let reading = try await service.latestHeartRate(now: now) {
                phase = .reading(reading)
            } else {
                phase = .empty
            }
        } catch let error as HealthProbeError {
            phase = error == .unavailable ? .unavailable : .failed(error)
        } catch {
            phase = .failed(.unexpected)
        }
    }
}