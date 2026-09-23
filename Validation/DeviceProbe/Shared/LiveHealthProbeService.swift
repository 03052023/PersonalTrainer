import Foundation
import HealthKit

@MainActor
final class LiveHealthProbeService: HealthProbeServicing {
    private let store = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestReadAccess() async throws {
        guard isAvailable,
              let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthProbeError.unavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            store.requestAuthorization(toShare: [], read: [heartRateType]) { @Sendable success, error in
                if success {
                    // HealthKit confirms that the request completed, not that reading was allowed.
                    continuation.resume()
                } else {
                    continuation.resume(throwing: HealthProbeError.authorizationFailed(
                        code: (error as NSError?)?.code
                    ))
                }
            }
        }
    }

    func latestHeartRate(now: Date) async throws -> HeartRateReading? {
        guard isAvailable,
              let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthProbeError.unavailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: now.addingTimeInterval(-24 * 60 * 60),
            end: now,
            options: [.strictStartDate, .strictEndDate]
        )
        let order = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<HeartRateReading?, any Error>) in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [order]
            ) { @Sendable _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthProbeError.readFailed(
                        code: (error as NSError).code
                    ))
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                // Only a Sendable value leaves the HealthKit callback; no HKSample crosses actors.
                let reading = HeartRateReading(
                    beatsPerMinute: sample.quantity.doubleValue(
                        for: HKUnit.count().unitDivided(by: .minute())
                    ),
                    sampledAt: sample.endDate
                )
                continuation.resume(returning: reading)
            }
            store.execute(query)
        }
    }
}