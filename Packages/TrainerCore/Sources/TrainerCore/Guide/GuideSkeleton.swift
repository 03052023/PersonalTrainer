import Foundation

/// A figura resolvida num instante: pontos do esqueleto e dos acessórios, em estaturas, no referencial do mundo
/// (docs/V23-CORE-CONTRACT.md §2.6). A tela só pinta isto.
public struct GuideSkeleton: Sendable, Hashable {
    public let points: [GuideJoint: GuidePoint]
    /// Por id do acessório; na vista frontal, um acessório na mão aparece também como "<id>Far". Cabos e elásticos
    /// não têm posição própria (vão de `from` a `to`).
    public let props: [String: GuidePoint]
    public let isFront: Bool

    public init(points: [GuideJoint: GuidePoint], props: [String: GuidePoint], isFront: Bool) {
        self.points = points
        self.props = props
        self.isFront = isFront
    }

    public subscript(joint: GuideJoint) -> GuidePoint? {
        points[joint]
    }

    /// Pontas resolvidas de um segmento, na vista desta figura.
    public func endpoints(of segment: GuideSegment) -> (proximal: GuidePoint, distal: GuidePoint)? {
        let names = segment.endpoints(in: isFront ? ExerciseGuide.Viewpoint.front : ExerciseGuide.Viewpoint.side)
        guard let proximal = points[names.proximal], let distal = points[names.distal] else {
            return nil
        }
        return (proximal: proximal, distal: distal)
    }

    /// Ângulo absoluto do segmento, em graus, medido nos pontos resolvidos (`atan2` entre as pontas).
    public func angle(of segment: GuideSegment) -> Double? {
        guard let ends = endpoints(of: segment) else {
            return nil
        }
        let delta = ends.distal - ends.proximal
        return atan2(delta.y, delta.x) * 180 / Double.pi
    }

    public func midpoint(of segment: GuideSegment) -> GuidePoint? {
        guard let ends = endpoints(of: segment) else {
            return nil
        }
        return GuidePoint.lerp(ends.proximal, ends.distal, 0.5)
    }
}
