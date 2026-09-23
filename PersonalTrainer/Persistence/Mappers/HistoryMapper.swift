import Foundation
import TrainerCore

/// `[SessionExerciseModel]` → `[ExerciseHistoryEntry]`, a entrada do motor de progressão.
///
/// Funções puras: não tocam `ModelContext`. O app faz a query; aqui só se filtra,
/// ordena e converte (ARCHITECTURE §6, "O motor recebe histórico já filtrado").
enum HistoryMapper {
    /// - Só sessões `completed` ou `abandoned` contam (SPEC P3); `inProgress` fica fora.
    /// - `statusRaw` desconhecido lança `MappingError.invalidRawValue`, como nos demais
    ///   mappers: descartar em silêncio faria o motor prescrever `calibrate` (reset de carga)
    ///   sobre um store corrompido. Um `SessionExerciseModel` sem `session` é ignorado.
    /// - Séries de aquecimento entram com `isWarmup = true`; quem descarta é o motor (SPEC P1).
    /// - Exercício pulado vira entrada com 0 séries; o motor ignora a sessão (SPEC P7).
    /// - Ordenado do mais recente ao mais antigo, com desempate determinístico (SPEC P11).
    static func historyEntries(
        from sessionExercises: [SessionExerciseModel],
        exerciseUUID: UUID
    ) throws -> [ExerciseHistoryEntry] {
        var entries: [ExerciseHistoryEntry] = []

        for sessionExercise in sessionExercises where sessionExercise.exerciseUUID == exerciseUUID {
            guard let session = sessionExercise.session else {
                continue
            }
            guard let status = session.status else {
                throw MappingError.invalidRawValue(
                    model: "WorkoutSessionModel",
                    field: "statusRaw",
                    value: session.statusRaw
                )
            }
            guard status == .completed || status == .abandoned else {
                continue
            }

            let sets = sessionExercise.sets
                .sorted { $0.index < $1.index }
                .map { setResult(from: $0) }

            entries.append(
                ExerciseHistoryEntry(
                    sessionID: session.uuid,
                    date: session.startedAt,
                    sets: sets,
                    wasDeload: session.isDeload
                )
            )
        }

        return entries.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date > rhs.date
            }
            return lhs.sessionID.uuidString > rhs.sessionID.uuidString
        }
    }

    static func setResult(from model: SetLogModel) -> SetResult {
        SetResult(
            load: model.load,
            reps: model.reps,
            rir: model.rir,
            isWarmup: model.isWarmup,
            completedAt: model.completedAt
        )
    }
}
