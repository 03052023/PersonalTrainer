import Foundation

/// New personal marks of a session — SPEC §7.11 C6 ("Novo melhor 1RM estimado de um
/// exercício (Epley)"). Pure function of the histories; no clock, no heart rate.
public enum PersonalRecordDetector: Sendable {
    /// Exercises whose best estimated 1RM in `latestSessionID` beats every earlier session.
    ///
    /// - "Earlier" is the history order of `ReviewHistory` (date, then `sessionID`), so a
    ///   session recorded after `latestSessionID` never lowers or raises the bar.
    /// - The first measurable session of an exercise is not a record (SPEC C6: a new
    ///   *best* needs a previous one). Sessions without added load (pure bodyweight,
    ///   Epley = 0) do not count as measured.
    /// - Deload sessions count as earlier sessions: a real lift is a real mark.
    /// - A tie is not a record, including ties that differ only by floating-point noise.
    ///
    /// - Parameters:
    ///   - latestSessionID: The session that just finished.
    ///   - histories: History per exercise, keyed by `ExerciseDefinition.id`, in any order.
    /// - Returns: One record per exercise, sorted by `exerciseID.uuidString` (SPEC R7).
    public static func newRecords(
        latestSessionID: UUID,
        histories: [UUID: [ExerciseHistoryEntry]]
    ) -> [PersonalRecord] {
        var records: [PersonalRecord] = []

        for (exerciseID, history) in histories {
            let sessions = ReviewHistory.sessions(from: history)
            guard let latestIndex = sessions.firstIndex(where: { $0.sessionID == latestSessionID }),
                  let best = ReviewHistory.measurableEstimate(of: sessions[latestIndex])
            else {
                continue
            }

            let previousBest = sessions[..<latestIndex]
                .compactMap { ReviewHistory.measurableEstimate(of: $0)?.e1rm }
                .max()

            guard let previousBest,
                  EstimatedOneRepMax.isImprovement(best.e1rm, over: previousBest)
            else {
                continue
            }

            records.append(
                PersonalRecord(
                    exerciseID: exerciseID,
                    e1rm: best.e1rm,
                    previousBest: previousBest,
                    load: best.set.load,
                    reps: best.set.reps
                )
            )
        }

        return records.sorted { $0.exerciseID.uuidString < $1.exerciseID.uuidString }
    }
}
