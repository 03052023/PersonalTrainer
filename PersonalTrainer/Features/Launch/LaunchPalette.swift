import SwiftUI

/// A paleta fixa da flor Brisa (`docs/design/render-app-icon.ps1`, `$Looks.default`/`.dark`, e
/// `docs/design/v23-animation/render-launch-assets.ps1`, que gera a tela de lançamento) e dos detalhes
/// sutis da abertura (`docs/design/v23-animation/launch.html`), separada do `Theme` do app: a abertura
/// reproduz o ícone (owner notes item 3, "idêntica ao ícone"), não a direção Tinta e papel — só o fundo
/// que ela revela (`Theme.background`) é o mesmo. `dark` já vem calculado (`colorScheme == .dark`),
/// então as cores aqui são fixas, sem precisar de `Color` dinâmica por traço.
///
/// Os hexadecimais ficam todos aqui. Os degradês (B6 da 2.3) misturam as mesmas cores, com as mesmas
/// frações, do script que gera a tela de lançamento, para o primeiro quadro da `Canvas` ser a imagem da
/// tela de lançamento: se uma mudar, muda a outra (os testes de `LaunchTimelineTests` conferem os
/// números do script).
enum LaunchPalette {
    /// Cor sólida em canais inteiros 0...255, como o `[System.Drawing.Color]` do script (a mistura
    /// arredonda canal a canal, como a função `Mix` dele).
    struct RGB: Equatable {
        let red: Int
        let green: Int
        let blue: Int

        init(red: Int, green: Int, blue: Int) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// A partir de `#RRGGBB`. Só recebe constantes deste arquivo, nunca entrada de pessoa: um texto
        /// malformado vira preto em vez de travar (AGENTS R11).
        init(hex: String) {
            let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            let value = UInt64(digits, radix: 16) ?? 0
            self.red = Int((value & 0xFF0000) >> 16)
            self.green = Int((value & 0x00FF00) >> 8)
            self.blue = Int(value & 0x0000FF)
        }

        /// `Mix(self, other, fraction)` do script: 0 devolve esta cor, 1 devolve `other`.
        func mixed(with other: RGB, fraction: Double) -> RGB {
            func channel(_ from: Int, _ to: Int) -> Int {
                Int((Double(from) + Double(to - from) * fraction).rounded())
            }
            return RGB(
                red: channel(red, other.red),
                green: channel(green, other.green),
                blue: channel(blue, other.blue)
            )
        }

        var color: Color {
            Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1)
        }
    }

    /// Duas cores de um degradê linear: `start` na origem do eixo e `end` no fim dele.
    struct Ramp: Equatable {
        let start: RGB
        let end: RGB

        var gradient: Gradient {
            Gradient(colors: [start.color, end.color])
        }
    }

    static func background(dark: Bool) -> Color {
        RGB(hex: dark ? "#141D29" : "#24354C").color
    }

    /// O degradê de cada pétala grande, da base (perto do miolo) para a ponta (B6): a cor da pétala
    /// misturada com o fundo escuro do ícone na base (claro 5 % com `#1C2B40`; escuro 6 % com `#101822`)
    /// e com o branco na ponta (claro 35 % com `#FFFFFF`; escuro 30 % com `#F4F1EA`) — `baseMix`/`tip`/
    /// `tipTo` de `$Looks` no script.
    static func petalRamp(dark: Bool) -> Ramp {
        if dark {
            let petal = RGB(hex: "#E3DED3")
            return Ramp(
                start: petal.mixed(with: RGB(hex: "#101822"), fraction: 0.06),
                end: petal.mixed(with: RGB(hex: "#F4F1EA"), fraction: 0.30)
            )
        }
        let petal = RGB(hex: "#F1EDE4")
        return Ramp(
            start: petal.mixed(with: RGB(hex: "#1C2B40"), fraction: 0.05),
            end: petal.mixed(with: RGB(hex: "#FFFFFF"), fraction: 0.35)
        )
    }

    /// O degradê vertical do miolo, de cima para baixo (B6): a cor do miolo em cima e, embaixo, ela
    /// misturada 18 % com o topo do degradê do fundo do ícone (`#2B3F58` claro, `#18222F` escuro).
    static func coreRamp(dark: Bool) -> Ramp {
        let top = RGB(hex: dark ? "#D3C4AB" : "#E9DCC6")
        let backgroundTop = RGB(hex: dark ? "#18222F" : "#2B3F58")
        return Ramp(start: top, end: top.mixed(with: backgroundTop, fraction: 0.18))
    }

    /// Só a aparência padrão tem halo (`glowA` = 55 de 255 no script do ícone); a escura não.
    static func halo(dark: Bool) -> Color? {
        dark ? nil : RGB(hex: "#6B798A").color
    }

    static let haloAlpha: Double = 0.216

    static let warm = RGB(hex: "#EBCFB0").color

    static func pollen(dark: Bool) -> Color {
        RGB(hex: dark ? "#E6DAC3" : "#F5EBD7").color
    }
}
