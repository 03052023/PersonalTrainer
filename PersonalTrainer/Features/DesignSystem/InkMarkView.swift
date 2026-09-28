import SwiftUI

/// A marca de tinta de uma meta (DESIGN §9.2 e §14; SPEC §7.16 W3; docs/V23-UI-CONTRACT.md §4.1 item 6):
/// o mesmo pincel do `EnsoRingView`, agora reto e da esquerda para a direita — começa mais grosso e afina,
/// pintado até `progress` na cor `tint`, com os últimos 8 % do traço pintado em "branco voador". O trilho
/// fica em `Theme.line`; sem dado (`hasData` falso), só o trilho pontilhado aparece, o que não é falha.
/// Ocupa a largura que receber, 6 pt de altura. Só decorativa (`accessibilityHidden`); quem chama dá o
/// texto e o rótulo do VoiceOver.
struct InkMarkView: View {
    let progress: Double
    let tint: Color
    let hasData: Bool

    init(progress: Double, tint: Color = Theme.inkMuted, hasData: Bool = true) {
        self.progress = progress
        self.tint = tint
        self.hasData = hasData
    }

    /// `progress` limitado a 0…1 (`testInkMark_progressIsClamped`).
    var clampedProgress: Double {
        min(1, max(0, progress))
    }

    private static let height: CGFloat = 6
    private static let trackLineWidth: CGFloat = 1
    private static let maxLineWidth: CGFloat = 5
    private static let minLineWidth: CGFloat = 2
    /// Do traço já pintado, não da largura inteira (DESIGN §14, mesma ideia do ensō).
    private static let flyingWhiteFraction: Double = 0.08
    private static let bodySegments = 14

    var body: some View {
        Canvas { context, size in
            let y = size.height / 2

            var trackPath = Path()
            trackPath.move(to: CGPoint(x: 0, y: y))
            trackPath.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(
                trackPath,
                with: .color(Theme.line),
                style: StrokeStyle(lineWidth: Self.trackLineWidth, lineCap: .round, dash: hasData ? [] : [3, 3])
            )

            guard hasData else { return }
            let painted = size.width * CGFloat(clampedProgress)
            guard painted > 0 else { return }
            let flyingWhiteLength = painted * CGFloat(Self.flyingWhiteFraction)
            let solidLength = painted - flyingWhiteLength

            if solidLength > 0 {
                for i in 0..<Self.bodySegments {
                    let x0 = solidLength * CGFloat(i) / CGFloat(Self.bodySegments)
                    let x1 = solidLength * CGFloat(i + 1) / CGFloat(Self.bodySegments)
                    guard x1 > x0 else { continue }
                    var segment = Path()
                    segment.move(to: CGPoint(x: x0, y: y))
                    segment.addLine(to: CGPoint(x: x1, y: y))
                    let widthFraction = (Double(i) + 0.5) / Double(Self.bodySegments)
                    let lineWidth = Self.maxLineWidth + (Self.minLineWidth - Self.maxLineWidth) * CGFloat(widthFraction)
                    context.stroke(segment, with: .color(tint), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }

            if flyingWhiteLength > 0 {
                let threads: [(offset: CGFloat, dash: [CGFloat], phase: CGFloat)] = [
                    (-Self.minLineWidth * 0.5, [2, 1.4], 0),
                    (0, [1.6, 1.2], 0.6),
                    (Self.minLineWidth * 0.5, [2.4, 1.6], 1.2),
                ]
                for thread in threads {
                    var threadPath = Path()
                    threadPath.move(to: CGPoint(x: solidLength, y: y + thread.offset))
                    threadPath.addLine(to: CGPoint(x: painted, y: y + thread.offset))
                    context.stroke(
                        threadPath,
                        with: .color(tint.opacity(0.85)),
                        style: StrokeStyle(lineWidth: Self.minLineWidth * 0.4, lineCap: .round, dash: thread.dash, dashPhase: thread.phase)
                    )
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}
