import SwiftUI
import TrainerCore

/// Os quadros do "Como fazer" parados, lado a lado (SPEC RF-40, §7.12 E7 e E9; DESIGN §12): com Reduzir Movimento
/// e nas guias `motion: "static"`. Cada quadro tem o número e a legenda embaixo; a seta do caminho fica no
/// primeiro, e nos seguintes a posição inicial aparece em fantasma (só em `loop`: `static` não desenha fantasma).
///
/// Mesmo desenho e mesma escala em todos os quadros (`GuidePainter` com o enquadramento do movimento inteiro). Para
/// o VoiceOver, a figura é um elemento só, com a descrição da guia; as legendas ficam de fora, porque a descrição
/// já conta o movimento.
struct GuideStaticFramesView: View {
    private let figure: GuideFigure

    @Environment(\.colorScheme) private var colorScheme

    init(figure: GuideFigure) {
        self.figure = figure
    }

    var body: some View {
        let ink = GuideInk.make(dark: colorScheme == .dark)
        let frames = Array(figure.guide.frames.enumerated())
        HStack(alignment: .top, spacing: 8) {
            ForEach(frames, id: \.offset) { pair in
                VStack(alignment: .leading, spacing: 6) {
                    panel(index: pair.offset, ink: ink)
                    caption(number: pair.offset + 1, text: pair.element.caption)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(figure.guide.a11y))
        .accessibilityAddTraits(.isImage)
    }

    private func panel(index: Int, ink: GuideInk) -> some View {
        let figure = self.figure
        let showsGhost = index > 0 && figure.guide.motion == .loop
        let showsCue = index == 0
        return Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let camera = GuideCamera(fitting: figure.bounds, in: rect)
            GuidePainter(figure: figure, ink: ink, camera: camera).draw(
                in: context,
                rect: rect,
                at: Double(index),
                ghostOpacity: showsGhost ? 1 : 0,
                cueOpacity: showsCue ? 1 : 0
            )
        }
        .aspectRatio(1, contentMode: .fit)
        // O quadro é da cor do fundo, como na folha: o fio que separa os segmentos (`GuideInk.background`) some nele.
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Legenda numerada, como na folha: o número num círculo em `accentSoft` e a legenda curta ao lado.
    private func caption(number: Int, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(String(number))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(minWidth: 20, minHeight: 20)
                .background(Theme.accentSoft, in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
