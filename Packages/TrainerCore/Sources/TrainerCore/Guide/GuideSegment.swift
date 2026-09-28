import Foundation

/// Segmento do corpo do manequim (docs/V23-CORE-CONTRACT.md §2.5), usado em `moving` (SPEC E9), nos acessórios presos
/// a um segmento e na trava das articulações (E10). "Far" é o lado de lá; tronco e cabeça são um só.
public enum GuideSegment: String, CaseIterable, Sendable {
    case trunk
    case head
    case thigh
    case shin
    case foot
    case upperArm
    case forearm
    case thighFar
    case shinFar
    case footFar
    case upperArmFar
    case forearmFar

    public var isFar: Bool {
        switch self {
        case .thighFar, .shinFar, .footFar, .upperArmFar, .forearmFar: return true
        default: return false
        }
    }

    /// O mesmo segmento do lado de lá; `nil` no tronco, na cabeça e nos que já são do lado de lá.
    public var farCounterpart: GuideSegment? {
        switch self {
        case .thigh: return .thighFar
        case .shin: return .shinFar
        case .foot: return .footFar
        case .upperArm: return .upperArmFar
        case .forearm: return .forearmFar
        default: return nil
        }
    }

    /// O mesmo segmento do lado de cá.
    public var nearCounterpart: GuideSegment {
        switch self {
        case .thighFar: return .thigh
        case .shinFar: return .shin
        case .footFar: return .foot
        case .upperArmFar: return .upperArm
        case .forearmFar: return .forearm
        default: return self
        }
    }

    public var isArm: Bool {
        switch nearCounterpart {
        case .upperArm, .forearm: return true
        default: return false
        }
    }

    /// Segmentos que aceitam acessório preso ao longo deles (`attach` com `along`): membros, nunca tronco ou cabeça.
    public var isAttachable: Bool {
        self != .trunk && self != .head
    }

    /// Segmento-pai no mesmo membro (E9): a cabeça, a coxa e o braço saem do tronco.
    public var parent: GuideSegment? {
        switch self {
        case .trunk: return nil
        case .head, .thigh, .upperArm, .thighFar, .upperArmFar: return .trunk
        case .shin: return .thigh
        case .foot: return .shin
        case .forearm: return .upperArm
        case .shinFar: return .thighFar
        case .footFar: return .shinFar
        case .forearmFar: return .upperArmFar
        }
    }

    /// Segmentos que podem só acompanhar, rígidos, um pai que se move (E9): cabeça, perna, pé e antebraço.
    public var isRigid: Bool {
        switch nearCounterpart {
        case .head, .shin, .foot, .forearm: return true
        default: return false
        }
    }

    /// Pontas do segmento (proximal → distal) na vista dada (docs/V23-CORE-CONTRACT.md §2.5).
    public func endpoints(in view: ExerciseGuide.Viewpoint) -> (proximal: GuideJoint, distal: GuideJoint) {
        let front = view == .front
        switch self {
        case .trunk:
            return (proximal: GuideJoint.hip, distal: front ? GuideJoint.neckBase : GuideJoint.shoulder)
        case .head:
            return (proximal: front ? GuideJoint.neckBase : GuideJoint.shoulder, distal: GuideJoint.head)
        case .thigh:
            return (proximal: front ? GuideJoint.hipJ : GuideJoint.hip, distal: GuideJoint.knee)
        case .shin:
            return (proximal: GuideJoint.knee, distal: GuideJoint.ankle)
        case .foot:
            return (proximal: GuideJoint.ankle, distal: GuideJoint.toe)
        case .upperArm:
            return (proximal: GuideJoint.shoulder, distal: GuideJoint.elbow)
        case .forearm:
            return (proximal: GuideJoint.elbow, distal: GuideJoint.wrist)
        case .thighFar:
            return (proximal: front ? GuideJoint.hipJFar : GuideJoint.hip, distal: GuideJoint.kneeFar)
        case .shinFar:
            return (proximal: GuideJoint.kneeFar, distal: GuideJoint.ankleFar)
        case .footFar:
            return (proximal: GuideJoint.ankleFar, distal: GuideJoint.toeFar)
        case .upperArmFar:
            return (proximal: front ? GuideJoint.shoulderFar : GuideJoint.shoulder, distal: GuideJoint.elbowFar)
        case .forearmFar:
            return (proximal: GuideJoint.elbowFar, distal: GuideJoint.wristFar)
        }
    }
}
