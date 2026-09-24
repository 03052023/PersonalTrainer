import Foundation

/// Deload week — SPEC §7.5 (triggers and content) and §7.11 C1 (the message that
/// announces it).
///
/// Pure functions: every instant is a parameter (AGENTS R3, SPEC P11) and nothing
/// here reads heart-rate data — SPEC §7.6 forbids it for deload decisions, and none
/// of the input types carries such a field (SPEC P12, AGENTS R2).
///
/// The three pieces are used together by the planner:
/// 1. `trigger` decides whether a deload should be scheduled (C1 shows the reason).
/// 2. While `isDeloadActive` is true, every exercise of the session gets
///    `deloadPrescription(from:)` of its normal prescription.
/// 3. The normal prescription itself is untouched: `DoubleProgressionRule` ignores
///    deload sessions for L and for the P4–P6 verdict (SPEC P3) but lets them reset
///    the P9 pause, so after the deload "a prescrição volta ao estado anterior".
public enum DeloadPolicy: Sendable {
    /// SPEC §7.5 (b): "a cada N semanas de treino (padrão 6)".
    public static let defaultWeeksBetweenDeloads = 6

    /// SPEC §7.5: RIR target of every deload prescription.
    public static let deloadTargetRIR = 4

    private static let secondsPerWeek: TimeInterval = 7 * 86_400

    // MARK: - Triggers

    /// Which SPEC §7.5 trigger, if any, schedules a deload now (SPEC §7.11 C1).
    ///
    /// - (a) `manyDecreases`: at least 50 % of `currentPrescriptions` carry the
    ///   `decrease` note. `calibrate` prescriptions are left out of the count: an
    ///   exercise with no evaluable history can neither progress nor regress, so it
    ///   says nothing about fatigue. With no prescription left, (a) never fires.
    /// - (b) `scheduled`: at least `weeksBetweenDeloads` weeks have elapsed since
    ///   `lastDeloadStart` or, when there was never a deload, since
    ///   `firstSessionDate`. Without either date the user has not trained yet.
    ///
    /// (a) is checked first, so when both hold the more specific reason is shown.
    /// `manual` (c) is the user's action and is never returned here.
    ///
    /// - Parameters:
    ///   - currentPrescriptions: the normal (non-deload) prescriptions of the active
    ///     program, one per program exercise, as `DoubleProgressionRule` computes them.
    ///   - lastDeloadStart: start of the most recent deload, or `nil` if never.
    ///   - firstSessionDate: start of the first session with this app, or `nil`.
    ///   - weeksBetweenDeloads: SPEC §7.5 N. A non-positive N disables (b).
    ///   - now: the reference instant (AGENTS R3).
    ///
    /// The caller evaluates this only while no deload is active (`isDeloadActive`).
    /// Note that the deload does not consume the evidence of (a): deload sessions
    /// are ignored by SPEC P3, so right after a deload the same `decrease` notes are
    /// still there until each exercise is trained normally again. The SPEC has no
    /// re-arm rule for (a); gating it is left to the caller (reported to the SPEC).
    public static func trigger(
        currentPrescriptions: [ExercisePrescription],
        lastDeloadStart: Date?,
        firstSessionDate: Date?,
        weeksBetweenDeloads: Int = DeloadPolicy.defaultWeeksBetweenDeloads,
        now: Date
    ) -> DeloadTrigger? {
        if hasManyDecreases(currentPrescriptions) {
            return .manyDecreases
        }
        if isScheduledDeloadDue(
            lastDeloadStart: lastDeloadStart,
            firstSessionDate: firstSessionDate,
            weeksBetweenDeloads: weeksBetweenDeloads,
            now: now
        ) {
            return .scheduled
        }
        return nil
    }

    // MARK: - Content

    /// The deload version of one normal prescription (SPEC §7.5).
    ///
    /// - sets = ⌈0.6 × S⌉, at least 1.
    /// - load = round↓(load × 0.85, inc), never below the SPEC P8 minimum (inc, or
    ///   0 for bodyweight work). No load stays no load: the user types it (SPEC P2).
    /// - targetRIR = 4, targetReps = repMin, note `deload`.
    /// - exercise, rep range and rest are copied unchanged.
    ///
    /// SPEC §7.5 writes the load as a fraction of the reference load L; the normal
    /// prescription's load is used instead because L is not part of a prescription.
    /// They coincide for `hold` and `retry`; for `decrease` and `returning` the
    /// deload is lighter, for `increase` one increment × 0.85 heavier (reported).
    ///
    /// - Parameters:
    ///   - normal: the prescription `DoubleProgressionRule` gives for today.
    ///   - loadIncrement: the exercise's `loadIncrement` (SPEC P8).
    ///   - isBodyweight: `equipment == .bodyweight`, where the P8 minimum is 0.
    public static func deloadPrescription(
        from normal: ExercisePrescription,
        loadIncrement: Double,
        isBodyweight: Bool
    ) -> ExercisePrescription {
        ExercisePrescription(
            exerciseID: normal.exerciseID,
            load: deloadLoad(normal.load, increment: loadIncrement, isBodyweight: isBodyweight),
            sets: deloadSets(normal.sets),
            repMin: normal.repMin,
            repMax: normal.repMax,
            targetReps: normal.repMin,
            targetRIR: deloadTargetRIR,
            restSeconds: normal.restSeconds,
            note: .deload
        )
    }

    // MARK: - Duration

    /// Whether the deload that started at `deloadStart` is still running.
    ///
    /// SPEC §7.5: the deload lasts "1 semana (uma passagem completa da rotação)",
    /// i.e. until `programDayCount` deload sessions have been completed since it
    /// started. A session counts when it is `completed`, flagged `isDeload`, has
    /// ≥ 1 working set and started at or after `deloadStart`; each id counts once.
    ///
    /// Conservative choices (SPEC §7.5 does not spell them out): an `abandoned` or
    /// empty session does not complete the pass — the rest week only ends once
    /// every day was actually done light — and elapsed time alone never ends it.
    /// With no deload (`nil`) or an empty program nothing is active.
    public static func isDeloadActive(
        deloadStart: Date?,
        sessionsSinceStart: [SessionSummary],
        programDayCount: Int
    ) -> Bool {
        guard let deloadStart, programDayCount > 0 else {
            return false
        }

        var counted = Set<UUID>()
        for session in sessionsSinceStart {
            guard session.status == .completed,
                  session.isDeload,
                  session.workingSetCount >= 1,
                  // The caller already filters, but a session before the start
                  // belongs to an older deload and must not shorten this one.
                  session.startedAt >= deloadStart
            else {
                continue
            }
            counted.insert(session.id)
        }
        return counted.count < programDayCount
    }
}

// MARK: - Rules

private extension DeloadPolicy {
    /// SPEC §7.5 (a): ≥ 50 % of the non-calibration prescriptions are `decrease`.
    /// Integer arithmetic keeps the 50 % boundary exact.
    static func hasManyDecreases(_ prescriptions: [ExercisePrescription]) -> Bool {
        let evaluated = prescriptions.filter { $0.note != .calibrate }
        guard !evaluated.isEmpty else {
            return false
        }
        let decreases = evaluated.filter { $0.note == .decrease }.count
        // decreases / evaluated ≥ 1/2 ⇔ 2 · decreases ≥ evaluated (no overflow: both
        // are array counts).
        return 2 * decreases >= evaluated.count
    }

    /// SPEC §7.5 (b) / §7.11 C1: "N semanas desde o último deload".
    ///
    /// Weeks are elapsed time (N × 7 × 24 h), not calendar weeks: the signature has
    /// no calendar, and elapsed time needs none. An anchor after `now` (clock skew)
    /// never fires.
    static func isScheduledDeloadDue(
        lastDeloadStart: Date?,
        firstSessionDate: Date?,
        weeksBetweenDeloads: Int,
        now: Date
    ) -> Bool {
        // A non-positive N would schedule a deload on every evaluation.
        guard weeksBetweenDeloads > 0,
              let anchor = lastDeloadStart ?? firstSessionDate
        else {
            return false
        }
        let interval = TimeInterval(weeksBetweenDeloads) * secondsPerWeek
        return now.timeIntervalSince(anchor) >= interval
    }

    /// SPEC §7.5: ⌈S × 0.6⌉ with a floor of one set.
    ///
    /// Computed in integers so no floating-point noise can push an exact product
    /// (0.6 × 5 = 3) over the ceiling: S = 10q + r → ⌈6S/10⌉ = 6q + ⌈6r/10⌉, which
    /// cannot overflow for any `Int` S.
    static func deloadSets(_ sets: Int) -> Int {
        guard sets > 0 else {
            return 1
        }
        let (quotient, remainder) = sets.quotientAndRemainder(dividingBy: 10)
        let result = 6 * quotient + (6 * remainder + 9) / 10
        return max(1, result)
    }

    /// SPEC §7.5 + P8: round↓(load × 0.85, inc), at least inc (0 for bodyweight).
    static func deloadLoad(_ load: Double?, increment: Double, isBodyweight: Bool) -> Double? {
        // A load that is not a number cannot be scaled; like SPEC P2 without a
        // starting load, the user types it on the first set.
        guard let load, load.isFinite else {
            return nil
        }
        // `× 85 / 100` instead of `× 0.85`: 0.85 has no exact binary form, while
        // `load × 85` is exact for any realistic load, so a product that lands on
        // the grid (100 → 85) stays exactly on it.
        let reduced = Load.round(load * 85 / 100, toIncrement: increment)
        let minimum = isBodyweight ? 0 : increment
        return max(reduced, minimum)
    }
}
