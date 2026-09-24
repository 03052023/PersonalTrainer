import Foundation

/// When the periodic review is due (SPEC §7.8: "a cada `reviewIntervalWeeks` (padrão 4)";
/// SPEC §7.11 C2: "A cada 4 semanas").
public enum ReviewSchedule: Sendable {
    public static let defaultIntervalWeeks = 4

    private static let secondsPerWeek: TimeInterval = 7 * 86_400

    /// Whether `intervalWeeks` weeks have elapsed since the last review or, before the
    /// first one, since the first session.
    ///
    /// - Weeks are elapsed time (N × 7 × 24 h), pauses included, like the scheduled
    ///   deload of SPEC §7.5 (b); the boundary is inclusive.
    /// - `lastReviewAt` wins over `firstSessionAt` whenever it exists.
    /// - Without either date the user has not trained yet: never due.
    /// - A non-positive interval disables the review; an anchor after `now` (clock
    ///   skew) is not due.
    public static func isDue(
        lastReviewAt: Date?,
        firstSessionAt: Date?,
        now: Date,
        intervalWeeks: Int = defaultIntervalWeeks
    ) -> Bool {
        guard intervalWeeks > 0, let anchor = lastReviewAt ?? firstSessionAt else {
            return false
        }
        return now.timeIntervalSince(anchor) >= TimeInterval(intervalWeeks) * secondsPerWeek
    }
}
