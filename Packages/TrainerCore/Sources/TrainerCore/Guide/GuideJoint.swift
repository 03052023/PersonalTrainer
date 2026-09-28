import Foundation

/// Ponto do esqueleto do manequim (docs/V23-CORE-CONTRACT.md §2.5). Os raw values são os nomes normativos usados em
/// `anchor.joint`, `attach`, `cue.track`, `cable.to` e no golden. "Far" é o lado de lá; `hand` é o meio da palma
/// (a pegada) e `fist` a ponta da mão fechada.
public enum GuideJoint: String, CaseIterable, Sendable {
    case hip
    case shoulder
    case head
    case knee
    case ankle
    case toe
    case heel
    case elbow
    case wrist
    case hand
    case fist
    case kneeFar
    case ankleFar
    case toeFar
    case heelFar
    case elbowFar
    case wristFar
    case handFar
    case fistFar
    /// Vista frontal: base do pescoço (topo do tronco).
    case neckBase
    /// Vista frontal: ombro do lado de lá.
    case shoulderFar
    /// Vista frontal: articulação do quadril do lado de cá.
    case hipJ
    /// Vista frontal: articulação do quadril do lado de lá.
    case hipJFar

    /// Pontos da vista lateral, na ordem do golden.
    public static let sidePoints: [GuideJoint] = [
        .hip, .shoulder, .head, .knee, .ankle, .toe, .heel, .elbow, .wrist, .hand, .fist,
        .kneeFar, .ankleFar, .toeFar, .heelFar, .elbowFar, .wristFar, .handFar, .fistFar,
    ]

    /// Pontos da vista frontal, na ordem do golden.
    public static let frontPoints: [GuideJoint] = [
        .hip, .neckBase, .head, .shoulder, .shoulderFar, .hipJ, .hipJFar, .elbow, .elbowFar, .wrist, .wristFar,
        .hand, .handFar, .fist, .fistFar, .knee, .kneeFar, .ankle, .ankleFar, .toe, .toeFar,
    ]

    public static func points(for view: ExerciseGuide.Viewpoint) -> [GuideJoint] {
        switch view {
        case .side: return sidePoints
        case .front: return frontPoints
        }
    }

    /// Cotovelo, punho e mão dos dois lados: só existem depois dos braços, então âncora ou acessório nesses pontos
    /// exige braços por ângulos (âncora) ou é calculado depois dos braços (acessório).
    public var isArmPoint: Bool {
        switch self {
        case .elbow, .wrist, .hand, .fist, .elbowFar, .wristFar, .handFar, .fistFar:
            return true
        default:
            return false
        }
    }
}
