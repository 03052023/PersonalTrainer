import SwiftUI

/// Aguada de montanha para o canto de cima da tela inicial (DESIGN §14; docs/V23-UI-CONTRACT.md §3.2): uma
/// montanha em tinta muito diluída, parada, que ocupa o espaço que a view receber. Só decorativa.
///
/// Andaime do arquiteto: a assinatura é o contrato entre a tarefa `ink` (dona, que desenha a aguada) e a
/// `home`, que só a posiciona. Até lá, não desenha nada.
struct MountainWashView: View {
    init() {}

    var body: some View {
        Color.clear
            .accessibilityHidden(true)
    }
}
