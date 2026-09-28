import SwiftUI

/// A marca de tinta de uma meta (DESIGN §9.2 e §14; SPEC §7.16 W3; docs/V23-UI-CONTRACT.md §3.2): um traço de
/// pincel horizontal que se pinta da esquerda para a direita conforme `progress` (0 = nada, 1 = a meta
/// cumprida). Sem dado (`hasData` falso), só o trilho pontilhado, que não é falha. Ocupa a largura que receber.
///
/// Andaime do arquiteto: a assinatura é o contrato entre a tarefa `ink` (dona, que desenha o pincel, com o
/// começo mais grosso e o "branco voador" no fim, como o ensō) e a `home`, que só usa a view nas Metas da
/// semana. Até lá, é uma linha simples. Só decorativa: quem chama dá o texto e o rótulo do VoiceOver.
struct InkMarkView: View {
    let progress: Double
    let tint: Color
    let hasData: Bool

    init(progress: Double, tint: Color = Theme.inkMuted, hasData: Bool = true) {
        self.progress = progress
        self.tint = tint
        self.hasData = hasData
    }

    private static let height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let fraction = CGFloat(min(1, max(0, progress)))
            ZStack(alignment: .leading) {
                Capsule()
                    .stroke(
                        Theme.line,
                        style: StrokeStyle(lineWidth: 1, dash: hasData ? [] : [3, 3])
                    )
                if hasData {
                    Capsule()
                        .fill(tint)
                        .frame(width: proxy.size.width * fraction)
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}
