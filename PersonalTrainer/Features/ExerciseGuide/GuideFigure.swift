import CoreGraphics
import Foundation
import TrainerCore

/// Uma guia pronta para desenhar (SPEC RF-40, §7.12; DESIGN §12): o que se move (E9), a seta, o enquadramento de
/// todo o movimento e a figura inicial do fantasma. Tudo sai das funções puras de `TrainerCore/Guide`; a tela só
/// pinta. Calculado uma vez por guia, nunca por quadro.
///
/// O enquadramento é o `Get-Bounds` da folha de revisão (`docs/design/exercise-guides/render-exercise-guides.ps1`):
/// todas as articulações, acessórios, a seta e a cena ao longo do movimento, com as mesmas folgas. Assim a figura
/// não muda de escala nem sai do quadro enquanto anima.
struct GuideFigure: Sendable, Hashable {
    /// Retângulo do mundo, em estaturas (H = 1); o chão (y = 0) sempre dentro.
    struct Bounds: Sendable, Hashable {
        var minX: Double
        var maxX: Double
        var minY: Double
        var maxY: Double

        var width: Double {
            max(maxX - minX, 0.000_001)
        }

        var height: Double {
            max(maxY - minY, 0.000_001)
        }

        mutating func grow(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            minX = min(minX, x1)
            maxX = max(maxX, x2)
            minY = min(minY, y1)
            maxY = max(maxY, y2)
        }
    }

    let guide: ExerciseGuide
    let moving: Set<GuideSegment>
    /// A seta do caminho da ida (41 pontos no mundo); vazia sem `cue`.
    let cue: [GuidePoint]
    let bounds: Bounds
    /// A figura no primeiro quadro: a posição inicial em fantasma nos quadros seguintes (SPEC E9).
    let start: GuideSkeleton

    init(guide: ExerciseGuide) {
        self.guide = guide
        moving = GuideMotion.movingSegments(of: guide)
        let cue = GuideMotion.cuePath(of: guide)
        self.cue = cue
        bounds = GuideFigure.bounds(of: guide, cue: cue)
        start = GuideKinematics.skeleton(of: guide, at: 0)
    }

    /// Último instante do movimento, em quadros (n − 1).
    var lastFrameTime: Double {
        Double(max(0, guide.frames.count - 1))
    }

    /// Anima em loop (E7): `motion` diferente de `static` e mais de um quadro.
    var animates: Bool {
        guide.motion == .loop && guide.frames.count > 1 && GuideTiming.cycleSeconds(of: guide) > 0
    }

    // MARK: - Enquadramento (`Get-Bounds`)

    static func bounds(of guide: ExerciseGuide, cue: [GuidePoint]) -> Bounds {
        var box = Bounds(minX: 1e9, maxX: -1e9, minY: 0, maxY: -1e9)
        let last = Double(max(0, guide.frames.count - 1))
        var radii: [String: Double] = [:]
        for prop in guide.props {
            let radius = propRadius(prop)
            radii[prop.id] = radius
            radii[prop.id + "Far"] = radius
        }
        let hasJumpRope = guide.props.contains { $0.kind == .jumpRope }
        let steps = max(1, Int(last * 10))
        for step in 0...steps {
            let skeleton = GuideKinematics.skeleton(of: guide, at: last * Double(step) / Double(steps))
            for (joint, point) in skeleton.points {
                let radius = joint == .head ? 0.072 : 0.062
                box.grow(point.x - radius, point.y - radius, point.x + radius, point.y + radius)
            }
            for (id, point) in skeleton.props {
                let radius = radii[id] ?? 0.03
                box.grow(point.x - radius, point.y - radius, point.x + radius, point.y + radius)
            }
            if hasJumpRope, let hand = skeleton.points[.hand] {
                box.grow(hand.x - 0.22, -0.03, hand.x + 0.22, 0)
            }
        }
        for point in cue {
            box.grow(point.x - 0.04, point.y - 0.04, point.x + 0.04, point.y + 0.04)
        }
        for item in guide.scene {
            grow(&box, with: item)
        }
        // Guia sem nada a enquadrar (não passa na validação, mas a tela nunca divide por zero).
        if box.maxX < box.minX {
            box.minX = -0.5
            box.maxX = 0.5
        }
        if box.maxY <= box.minY {
            box.maxY = box.minY + 1
        }
        return box
    }

    private static func grow(_ box: inout Bounds, with item: GuideSceneItem) {
        switch item.kind {
        case .bench, .seat:
            if let x = item.x, let length = item.length, let top = item.top {
                box.grow(x, 0, x + length, top)
            }
        case .rail:
            if let x1 = item.x1, let x2 = item.x2 {
                box.grow(x1, 0, x2, 0.04)
            }
        case .tower:
            if let x = item.x, let width = item.width, let height = item.height {
                box.grow(x, 0, x + width, height)
            }
        case .block:
            if let x = item.x, let y = item.y, let width = item.width, let height = item.height {
                box.grow(x, y, x + width, y + height)
            }
        case .steps:
            if let x = item.x, let count = item.count, let rise = item.rise, let run = item.run {
                box.grow(x, 0, x + Double(count) * run, Double(count) * rise)
            }
        case .post:
            if let from = item.from, let to = item.to {
                box.grow(min(from.x, to.x) - 0.02, min(from.y, to.y), max(from.x, to.x) + 0.02, max(from.y, to.y) + 0.02)
            }
        case .wheel:
            if let at = item.at, let radius = item.radius {
                box.grow(at.x - radius, at.y - radius, at.x + radius, at.y + radius)
            }
        case .pulley:
            if let at = item.at {
                box.grow(at.x - 0.03, at.y - 0.03, at.x + 0.03, at.y + 0.03)
            }
        case .footPlate, .pad:
            if let at = item.at {
                let half = (item.length ?? 0.1) / 2 + 0.03
                box.grow(at.x - half, at.y - half, at.x + half, at.y + half)
            }
        }
    }

    /// Raio de enquadramento de cada acessório (`Get-PropRadius`).
    static func propRadius(_ prop: GuideProp) -> Double {
        switch prop.kind {
        case .barbell: return GuideRig.Radius.plate
        case .dumbbell: return 0.042
        case .kettlebell: return 0.12
        case .ball: return 0.075
        case .vHandle: return 0.07
        case .bar: return 0.03
        case .rope: return 0.08
        case .plate: return (prop.length ?? 0.1) / 2 + 0.02
        case .roller: return (prop.radius ?? GuideRig.Radius.roller) + 0.01
        case .jumpRope: return 0.03
        case .cable, .band: return 0.03
        }
    }
}

/// Do mundo (estaturas, y para cima) para a tela (pontos, y para baixo), como o `Set-Camera` da folha: a figura
/// centrada na horizontal e apoiada no chão, com as mesmas folgas proporcionais do quadro de 360 px.
struct GuideCamera: Sendable, Hashable {
    /// Pontos por estatura.
    let scale: Double
    let originX: Double
    let originY: Double

    /// Folgas do quadro da folha de revisão (`Get-CommonScale $panel 8 10 14` num quadro de 360 px).
    static let sidePadding = 8.0 / 360
    static let topPadding = 10.0 / 360
    static let bottomPadding = 14.0 / 360

    init(scale: Double, originX: Double, originY: Double) {
        self.scale = scale
        self.originX = originX
        self.originY = originY
    }

    /// A câmera que cabe `bounds` inteiro dentro de `rect`.
    init(fitting bounds: GuideFigure.Bounds, in rect: CGRect) {
        let width = Double(rect.width)
        let height = Double(rect.height)
        let side = GuideCamera.sidePadding * width
        let top = GuideCamera.topPadding * height
        let bottom = GuideCamera.bottomPadding * height
        let fit = min((width - 2 * side) / bounds.width, (height - bottom - top) / bounds.height)
        let scale = max(0.000_001, fit)
        let centerX = (bounds.minX + bounds.maxX) / 2
        self.scale = scale
        originX = Double(rect.midX) - centerX * scale
        originY = Double(rect.maxY) - bottom + bounds.minY * scale
    }

    func point(_ world: GuidePoint) -> CGPoint {
        CGPoint(x: originX + world.x * scale, y: originY - world.y * scale)
    }

    /// Uma medida do mundo em pontos.
    func length(_ world: Double) -> CGFloat {
        CGFloat(world * scale)
    }
}
