import Foundation
import TrainerCore

extension WorkoutRecordKind {
    /// O tipo de treino de uma sessão (SPEC F5). Só conta o exercício com ao menos uma série de
    /// trabalho (aquecimento não conta, e exercício pulado ou sem série fica de fora):
    /// - todos os que contam são aeróbicos (`movementPattern == .cardio`): `.aerobic` com o tipo
    ///   do primeiro deles, na ordem da sessão;
    /// - qualquer outro caso, inclusive nenhuma série, um exercício que saiu do catálogo ou sem
    ///   padrão de movimento, e a mistura de força com aeróbico: `.strength`, como sempre foi.
    ///
    /// Lê o exercício que foi feito (a troca já regrava a relação), e não o do plano.
    static func kind(for session: WorkoutSessionModel) -> WorkoutRecordKind {
        let worked = session.exercises
            .filter { sessionExercise in sessionExercise.sets.contains { !$0.isWarmup } }
            .sorted { $0.order < $1.order }
        guard let first = worked.first else {
            return .strength
        }
        let allAerobic = worked.allSatisfy { $0.exercise?.movementPattern == .cardio }
        guard allAerobic else {
            return .strength
        }
        return aerobicKind(forSlug: first.exercise?.slug ?? "")
    }
}
