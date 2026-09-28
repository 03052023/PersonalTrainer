import Foundation

// Regras de formato que dependem do contexto (docs/V23-CORE-CONTRACT.md §2.5), E2 dos quadros, E7 e E9. Mesmas
// mensagens, em essência, do `Test-Guide` da ferramenta.
extension ExerciseGuideValidator {
    static func checkStructure(_ guide: ExerciseGuide, into collector: inout GuideProblemCollector) {
        let viewPoints = Set(GuideJoint.points(for: guide.view).map(\.rawValue))
        checkIdentifiers(guide, into: &collector)
        checkScene(guide, into: &collector)
        checkProps(guide, viewPoints: viewPoints, into: &collector)
        checkArms(guide, into: &collector)
        checkAnchor(guide, viewPoints: viewPoints, into: &collector)
        checkRhythm(guide, into: &collector)
        checkFrames(guide, into: &collector)
        checkCue(guide, viewPoints: viewPoints, into: &collector)
        checkMoving(guide, into: &collector)
    }

    /// Ids de acessório com posição própria (tudo menos cabo e elástico).
    static func positionedPropIDs(of guide: ExerciseGuide) -> Set<String> {
        Set(guide.props.filter { !$0.kind.isLine }.map(\.id))
    }

    static func checkIdentifiers(_ guide: ExerciseGuide, into collector: inout GuideProblemCollector) {
        var ids = Set<String>()
        for item in guide.scene {
            guard let id = item.id else {
                if item.kind == .pulley {
                    collector.format("pulley precisa de id")
                }
                continue
            }
            if id.isEmpty {
                collector.format("scene.id deve ser um texto")
            } else if !ids.insert(id).inserted {
                collector.format("id repetido: \(id)")
            }
        }
        for prop in guide.props {
            if prop.id.isEmpty {
                collector.format("acessório sem id")
            } else if !ids.insert(prop.id).inserted {
                collector.format("id repetido: \(prop.id)")
            } else if GuideJoint(rawValue: prop.id) != nil {
                collector.format("id de acessório não pode ser nome de ponto do esqueleto: \(prop.id)")
            }
        }
    }

    static func missingParameters(of item: GuideSceneItem) -> [String] {
        var missing: [String] = []
        func require(_ name: String, _ present: Bool) {
            if !present {
                missing.append(name)
            }
        }
        switch item.kind {
        case .bench, .seat:
            require("x", item.x != nil)
            require("top", item.top != nil)
            require("length", item.length != nil)
        case .rail:
            require("x1", item.x1 != nil)
            require("x2", item.x2 != nil)
        case .tower:
            require("x", item.x != nil)
            require("width", item.width != nil)
            require("height", item.height != nil)
        case .footPlate, .pad:
            require("at", item.at != nil)
            require("length", item.length != nil)
            require("angle", item.angle != nil)
        case .pulley:
            require("at", item.at != nil)
        case .block:
            require("x", item.x != nil)
            require("y", item.y != nil)
            require("width", item.width != nil)
            require("height", item.height != nil)
        case .post:
            require("from", item.from != nil)
            require("to", item.to != nil)
        case .wheel:
            require("at", item.at != nil)
            require("radius", item.radius != nil)
        case .steps:
            require("x", item.x != nil)
            require("count", item.count != nil)
            require("rise", item.rise != nil)
            require("run", item.run != nil)
        }
        return missing
    }

    static func checkScene(_ guide: ExerciseGuide, into collector: inout GuideProblemCollector) {
        for item in guide.scene {
            let place = "scene \(item.kind.rawValue)"
            for name in missingParameters(of: item) {
                collector.format("\(place) sem '\(name)'")
            }
            let sizes: [(name: String, value: Double?)] = [
                (name: "length", value: item.length), (name: "width", value: item.width), (name: "height", value: item.height),
                (name: "radius", value: item.radius), (name: "rise", value: item.rise), (name: "run", value: item.run),
                (name: "thick", value: item.thick),
            ]
            for size in sizes {
                if let value = size.value, !(value > 0) {
                    collector.format("\(place).\(size.name) deve ser maior que 0")
                }
            }
            if let count = item.count, count < 1 {
                collector.format("\(place).count deve ser um inteiro >= 1")
            }
        }
    }

    static func checkProps(_ guide: ExerciseGuide, viewPoints: Set<String>, into collector: inout GuideProblemCollector) {
        let sceneReferences = Set(guide.scene.compactMap { $0.referencePoint == nil ? nil : $0.id })
        let positioned = positionedPropIDs(of: guide)
        for prop in guide.props {
            let place = "props \(prop.id)"
            if prop.kind.isLine {
                if prop.attach != nil || prop.offset != nil || prop.along != nil || prop.side != nil {
                    collector.format("\(place): cable e band não usam attach, offset, along nem side")
                }
                let fromOK = prop.from.map { sceneReferences.contains($0) } ?? false
                if !fromOK {
                    collector.format("\(place).from deve ser o id de um item da cena com ponto de referência (pulley, wheel, pad, footPlate ou post)")
                }
                let toOK = prop.to.map { viewPoints.contains($0) || positioned.contains($0) } ?? false
                if !toOK {
                    collector.format("\(place).to deve ser um acessório ou um ponto do esqueleto desta vista")
                }
                continue
            }
            var onSegment = false
            if let attach = prop.attach {
                if attach == GuideProp.backAttach || attach == GuideProp.chestAttach || viewPoints.contains(attach) {
                    onSegment = false
                } else if let segment = GuideSegment(rawValue: attach), segment.isAttachable {
                    onSegment = true
                } else {
                    collector.format("\(place).attach desconhecido: \(attach)")
                }
            } else {
                collector.format("\(place) sem attach")
            }
            if onSegment {
                if let along = prop.along {
                    if along < 0 || along > 1 {
                        collector.format("\(place).along deve ficar entre 0 e 1")
                    }
                } else {
                    collector.format("\(place) sem 'along'")
                }
            } else if prop.along != nil || prop.side != nil {
                collector.format("\(place).along e .side só valem com attach num segmento")
            }
            if prop.kind == .plate {
                if let length = prop.length {
                    if !(length > 0) {
                        collector.format("\(place).length deve ser maior que 0")
                    }
                } else {
                    collector.format("\(place) sem 'length'")
                }
                if prop.angle == nil {
                    collector.format("\(place) sem 'angle'")
                }
            }
            if prop.kind == .roller, let radius = prop.radius, !(radius > 0) {
                collector.format("\(place).radius deve ser maior que 0")
            }
        }
    }

    static func checkDepth(_ depth: GuideDepth, _ place: String, into collector: inout GuideProblemCollector) {
        for value in [depth.upper, depth.lower] where !(value >= 0.3 && value <= 1) {
            collector.format("\(place) fora de 0,3 a 1: \(value)")
        }
    }

    static func checkArms(_ guide: ExerciseGuide, into collector: inout GuideProblemCollector) {
        guard let arms = guide.arms else {
            return
        }
        if let reach = arms.reach {
            if guide.view == .front {
                collector.format("na vista frontal os braços são por ângulos (sem arms.reach)")
            }
            if reach != GuideArms.gripReach {
                if let target = guide.props.first(where: { $0.id == reach }), !target.kind.isLine {
                    let attach = target.attach ?? ""
                    if attach != GuideProp.backAttach && attach != GuideProp.chestAttach && attach != GuideJoint.hip.rawValue {
                        collector.format("arms.reach exige um acessório em back, chest ou hip")
                    }
                } else {
                    collector.format("arms.reach aponta para acessório inexistente: \(reach)")
                }
            }
        }
        if let depth = arms.depth {
            checkDepth(depth, "arms.depth", into: &collector)
        }
        if arms.forearm != nil && arms.reach == nil {
            collector.format("arms.forearm só vale com arms.reach")
        }
        if let farArm = arms.farArm {
            if guide.view == .front {
                collector.format("arms.farArm só vale na vista lateral")
            }
            if farArm == .pose && arms.reach == nil {
                collector.format("arms.farArm 'pose' só vale com arms.reach")
            }
        }
    }

    static func checkAnchor(_ guide: ExerciseGuide, viewPoints: Set<String>, into collector: inout GuideProblemCollector) {
        let anchor = guide.anchor
        if anchor.isNone {
            for (index, frame) in guide.frames.enumerated() where frame.root == nil {
                collector.format("frames[\(index)] sem root (anchor none)")
            }
            return
        }
        if !viewPoints.contains(anchor.joint) {
            collector.format("anchor.joint desconhecido nesta vista: \(anchor.joint)")
        } else if let joint = anchor.point, joint.isArmPoint, guide.arms?.reach != nil {
            collector.format("âncora na mão ou no braço exige braços por ângulos")
        }
        if anchor.at == nil {
            collector.format("anchor sem 'at'")
        }
    }

    static func checkRhythm(_ guide: ExerciseGuide, into collector: inout GuideProblemCollector) {
        guard let timing = guide.timing else {
            if guide.motion == .loop {
                collector.format("timing é obrigatório em motion 'loop'")
            }
            return
        }
        let phases: [(name: String, value: Double)] = [(name: "toEnd", value: timing.toEnd), (name: "toStart", value: timing.toStart)]
        for phase in phases where !(phase.value >= 0.8 && phase.value <= 3.0) {
            collector.add("E7", "timing.\(phase.name) fora de 0,8 a 3,0 s: \(phase.value)")
        }
        if !(timing.hold >= 0.2 && timing.hold <= 1.0) {
            collector.add("E7", "timing.hold fora de 0,2 a 1,0 s: \(timing.hold)")
        }
    }

    static func checkFrames(_ guide: ExerciseGuide, into collector: inout GuideProblemCollector) {
        let count = guide.frames.count
        switch guide.motion {
        case .loop:
            if count < 2 || count > 3 {
                collector.add("E2", "motion 'loop' precisa de 2 ou 3 quadros (tem \(count))")
            }
        case .still:
            if count < 1 || count > 3 {
                collector.add("E2", "motion 'static' precisa de 1 a 3 quadros (tem \(count))")
            }
        }
        let labels: [GuideFrame.Label]
        switch count {
        case 1: labels = [.position]
        case 2: labels = [.start, .end]
        case 3: labels = [.start, .middle, .end]
        default: labels = []
        }
        let usesIK = guide.arms?.reach != nil
        var required: Set<GuidePose.Key>
        if guide.view == .front {
            required = [.trunk, .neck, .thigh, .shin, .upperArm, .forearm]
        } else {
            required = [.trunk, .neck, .thigh, .shin, .foot]
            if !usesIK {
                required.formUnion([.upperArm, .forearm])
            }
        }
        if guide.arms?.farArm == .pose {
            required.formUnion([.upperArmFar, .forearmFar])
        }
        let needsGrip = guide.arms?.reach == GuideArms.gripReach
        let firstKeys = guide.frames.first?.pose.keys
        for (index, frame) in guide.frames.enumerated() {
            let place = "frames[\(index)]"
            if index < labels.count && frame.label != labels[index] {
                collector.add("E2", "\(place).label deve ser '\(labels[index].rawValue)'")
            }
            if textLength(frame.caption) < 1 || frame.caption.count > 28 {
                collector.add("E2", "\(place).caption precisa ter de 1 a 28 caracteres (tem \(frame.caption.count))")
            }
            let keys = frame.pose.keys
            for key in GuidePose.Key.allCases where required.contains(key) && !keys.contains(key) {
                collector.format("\(place).pose sem '\(key.rawValue)'")
            }
            if let firstKeys, keys != firstKeys {
                collector.format("\(place).pose tem chaves diferentes do primeiro quadro (todos os quadros têm o mesmo conjunto)")
            }
            if needsGrip && frame.grip == nil {
                collector.format("\(place) sem grip (arms.reach = grip)")
            }
            if let depth = frame.armDepth {
                checkDepth(depth, "\(place).armDepth", into: &collector)
            }
            if let depth = frame.legDepth {
                checkDepth(depth, "\(place).legDepth", into: &collector)
            }
        }
    }

    static func checkCue(_ guide: ExerciseGuide, viewPoints: Set<String>, into collector: inout GuideProblemCollector) {
        guard let cue = guide.cue else {
            if guide.motion == .loop {
                collector.format("cue é obrigatório em motion 'loop'")
            }
            return
        }
        if !(viewPoints.contains(cue.track) || positionedPropIDs(of: guide).contains(cue.track)) {
            collector.format("cue.track deve ser um ponto do esqueleto desta vista ou o id de um acessório")
        }
        if let span = cue.span {
            if span.count != 2 || span[0] < 0 || span[0] >= span[1] || span[1] > 1 {
                collector.format("cue.span deve ser [a, b] com 0 <= a < b <= 1")
            }
        }
        if cue.side != nil && !((cue.gap ?? 0) > 0) {
            collector.format("cue.side exige gap maior que 0")
        }
        if cue.gap != nil && cue.side == nil {
            collector.format("cue.gap só vale com cue.side")
        }
        if cue.offset == nil && cue.side == nil {
            collector.format("cue precisa de offset ou de side com gap (a seta não cobre o corpo)")
        }
        if guide.frames.count == 1 {
            collector.format("com 1 quadro não há caminho para a seta: tire o cue")
        }
    }

    static func checkMoving(_ guide: ExerciseGuide, into collector: inout GuideProblemCollector) {
        guard let moving = guide.moving else {
            if guide.motion == .still && guide.frames.count == 1 {
                collector.add("E9", "moving é obrigatório em motion 'static' com 1 quadro")
            }
            return
        }
        if moving.isEmpty {
            collector.add("E9", "moving deve ser uma lista não vazia de segmentos")
        }
        for name in moving where GuideSegment(rawValue: name) == nil {
            collector.add("E9", "moving tem segmento desconhecido: \(name)")
        }
    }
}
