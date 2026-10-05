import Foundation
import SwiftUI
import TrainerCore

/// Pinta um instante da figura do "Como fazer" numa `GraphicsContext` (SPEC RF-40, §7.12 E9; DESIGN §12). É o
/// `Draw-Frame` da folha de revisão (`docs/design/exercise-guides/render-exercise-guides.ps1`) com as mesmas
/// espessuras, raios, camadas e cores, para o app desenhar o que o dono aprovou nas folhas.
///
/// Só desenha: a pose vem de `GuideKinematics`, o que se move de `GuideMotion`, a seta de `GuideMotion.cuePath`.
/// Os tamanhos são frações da estatura (`GuideRig`), convertidos pela `GuideCamera`.
struct GuidePainter {
    let figure: GuideFigure
    let ink: GuideInk
    let camera: GuideCamera

    /// Contorno na cor do fundo que separa segmentos sobrepostos (`$GapW`).
    static let gapWidth = 0.011
    /// Deslocamento do lado de lá na vista lateral (a câmera fica um pouco acima e à frente).
    static let farShift = GuideRig.farShift
    /// Só entra no fantasma o que mudou de lugar mais que 0,02 H (`$GhostTol`).
    static let ghostTolerance = 0.02

    private typealias Radius = GuideRig.Radius

    /// Um quadro inteiro, na ordem de camadas da folha. `ghostOpacity` > 0 desenha a posição inicial em fantasma
    /// (só em `loop`); `cueOpacity` > 0 desenha a seta do caminho da ida.
    func draw(in context: GraphicsContext, rect: CGRect, at t: Double, ghostOpacity: Double, cueOpacity: Double) {
        let skeleton = GuideKinematics.skeleton(of: figure.guide, at: t)
        drawFloor(in: context, rect: rect)
        drawScene(in: context, layer: .back)
        if ghostOpacity > 0.001 {
            var ghostContext = context
            ghostContext.opacity = min(1, ghostOpacity)
            drawGhost(in: ghostContext, from: figure.start, now: skeleton)
        }
        let tones = self.tones(front: skeleton.isFront)
        if skeleton.isFront {
            drawScene(in: context, layer: .mid)
            drawLines(in: context, skeleton: skeleton)
            drawHeldProps(in: context, skeleton: skeleton, layer: .mid)
            drawHeldProps(in: context, skeleton: skeleton, layer: .behindTrunk)
            drawFrontBody(in: context, skeleton: skeleton, tones: tones)
            drawHeldProps(in: context, skeleton: skeleton, layer: .front)
        } else {
            let shift = GuidePainter.farShift
            drawArm(in: context, skeleton: skeleton, far: true, tones: tones, gap: nil, shift: shift, shoulder: .shoulder)
            drawLeg(in: context, skeleton: skeleton, far: true, tones: tones, gap: nil, shift: shift)
            drawHeldProps(in: context, skeleton: skeleton, layer: .far)
            drawScene(in: context, layer: .mid)
            drawLines(in: context, skeleton: skeleton)
            drawHeldProps(in: context, skeleton: skeleton, layer: .mid)
            drawHeldProps(in: context, skeleton: skeleton, layer: .behindTrunk)
            drawTrunkHead(in: context, skeleton: skeleton, tones: tones, gap: ink.background)
            drawLeg(in: context, skeleton: skeleton, far: false, tones: tones, gap: ink.background, shift: .zero)
            drawHeldProps(in: context, skeleton: skeleton, layer: .beforeNearArm)
            drawArm(in: context, skeleton: skeleton, far: false, tones: tones, gap: ink.background, shift: .zero, shoulder: .shoulder)
            drawHeldProps(in: context, skeleton: skeleton, layer: .front)
        }
        drawScene(in: context, layer: .front)
        if cueOpacity > 0.001, figure.cue.count >= 2 {
            var cueContext = context
            cueContext.opacity = min(1, cueOpacity)
            drawArrow(in: cueContext, points: figure.cue.map { camera.point($0) }, color: ink.arrow)
        }
    }

    // MARK: - Tons (`Get-Tones`)

    /// Tom de cada segmento: o que se move em acento forte, o resto suave; o lado de lá mais claro na vista lateral.
    /// Na vista frontal não há lado de lá: os dois lados usam os tons de cá.
    private func tones(front: Bool) -> [GuideSegment: GuideInk.RGB] {
        var tones: [GuideSegment: GuideInk.RGB] = [:]
        let near: [GuideSegment] = [.trunk, .head, .upperArm, .forearm, .thigh, .shin, .foot]
        for segment in near {
            tones[segment] = figure.moving.contains(segment) ? ink.nearMove : ink.nearStill
            guard let far = segment.farCounterpart else {
                continue
            }
            if front {
                tones[far] = figure.moving.contains(far) ? ink.nearMove : ink.nearStill
            } else {
                tones[far] = figure.moving.contains(far) ? ink.farMove : ink.farStill
            }
        }
        return tones
    }

    private func tone(_ tones: [GuideSegment: GuideInk.RGB], _ segment: GuideSegment) -> GuideInk.RGB {
        tones[segment] ?? ink.nearStill
    }

    // MARK: - Chão e cena

    private func drawFloor(in context: GraphicsContext, rect: CGRect) {
        let y = camera.point(.zero).y
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 0.05 * rect.width, y: y))
        path.addLine(to: CGPoint(x: rect.maxX - 0.05 * rect.width, y: y))
        context.stroke(path, with: .color(ink.floor.color), style: StrokeStyle(lineWidth: camera.length(0.007), lineCap: .round))
    }

    private func drawScene(in context: GraphicsContext, layer: GuideSceneItem.Layer) {
        for item in figure.guide.scene where item.resolvedLayer == layer {
            drawSceneItem(item, in: context)
        }
    }

    /// `Draw-SceneItem`: a estrutura fixa, mais clara que o equipamento que se move.
    private func drawSceneItem(_ item: GuideSceneItem, in context: GraphicsContext) {
        var solid = ink.structure
        var soft = ink.structureSoft
        if item.resolvedTone == .soft {
            solid = ink.structureSoft
            soft = GuideInk.mix(ink.structureSoft, ink.background, 0.45)
        }
        switch item.kind {
        case .bench:
            guard let x = item.x, let top = item.top, let length = item.length else { return }
            let thickness = 0.042
            for legX in [x + 0.10, x + length - 0.10] {
                fillRect(context, soft, x: legX - 0.014, y: 0, width: 0.028, height: top - thickness, radius: 0.004)
                fillRect(context, soft, x: legX - 0.075, y: 0, width: 0.15, height: 0.018, radius: 0.009)
            }
            fillRect(context, solid, x: x, y: top - thickness, width: length, height: thickness, radius: 0.016)
        case .seat:
            guard let x = item.x, let top = item.top, let length = item.length else { return }
            let thickness = 0.042
            let middle = x + length / 2
            fillRect(context, soft, x: middle - 0.016, y: 0.03, width: 0.032, height: top - thickness - 0.03, radius: 0.004)
            fillRect(context, solid, x: x, y: top - thickness, width: length, height: thickness, radius: 0.016)
        case .rail:
            guard let x1 = item.x1, let x2 = item.x2 else { return }
            fillRect(context, soft, x: x1, y: 0, width: x2 - x1, height: 0.036, radius: 0.012)
        case .tower:
            guard let x = item.x, let width = item.width, let height = item.height else { return }
            fillRect(context, soft, x: x, y: 0, width: width, height: height, radius: 0.02)
            let inner = GuideInk.mix(soft, ink.background, 0.55)
            fillRect(context, inner, x: x + 0.022, y: 0.05, width: width - 0.044, height: height - 0.10, radius: 0.012)
            for plate in 0..<7 {
                fillRect(context, solid, x: x + 0.034, y: 0.065 + Double(plate) * 0.046, width: width - 0.068, height: 0.036, radius: 0.008)
            }
            fillCircle(context, solid, center: GuidePoint(x: x + width / 2, y: height - 0.045), radius: 0.02)
        case .footPlate:
            guard let at = item.at, let angle = item.angle, let length = item.length else { return }
            fillBar(context, solid, center: at, angle: angle, length: length, thickness: 0.036)
        case .pulley:
            guard let at = item.at else { return }
            fillCircle(context, solid, center: at, radius: 0.028)
            fillCircle(context, ink.equipment, center: at, radius: 0.010)
        case .block:
            guard let x = item.x, let y = item.y, let width = item.width, let height = item.height else { return }
            fillRect(context, solid, x: x, y: y, width: width, height: height, radius: 0.014)
        case .pad:
            guard let at = item.at, let angle = item.angle, let length = item.length else { return }
            fillBar(context, solid, center: at, angle: angle, length: length, thickness: item.thick ?? GuideRig.padThickness)
        case .post:
            guard let from = item.from, let to = item.to else { return }
            let thickness = item.thick ?? GuideRig.postThickness
            let delta = to - from
            let angle = atan2(delta.y, delta.x) * 180 / Double.pi
            fillBar(context, soft, center: GuidePoint.lerp(from, to, 0.5), angle: angle, length: delta.length + thickness, thickness: thickness)
        case .wheel:
            guard let at = item.at, let radius = item.radius else { return }
            if radius <= 0.03 {
                fillCircle(context, solid, center: at, radius: radius)
            } else {
                strokeCircle(context, solid, center: at, radius: radius - 0.007, width: 0.014)
                fillCircle(context, solid, center: at, radius: 0.014)
            }
        case .steps:
            guard let x = item.x, let count = item.count, let rise = item.rise, let run = item.run, count > 0 else { return }
            var path = Path()
            path.move(to: camera.point(GuidePoint(x: x, y: 0)))
            for step in 0..<count {
                path.addLine(to: camera.point(GuidePoint(x: x + Double(step) * run, y: Double(step + 1) * rise)))
                path.addLine(to: camera.point(GuidePoint(x: x + Double(step + 1) * run, y: Double(step + 1) * rise)))
            }
            path.addLine(to: camera.point(GuidePoint(x: x + Double(count) * run, y: 0)))
            path.closeSubpath()
            context.fill(path, with: .color(solid.color))
        }
    }

    // MARK: - Corpo (vista lateral)

    private func drawLeg(
        in context: GraphicsContext,
        skeleton: GuideSkeleton,
        far: Bool,
        tones: [GuideSegment: GuideInk.RGB],
        gap: GuideInk.RGB?,
        shift: GuidePoint
    ) {
        let heel: GuideJoint = far ? .heelFar : .heel
        let toe: GuideJoint = far ? .toeFar : .toe
        let ankle: GuideJoint = far ? .ankleFar : .ankle
        let knee: GuideJoint = far ? .kneeFar : .knee
        let foot = tone(tones, far ? .footFar : .foot)
        limb(context, skeleton, foot, gap: gap, heel, Radius.heel, toe, Radius.toe, shift: shift)
        limb(context, skeleton, foot, gap: nil, ankle, Radius.ankle, heel, Radius.heel, shift: shift)
        limb(context, skeleton, tone(tones, far ? .shinFar : .shin), gap: gap, knee, Radius.kneeLow, ankle, Radius.ankle, shift: shift)
        limb(context, skeleton, tone(tones, far ? .thighFar : .thigh), gap: gap, .hip, Radius.thighTop, knee, Radius.knee, shift: shift)
    }

    private func drawArm(
        in context: GraphicsContext,
        skeleton: GuideSkeleton,
        far: Bool,
        tones: [GuideSegment: GuideInk.RGB],
        gap: GuideInk.RGB?,
        shift: GuidePoint,
        shoulder: GuideJoint
    ) {
        let elbow: GuideJoint = far ? .elbowFar : .elbow
        let wrist: GuideJoint = far ? .wristFar : .wrist
        let fist: GuideJoint = far ? .fistFar : .fist
        let forearm = tone(tones, far ? .forearmFar : .forearm)
        limb(context, skeleton, tone(tones, far ? .upperArmFar : .upperArm), gap: gap, shoulder, Radius.shoulder, elbow, Radius.elbow, shift: shift)
        limb(context, skeleton, forearm, gap: gap, elbow, Radius.elbowLow, wrist, Radius.wrist, shift: shift)
        limb(context, skeleton, forearm, gap: nil, wrist, Radius.wrist, fist, Radius.hand, shift: shift)
    }

    /// `Draw-TrunkHead`: tronco, pescoço, cabeça e um nariz discreto que diz para onde a pessoa olha, sem rosto.
    private func drawTrunkHead(
        in context: GraphicsContext,
        skeleton: GuideSkeleton,
        tones: [GuideSegment: GuideInk.RGB],
        gap: GuideInk.RGB?
    ) {
        guard let hip = skeleton.points[.hip], let shoulder = skeleton.points[.shoulder], let head = skeleton.points[.head] else {
            return
        }
        let trunkAngle = skeleton.angle(of: .trunk) ?? 90
        let neckAngle = skeleton.angle(of: .head) ?? 90
        let up = GuidePoint.direction(trunkAngle)
        let trunk = tone(tones, .trunk)
        let headTone = tone(tones, .head)
        hull(context, trunk, gap: gap, hip, Radius.hip, shoulder - up * 0.012, Radius.chest)
        hull(context, headTone, gap: nil, shoulder, Radius.neck, head, Radius.neck)
        hull(context, headTone, gap: gap, head, Radius.head, head, Radius.head)
        let face = GuidePoint.direction(neckAngle - 90)
        let noseStart = head + face * 0.047
        let noseEnd = head + face * 0.061 + GuidePoint.direction(neckAngle) * -0.004
        hull(context, headTone, gap: nil, noseStart, 0.017, noseEnd, 0.011)
    }

    // MARK: - Corpo (vista frontal)

    private func drawFrontBody(in context: GraphicsContext, skeleton: GuideSkeleton, tones: [GuideSegment: GuideInk.RGB]) {
        let gap = ink.background
        for far in [true, false] {
            let ankle: GuideJoint = far ? .ankleFar : .ankle
            let toe: GuideJoint = far ? .toeFar : .toe
            let knee: GuideJoint = far ? .kneeFar : .knee
            let hipJoint: GuideJoint = far ? .hipJFar : .hipJ
            limb(context, skeleton, tone(tones, far ? .footFar : .foot), gap: nil, ankle, Radius.ankle, toe, 0.018, shift: .zero)
            limb(context, skeleton, tone(tones, far ? .shinFar : .shin), gap: gap, knee, Radius.kneeLow, ankle, Radius.ankle, shift: .zero)
            limb(context, skeleton, tone(tones, far ? .thighFar : .thigh), gap: gap, hipJoint, Radius.thighTop, knee, Radius.knee, shift: .zero)
        }
        if let torso = frontTorsoPoints(skeleton) {
            drawTorso(context, points: torso, color: tone(tones, .trunk), gap: gap)
        }
        let headTone = tone(tones, .head)
        limb(context, skeleton, headTone, gap: nil, .neckBase, Radius.neck, .head, Radius.neck, shift: .zero)
        limb(context, skeleton, headTone, gap: gap, .head, Radius.head, .head, Radius.head, shift: .zero)
        drawArm(in: context, skeleton: skeleton, far: true, tones: tones, gap: gap, shift: .zero, shoulder: .shoulderFar)
        drawArm(in: context, skeleton: skeleton, far: false, tones: tones, gap: gap, shift: .zero, shoulder: .shoulder)
    }

    /// `Get-FrontTorsoPts`: o tronco de frente, um hexágono de cantos redondos.
    private func frontTorsoPoints(_ skeleton: GuideSkeleton) -> [GuidePoint]? {
        guard let hip = skeleton.points[.hip], let neckBase = skeleton.points[.neckBase] else {
            return nil
        }
        let trunkAngle = skeleton.angle(of: .trunk) ?? 90
        let up = GuidePoint.direction(trunkAngle)
        let right = GuidePoint.direction(trunkAngle - 90)
        return [
            neckBase + right * 0.118 - up * 0.01,
            hip + up * 0.13 + right * 0.088,
            hip + right * 0.100 - up * 0.02,
            hip - right * 0.100 - up * 0.02,
            hip + up * 0.13 - right * 0.088,
            neckBase - right * 0.118 - up * 0.01,
        ]
    }

    private func drawTorso(_ context: GraphicsContext, points: [GuidePoint], color: GuideInk.RGB, gap: GuideInk.RGB?) {
        let path = polygon(points)
        let round = camera.length(0.05)
        if let gap {
            let width = round + 2 * camera.length(GuidePainter.gapWidth)
            context.stroke(path, with: .color(gap.color), style: StrokeStyle(lineWidth: width, lineJoin: .round))
        }
        context.stroke(path, with: .color(color.color), style: StrokeStyle(lineWidth: round, lineJoin: .round))
        context.fill(path, with: .color(color.color))
    }

    // MARK: - Acessórios (movem-se com o corpo)

    /// Camada de desenho de um acessório (`Get-PropLayer`).
    private enum PropLayer {
        case far
        case mid
        case behindTrunk
        case beforeNearArm
        case front
    }

    private func propLayer(_ prop: GuideProp, front: Bool) -> PropLayer {
        if prop.kind == .jumpRope {
            return .mid
        }
        if prop.attach == GuideProp.backAttach {
            return .behindTrunk
        }
        if front {
            return .front
        }
        if prop.attach == GuideProp.chestAttach || prop.kind == .vHandle || prop.kind == .rope {
            return .beforeNearArm
        }
        if let attach = prop.attach, attach.hasSuffix("Far") {
            return .far
        }
        return .front
    }

    private func drawHeldProps(in context: GraphicsContext, skeleton: GuideSkeleton, layer: PropLayer) {
        for prop in figure.guide.props {
            guard !prop.kind.isLine, prop.attach != nil, propLayer(prop, front: skeleton.isFront) == layer else {
                continue
            }
            let shift = layer == .far ? GuidePainter.farShift : GuidePoint.zero
            if prop.kind == .jumpRope {
                drawJumpRope(in: context, skeleton: skeleton, color: ink.equipment, shift: shift)
                continue
            }
            for key in [prop.id, prop.id + "Far"] {
                guard let center = skeleton.props[key] else {
                    continue
                }
                drawProp(prop, at: center + shift, in: context, color: ink.equipment, ghost: false)
            }
        }
    }

    /// `Draw-Prop`: o desenho de cada tipo de acessório. `ghost` desenha só o contorno (posição inicial).
    private func drawProp(_ prop: GuideProp, at center: GuidePoint, in context: GraphicsContext, color: GuideInk.RGB, ghost: Bool) {
        switch prop.kind {
        case .barbell:
            drawPlate(context, center: center, color: color, veil: !ghost && prop.attach != GuideProp.backAttach)
        case .dumbbell:
            if !ghost {
                fillCircle(context, ink.background, opacity: 80.0 / 255, center: center, radius: 0.041)
            }
            strokeCircle(context, color, center: center, radius: 0.034, width: 0.013)
            fillCircle(context, color, center: center, radius: 0.012)
        case .kettlebell:
            let body = center + GuidePoint(x: 0, y: -0.068)
            strokeCircle(context, color, center: center + GuidePoint(x: 0, y: -0.012), radius: 0.024, width: 0.011)
            if ghost {
                strokeCircle(context, color, center: body, radius: 0.045, width: 0.01)
            } else {
                fillCircle(context, color, center: body, radius: 0.046)
            }
        case .ball:
            if !ghost {
                fillCircle(context, ink.background, opacity: 90.0 / 255, center: center, radius: 0.07)
            }
            strokeCircle(context, color, center: center, radius: 0.064, width: 0.012)
            strokeLine(context, color, from: center + GuidePoint(x: -0.058, y: 0.012), to: center + GuidePoint(x: 0.058, y: 0.012), width: 0.008)
        case .vHandle:
            drawVHandle(context, prop: prop, center: center, color: color)
        case .bar:
            if ghost {
                strokeCircle(context, color, center: center, radius: 0.018, width: 0.01)
            } else {
                fillCircle(context, color, center: center, radius: 0.021)
            }
        case .rope:
            drawRopeHandle(context, prop: prop, center: center, color: color)
        case .plate:
            let angle = prop.angle ?? 0
            let length = prop.length ?? 0.1
            if ghost {
                strokeBar(context, color, center: center, angle: angle, length: length, thickness: 0.03, width: 0.008)
            } else {
                fillBar(context, color, center: center, angle: angle, length: length, thickness: 0.03)
            }
        case .roller:
            let radius = prop.radius ?? GuideRig.Radius.roller
            if !ghost {
                fillCircle(context, GuideInk.mix(color, ink.background, 0.55), center: center, radius: radius)
            }
            strokeCircle(context, color, center: center, radius: radius - 0.005, width: 0.01)
        case .jumpRope, .cable, .band:
            break
        }
    }

    /// A anilha vista de frente: aro, miolo e um véu translúcido para o corpo continuar legível atrás dela.
    private func drawPlate(_ context: GraphicsContext, center: GuidePoint, color: GuideInk.RGB, veil: Bool) {
        if veil {
            fillCircle(context, ink.background, opacity: 80.0 / 255, center: center, radius: Radius.plate)
        }
        strokeCircle(context, color, center: center, radius: Radius.plate - 0.007, width: 0.014)
        fillCircle(context, color, center: center, radius: 0.017)
    }

    /// Origem do cabo ou elástico que termina neste acessório (`Get-LineSource`), para orientar puxador e corda.
    private func lineSource(toPropID id: String) -> GuidePoint? {
        for prop in figure.guide.props where prop.kind.isLine && prop.to == id {
            if let from = prop.from, let source = sceneReference(from) {
                return source
            }
        }
        return nil
    }

    private func sceneReference(_ id: String) -> GuidePoint? {
        figure.guide.scene.first { $0.id == id }?.referencePoint
    }

    private func drawVHandle(_ context: GraphicsContext, prop: GuideProp, center: GuidePoint, color: GuideInk.RGB) {
        let direction = lineSource(toPropID: prop.id).map { ($0 - center).unit } ?? GuidePoint(x: 1, y: 0)
        let apex = center + direction * 0.06
        let normal = direction.perpendicular
        let top = center + normal * 0.044
        let bottom = center - normal * 0.044
        strokeLine(context, color, from: top, to: apex, width: 0.013)
        strokeLine(context, color, from: bottom, to: apex, width: 0.013)
        strokeLine(context, color, from: top, to: bottom, width: 0.022)
    }

    private func drawRopeHandle(_ context: GraphicsContext, prop: GuideProp, center: GuidePoint, color: GuideInk.RGB) {
        let direction = lineSource(toPropID: prop.id).map { ($0 - center).unit } ?? GuidePoint(x: 0, y: 1)
        let apex = center + direction * 0.06
        let normal = direction.perpendicular
        for side in [1.0, -1.0] {
            let end = center + normal * (0.02 * side) - direction * 0.018
            strokeLine(context, color, from: apex, to: end, width: 0.011)
            fillCircle(context, color, center: end, radius: 0.012)
        }
    }

    /// `Draw-Lines`: cabos e elásticos, de um item da cena até um acessório ou ponto do esqueleto.
    private func drawLines(in context: GraphicsContext, skeleton: GuideSkeleton) {
        for prop in figure.guide.props where prop.kind.isLine {
            guard let fromID = prop.from, let toID = prop.to, let from = sceneReference(fromID) else {
                continue
            }
            var target: GuidePoint
            if let point = skeleton.props[toID] {
                target = point
            } else if let joint = GuideJoint(rawValue: toID), let point = skeleton.points[joint] {
                target = point
            } else {
                continue
            }
            if let held = figure.guide.props.first(where: { $0.id == toID }), held.kind == .vHandle || held.kind == .rope {
                target = target + (from - target).unit * 0.06
            }
            let width = prop.kind == .band ? 0.02 : 0.0075
            strokeLine(context, ink.equipment, from: from, to: target, width: width)
        }
    }

    /// `Draw-JumpRope`: a corda passa por baixo dos pés; de frente é um U de uma mão à outra, de lado um fio da mão
    /// até embaixo dos pés.
    private func drawJumpRope(in context: GraphicsContext, skeleton: GuideSkeleton, color: GuideInk.RGB, shift: GuidePoint) {
        guard let hand = skeleton.points[.hand] else {
            return
        }
        let feetJoints: [GuideJoint] = [.toe, .toeFar, .heel, .heelFar, .ankle, .ankleFar]
        let feet = feetJoints.compactMap { skeleton.points[$0] }
        guard !feet.isEmpty else {
            return
        }
        let low = (feet.map(\.y).min() ?? 0) - 0.022
        let centerX = feet.map(\.x).reduce(0, +) / Double(feet.count)
        var path = Path()
        if skeleton.isFront {
            guard let otherHand = skeleton.points[.handFar] else {
                return
            }
            let controlY = (low - 0.25 * (hand.y + otherHand.y) / 2) / 0.75
            path.move(to: camera.point(hand))
            path.addCurve(
                to: camera.point(otherHand),
                control1: camera.point(GuidePoint(x: hand.x, y: controlY)),
                control2: camera.point(GuidePoint(x: otherHand.x, y: controlY))
            )
        } else {
            let bottom = GuidePoint(x: centerX, y: low)
            path.move(to: camera.point(hand + shift))
            path.addCurve(
                to: camera.point(bottom),
                control1: camera.point(hand + GuidePoint(x: 0.06, y: -0.22)),
                control2: camera.point(bottom + GuidePoint(x: 0.16, y: 0.06))
            )
        }
        context.stroke(path, with: .color(color.color), style: StrokeStyle(lineWidth: camera.length(0.007), lineCap: .round))
    }

    // MARK: - Fantasma (posição inicial)

    /// Uma forma do corpo no mundo, para comparar a posição inicial com a de agora.
    private enum BodyShape {
        case hull(GuidePoint, Double, GuidePoint, Double)
        case torso([GuidePoint])
    }

    /// `Get-BodyShapes`: na vista lateral só o lado de cá; na frontal, os dois lados.
    private func bodyShapes(_ skeleton: GuideSkeleton) -> [BodyShape] {
        var shapes: [BodyShape] = []
        func add(_ a: GuideJoint, _ ra: Double, _ b: GuideJoint, _ rb: Double) {
            guard let pa = skeleton.points[a], let pb = skeleton.points[b] else {
                return
            }
            shapes.append(.hull(pa, ra, pb, rb))
        }
        if skeleton.isFront {
            for far in [true, false] {
                let ankle: GuideJoint = far ? .ankleFar : .ankle
                let knee: GuideJoint = far ? .kneeFar : .knee
                add(ankle, Radius.ankle, far ? .toeFar : .toe, 0.018)
                add(knee, Radius.kneeLow, ankle, Radius.ankle)
                add(far ? .hipJFar : .hipJ, Radius.thighTop, knee, Radius.knee)
            }
            if let torso = frontTorsoPoints(skeleton) {
                shapes.append(.torso(torso))
            }
            add(.neckBase, Radius.neck, .head, Radius.neck)
            add(.head, Radius.head, .head, Radius.head)
            for far in [true, false] {
                let elbow: GuideJoint = far ? .elbowFar : .elbow
                let wrist: GuideJoint = far ? .wristFar : .wrist
                add(far ? .shoulderFar : .shoulder, Radius.shoulder, elbow, Radius.elbow)
                add(elbow, Radius.elbowLow, wrist, Radius.wrist)
                add(wrist, Radius.wrist, far ? .fistFar : .fist, Radius.hand)
            }
            return shapes
        }
        add(.heel, Radius.heel, .toe, Radius.toe)
        add(.ankle, Radius.ankle, .heel, Radius.heel)
        add(.knee, Radius.kneeLow, .ankle, Radius.ankle)
        add(.hip, Radius.thighTop, .knee, Radius.knee)
        if let hip = skeleton.points[.hip], let shoulder = skeleton.points[.shoulder], let head = skeleton.points[.head] {
            let trunkAngle = skeleton.angle(of: .trunk) ?? 90
            let neckAngle = skeleton.angle(of: .head) ?? 90
            let up = GuidePoint.direction(trunkAngle)
            let face = GuidePoint.direction(neckAngle - 90)
            shapes.append(.hull(hip, Radius.hip, shoulder - up * 0.012, Radius.chest))
            shapes.append(.hull(shoulder, Radius.neck, head, Radius.neck))
            shapes.append(.hull(head, Radius.head, head, Radius.head))
            shapes.append(.hull(
                head + face * 0.047,
                0.017,
                head + face * 0.061 + GuidePoint.direction(neckAngle) * -0.004,
                0.011
            ))
        }
        add(.shoulder, Radius.shoulder, .elbow, Radius.elbow)
        add(.elbow, Radius.elbowLow, .wrist, Radius.wrist)
        add(.wrist, Radius.wrist, .fist, Radius.hand)
        return shapes
    }

    private func moved(_ start: BodyShape, _ now: BodyShape) -> Bool {
        let tolerance = GuidePainter.ghostTolerance
        switch (start, now) {
        case let (.hull(a0, _, b0, _), .hull(a1, _, b1, _)):
            return a0.distance(to: a1) > tolerance || b0.distance(to: b1) > tolerance
        case let (.torso(points0), .torso(points1)):
            return zip(points0, points1).contains { $0.distance(to: $1) > tolerance }
        default:
            return true
        }
    }

    private func path(of shape: BodyShape) -> Path {
        switch shape {
        case let .hull(a, ra, b, rb):
            return GuidePainter.hullPath(camera.point(a), camera.length(ra), camera.point(b), camera.length(rb))
        case let .torso(points):
            return polygon(points)
        }
    }

    /// `Draw-Ghost`: só as partes que mudaram de lugar, com contorno tracejado da união e miolo quase fundo.
    private func drawGhost(in context: GraphicsContext, from start: GuideSkeleton, now: GuideSkeleton) {
        let startShapes = bodyShapes(start)
        let nowShapes = bodyShapes(now)
        var selected: [BodyShape] = []
        for (index, shape) in startShapes.enumerated() where index < nowShapes.count {
            if moved(shape, nowShapes[index]) {
                selected.append(shape)
            }
        }
        var movedProps: Set<String> = []
        for (key, point) in start.props {
            guard let current = now.props[key] else {
                movedProps.insert(key)
                continue
            }
            if point.distance(to: current) > GuidePainter.ghostTolerance {
                movedProps.insert(key)
            }
        }
        let props = figure.guide.props
        for prop in props where prop.kind == .barbell && prop.attach == GuideProp.backAttach && movedProps.contains(prop.id) {
            if let center = start.props[prop.id] {
                drawPlate(context, center: center, color: ink.ghostLine, veil: false)
            }
        }
        drawGhostShapes(context, shapes: selected)
        for prop in props {
            if prop.kind.isLine || prop.kind == .jumpRope || (prop.kind == .barbell && prop.attach == GuideProp.backAttach) {
                continue
            }
            for key in [prop.id, prop.id + "Far"] where movedProps.contains(key) {
                if let center = start.props[key] {
                    drawProp(prop, at: center, in: context, color: ink.ghostLine, ghost: true)
                }
            }
        }
    }

    /// Contorno tracejado da UNIÃO das formas: primeiro cada forma com o dobro da espessura, depois todas
    /// preenchidas por cima, cobrindo a metade de dentro do traço e as linhas onde as formas se sobrepõem.
    private func drawGhostShapes(_ context: GraphicsContext, shapes: [BodyShape]) {
        let lineWidth = camera.length(0.0075)
        let round = camera.length(0.05)
        let dash = camera.length(0.026)
        let gapLength = camera.length(0.017)
        for shape in shapes {
            var width = 2 * lineWidth
            if case .torso = shape {
                width += round
            }
            context.stroke(
                path(of: shape),
                with: .color(ink.ghostLine.color),
                style: StrokeStyle(lineWidth: width, lineJoin: .round, dash: [dash, gapLength])
            )
        }
        for shape in shapes {
            let shapePath = path(of: shape)
            context.fill(shapePath, with: .color(ink.ghostFill.color))
            if case .torso = shape {
                context.stroke(shapePath, with: .color(ink.ghostFill.color), style: StrokeStyle(lineWidth: round, lineJoin: .round))
            }
        }
    }

    // MARK: - Seta (`Draw-ArrowScreen`)

    /// Traço até o entalhe da ponta e a ponta em forma de flecha, alinhada ao fim da curva.
    private func drawArrow(in context: GraphicsContext, points: [CGPoint], color: GuideInk.RGB) {
        guard let end = points.last, points.count >= 2 else {
            return
        }
        let headLength = Double(camera.length(0.056))
        let headWidth = Double(camera.length(0.034))
        let lineWidth = camera.length(0.013)
        var index = points.count - 1
        while index > 1 && distance(end, points[index - 1]) < headLength {
            index -= 1
        }
        let previous = points[index - 1]
        var ux = Double(end.x - previous.x)
        var uy = Double(end.y - previous.y)
        let size = (ux * ux + uy * uy).squareRoot()
        if size < 1e-9 {
            ux = 1
            uy = 0
        } else {
            ux /= size
            uy /= size
        }
        let nx = -uy
        let ny = ux
        let notch = CGPoint(x: Double(end.x) - ux * headLength * 0.72, y: Double(end.y) - uy * headLength * 0.72)
        let base = CGPoint(x: Double(end.x) - ux * headLength, y: Double(end.y) - uy * headLength)
        var line = Path()
        line.move(to: points[0])
        for position in 1..<index {
            line.addLine(to: points[position])
        }
        line.addLine(to: notch)
        context.stroke(line, with: .color(color.color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        var head = Path()
        head.move(to: end)
        head.addLine(to: CGPoint(x: Double(base.x) + nx * headWidth, y: Double(base.y) + ny * headWidth))
        head.addLine(to: notch)
        head.addLine(to: CGPoint(x: Double(base.x) - nx * headWidth, y: Double(base.y) - ny * headWidth))
        head.closeSubpath()
        context.fill(head, with: .color(color.color))
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(a.x - b.x)
        let dy = Double(a.y - b.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Primitivas

    /// Segmento do corpo entre dois pontos do esqueleto; some se algum ponto não existe.
    private func limb(
        _ context: GraphicsContext,
        _ skeleton: GuideSkeleton,
        _ color: GuideInk.RGB,
        gap: GuideInk.RGB?,
        _ a: GuideJoint,
        _ ra: Double,
        _ b: GuideJoint,
        _ rb: Double,
        shift: GuidePoint
    ) {
        guard let pa = skeleton.points[a], let pb = skeleton.points[b] else {
            return
        }
        hull(context, color, gap: gap, pa + shift, ra, pb + shift, rb)
    }

    /// `Draw-Limb`: o casco tangente a dois círculos; o contorno na cor do fundo separa sobreposições.
    private func hull(_ context: GraphicsContext, _ color: GuideInk.RGB, gap: GuideInk.RGB?, _ a: GuidePoint, _ ra: Double, _ b: GuidePoint, _ rb: Double) {
        let path = GuidePainter.hullPath(camera.point(a), camera.length(ra), camera.point(b), camera.length(rb))
        if let gap {
            context.stroke(path, with: .color(gap.color), style: StrokeStyle(lineWidth: camera.length(GuidePainter.gapWidth), lineJoin: .round))
        }
        context.fill(path, with: .color(color.color))
    }

    /// `New-HullPath` na tela: o arco de trás do primeiro círculo e o da frente do segundo, amostrados em pontos
    /// (ângulos crescem para baixo, como no GDI+ do script). Círculos quase concêntricos viram só o maior.
    static func hullPath(_ c1: CGPoint, _ r1: CGFloat, _ c2: CGPoint, _ r2: CGFloat) -> Path {
        let dx = Double(c2.x - c1.x)
        let dy = Double(c2.y - c1.y)
        let length = (dx * dx + dy * dy).squareRoot()
        let radius1 = Double(r1)
        let radius2 = Double(r2)
        if length <= abs(radius1 - radius2) + 0.5 {
            let center = radius1 >= radius2 ? c1 : c2
            let radius = CGFloat(max(radius1, radius2))
            return Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        }
        let base = atan2(dy, dx)
        let phi = acos(max(-1, min(1, (radius1 - radius2) / length)))
        let samples = 16
        var path = Path()
        for step in 0...samples {
            let angle = base + phi + (2 * Double.pi - 2 * phi) * Double(step) / Double(samples)
            let point = CGPoint(x: Double(c1.x) + radius1 * cos(angle), y: Double(c1.y) + radius1 * sin(angle))
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        for step in 0...samples {
            let angle = base - phi + 2 * phi * Double(step) / Double(samples)
            path.addLine(to: CGPoint(x: Double(c2.x) + radius2 * cos(angle), y: Double(c2.y) + radius2 * sin(angle)))
        }
        path.closeSubpath()
        return path
    }

    private func polygon(_ points: [GuidePoint]) -> Path {
        var path = Path()
        guard let first = points.first else {
            return path
        }
        path.move(to: camera.point(first))
        for point in points.dropFirst() {
            path.addLine(to: camera.point(point))
        }
        path.closeSubpath()
        return path
    }

    /// Retângulo arredondado no mundo: canto inferior esquerdo (x, y), largura e altura (`Fill-WorldRect`).
    private func fillRect(_ context: GraphicsContext, _ color: GuideInk.RGB, x: Double, y: Double, width: Double, height: Double, radius: Double) {
        guard width > 0, height > 0 else {
            return
        }
        let topLeft = camera.point(GuidePoint(x: x, y: y + height))
        let rect = CGRect(x: topLeft.x, y: topLeft.y, width: camera.length(width), height: camera.length(height))
        let corner = max(0.5, min(camera.length(radius), min(rect.width, rect.height) / 2))
        context.fill(Path(roundedRect: rect, cornerRadius: corner, style: .circular), with: .color(color.color))
    }

    /// Barra girada: centro, direção em graus, comprimento e espessura (`Fill-WorldBar`).
    private func barPath(center: GuidePoint, angle: Double, length: Double, thickness: Double) -> Path {
        let offset = GuidePoint.direction(angle) * max(0, length / 2 - thickness / 2)
        let radius = camera.length(thickness / 2)
        return GuidePainter.hullPath(camera.point(center - offset), radius, camera.point(center + offset), radius)
    }

    private func fillBar(_ context: GraphicsContext, _ color: GuideInk.RGB, center: GuidePoint, angle: Double, length: Double, thickness: Double) {
        context.fill(barPath(center: center, angle: angle, length: length, thickness: thickness), with: .color(color.color))
    }

    private func strokeBar(
        _ context: GraphicsContext,
        _ color: GuideInk.RGB,
        center: GuidePoint,
        angle: Double,
        length: Double,
        thickness: Double,
        width: Double
    ) {
        context.stroke(
            barPath(center: center, angle: angle, length: length, thickness: thickness),
            with: .color(color.color),
            style: StrokeStyle(lineWidth: camera.length(width))
        )
    }

    private func circlePath(center: GuidePoint, radius: Double) -> Path {
        let point = camera.point(center)
        let size = camera.length(radius)
        return Path(ellipseIn: CGRect(x: point.x - size, y: point.y - size, width: 2 * size, height: 2 * size))
    }

    private func fillCircle(_ context: GraphicsContext, _ color: GuideInk.RGB, opacity: Double = 1, center: GuidePoint, radius: Double) {
        context.fill(circlePath(center: center, radius: radius), with: .color(GuideInk.color(color, opacity: opacity)))
    }

    private func strokeCircle(_ context: GraphicsContext, _ color: GuideInk.RGB, center: GuidePoint, radius: Double, width: Double) {
        context.stroke(circlePath(center: center, radius: radius), with: .color(color.color), style: StrokeStyle(lineWidth: camera.length(width)))
    }

    private func strokeLine(_ context: GraphicsContext, _ color: GuideInk.RGB, from: GuidePoint, to: GuidePoint, width: Double) {
        var path = Path()
        path.move(to: camera.point(from))
        path.addLine(to: camera.point(to))
        context.stroke(path, with: .color(color.color), style: StrokeStyle(lineWidth: camera.length(width), lineCap: .round))
    }
}
