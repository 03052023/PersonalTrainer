import SwiftUI

/// O descanso como um ensō (DESIGN §14; docs/V23-UI-CONTRACT.md §3.2): um traço de pincel aberto que se
/// pinta conforme o tempo passa. `progress` vai de 0 (nada pintado) a 1 (o traço inteiro); quem chama
/// passa a fração do descanso que já passou.
///
/// Andaime do arquiteto: a assinatura é o contrato entre a tarefa `ink` (dona, que desenha o pincel, com o
/// começo mais grosso e o "branco voador" no fim) e a `session`, que só usa a view. Até lá, é um arco
/// simples. Só decorativo: quem chama dá o rótulo do VoiceOver.
struct EnsoRingView: View {
    let progress: Double
    let diameter: CGFloat

    init(progress: Double, diameter: CGFloat = 48) {
        self.progress = progress
        self.diameter = diameter
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.line, lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}
