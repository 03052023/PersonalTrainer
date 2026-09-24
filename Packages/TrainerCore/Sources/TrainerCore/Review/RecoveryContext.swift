import Foundation

/// Aggregated recovery trends for the periodic review (SPEC §7.8 R6, §7.10 A4).
///
/// Only booleans derived from 7-day vs 28-day averages reach this module; the app maps
/// them from the Health module. No raw sample of any strength session exists here, and
/// this type lives in `Review/`, never in `Engine/` (AGENTS R2, SPEC P12): it can only
/// modulate suggestions that R1–R4 already produced, never create one or touch a load.
public struct RecoveryContext: Codable, Sendable, Hashable {
    /// HRV (SDNN) 7-day average dropped ≥ 10 % against the 28-day average (SPEC A4).
    public let hrvDropped: Bool
    /// Resting heart rate 7-day average rose ≥ 5 bpm against the 28-day average (SPEC A4).
    public let restingHeartRateRose: Bool
    /// Sleep below the goal in the recent average (SPEC §7.9: 7–9 h).
    public let sleepLow: Bool
    /// `false` when there is not enough night data to judge; every flag is then ignored.
    public let hasData: Bool

    public init(
        hrvDropped: Bool = false,
        restingHeartRateRose: Bool = false,
        sleepLow: Bool = false,
        hasData: Bool
    ) {
        self.hrvDropped = hrvDropped
        self.restingHeartRateRose = restingHeartRateRose
        self.sleepLow = sleepLow
        self.hasData = hasData
    }

    /// No recovery data: R6 leaves every suggestion as R1–R5 produced it.
    public static let unknown = RecoveryContext(hasData: false)

    /// SPEC R6: a recovery trend pointing down reinforces deload and weakens added volume.
    var isStrained: Bool {
        hasData && (hrvDropped || restingHeartRateRose)
    }

    /// SPEC R6: "HRV estável ou em alta enfraquece". Low sleep is not "stable", so it
    /// blocks the weakening, but on its own it neither reinforces nor weakens anything
    /// (the SPEC only names HRV and resting heart rate as modulators).
    var isStable: Bool {
        hasData && !hrvDropped && !restingHeartRateRose && !sleepLow
    }
}
