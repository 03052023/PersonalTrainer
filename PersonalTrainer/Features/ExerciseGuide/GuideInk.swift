import SwiftUI
import UIKit

/// As cores da figura do "Como fazer" (DESIGN §12; SPEC E9), derivadas dos tokens do `Theme` com as mesmas
/// misturas da folha de revisão (`New-Ink` em `docs/design/exercise-guides/render-exercise-guides.ps1`): o que se
/// move em `accent` forte, o resto do corpo em `accent` misturado ao fundo, o lado de lá mais claro, o equipamento
/// que se move em `textSecondary`, a estrutura fixa ainda mais clara e a seta em `textPrimary`.
///
/// A mistura é feita componente a componente em sRGB, como no script (`Mix`). Os tokens são resolvidos para o modo
/// claro ou escuro com o `UITraitCollection` do instante; o valor é calculado uma vez por desenho, nunca por quadro.
struct GuideInk: Sendable, Hashable {
    /// Cor opaca em sRGB, de 0 a 1.
    struct RGB: Sendable, Hashable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
        }
    }

    /// Frações de cada tom que vão para o fundo (`$Mixes` do script). No escuro o `accent` já contrasta mais com o
    /// fundo, então as misturas são maiores para a figura manter a mesma hierarquia.
    struct Mixes: Sendable, Hashable {
        let farMove: Double
        let nearStill: Double
        let farStill: Double
        let ghostFill: Double
        let ghostLine: Double
        let structure: Double
        let structureSoft: Double
        let floor: Double

        static let light = Mixes(
            farMove: 0.25, nearStill: 0.56, farStill: 0.72, ghostFill: 0.90, ghostLine: 0.50,
            structure: 0.62, structureSoft: 0.76, floor: 0.60
        )
        static let dark = Mixes(
            farMove: 0.40, nearStill: 0.62, farStill: 0.76, ghostFill: 0.90, ghostLine: 0.52,
            structure: 0.64, structureSoft: 0.78, floor: 0.62
        )
    }

    /// Fundo do quadro (o papel): também a cor do fio que separa segmentos sobrepostos.
    let background: RGB
    /// O que se move, lado de cá e lado de lá (contraste de pelo menos 3:1).
    let nearMove: RGB
    let farMove: RGB
    /// O resto do corpo, lado de cá e lado de lá.
    let nearStill: RGB
    let farStill: RGB
    /// A posição inicial em fantasma: miolo quase fundo e contorno tracejado.
    let ghostFill: RGB
    let ghostLine: RGB
    /// O equipamento que se move (barra, anilha, halter, puxador, cabo).
    let equipment: RGB
    /// Estrutura fixa (estofado, assento, plataforma) e a parte mais clara dela (pés do banco, trilho, torre).
    let structure: RGB
    let structureSoft: RGB
    let floor: RGB
    /// A seta do caminho da ida.
    let arrow: RGB

    init(background: RGB, accent: RGB, textPrimary: RGB, textSecondary: RGB, mixes: Mixes) {
        self.background = background
        nearMove = accent
        farMove = GuideInk.mix(accent, background, mixes.farMove)
        nearStill = GuideInk.mix(accent, background, mixes.nearStill)
        farStill = GuideInk.mix(accent, background, mixes.farStill)
        ghostFill = GuideInk.mix(accent, background, mixes.ghostFill)
        ghostLine = GuideInk.mix(accent, background, mixes.ghostLine)
        equipment = textSecondary
        structure = GuideInk.mix(textSecondary, background, mixes.structure)
        structureSoft = GuideInk.mix(textSecondary, background, mixes.structureSoft)
        floor = GuideInk.mix(textSecondary, background, mixes.floor)
        arrow = textPrimary
    }

    /// As cores do modo claro ou escuro, a partir dos tokens do `Theme`.
    @MainActor
    static func make(dark: Bool) -> GuideInk {
        let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        return GuideInk(
            background: resolve(Theme.background, traits: traits),
            accent: resolve(Theme.accent, traits: traits),
            textPrimary: resolve(Theme.textPrimary, traits: traits),
            textSecondary: resolve(Theme.textSecondary, traits: traits),
            mixes: dark ? .dark : .light
        )
    }

    /// `a` misturado a `b` na fração `t` (0 = `a`, 1 = `b`), arredondado a 1/255 como o `Mix` do script.
    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        func channel(_ x: Double, _ y: Double) -> Double {
            ((x + (y - x) * t) * 255).rounded() / 255
        }
        return RGB(red: channel(a.red, b.red), green: channel(a.green, b.green), blue: channel(a.blue, b.blue))
    }

    /// A mesma cor com outra opacidade (véus do equipamento sobre o corpo).
    static func color(_ rgb: RGB, opacity: Double) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }

    /// Componentes sRGB de um token dinâmico no modo pedido. Um token que não se deixa ler vira preto (nunca trava).
    @MainActor
    private static func resolve(_ color: Color, traits: UITraitCollection) -> RGB {
        let resolved = UIColor(color).resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return RGB(red: 0, green: 0, blue: 0)
        }
        return RGB(red: Double(red), green: Double(green), blue: Double(blue))
    }
}
