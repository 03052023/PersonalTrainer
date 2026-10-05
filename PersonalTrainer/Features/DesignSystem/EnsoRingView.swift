import SwiftUI

/// O descanso como um ensō (DESIGN §14; docs/V23-UI-CONTRACT.md §4.1 item 5): um traço de pincel aberto
/// (vão de cerca de 30°) que se pinta conforme o tempo passa, começando mais grosso e afinando, com os
/// últimos 8 % do traço pintado em "branco voador" (três fios finos, com falhas fixas). `progress` vai
/// de 0 (nada pintado) a 1 (o traço inteiro, menos o vão); quem chama passa a fração do descanso que já
/// passou e anima esse valor no próprio ritmo (esta view não tem animação própria).
struct EnsoRingView: View {
    let progress: Double
    let diameter: CGFloat

    init(progress: Double, diameter: CGFloat = 48) {
        self.progress = progress
        self.diameter = diameter
    }

    /// `progress` limitado a 0…1 (`testEnso_progressIsClamped`).
    var clampedProgress: Double {
        min(1, max(0, progress))
    }

    /// Vão do traço, sempre no mesmo lugar (embaixo): `0` = topo, sentido horário, como a
    /// `BrisaGeometry` — o traço começa logo depois do vão e vai quase a volta toda.
    private static let gapDegrees: Double = 30
    private static let sweepDegrees: Double = 360 - gapDegrees
    private static let startDegrees: Double = 180 + gapDegrees / 2
    /// Do traço já pintado, não do vão inteiro: "os últimos 8 % do traço pintado" (DESIGN §14).
    private static let flyingWhiteFraction: Double = 0.08
    private static let bodySegments = 24

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxWidth = diameter * 0.11
            let minWidth = diameter * 0.035
            let trackWidth = diameter * 0.05
            let radius = min(size.width, size.height) / 2 - maxWidth / 2

            // Trilho: o vão inteiro (330°), sempre visível, por baixo do traço pintado.
            context.stroke(
                Self.arcPath(center: center, radius: radius, startDegrees: Self.startDegrees, sweepDegrees: Self.sweepDegrees),
                with: .color(Theme.line),
                style: StrokeStyle(lineWidth: trackWidth, lineCap: .round)
            )

            let paintedSweep = Self.sweepDegrees * clampedProgress
            guard paintedSweep > 0 else { return }
            let flyingWhiteSweep = paintedSweep * Self.flyingWhiteFraction
            let solidSweep = paintedSweep - flyingWhiteSweep

            // Corpo do traço: segmentado, afinando de `maxWidth` a `minWidth` (Canvas não faz um
            // traço de espessura variável numa só chamada; muitos arcos curtos simulam o pincel).
            if solidSweep > 0 {
                for i in 0..<Self.bodySegments {
                    let a0 = Self.startDegrees + solidSweep * Double(i) / Double(Self.bodySegments)
                    let a1 = Self.startDegrees + solidSweep * Double(i + 1) / Double(Self.bodySegments)
                    guard a1 > a0 else { continue }
                    let widthFraction = (Double(i) + 0.5) / Double(Self.bodySegments)
                    let width = maxWidth + (minWidth - maxWidth) * CGFloat(widthFraction)
                    context.stroke(
                        Self.arcPath(center: center, radius: radius, startDegrees: a0, sweepDegrees: a1 - a0),
                        with: .color(Theme.accent),
                        style: StrokeStyle(lineWidth: width, lineCap: .round)
                    )
                }
            }

            // Branco voador: 3 fios finos, cada um com o próprio traço/vão fixo, levemente separados
            // em raio para não colarem num traço só.
            if flyingWhiteSweep > 0 {
                let radiusStep = maxWidth * 0.18
                let threads: [(radiusOffset: CGFloat, dash: [CGFloat], phase: CGFloat)] = [
                    (-radiusStep, [3, 2.2], 0),
                    (0, [2.2, 1.6], 0.9),
                    (radiusStep, [3.6, 2.4], 1.8),
                ]
                let startAngle = Self.startDegrees + solidSweep
                for thread in threads {
                    context.stroke(
                        Self.arcPath(center: center, radius: radius + thread.radiusOffset, startDegrees: startAngle, sweepDegrees: flyingWhiteSweep),
                        with: .color(Theme.accent.opacity(0.85)),
                        style: StrokeStyle(lineWidth: minWidth * 0.4, lineCap: .round, dash: thread.dash, dashPhase: thread.phase)
                    )
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    /// Um arco em graus (`0` = topo, sentido horário, como o resto do app) convertido para o ângulo
    /// matemático que `Path.addArc` espera (`0` = direita).
    private static func arcPath(center: CGPoint, radius: CGFloat, startDegrees: Double, sweepDegrees: Double) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startDegrees - 90),
            endAngle: .degrees(startDegrees + sweepDegrees - 90),
            clockwise: false
        )
        return path
    }
}
