import Foundation

/// O que se move e a seta (SPEC E9; docs/V23-CORE-CONTRACT.md §2.5). Porta de `Get-Moving` e `Get-CuePath` de
/// docs/design/exercise-guides/render-exercise-guides.ps1.
public enum GuideMotion {
    /// Segmentos em acento forte. Com `moving`, é a lista dada (uma chave do lado de cá vale também para o de lá).
    /// Sem ela, um segmento se move quando gira pelo menos 12° ou o meio dele anda pelo menos 0,04 H entre o
    /// primeiro e o último quadro, E a articulação com o pai muda pelo menos 12° (ou ele só acompanha, rígido, um
    /// pai que se move no mesmo membro). Assim os braços que só seguram a barra no agachamento ficam suaves.
    public static func movingSegments(of guide: ExerciseGuide) -> Set<GuideSegment> {
        if let names = guide.moving {
            var chosen = Set<GuideSegment>()
            for name in names {
                guard let segment = GuideSegment(rawValue: name) else { continue }
                chosen.insert(segment)
                if let far = segment.farCounterpart {
                    chosen.insert(far)
                }
            }
            return chosen
        }
        let last = Double(max(0, guide.frames.count - 1))
        let first = GuideKinematics.skeleton(of: guide, at: 0)
        let final = GuideKinematics.skeleton(of: guide, at: last)
        let order: [GuideSegment] = [.trunk, .head, .thigh, .shin, .foot, .upperArm, .forearm]
        var moving = Set<GuideSegment>()
        for isFar in [false, true] {
            for base in order {
                let isCentral = base == .trunk || base == .head
                if isCentral && isFar {
                    continue
                }
                let segment = isFar ? (base.farCounterpart ?? base) : base
                guard let startAngle = first.angle(of: segment),
                      let endAngle = final.angle(of: segment),
                      let startMid = first.midpoint(of: segment),
                      let endMid = final.midpoint(of: segment) else {
                    continue
                }
                let turn = angleDifference(startAngle, endAngle)
                let shift = startMid.distance(to: endMid)
                var jointChange = turn
                let parent = segment.parent
                if let parent, let parentStart = first.angle(of: parent), let parentEnd = final.angle(of: parent) {
                    jointChange = angleDifference(startAngle - parentStart, endAngle - parentEnd)
                }
                let follows = segment.isRigid && parent.map { moving.contains($0) } == true
                let travels = turn >= GuideRig.movingAngle || shift >= GuideRig.movingShift
                if travels && (jointChange >= GuideRig.movingAngle || follows) {
                    moving.insert(segment)
                }
            }
        }
        return moving
    }

    /// Caminho da seta: a trajetória de `cue.track` em 80 passos do primeiro ao último quadro, reamostrada por
    /// comprimento de arco em 41 pontos, recortada em `span` e afastada por `gap` para o lado e por `offset`.
    /// Vazio sem `cue`.
    public static func cuePath(of guide: ExerciseGuide) -> [GuidePoint] {
        guard let cue = guide.cue, !guide.frames.isEmpty else {
            return []
        }
        let last = Double(guide.frames.count - 1)
        let steps = 80
        var raw: [GuidePoint] = []
        raw.reserveCapacity(steps + 1)
        for step in 0...steps {
            let skeleton = GuideKinematics.skeleton(of: guide, at: last * Double(step) / Double(steps))
            raw.append(trackPoint(cue.track, in: skeleton))
        }
        var cumulative: [Double] = [0]
        for step in 1...steps {
            cumulative.append(cumulative[step - 1] + raw[step].distance(to: raw[step - 1]))
        }
        let total = cumulative[steps]
        var spanStart = 0.0
        var spanEnd = 1.0
        if let span = cue.span, span.count == 2 {
            spanStart = span[0]
            spanEnd = span[1]
        }
        let samples = 40
        var resampled: [GuidePoint] = []
        var index = 1
        for sample in 0...samples {
            let target = total * (spanStart + (spanEnd - spanStart) * Double(sample) / Double(samples))
            while index < steps && cumulative[index] < target {
                index += 1
            }
            let piece = max(1e-9, cumulative[index] - cumulative[index - 1])
            let fraction = max(0, min(1, (target - cumulative[index - 1]) / piece))
            resampled.append(GuidePoint.lerp(raw[index - 1], raw[index], fraction))
        }
        var path: [GuidePoint] = []
        path.reserveCapacity(samples + 1)
        for sample in 0...samples {
            var point = resampled[sample]
            if let side = cue.side {
                let tangent = (resampled[min(samples, sample + 2)] - resampled[max(0, sample - 2)]).unit
                // à direita de quem anda pelo caminho; `left` inverte
                var normal = GuidePoint(x: tangent.y, y: -tangent.x)
                if side == .left {
                    normal = normal * -1
                }
                point = point + normal * (cue.gap ?? 0)
            }
            if let offset = cue.offset {
                point = point + offset
            }
            path.append(point)
        }
        return path
    }

    /// Ponto do esqueleto (se o nome for um) ou acessório; sem nenhum, a origem.
    static func trackPoint(_ track: String, in skeleton: GuideSkeleton) -> GuidePoint {
        if let joint = GuideJoint(rawValue: track), let point = skeleton.points[joint] {
            return point
        }
        return skeleton.props[track] ?? .zero
    }

    /// Diferença absoluta entre dois ângulos, pelo menor arco (`AngDiff` do script).
    static func angleDifference(_ from: Double, _ to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 {
            delta -= 360
        } else if delta < -180 {
            delta += 360
        }
        return abs(delta)
    }
}
