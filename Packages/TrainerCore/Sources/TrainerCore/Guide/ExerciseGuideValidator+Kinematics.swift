import Foundation

// E4, E5, E6 e E10 em t = 0, 0,05, …, n − 1 (docs/V23-CORE-CONTRACT.md §2.5), como o `Test-Kinematics` da
// ferramenta. Cada regra aparece no máximo uma vez por guia (e, no E10, por articulação), no primeiro t que falha.
extension ExerciseGuideValidator {
    /// Folga numérica das faixas do E10: uma pose desenhada bem na borda não pode passar num lado e falhar no outro.
    static let jointTolerance = 1e-6

    /// Faixas das articulações possíveis (SPEC E10), com o ângulo relativo em (−180°, 180°].
    enum JointRange {
        /// Joelho, `shin − thigh`: de −165° a 5°.
        case knee
        /// Tornozelo, `foot − shin`: de 0° a 140°.
        case ankle
        /// Pescoço, `neck − trunk`: de −60° a 60°.
        case neck
        /// Quadril, `thigh − trunk`: de 150° a 180° ou de −180° a −25°.
        case hip

        func contains(_ value: Double) -> Bool {
            let slack = ExerciseGuideValidator.jointTolerance
            switch self {
            case .knee:
                return value >= -165 - slack && value <= 5 + slack
            case .ankle:
                return value >= 0 - slack && value <= 140 + slack
            case .neck:
                return value >= -60 - slack && value <= 60 + slack
            case .hip:
                return (value >= 150 - slack && value <= 180 + slack) || (value >= -180 - slack && value <= -25 + slack)
            }
        }

        var accepted: String {
            switch self {
            case .knee: return "de -165° a 5°"
            case .ankle: return "de 0° a 140°"
            case .neck: return "de -60° a 60°"
            case .hip: return "de 150° a 180° ou de -180° a -25°"
            }
        }
    }

    static func decimal(_ value: Double, places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    static func checkKinematics(_ guide: ExerciseGuide, into collector: inout GuideProblemCollector) {
        let last = guide.frames.count - 1
        guard last >= 0 else {
            return
        }
        let isFront = guide.view == .front
        let usesIK = !isFront && guide.arms?.reach != nil
        var reported = Set<String>()
        for step in 0...(20 * last) {
            let t = Double(step) / 20
            let solution = GuideKinematics.solve(guide, at: t)
            let points = solution.points
            let finite = points.values.allSatisfy { $0.isFinite } && solution.props.values.allSatisfy { $0.isFinite }
            if !finite {
                // com uma coordenada não finita, as outras contas não dizem nada: para aqui
                collector.add("E4", "coordenada não finita em t = \(decimal(t, places: 2))")
                return
            }
            if !reported.contains("E5"), let joint = guide.anchor.point, let at = guide.anchor.at {
                let drift = points[joint].map { $0.distance(to: at) } ?? Double.infinity
                if drift > GuideRig.anchorTolerance {
                    collector.add("E5", "a âncora \(joint.rawValue) sai do lugar em t = \(decimal(t, places: 2))")
                    reported.insert("E5")
                }
            }
            if usesIK && !reported.contains("E6") {
                if let problem = reachProblem(guide, solution: solution, t: t) {
                    collector.add("E6", problem)
                    reported.insert("E6")
                }
            }
            if !isFront {
                checkJoints(solution.skeleton, t: t, reported: &reported, into: &collector)
            }
        }
    }

    /// E6: a mão chega ao alvo alcançável; com o antebraço travado, o braço nunca estica além do comprimento.
    static func reachProblem(_ guide: ExerciseGuide, solution: GuideKinematics.Solution, t: Double) -> String? {
        guard let shoulder = solution.points[.shoulder] else {
            return nil
        }
        if guide.arms?.forearm != nil {
            guard let elbow = solution.points[.elbow] else {
                return nil
            }
            let need = elbow.distance(to: shoulder)
            if need > GuideRig.upperArm + GuideRig.reachTolerance {
                return "com o antebraço travado, o braço precisaria medir \(decimal(need, places: 3)) H em t = \(decimal(t, places: 2)) (máx. \(GuideRig.upperArm))"
            }
            return nil
        }
        guard let target = solution.ikTarget, let hand = solution.points[.hand] else {
            return nil
        }
        let distance = target.distance(to: shoulder)
        let shortest = abs(solution.upperArmLength - solution.reachLength)
        let longest = solution.upperArmLength + solution.reachLength
        guard distance >= shortest && distance <= longest else {
            return nil
        }
        let miss = hand.distance(to: target)
        if miss > GuideRig.reachTolerance {
            return "a mão fica a \(decimal(miss, places: 3)) H do alvo em t = \(decimal(t, places: 2))"
        }
        return nil
    }

    /// E10 na vista lateral, nos dois lados, com os ângulos medidos nos pontos resolvidos.
    static func checkJoints(
        _ skeleton: GuideSkeleton,
        t: Double,
        reported: inout Set<String>,
        into collector: inout GuideProblemCollector
    ) {
        guard let trunk = skeleton.angle(of: .trunk), let head = skeleton.angle(of: .head) else {
            return
        }
        var checks: [(key: String, name: String, value: Double, range: JointRange)] = [
            (key: "neck", name: "pescoço", value: GuideKinematics.normalized(head - trunk), range: .neck),
        ]
        let sides: [(limb: GuideKinematics.Limb, suffix: String, name: String)] = [
            (limb: GuideKinematics.Limb.near, suffix: "", name: "lado de cá"),
            (limb: GuideKinematics.Limb.far, suffix: "Far", name: "lado de lá"),
        ]
        for side in sides {
            guard let thigh = skeleton.angle(of: side.limb.thighSegment),
                  let shin = skeleton.angle(of: side.limb.shinSegment),
                  let foot = skeleton.angle(of: side.limb.footSegment) else {
                continue
            }
            checks.append((key: "knee" + side.suffix, name: "joelho (\(side.name))", value: GuideKinematics.normalized(shin - thigh), range: .knee))
            checks.append((key: "ankle" + side.suffix, name: "tornozelo (\(side.name))", value: GuideKinematics.normalized(foot - shin), range: .ankle))
            checks.append((key: "hip" + side.suffix, name: "quadril (\(side.name))", value: GuideKinematics.normalized(thigh - trunk), range: .hip))
        }
        for check in checks {
            let key = "E10" + check.key
            guard !reported.contains(key), !check.range.contains(check.value) else { continue }
            collector.add(
                "E10",
                "\(check.name) em \(decimal(check.value, places: 1))° em t = \(decimal(t, places: 2)) (aceito \(check.range.accepted))"
            )
            reported.insert(key)
        }
    }
}
