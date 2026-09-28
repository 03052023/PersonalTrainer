import SwiftUI

/// A moldura da flor principal da primeira tela (docs/V23-UI-CONTRACT.md §3.2): a abertura (`Features/Launch`)
/// põe a florzinha de verdade nesse lugar antes de sair, para a cor da pétala do objetivo "passar" da flor
/// grande para a da tela (protótipo `docs/design/v23-animation/launch.html`, detalhe "Pétala do objetivo").
///
/// Congelado: a tela inicial publica com `publishesGoalFlowerAnchor()` na sua `FlowerView` e a abertura lê
/// com `overlayPreferenceValue(GoalFlowerAnchorKey.self)`. Só a primeira flor publicada vale.
struct GoalFlowerAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? {
        nil
    }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if value == nil {
            value = nextValue()
        }
    }
}

extension View {
    /// Publica a moldura desta view como a da flor principal da tela.
    func publishesGoalFlowerAnchor() -> some View {
        anchorPreference(key: GoalFlowerAnchorKey.self, value: .bounds) { anchor in
            Optional(anchor)
        }
    }
}
