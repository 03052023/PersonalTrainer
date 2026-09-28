import Foundation

/// Cinemática normativa do "Como fazer" (SPEC E4–E6; docs/V23-CORE-CONTRACT.md §2.5). É a porta de `Solve-Guide`,
/// `Solve-Front`, `Solve-TwoBone` e `Set-ForearmPoints` de docs/design/exercise-guides/render-exercise-guides.ps1,
/// com as extensões (a)–(e) da 2.3; o GuideGoldenTests compara os dois em até 0,001 H.
///
/// Função pura de (guia, t): nada de relógio nem de aleatório, então a mesma guia e o mesmo t dão sempre as mesmas
/// coordenadas (E4).
public enum GuideKinematics {
    /// A figura no instante `t`, em 0…(n − 1) quadros; fora da faixa é limitado. Sem quadros, figura vazia.
    public static func skeleton(of guide: ExerciseGuide, at t: Double) -> GuideSkeleton {
        solve(guide, at: t).skeleton
    }

    // MARK: - Resultado interno (o validador também lê o alvo do IK e os comprimentos)

    struct Solution {
        var points: [GuideJoint: GuidePoint]
        var props: [String: GuidePoint]
        var isFront: Bool
        /// Comprimento aparente do braço e do antebraço até a pegada, com o escorço do instante.
        var upperArmLength: Double
        var reachLength: Double
        /// Alvo do IK dos braços (pegada ou acessório); `nil` com braços por ângulos.
        var ikTarget: GuidePoint?

        var skeleton: GuideSkeleton {
            GuideSkeleton(points: points, props: props, isFront: isFront)
        }
    }

    struct FramePair {
        let from: GuideFrame
        let to: GuideFrame
        /// Fração suavizada (`ease`) entre os dois quadros.
        let fraction: Double
    }

    /// Nomes de um lado do corpo: chaves da pose, pontos e segmentos da perna.
    struct Limb: Sendable {
        let thigh: GuidePose.Key
        let shin: GuidePose.Key
        let foot: GuidePose.Key
        let upperArm: GuidePose.Key
        let forearm: GuidePose.Key
        /// Ombro e quadril de cada lado na vista frontal.
        let shoulder: GuideJoint
        let hipJoint: GuideJoint
        let knee: GuideJoint
        let ankle: GuideJoint
        let toe: GuideJoint
        let heel: GuideJoint
        let elbow: GuideJoint
        let wrist: GuideJoint
        let hand: GuideJoint
        let fist: GuideJoint
        let thighSegment: GuideSegment
        let shinSegment: GuideSegment
        let footSegment: GuideSegment

        static let near = Limb(
            thigh: .thigh, shin: .shin, foot: .foot, upperArm: .upperArm, forearm: .forearm,
            shoulder: .shoulder, hipJoint: .hipJ, knee: .knee, ankle: .ankle, toe: .toe, heel: .heel,
            elbow: .elbow, wrist: .wrist, hand: .hand, fist: .fist,
            thighSegment: .thigh, shinSegment: .shin, footSegment: .foot
        )

        static let far = Limb(
            thigh: .thighFar, shin: .shinFar, foot: .footFar, upperArm: .upperArmFar, forearm: .forearmFar,
            shoulder: .shoulderFar, hipJoint: .hipJFar, knee: .kneeFar, ankle: .ankleFar, toe: .toeFar, heel: .heelFar,
            elbow: .elbowFar, wrist: .wristFar, hand: .handFar, fist: .fistFar,
            thighSegment: .thighFar, shinSegment: .shinFar, footSegment: .footFar
        )
    }

    // MARK: - Interpolação (E4)

    /// Pelo menor arco. `%` do script é o resto truncado (`truncatingRemainder`).
    static func lerpAngle(_ from: Double, _ to: Double, _ fraction: Double) -> Double {
        let delta = (to - from + 540).truncatingRemainder(dividingBy: 360) - 180
        return from + delta * fraction
    }

    /// easeInOut senoidal, com a entrada limitada a 0…1.
    static func ease(_ fraction: Double) -> Double {
        0.5 - 0.5 * cos(Double.pi * max(0, min(1, fraction)))
    }

    static func lerp(_ from: Double, _ to: Double, _ fraction: Double) -> Double {
        from + (to - from) * fraction
    }

    /// Ângulo relativo em (−180°, 180°] (E10).
    static func normalized(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value <= -180 {
            value += 360
        } else if value > 180 {
            value -= 360
        }
        return value
    }

    static func framePair(of guide: ExerciseGuide, at t: Double) -> FramePair? {
        let count = guide.frames.count
        guard count > 0 else {
            return nil
        }
        if count == 1 {
            return FramePair(from: guide.frames[0], to: guide.frames[0], fraction: 0)
        }
        let limited = max(0, min(Double(count - 1), t.isFinite ? t : 0))
        let index = max(0, min(Int(limited.rounded(.down)), count - 2))
        return FramePair(from: guide.frames[index], to: guide.frames[index + 1], fraction: ease(limited - Double(index)))
    }

    /// Ângulos do instante. Uma chave ausente num dos quadros vale a do outro; ausente nos dois, 0 no lado de cá e o
    /// lado de cá no lado de lá.
    static func interpolatedAngles(_ pair: FramePair) -> [GuidePose.Key: Double] {
        var angles: [GuidePose.Key: Double] = [:]
        for key in GuidePose.Key.allCases {
            let start = pair.from.pose[key]
            let end = pair.to.pose[key]
            if let start, let end {
                angles[key] = lerpAngle(start, end, pair.fraction)
            } else if let start {
                angles[key] = start
            } else if let end {
                angles[key] = end
            }
        }
        for key in GuidePose.Key.nearKeys where angles[key] == nil {
            angles[key] = 0
        }
        for key in GuidePose.Key.nearKeys {
            guard let far = key.far, angles[far] == nil else { continue }
            angles[far] = angles[key] ?? 0
        }
        return angles
    }

    static func depth(_ from: GuideDepth?, _ to: GuideDepth?, fallback: GuideDepth, fraction: Double) -> GuideDepth {
        let start = from ?? fallback
        let end = to ?? fallback
        return GuideDepth(upper: lerp(start.upper, end.upper, fraction), lower: lerp(start.lower, end.lower, fraction))
    }

    // MARK: - Solução

    static func solve(_ guide: ExerciseGuide, at t: Double) -> Solution {
        let isFront = guide.view == .front
        guard let pair = framePair(of: guide, at: t) else {
            return Solution(points: [:], props: [:], isFront: isFront, upperArmLength: 0, reachLength: 0, ikTarget: nil)
        }
        let angles = interpolatedAngles(pair)
        let legDepth = depth(pair.from.legDepth, pair.to.legDepth, fallback: .full, fraction: pair.fraction)
        var hip = GuidePoint.zero
        if guide.anchor.isNone {
            // (c) sem âncora: o quadril segue `root`, com a mesma fração suavizada dos ângulos, e não há translação
            hip = GuidePoint.lerp(pair.from.root ?? .zero, pair.to.root ?? .zero, pair.fraction)
        }
        if isFront {
            return solveFront(guide, angles: angles, hip: hip, legDepth: legDepth)
        }
        return solveSide(guide, pair: pair, angles: angles, hip: hip, legDepth: legDepth)
    }

    static func solveSide(
        _ guide: ExerciseGuide,
        pair: FramePair,
        angles: [GuidePose.Key: Double],
        hip: GuidePoint,
        legDepth: GuideDepth
    ) -> Solution {
        func angle(_ key: GuidePose.Key) -> Double {
            angles[key] ?? 0
        }
        var points: [GuideJoint: GuidePoint] = [:]
        let shoulder = hip + GuidePoint.direction(angle(.trunk)) * GuideRig.trunk
        points[.hip] = hip
        points[.shoulder] = shoulder
        points[.head] = shoulder + GuidePoint.direction(angle(.neck)) * GuideRig.neck
        for limb in [Limb.near, Limb.far] {
            // (a) legDepth encurta coxa e perna
            let knee = hip + GuidePoint.direction(angle(limb.thigh)) * (GuideRig.thigh * legDepth.upper)
            let ankle = knee + GuidePoint.direction(angle(limb.shin)) * (GuideRig.shin * legDepth.lower)
            let footAngle = angle(limb.foot)
            points[limb.knee] = knee
            points[limb.ankle] = ankle
            points[limb.toe] = ankle + GuidePoint.direction(footAngle) * GuideRig.foot
            points[limb.heel] = ankle + GuideRig.heelOffset.rotated(by: footAngle)
        }

        let arms = guide.arms
        let armDepth = depth(pair.from.armDepth, pair.to.armDepth, fallback: arms?.depth ?? .full, fraction: pair.fraction)
        let upperArmLength = GuideRig.upperArm * armDepth.upper
        let reachLength = GuideRig.reach * armDepth.lower
        let reachName = arms?.reach
        if reachName == nil {
            // (b) braços por ângulos: cinemática direta antes da âncora (a âncora pode estar na mão)
            for limb in [Limb.near, Limb.far] {
                let elbow = shoulder + GuidePoint.direction(angle(limb.upperArm)) * upperArmLength
                setForearm(&points, limb, elbow: elbow, direction: GuidePoint.direction(angle(limb.forearm)), depth: armDepth.lower)
            }
        }
        applyAnchor(guide.anchor, to: &points)

        var props: [String: GuidePoint] = [:]
        placeProps(guide, points: points, angles: angles, isFront: false, armPass: false, into: &props)
        var ikTarget: GuidePoint?
        if let arms, let reachName {
            let placedShoulder = points[.shoulder] ?? shoulder
            let target: GuidePoint
            if reachName == GuideArms.gripReach {
                let startGrip = pair.from.grip ?? placedShoulder
                let endGrip = pair.to.grip ?? placedShoulder
                target = GuidePoint.lerp(startGrip, endGrip, pair.fraction)
            } else {
                target = props[reachName] ?? placedShoulder
            }
            ikTarget = target
            let farFollowsPose = arms.farArm == .pose
            if let locked = arms.forearm {
                // antebraço com ângulo travado (supino: vertical sob a barra); o cotovelo fica sob a pegada
                let direction = GuidePoint.direction(locked)
                let elbow = target - direction * reachLength
                setForearm(&points, .near, elbow: elbow, direction: direction, depth: armDepth.lower)
                if !farFollowsPose {
                    setForearm(&points, .far, elbow: elbow, direction: direction, depth: armDepth.lower)
                }
            } else {
                let defaultHint = arms.elbow ?? GuideRig.defaultElbowHint
                let hint = lerpAngle(pair.from.elbow ?? defaultHint, pair.to.elbow ?? defaultHint, pair.fraction)
                let solved = solveTwoBone(shoulder: placedShoulder, target: target, upper: upperArmLength, lower: reachLength, hint: hint)
                let direction = (solved.end - solved.elbow).unit
                setForearm(&points, .near, elbow: solved.elbow, direction: direction, depth: armDepth.lower)
                if !farFollowsPose {
                    setForearm(&points, .far, elbow: solved.elbow, direction: direction, depth: armDepth.lower)
                }
            }
            if farFollowsPose {
                // (d) o braço de lá segue os ângulos do quadro, a partir do ombro, com o mesmo escorço
                let elbow = placedShoulder + GuidePoint.direction(angle(.upperArmFar)) * upperArmLength
                setForearm(&points, .far, elbow: elbow, direction: GuidePoint.direction(angle(.forearmFar)), depth: armDepth.lower)
            }
        }
        // (e) acessórios presos ao braço, depois dos braços
        placeProps(guide, points: points, angles: angles, isFront: false, armPass: true, into: &props)
        return Solution(
            points: points,
            props: props,
            isFront: false,
            upperArmLength: upperArmLength,
            reachLength: reachLength,
            ikTarget: ikTarget
        )
    }

    /// Vista frontal: mesmos nomes de ângulo, no plano frontal. O lado de cá é o direito da tela (0 = para fora); o
    /// de lá é espelhado (180 − a). Os braços são sempre por ângulos, sem escorço.
    static func solveFront(
        _ guide: ExerciseGuide,
        angles: [GuidePose.Key: Double],
        hip: GuidePoint,
        legDepth: GuideDepth
    ) -> Solution {
        func angle(_ key: GuidePose.Key) -> Double {
            angles[key] ?? 0
        }
        func mirrored(_ degrees: Double, _ sign: Double) -> Double {
            sign > 0 ? degrees : 180 - degrees
        }
        var points: [GuideJoint: GuidePoint] = [:]
        let up = GuidePoint.direction(angle(.trunk))
        let side = GuidePoint.direction(angle(.trunk) - 90)
        let neckBase = hip + up * GuideRig.trunk
        points[.hip] = hip
        points[.neckBase] = neckBase
        points[.head] = neckBase + GuidePoint.direction(angle(.neck)) * GuideRig.neck
        let limbs: [(limb: Limb, sign: Double)] = [(limb: Limb.near, sign: 1), (limb: Limb.far, sign: -1)]
        for entry in limbs {
            let limb = entry.limb
            let sign = entry.sign
            let shoulderOut = neckBase + side * (GuideRig.frontShoulderHalfWidth * sign)
            let shoulderPoint = shoulderOut - up * GuideRig.frontShoulderDrop
            let hipJoint = hip + side * (GuideRig.frontHipHalfWidth * sign)
            points[limb.shoulder] = shoulderPoint
            points[limb.hipJoint] = hipJoint
            let elbow = shoulderPoint + GuidePoint.direction(mirrored(angle(limb.upperArm), sign)) * GuideRig.upperArm
            setForearm(&points, limb, elbow: elbow, direction: GuidePoint.direction(mirrored(angle(limb.forearm), sign)), depth: 1)
            let knee = hipJoint + GuidePoint.direction(mirrored(angle(limb.thigh), sign)) * (GuideRig.thigh * legDepth.upper)
            let ankle = knee + GuidePoint.direction(mirrored(angle(limb.shin), sign)) * (GuideRig.shin * legDepth.lower)
            points[limb.knee] = knee
            points[limb.ankle] = ankle
            points[limb.toe] = ankle + GuidePoint(x: GuideRig.frontToeOffset.x * sign, y: GuideRig.frontToeOffset.y)
        }
        applyAnchor(guide.anchor, to: &points)
        var props: [String: GuidePoint] = [:]
        placeProps(guide, points: points, angles: angles, isFront: true, armPass: false, into: &props)
        placeProps(guide, points: points, angles: angles, isFront: true, armPass: true, into: &props)
        return Solution(
            points: points,
            props: props,
            isFront: true,
            upperArmLength: GuideRig.upperArm,
            reachLength: GuideRig.reach,
            ikTarget: nil
        )
    }

    // MARK: - Peças

    /// Antebraço e mão a partir do cotovelo numa direção: punho, pegada (meio da palma) e ponta da mão fechada.
    static func setForearm(
        _ points: inout [GuideJoint: GuidePoint],
        _ limb: Limb,
        elbow: GuidePoint,
        direction: GuidePoint,
        depth: Double
    ) {
        let wristLength: Double = GuideRig.forearm * depth
        let handLength: Double = (GuideRig.forearm + GuideRig.gripAt * GuideRig.hand) * depth
        let fistLength: Double = (GuideRig.forearm + GuideRig.fistAt * GuideRig.hand) * depth
        points[limb.elbow] = elbow
        points[limb.wrist] = elbow + direction * wristLength
        points[limb.hand] = elbow + direction * handLength
        points[limb.fist] = elbow + direction * fistLength
    }

    /// Dois ossos (lei dos cossenos): ombro, alvo, comprimentos e dica (graus) para o lado do cotovelo. Fora do
    /// alcance, o braço estende na direção do alvo; nunca produz NaN (E6).
    static func solveTwoBone(
        shoulder: GuidePoint,
        target: GuidePoint,
        upper: Double,
        lower: Double,
        hint: Double
    ) -> (elbow: GuidePoint, end: GuidePoint) {
        let delta = target - shoulder
        let distance = max(abs(upper - lower) + 1e-4, min(upper + lower - 1e-4, delta.length))
        let direction = delta.unit
        let end = shoulder + direction * distance
        let along = (upper * upper - lower * lower + distance * distance) / (2 * distance)
        let height = max(0, upper * upper - along * along).squareRoot()
        var normal = direction.perpendicular
        if normal.dot(GuidePoint.direction(hint)) < 0 {
            normal = normal * -1
        }
        let onLine = shoulder + direction * along
        let elbow = onLine + normal * height
        return (elbow: elbow, end: end)
    }

    /// Translada o corpo para a âncora ficar em `at` (E5). Sem âncora, ou com o ponto ainda não calculado, não mexe.
    static func applyAnchor(_ anchor: GuideAnchor, to points: inout [GuideJoint: GuidePoint]) {
        guard let joint = anchor.point, let at = anchor.at, let current = points[joint] else {
            return
        }
        let offset = at - current
        points = points.mapValues { $0 + offset }
    }

    /// `true` quando o acessório depende dos braços (ponto ou segmento do braço).
    static func isArmAttach(_ attach: String) -> Bool {
        if let joint = GuideJoint(rawValue: attach) {
            return joint.isArmPoint
        }
        if let segment = GuideSegment(rawValue: attach) {
            return segment.isArm
        }
        return false
    }

    /// Acessórios de uma passada: os do braço (`armPass`) ou os do resto do corpo. Na vista frontal, um acessório na
    /// mão aparece nas duas, com o `offset` espelhado no lado de lá.
    static func placeProps(
        _ guide: ExerciseGuide,
        points: [GuideJoint: GuidePoint],
        angles: [GuidePose.Key: Double],
        isFront: Bool,
        armPass: Bool,
        into props: inout [String: GuidePoint]
    ) {
        for prop in guide.props where !prop.kind.isLine {
            guard let attach = prop.attach, isArmAttach(attach) == armPass else { continue }
            let offset = prop.offset ?? .zero
            if isFront && attach == GuideJoint.hand.rawValue {
                if let hand = points[.hand] {
                    props[prop.id] = hand + offset
                }
                if let handFar = points[.handFar] {
                    props[prop.id + "Far"] = handFar + GuidePoint(x: -offset.x, y: offset.y)
                }
                continue
            }
            if let point = attachPoint(attach, of: prop, offset: offset, points: points, angles: angles, isFront: isFront) {
                props[prop.id] = point
            }
        }
    }

    static func attachPoint(
        _ attach: String,
        of prop: GuideProp,
        offset: GuidePoint,
        points: [GuideJoint: GuidePoint],
        angles: [GuidePose.Key: Double],
        isFront: Bool
    ) -> GuidePoint? {
        if attach == GuideProp.backAttach || attach == GuideProp.chestAttach {
            // referencial do tronco a partir do topo do tronco: ombro de lado, base do pescoço de frente
            guard let top = points[isFront ? GuideJoint.neckBase : GuideJoint.shoulder] else {
                return nil
            }
            let trunk = angles[.trunk] ?? 0
            let up = GuidePoint.direction(trunk)
            let forward = GuidePoint.direction(trunk - 90)
            let alongForward = top + forward * offset.x
            return alongForward + up * offset.y
        }
        if let joint = GuideJoint(rawValue: attach) {
            guard let point = points[joint] else {
                return nil
            }
            return point + offset
        }
        if let segment = GuideSegment(rawValue: attach), segment.isAttachable {
            let names = segment.endpoints(in: isFront ? ExerciseGuide.Viewpoint.front : ExerciseGuide.Viewpoint.side)
            guard let start = points[names.proximal], let end = points[names.distal] else {
                return nil
            }
            let delta = end - start
            let normal = delta.unit.perpendicular
            let alongSegment = start + delta * (prop.along ?? 0)
            return alongSegment + normal * (prop.side ?? 0)
        }
        return nil
    }
}
