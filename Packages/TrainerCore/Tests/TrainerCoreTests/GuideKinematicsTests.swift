import Foundation
import Testing
@testable import TrainerCore

// Cinemática normativa do "Como fazer" (SPEC E4–E7 e E9; docs/V23-CORE-CONTRACT.md §2.5 com as extensões a–e):
// âncora, IK, antebraço travado, farArm, legDepth, anchor none, acessórios e tempo.

private enum KinematicsFixture {
    static let standingPose = "\"trunk\": 90, \"neck\": 90, \"thigh\": -90, \"shin\": -90, \"foot\": 0"
    static let texts = """
      "a11y": "Figura de teste.",
      "steps": ["Um.", "Dois.", "Três."],
      "mistakes": ["Erro: acerto.", "Outro erro: outro acerto."]
    """

    /// Em pé, o braço de cá levanta um halter por IK e o de lá segue os ângulos (`farArm: pose`).
    static let farArmJSON = """
    {
      "slug": "vocab-far-arm", "view": "side",
      "anchor": { "joint": "ankle", "at": [0.0, 0.039] },
      "timing": { "toEnd": 1.4, "toStart": 1.4, "hold": 0.4, "easing": "easeInOut" },
      "scene": [], "props": [ { "id": "dumbbell", "kind": "dumbbell", "attach": "hand" } ],
      "arms": { "reach": "grip", "farArm": "pose" },
      "frames": [
        { "label": "Início", "caption": "a", "grip": [0.05, 0.85], "pose": { \(standingPose), "upperArmFar": -90, "forearmFar": -90 } },
        { "label": "Fim", "caption": "b", "grip": [0.05, 1.12], "pose": { \(standingPose), "upperArmFar": -80, "forearmFar": -85 } }
      ],
      "cue": { "track": "dumbbell", "offset": [0.06, 0.0] },
    \(texts)
    }
    """

    /// De frente, sentado: coxas encurtadas pelo escorço (`legDepth`), halter nas duas mãos com offset.
    static let legDepthJSON = """
    {
      "slug": "vocab-leg-depth", "view": "front",
      "anchor": { "joint": "hip", "at": [0.0, 0.5] },
      "timing": { "toEnd": 1.4, "toStart": 1.4, "hold": 0.4, "easing": "easeInOut" },
      "scene": [], "props": [ { "id": "dumbbell", "kind": "dumbbell", "attach": "hand", "offset": [0.02, -0.01] } ],
      "frames": [
        { "label": "Início", "caption": "a", "legDepth": [0.4, 1.0], "pose": { "trunk": 90, "neck": 90, "thigh": -90, "shin": -90, "upperArm": -80, "forearm": -80 } },
        { "label": "Fim", "caption": "b", "legDepth": [0.4, 1.0], "pose": { "trunk": 90, "neck": 90, "thigh": -90, "shin": -90, "upperArm": 0, "forearm": 0 } }
      ],
      "cue": { "track": "hand", "side": "right", "gap": 0.06 },
    \(texts)
    }
    """

    /// Salto: sem âncora, o quadril segue `root` de cada quadro.
    static let jumpJSON = """
    {
      "slug": "vocab-none", "view": "side",
      "anchor": { "joint": "none" },
      "timing": { "toEnd": 1.0, "toStart": 1.0, "hold": 0.3, "easing": "easeInOut" },
      "scene": [], "props": [],
      "frames": [
        { "label": "Início", "caption": "a", "root": [0.0, 0.53], "pose": { \(standingPose), "upperArm": -90, "forearm": -90 } },
        { "label": "Fim", "caption": "b", "root": [0.1, 0.60], "pose": { \(standingPose), "upperArm": -90, "forearm": -90 } }
      ],
      "cue": { "track": "hip", "offset": [-0.1, 0.0] },
    \(texts)
    }
    """

    /// Pendurado na barra: âncora na mão, com braços por ângulos.
    static let hangJSON = """
    {
      "slug": "vocab-hang", "view": "side",
      "anchor": { "joint": "hand", "at": [0.0, 1.1] },
      "timing": { "toEnd": 1.4, "toStart": 1.4, "hold": 0.4, "easing": "easeInOut" },
      "scene": [], "props": [],
      "frames": [
        { "label": "Início", "caption": "a", "pose": { "trunk": 90, "neck": 90, "thigh": -95, "shin": -100, "foot": -30, "upperArm": 90, "forearm": 90 } },
        { "label": "Fim", "caption": "b", "pose": { "trunk": 90, "neck": 90, "thigh": -95, "shin": -100, "foot": -30, "upperArm": -60, "forearm": 95 } }
      ],
      "cue": { "track": "head", "offset": [0.08, 0.0] },
    \(texts)
    }
    """

    /// Acessórios no peito e ao longo de segmentos (pé e perna).
    static let attachJSON = """
    {
      "slug": "vocab-attach", "view": "side",
      "anchor": { "joint": "ankle", "at": [0.0, 0.039] },
      "timing": { "toEnd": 1.4, "toStart": 1.4, "hold": 0.4, "easing": "easeInOut" },
      "scene": [],
      "props": [
        { "id": "bar", "kind": "barbell", "attach": "chest", "offset": [0.05, -0.03] },
        { "id": "platform", "kind": "plate", "attach": "foot", "along": 0.5, "side": 0.02, "length": 0.3, "angle": 0 },
        { "id": "pad", "kind": "roller", "attach": "shin", "along": 1.0 }
      ],
      "arms": { "reach": "bar", "elbow": -60 },
      "frames": [
        { "label": "Início", "caption": "a", "pose": { "trunk": 88, "neck": 90, "thigh": -90, "shin": -88, "foot": -10 } },
        { "label": "Fim", "caption": "b", "pose": { "trunk": 70, "neck": 80, "thigh": -20, "shin": -110, "foot": -10 } }
      ],
      "cue": { "track": "hip", "offset": [-0.08, 0.0] },
    \(texts)
    }
    """

    static func guide(_ json: String) throws -> ExerciseGuide {
        try GuideTestSupport.guide(json)
    }

    static let instants: [Double] = [0, 0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9, 1]
}

private func nearlyEqual(_ a: GuidePoint?, _ b: GuidePoint?, _ tolerance: Double = 1e-6) -> Bool {
    guard let a, let b else { return false }
    return a.distance(to: b) <= tolerance
}

// MARK: - E5

@Test("E5 âncora parada em cada t, nas guias do bundle e com âncora no pé, no quadril e na mão")
func guideKinematicsAnchorStaysPut() throws {
    let catalog = try GuideTestSupport.bundleCatalog()
    var guides = catalog.guides
    guides.append(try KinematicsFixture.guide(KinematicsFixture.hangJSON))
    guides.append(try KinematicsFixture.guide(KinematicsFixture.attachJSON))
    // Com "anchor": "none" (saltos e carregadas do bundle) não há ponto parado; o teste de baixo cobre o root.
    for guide in guides where !guide.anchor.isNone {
        let joint = try #require(guide.anchor.point, "\(guide.slug)")
        let at = try #require(guide.anchor.at, "\(guide.slug)")
        let last = Double(guide.frames.count - 1)
        for step in 0...20 {
            let t = last * Double(step) / 20
            let point = GuideKinematics.skeleton(of: guide, at: t).points[joint]
            #expect(nearlyEqual(point, at, GuideRig.anchorTolerance), "\(guide.slug) t=\(t)")
        }
    }
}

@Test("E5 anchor none: sem translação, o quadril segue root com a mesma fração suavizada")
func guideKinematicsNoneAnchorFollowsRoot() throws {
    let jump = try KinematicsFixture.guide(KinematicsFixture.jumpJSON)
    #expect(nearlyEqual(GuideKinematics.skeleton(of: jump, at: 0).points[.hip], GuidePoint(x: 0, y: 0.53)))
    #expect(nearlyEqual(GuideKinematics.skeleton(of: jump, at: 1).points[.hip], GuidePoint(x: 0.1, y: 0.60)))
    // ease(0,5) = 0,5: no meio do caminho
    #expect(nearlyEqual(GuideKinematics.skeleton(of: jump, at: 0.5).points[.hip], GuidePoint(x: 0.05, y: 0.565)))
    // o resto do corpo sai do quadril: o ombro fica 0,288 H acima
    let skeleton = GuideKinematics.skeleton(of: jump, at: 0.25)
    let hip = try #require(skeleton.points[.hip])
    #expect(nearlyEqual(skeleton.points[.shoulder], hip + GuidePoint(x: 0, y: GuideRig.trunk)))
}

// MARK: - E6

@Test("E6 a mão chega à pegada alcançável (remada) e ao acessório nas costas (agachamento)")
func guideKinematicsHandReachesTarget() throws {
    let row = try GuideTestSupport.bundleGuide("seated-cable-row")
    for (index, frame) in row.frames.enumerated() {
        let hand = GuideKinematics.skeleton(of: row, at: Double(index)).points[.hand]
        #expect(nearlyEqual(hand, frame.grip, GuideRig.reachTolerance), "quadro \(index)")
    }
    let squat = try GuideTestSupport.bundleGuide("barbell-back-squat")
    for t in KinematicsFixture.instants {
        let skeleton = GuideKinematics.skeleton(of: squat, at: t)
        #expect(nearlyEqual(skeleton.points[.hand], skeleton.props["barbell"], GuideRig.reachTolerance), "t=\(t)")
    }
}

@Test("E6 antebraço travado não estica o braço: no supino, o antebraço fica vertical sob a barra")
func guideKinematicsLockedForearm() throws {
    let bench = try GuideTestSupport.bundleGuide("barbell-bench-press")
    for t in KinematicsFixture.instants {
        let skeleton = GuideKinematics.skeleton(of: bench, at: t)
        let elbow = try #require(skeleton.points[.elbow])
        let wrist = try #require(skeleton.points[.wrist])
        let shoulder = try #require(skeleton.points[.shoulder])
        #expect(abs(wrist.x - elbow.x) < 1e-9, "t=\(t)")
        #expect(wrist.y > elbow.y, "t=\(t)")
        #expect(elbow.distance(to: shoulder) <= GuideRig.upperArm + GuideRig.reachTolerance, "t=\(t)")
        // a barra está na mão, e o lado de lá repete o de cá
        #expect(nearlyEqual(skeleton.props["barbell"], skeleton.points[.hand]), "t=\(t)")
        #expect(nearlyEqual(skeleton.points[.handFar], skeleton.points[.hand]), "t=\(t)")
    }
    let start = GuideKinematics.skeleton(of: bench, at: 0)
    #expect(nearlyEqual(start.points[.hand], bench.frames[0].grip))
}

@Test("E6 farArm pose: o braço de cá vai à pegada por IK e o de lá segue os ângulos do quadro")
func guideKinematicsFarArmPose() throws {
    let guide = try KinematicsFixture.guide(KinematicsFixture.farArmJSON)
    let start = GuideKinematics.skeleton(of: guide, at: 0)
    let shoulder = try #require(start.points[.shoulder])
    #expect(nearlyEqual(start.points[.hand], GuidePoint(x: 0.05, y: 0.85), GuideRig.reachTolerance))
    #expect(nearlyEqual(start.points[.elbowFar], shoulder + GuidePoint(x: 0, y: -GuideRig.upperArm)))
    #expect(nearlyEqual(start.points[.wristFar], shoulder + GuidePoint(x: 0, y: -GuideRig.upperArm - GuideRig.forearm)))
    let end = GuideKinematics.skeleton(of: guide, at: 1)
    let endShoulder = try #require(end.points[.shoulder])
    #expect(nearlyEqual(end.points[.elbowFar], endShoulder + GuidePoint.direction(-80) * GuideRig.upperArm))
    #expect(!nearlyEqual(end.points[.handFar], end.points[.hand], 0.01))
    // o halter segue a mão de cá
    #expect(nearlyEqual(end.props["dumbbell"], end.points[.hand]))
}

@Test("E6 o IK nunca produz NaN, nem com o alvo em cima do ombro ou longe demais")
func guideKinematicsTwoBoneIsFinite() {
    let shoulder = GuidePoint(x: 0, y: 0.8)
    let targets: [GuidePoint] = [shoulder, GuidePoint(x: 3, y: 0.8), GuidePoint(x: 0.1, y: 0.75)]
    for target in targets {
        let solved = GuideKinematics.solveTwoBone(shoulder: shoulder, target: target, upper: 0.186, lower: 0.189, hint: -90)
        #expect(solved.elbow.isFinite && solved.end.isFinite, "\(target)")
    }
    // fora do alcance, o braço estende na direção do alvo
    let far = GuideKinematics.solveTwoBone(shoulder: shoulder, target: GuidePoint(x: 3, y: 0.8), upper: 0.186, lower: 0.189, hint: -90)
    #expect(abs(far.end.y - 0.8) < 1e-9)
    #expect(abs(far.end.x - (0.186 + 0.189 - 1e-4)) < 1e-9)
}

// MARK: - legDepth, acessórios

@Test("legDepth encurta coxa e perna; na vista frontal o acessório da mão aparece nas duas, com offset espelhado")
func guideKinematicsLegDepthAndFrontProps() throws {
    let guide = try KinematicsFixture.guide(KinematicsFixture.legDepthJSON)
    for t in KinematicsFixture.instants {
        let skeleton = GuideKinematics.skeleton(of: guide, at: t)
        let hipJoint = try #require(skeleton.points[.hipJ])
        let knee = try #require(skeleton.points[.knee])
        let ankle = try #require(skeleton.points[.ankle])
        #expect(abs(knee.distance(to: hipJoint) - GuideRig.thigh * 0.4) < 1e-9, "t=\(t)")
        #expect(abs(ankle.distance(to: knee) - GuideRig.shin) < 1e-9, "t=\(t)")
        let hand = try #require(skeleton.points[.hand])
        let handFar = try #require(skeleton.points[.handFar])
        #expect(abs(hand.x + handFar.x) < 1e-9 && abs(hand.y - handFar.y) < 1e-9, "espelho t=\(t)")
        #expect(nearlyEqual(skeleton.props["dumbbell"], hand + GuidePoint(x: 0.02, y: -0.01)), "t=\(t)")
        #expect(nearlyEqual(skeleton.props["dumbbellFar"], handFar + GuidePoint(x: -0.02, y: -0.01)), "t=\(t)")
    }
}

@Test("acessórios nas costas, no peito e ao longo de um segmento seguem o referencial do contrato")
func guideKinematicsPropAttachments() throws {
    let squat = try GuideTestSupport.bundleGuide("barbell-back-squat")
    let squatStart = GuideKinematics.skeleton(of: squat, at: 0)
    let shoulder = try #require(squatStart.points[.shoulder])
    // back: ombro + offset[0] × frente, com frente = Dir(trunk − 90); trunk 84 no quadro 1
    #expect(nearlyEqual(squatStart.props["barbell"], shoulder + GuidePoint.direction(84 - 90) * -0.085))

    let guide = try KinematicsFixture.guide(KinematicsFixture.attachJSON)
    for t in KinematicsFixture.instants {
        let skeleton = GuideKinematics.skeleton(of: guide, at: t)
        let top = try #require(skeleton.points[.shoulder])
        let trunk = try #require(skeleton.angle(of: .trunk))
        let forward = top + GuidePoint.direction(trunk - 90) * 0.05
        let chest = forward + GuidePoint.direction(trunk) * -0.03
        #expect(nearlyEqual(skeleton.props["bar"], chest), "peito t=\(t)")
        #expect(nearlyEqual(skeleton.points[.hand], skeleton.props["bar"], GuideRig.reachTolerance), "mão na barra t=\(t)")
        let ankle = try #require(skeleton.points[.ankle])
        let toe = try #require(skeleton.points[.toe])
        let footDelta = toe - ankle
        let midFoot = ankle + footDelta * 0.5
        let alongFoot = midFoot + footDelta.unit.perpendicular * 0.02
        #expect(nearlyEqual(skeleton.props["platform"], alongFoot), "pé t=\(t)")
        #expect(nearlyEqual(skeleton.props["pad"], ankle), "perna t=\(t)")
    }
}

// MARK: - E4

@Test("E4 determinismo: t fora da faixa é limitado e o resultado não muda entre chamadas")
func guideKinematicsClampsAndRepeats() throws {
    let squat = try GuideTestSupport.bundleGuide("barbell-back-squat")
    #expect(GuideKinematics.skeleton(of: squat, at: -3) == GuideKinematics.skeleton(of: squat, at: 0))
    #expect(GuideKinematics.skeleton(of: squat, at: 7) == GuideKinematics.skeleton(of: squat, at: 1))
    #expect(GuideKinematics.skeleton(of: squat, at: .nan) == GuideKinematics.skeleton(of: squat, at: 0))
    #expect(GuideKinematics.skeleton(of: squat, at: 0.37) == GuideKinematics.skeleton(of: squat, at: 0.37))
    // no início de cada fase a pose é exatamente a do quadro
    let start = GuideKinematics.skeleton(of: squat, at: 0)
    let trunk = try #require(start.angle(of: .trunk))
    #expect(abs(trunk - 84) < 1e-9)
}

// MARK: - E7

@Test("E7 tempo: t nas quatro fases do ciclo e nas bordas; guia parada não anima")
func guideKinematicsTimingPhases() throws {
    let squat = try GuideTestSupport.bundleGuide("barbell-back-squat")   // pausa 0,4 · ida 1,6 · volta 1,2
    #expect(abs(GuideTiming.cycleSeconds(of: squat) - 3.6) < 1e-9)
    let expected: [(seconds: Double, t: Double)] = [
        (seconds: 0, t: 0), (seconds: 0.2, t: 0), (seconds: 0.4, t: 0),   // pausa do início e a borda da ida
        (seconds: 1.2, t: 0.5),                                           // meio da ida
        (seconds: 2.0, t: 1), (seconds: 2.2, t: 1), (seconds: 2.4, t: 1), // pausa do fim e a borda da volta
        (seconds: 3.0, t: 0.5),                                           // meio da volta
        (seconds: 3.6, t: 0), (seconds: 4.8, t: 0.5),                     // o ciclo se repete
        (seconds: -0.4, t: 1.0 / 3.0),                                    // segundos negativos contam de trás
    ]
    for entry in expected {
        let t = GuideTiming.frameTime(of: squat, atSeconds: entry.seconds)
        #expect(abs(t - entry.t) < 1e-9, "\(entry.seconds) s → \(t)")
    }
    let plank = try GuideTestSupport.guide(GuideTestSupport.plankJSON)
    #expect(GuideTiming.cycleSeconds(of: plank) == 0)
    #expect(GuideTiming.frameTime(of: plank, atSeconds: 1.7) == 0)
}

// MARK: - E9

@Test("E9 nas guias do protótipo: agachamento com coxa e perna, braços parados; supino, remada e elevação com os braços")
func guideKinematicsMovingSegmentsOfPrototype() throws {
    let squatGuide = try GuideTestSupport.bundleGuide("barbell-back-squat")
    let squat = GuideMotion.movingSegments(of: squatGuide)
    #expect(squat.isSuperset(of: [.thigh, .shin, .thighFar, .shinFar]))
    #expect(squat.isDisjoint(with: [.upperArm, .forearm, .upperArmFar, .forearmFar]))

    for slug in ["barbell-bench-press", "seated-cable-row", "dumbbell-lateral-raise"] {
        let guide = try GuideTestSupport.bundleGuide(slug)
        let moving = GuideMotion.movingSegments(of: guide)
        #expect(moving.isSuperset(of: [.upperArm, .forearm]), "\(slug): \(moving)")
        #expect(moving.isDisjoint(with: [.trunk, .thigh, .shin]), "\(slug): \(moving)")
    }

    // moving do JSON sobrepõe o cálculo e vale também para o lado de lá
    let plankGuide = try GuideTestSupport.guide(GuideTestSupport.plankJSON)
    let plank = GuideMotion.movingSegments(of: plankGuide)
    #expect(plank == [.trunk])
    let overrideJSON = try GuideTestSupport.replacing(GuideTestSupport.plankJSON, "\"moving\": [\"trunk\"]", "\"moving\": [\"trunk\", \"thigh\"]")
    let override = try GuideTestSupport.guide(overrideJSON)
    #expect(GuideMotion.movingSegments(of: override) == [.trunk, .thigh, .thighFar])
}

@Test("E9 seta: 41 pontos pelo caminho da ida, afastados do ponto seguido; vazia sem cue")
func guideKinematicsCuePath() throws {
    let catalog = try GuideTestSupport.bundleCatalog()
    for guide in catalog.guides {
        let path = GuideMotion.cuePath(of: guide)
        // A seta é obrigatória em "loop" e opcional em "static" (§2.5): sem cue, o caminho é vazio.
        if guide.cue == nil {
            #expect(guide.motion == .still, "\(guide.slug): loop sem seta")
            #expect(path.isEmpty, "\(guide.slug)")
        } else {
            #expect(path.count == 41, "\(guide.slug)")
            #expect(path.allSatisfy { $0.isFinite }, "\(guide.slug)")
        }
    }
    // o agachamento segue o quadril, com offset [-0,082, 0] e span [0, 0,97]: o primeiro ponto é o quadril em t = 0
    let squat = try GuideTestSupport.bundleGuide("barbell-back-squat")
    let first = try #require(GuideMotion.cuePath(of: squat).first)
    let hip = try #require(GuideKinematics.skeleton(of: squat, at: 0).points[.hip])
    #expect(nearlyEqual(first, hip + GuidePoint(x: -0.082, y: 0)))
    let plank = try GuideTestSupport.guide(GuideTestSupport.plankJSON)
    #expect(GuideMotion.cuePath(of: plank).isEmpty)
}
