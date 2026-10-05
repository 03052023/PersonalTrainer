import Foundation

/// Bézier cúbica unitária (P0 = (0,0), P3 = (1,1)), no mesmo formato do CSS `cubic-bezier()` e do
/// protótipo aprovado (`docs/design/v23-animation/launch.html`, função `bezier`): dados os dois
/// pontos de controle, resolve `t` a partir de `x` por Newton-Raphson (com bisseção como recurso,
/// exatamente como no protótipo) e devolve `y`. Sem estado, determinístico (SPEC RF-50).
///
/// Implementado à mão (em vez de `UnitCurve` do SwiftUI, iOS 17+) para reproduzir bit a bit a mesma
/// conta do protótipo, que é a fonte dos números desta abertura, e para não depender de uma API que
/// não dá para conferir sem o CI (AGENTS R11).
struct LaunchCurve: Sendable {
    private let ax: Double
    private let bx: Double
    private let cx: Double
    private let ay: Double
    private let by: Double
    private let cy: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        cx = 3 * x1
        bx = 3 * (x2 - x1) - cx
        ax = 1 - cx - bx
        cy = 3 * y1
        by = 3 * (y2 - y1) - cy
        ay = 1 - cy - by
    }

    private func sampleX(_ t: Double) -> Double {
        ((ax * t + bx) * t + cx) * t
    }

    private func sampleY(_ t: Double) -> Double {
        ((ay * t + by) * t + cy) * t
    }

    private func sampleDerivativeX(_ t: Double) -> Double {
        (3 * ax * t + 2 * bx) * t + cx
    }

    /// `y` na fração `x` do trajeto (0...1); fora do intervalo, fixado em 0 ou 1 (o protótipo faz o
    /// mesmo em `seg`, então `x` chega sempre grampeado, mas a função fica segura de qualquer jeito).
    func value(at x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }

        var t = x
        for _ in 0..<8 {
            let error = sampleX(t) - x
            let derivative = sampleDerivativeX(t)
            if abs(error) < 1e-6 || abs(derivative) < 1e-6 { break }
            t -= error / derivative
        }
        if !(t >= 0 && t <= 1) || abs(sampleX(t) - x) > 1e-5 {
            var lo = 0.0
            var hi = 1.0
            t = x
            for _ in 0..<40 {
                if sampleX(t) < x { lo = t } else { hi = t }
                t = (lo + hi) / 2
            }
        }
        return sampleY(t)
    }
}
