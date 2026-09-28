import Foundation

// Vetor 2D do cálculo normativo (a classe V2 de docs/design/exercise-guides/render-exercise-guides.ps1). As contas
// seguem a mesma ordem das do script, para o GuideGoldenTests comparar os dois em até 0,001 H.
extension GuidePoint {
    public static let zero = GuidePoint(x: 0, y: 0)

    public static func + (lhs: GuidePoint, rhs: GuidePoint) -> GuidePoint {
        GuidePoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func - (lhs: GuidePoint, rhs: GuidePoint) -> GuidePoint {
        GuidePoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func * (lhs: GuidePoint, rhs: Double) -> GuidePoint {
        GuidePoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }

    public func dot(_ other: GuidePoint) -> Double {
        x * other.x + y * other.y
    }

    public var length: Double {
        (x * x + y * y).squareRoot()
    }

    /// Vetor unitário; o vetor nulo vira (1, 0), como no script, para nenhuma conta produzir NaN (E6).
    public var unit: GuidePoint {
        let size = length
        if size < 1e-9 {
            return GuidePoint(x: 1, y: 0)
        }
        return GuidePoint(x: x / size, y: y / size)
    }

    /// Girado +90°.
    public var perpendicular: GuidePoint {
        GuidePoint(x: -y, y: x)
    }

    public func rotated(by degrees: Double) -> GuidePoint {
        let radians = degrees * Double.pi / 180
        let cosine = cos(radians)
        let sine = sin(radians)
        return GuidePoint(x: x * cosine - y * sine, y: x * sine + y * cosine)
    }

    public func distance(to other: GuidePoint) -> Double {
        (self - other).length
    }

    public var isFinite: Bool {
        x.isFinite && y.isFinite
    }

    /// Direção unitária de um ângulo absoluto em graus (0 = direita, 90 = cima).
    public static func direction(_ degrees: Double) -> GuidePoint {
        let radians = degrees * Double.pi / 180
        return GuidePoint(x: cos(radians), y: sin(radians))
    }

    public static func lerp(_ from: GuidePoint, _ to: GuidePoint, _ fraction: Double) -> GuidePoint {
        GuidePoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)
    }
}
