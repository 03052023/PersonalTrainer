import SwiftUI

/// Superfícies da direção Tinta e papel (DESIGN §14; docs/V23-UI-CONTRACT.md §4.1 itens 2 e 3).
extension View {
    /// Fundo de papel da tela inteira, por baixo das áreas seguras: `Theme.background` com a fibra de
    /// washi (`PaperFiber.imageset`, gerada por `docs/design/v23-ink/render-paper-fiber.ps1`) ladrilhada
    /// a 4 %. A fibra some com Aumentar Contraste (`colorSchemeContrast == .increased`), como o papel
    /// liso que a decisão pede. Use no lugar de `.background(Theme.background)` na raiz de cada tela.
    func paperBackground() -> some View {
        background(PaperBackgroundLayer())
    }

    /// Cartão de papel novo: `Theme.surface` com canto contínuo de `cornerRadius` e um fio fino em
    /// `Theme.line` (1 pt em `Theme.textSecondary` com Aumentar Contraste, DESIGN §3/§14). Sem sombra.
    /// Não acrescenta espaçamento: quem chama põe o `padding` antes.
    func inkCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(InkCardModifier(cornerRadius: cornerRadius))
    }
}

/// A camada de fundo de `paperBackground()`: o washi liso e, por cima, a fibra ladrilhada bem sutil.
/// Só decorativa (`accessibilityHidden`); nunca recebe toque (`allowsHitTesting(false)`), para não
/// atrapalhar gestos da tela que a usa como fundo.
private struct PaperBackgroundLayer: View {
    @Environment(\.colorSchemeContrast) private var contrast

    /// DESIGN §14: "a 4 %". Aplicado sobre a imagem inteira (que já tem a fibra bem mais forte —
    /// docs/design/v23-ink/render-paper-fiber.ps1), não sobre cada fibra isolada.
    private static let fiberOpacity: Double = 0.04

    var body: some View {
        ZStack {
            Theme.background
            if contrast != .increased {
                // "PaperFiber" resolve sozinha entre claro/escuro pelas `appearances` do
                // `Contents.json` (mesmo truque do `AppIcon-dark.png`); nada de escolher o nome aqui.
                Image("PaperFiber")
                    .resizable(resizingMode: .tile)
                    .opacity(Self.fiberOpacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// O cartão de papel de `inkCard(cornerRadius:)`. Em `ViewModifier` (não só num `background(_:in:)`)
/// porque o fio muda de cor e espessura com Aumentar Contraste (`@Environment`), o que um modificador
/// de função livre não consegue ler.
private struct InkCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let highContrast = contrast == .increased
        content
            .background(Theme.surface, in: shape)
            .overlay(
                shape.stroke(highContrast ? Theme.textSecondary : Theme.line, lineWidth: highContrast ? 1 : 0.5)
            )
    }
}
