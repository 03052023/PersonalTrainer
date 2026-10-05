import Foundation
import TrainerCore

/// O tipo de treino que o app grava no Saúde para uma sessão (SPEC RF-13, §7.14 F5).
///
/// - `strength`: musculação, ou sessão que mistura força e aeróbico; é o que o app sempre gravou.
/// - `aerobic`: sessão só de aeróbicos (Cardio, 2.3), com o tipo do primeiro aeróbico que teve série.
/// - `jumpRope`: o `AerobicActivity` do `TrainerCore` não tem corda (e o núcleo não muda aqui), mas o
///   Saúde tem o tipo próprio; por isso é um caso à parte. Na leitura volta como HIIT (forte pelo tipo, A1).
///
/// Vive no app e não no `TrainerCore` porque só existe para escolher o `HKWorkoutActivityType`; o
/// núcleo não sabe de HealthKit (AGENTS R1).
enum WorkoutRecordKind: Sendable, Hashable {
    case strength
    case aerobic(AerobicActivity)
    case jumpRope

    /// Tipo do treino para o slug de um exercício aeróbico do catálogo (SPEC F5). Um slug que não
    /// está na tabela (exercício criado pela pessoa, com padrão de movimento `cardio`) vira
    /// `.aerobic(.other)`, que o Live grava como cardio misto.
    static func aerobicKind(forSlug slug: String) -> WorkoutRecordKind {
        switch slug {
        case "brisk-walk":
            return .aerobic(.walking)
        case "easy-run", "run-intervals":
            return .aerobic(.running)
        case "stationary-bike", "bike-intervals":
            return .aerobic(.cycling)
        case "rowing-machine":
            return .aerobic(.rowing)
        case "elliptical":
            return .aerobic(.elliptical)
        case "stair-climb":
            return .aerobic(.stairs)
        case "jump-rope":
            return .jumpRope
        case "bodyweight-circuit":
            return .aerobic(.hiit)
        default:
            return .aerobic(.other)
        }
    }
}
