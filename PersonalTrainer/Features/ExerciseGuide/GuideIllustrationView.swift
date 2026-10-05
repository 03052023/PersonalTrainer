import SwiftUI
import TrainerCore

/// A figura animada do "Como fazer" (SPEC RF-40 a, §7.12 E4, E7 e E9; DESIGN §12): `TimelineView(.animation)` dá o
/// relógio, `GuideTiming.frameTime` converte os segundos no instante do movimento e a `Canvas` pinta a pose com o
/// `GuidePainter`, o mesmo desenho da folha de revisão.
///
/// Na ida, a seta mostra o caminho e some aos poucos enquanto a figura se move; perto do fim, a posição inicial
/// aparece em fantasma. A animação para com `isPaused` (Pausar), quando a view sai da tela (a folha fecha) e não
/// roda com Reduzir Movimento nem em `motion: "static"`: quem apresenta mostra `GuideStaticFramesView` no lugar
/// (SPEC E7).
///
/// Para o VoiceOver é um elemento só, com a descrição da guia (`a11y`).
struct GuideIllustrationView: View {
    private let figure: GuideFigure
    private let isPaused: Bool

    @Environment(\.colorScheme) private var colorScheme
    /// Origem do relógio da animação; `nil` até aparecer (o primeiro quadro é o inicial).
    @State private var startDate: Date? = nil
    /// Segundos mostrados enquanto pausado.
    @State private var frozenSeconds: Double = 0

    init(figure: GuideFigure, isPaused: Bool) {
        self.figure = figure
        self.isPaused = isPaused
    }

    var body: some View {
        let ink = GuideInk.make(dark: colorScheme == .dark)
        let figure = self.figure
        let isPaused = self.isPaused
        let frozen = frozenSeconds
        let origin = startDate
        TimelineView(.animation(minimumInterval: nil, paused: isPaused)) { timeline in
            let seconds = isPaused ? frozen : GuideIllustrationView.elapsed(from: origin, to: timeline.date)
            Canvas { context, size in
                let rect = CGRect(origin: .zero, size: size)
                let camera = GuideCamera(fitting: figure.bounds, in: rect)
                let painter = GuidePainter(figure: figure, ink: ink, camera: camera)
                let t = GuideTiming.frameTime(of: figure.guide, atSeconds: seconds)
                painter.draw(
                    in: context,
                    rect: rect,
                    at: t,
                    ghostOpacity: GuideIllustrationView.ghostOpacity(at: t, last: figure.lastFrameTime),
                    cueOpacity: GuideIllustrationView.cueOpacity(at: t, last: figure.lastFrameTime)
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(figure.guide.a11y))
        .accessibilityAddTraits(.isImage)
        .onAppear {
            if startDate == nil {
                startDate = Date()
            }
        }
        .onChange(of: isPaused) { _, paused in
            let now = Date()
            if paused {
                frozenSeconds = GuideIllustrationView.elapsed(from: startDate, to: now)
            } else {
                // Continua de onde parou.
                startDate = now.addingTimeInterval(-frozenSeconds)
            }
        }
    }

    // MARK: - Tempo e sinais (puros)

    static func elapsed(from origin: Date?, to date: Date) -> Double {
        guard let origin else {
            return 0
        }
        return max(0, date.timeIntervalSince(origin))
    }

    /// A seta aparece no quadro inicial e some no primeiro terço da ida (SPEC E9: o caminho da ida).
    static func cueOpacity(at t: Double, last: Double) -> Double {
        guard last > 0 else {
            return 1
        }
        let fraction = t / (last * 0.35)
        return max(0, min(1, 1 - fraction))
    }

    /// O fantasma da posição inicial cresce à medida que a figura se afasta dela e fica inteiro no fim.
    static func ghostOpacity(at t: Double, last: Double) -> Double {
        guard last > 0 else {
            return 0
        }
        return max(0, min(1, t / last))
    }
}
