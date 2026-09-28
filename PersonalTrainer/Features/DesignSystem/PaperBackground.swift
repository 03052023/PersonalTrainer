import SwiftUI

/// Superfícies da direção Tinta e papel (DESIGN §14; docs/V23-UI-CONTRACT.md §3.2).
///
/// Andaime do arquiteto: as assinaturas são o contrato entre a tarefa `ink` (dona, que desenha a fibra de
/// washi e o fio dos cartões) e as telas das outras tarefas, que só chamam os modificadores. Até lá, o
/// fundo é liso e o cartão é o `surface` de sempre.
extension View {
    /// Fundo de papel da tela inteira, por baixo das áreas seguras: `Theme.background` com a fibra de
    /// washi bem leve (some com Aumentar Contraste). Use no lugar de `.background(Theme.background)` na
    /// raiz de cada tela.
    func paperBackground() -> some View {
        background(Theme.background)
    }

    /// Cartão de papel novo: `Theme.surface` com canto contínuo de `cornerRadius` e, na versão da `ink`, um
    /// fio fino em `Theme.line`. Não acrescenta espaçamento: quem chama põe o `padding` antes.
    func inkCard(cornerRadius: CGFloat = 16) -> some View {
        background(Theme.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
