import Foundation

/// Plain rotation over the program days (SPEC §7.3 v1, rules S1–S4).
///
/// The next day is the one that follows, in `order`, the day of the most recent
/// session that was `completed` or `abandoned` with at least one working set
/// (SPEC S2). Without such a session the rotation starts at D1; after Dn it wraps
/// back to D1.
///
/// Sessions with status `inProgress` are ignored here. SPEC S3 ("resume the open
/// session") is the `SessionPlanner`'s responsibility: it resumes an in-progress
/// session *before* calling the selector, so from the selector's point of view an
/// open session never exists.
///
/// SPEC S4 (manual override) needs no extra input: when the user picks a day by
/// hand, the session recorded for it becomes the most recent reference and the
/// rotation naturally continues from that day.
///
/// If the reference session points to a day that is no longer in the program
/// (the program was edited since), the rotation restarts at D1. This is the
/// conservative reading of S2 for a case the SPEC does not spell out.
public struct RotationSelector: WorkoutSelector {
    public init() {}

    public func nextDay(
        program: ProgramTemplate,
        recentSessions: [SessionSummary],
        now: Date
    ) -> ProgramDayTemplate? {
        // SPEC S1: the rotation follows `order`, never the array layout.
        let orderedDays = Self.orderedDays(of: program)
        guard let firstDay = orderedDays.first else {
            return nil
        }

        // SPEC S2: no finished session with working sets yet → D1.
        guard let reference = Self.referenceSession(in: recentSessions) else {
            return firstDay
        }

        // Program changed since that session: its day is gone → restart at D1.
        guard let referenceIndex = orderedDays.firstIndex(where: { $0.id == reference.programDayID }) else {
            return firstDay
        }

        // SPEC S2: the day right after the reference; after Dn → D1.
        let nextIndex = orderedDays.index(after: referenceIndex)
        return nextIndex < orderedDays.endIndex ? orderedDays[nextIndex] : firstDay
    }
}

private extension RotationSelector {
    /// Days ranked by `order` (SPEC S1). Ties on `order` would be a program
    /// invariant violation; array position breaks them so the result stays
    /// deterministic instead of depending on sort stability (SPEC P11).
    static func orderedDays(of program: ProgramTemplate) -> [ProgramDayTemplate] {
        program.days
            .enumerated()
            .sorted { ($0.element.order, $0.offset) < ($1.element.order, $1.offset) }
            .map(\.element)
    }

    /// The most recent session that moves the rotation (SPEC S2).
    ///
    /// Input order is not trusted: sessions are ranked by `startedAt` descending,
    /// with `id` as a deterministic tie-breaker for identical instants (SPEC P11).
    static func referenceSession(in sessions: [SessionSummary]) -> SessionSummary? {
        sessions
            .sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt {
                    return lhs.startedAt > rhs.startedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .first(where: movesRotation)
    }

    /// Whether a session counts as the rotation reference.
    static func movesRotation(_ session: SessionSummary) -> Bool {
        switch session.status {
        case .inProgress:
            // SPEC S3 is handled upstream by the SessionPlanner (see type doc).
            return false
        case .completed, .abandoned:
            // SPEC S2: a finished session only counts with ≥ 1 working set.
            return session.workingSetCount >= 1
        }
    }
}
