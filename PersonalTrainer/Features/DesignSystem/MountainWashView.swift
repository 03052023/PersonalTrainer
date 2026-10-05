import SwiftUI

/// Aguada de montanha para o canto de cima da tela inicial (DESIGN §14; docs/V23-UI-CONTRACT.md §4.1
/// item 7): duas silhuetas de montanha em curvas, em `Theme.textPrimary` a 7 % e 4 %, com a base
/// esmaecendo por degradê. Parada (sem animação própria), só decorativa. Ocupa o quadro que a view
/// receber (`home` posiciona; DESIGN §9.1: cerca de 55 % da largura, 140 pt de altura).
struct MountainWashView: View {
    init() {}

    var body: some View {
        Canvas { context, size in
            for layer in Self.layers {
                let path = Self.path(for: layer.ridge, size: size)
                let gradient = Gradient(stops: [
                    .init(color: Theme.textPrimary.opacity(layer.peakOpacity), location: 0),
                    .init(color: Theme.textPrimary.opacity(0), location: 1),
                ])
                context.fill(
                    path,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: size.width / 2, y: size.height * layer.gradientStart),
                        endPoint: CGPoint(x: size.width / 2, y: size.height)
                    )
                )
            }
        }
        .accessibilityHidden(true)
    }

    /// Uma cadeia de montanhas (DESIGN §14): `ridge` é a linha do cume, em pontos unitários (0…1 de
    /// largura/altura do quadro recebido); `peakOpacity` é a opacidade no cume, que o degradê linear
    /// esmaece até 0 na base (`gradientStart` marca em que fração da altura o degradê começa a cair).
    private struct MountainLayer {
        let ridge: [(x: Double, y: Double)]
        let peakOpacity: Double
        let gradientStart: Double
    }

    /// Um cume só com bossas gaussianas (determinístico, sem `Get-Random`): cada pico é
    /// `height · exp(-((x - center) / width)²)`, subtraído de uma linha de base. Números fixos à mão,
    /// como a ondulação da `BrisaGeometry`.
    private static func ridge(
        baseline: Double,
        peaks: [(center: Double, height: Double, width: Double)],
        samples: Int = 48
    ) -> [(x: Double, y: Double)] {
        (0...samples).map { i in
            let x = Double(i) / Double(samples)
            var y = baseline
            for peak in peaks {
                let d = (x - peak.center) / peak.width
                y -= peak.height * exp(-d * d)
            }
            return (x, y)
        }
    }

    /// A mais ao fundo (mais diluída) primeiro, depois a mais perto (um pouco mais forte), com os
    /// cumes deslocados entre si para não parecerem uma cópia só.
    private static let layers: [MountainLayer] = [
        MountainLayer(
            ridge: ridge(
                baseline: 0.62,
                peaks: [
                    (center: 0.16, height: 0.24, width: 0.20),
                    (center: 0.52, height: 0.32, width: 0.24),
                    (center: 0.86, height: 0.20, width: 0.18),
                ]
            ),
            peakOpacity: 0.04,
            gradientStart: 0.30
        ),
        MountainLayer(
            ridge: ridge(
                baseline: 0.80,
                peaks: [
                    (center: 0.04, height: 0.18, width: 0.16),
                    (center: 0.38, height: 0.36, width: 0.22),
                    (center: 0.70, height: 0.26, width: 0.18),
                    (center: 0.97, height: 0.14, width: 0.14),
                ]
            ),
            peakOpacity: 0.07,
            gradientStart: 0.55
        ),
    ]

    /// Fecha a linha do cume por baixo (borda inferior do quadro) para virar uma silhueta preenchível.
    private static func path(for ridge: [(x: Double, y: Double)], size: CGSize) -> Path {
        var path = Path()
        guard let first = ridge.first else { return path }
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for point in ridge.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.addLine(to: CGPoint(x: 0, y: size.height))
        path.closeSubpath()
        return path
    }
}
