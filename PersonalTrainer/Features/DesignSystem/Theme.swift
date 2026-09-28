import SwiftUI
import UIKit

/// Paleta do Magister (DESIGN.md §3), desde a 2.3 na direção **A · Tinta e papel** (washi, tinta sumi em
/// tons de uma tinta só e um índigo como cor de ação; docs/design/v23-aesthetics/directions.html). Cada
/// token é uma `Color` dinâmica clara/escura — nunca um hexadecimal solto pelas views — para telas e
/// previews acompanharem a aparência do sistema.
///
/// Os nomes são congelados (docs/V23-UI-CONTRACT.md §3.2): a tarefa `ink` pode ajustar valores, sempre com
/// os contrastes do DESIGN §3, mas não renomeia nem tira tokens.
enum Theme {
    /// Um par de hexadecimais claro/escuro (e as variantes de Aumentar Contraste, quando o token muda
    /// com ele — DESIGN §3), independente de `UIColor`/`Color`. É a "tabela interna" que `dynamic(_:)`
    /// usa (docs/V23-UI-CONTRACT.md §4.1 item 1): os testes de contraste (`InkDesignTests`) leem os
    /// hexadecimais direto daqui, sem precisar resolver traits de uma `UIColor` dinâmica.
    struct HexPair {
        let light: String
        let dark: String
        let highContrastLight: String?
        let highContrastDark: String?

        init(light: String, dark: String, highContrastLight: String? = nil, highContrastDark: String? = nil) {
            self.light = light
            self.dark = dark
            self.highContrastLight = highContrastLight
            self.highContrastDark = highContrastDark
        }
    }

    // MARK: - Hexadecimais da direção A (DESIGN §3) — a tabela

    /// Washi: fundo das telas.
    static let backgroundHex = HexPair(light: "#F4EEE4", dark: "#191715")
    /// Papel novo: cartões, folhas, listas.
    static let surfaceHex = HexPair(light: "#FCF9F3", dark: "#25211E")
    /// Sumi: texto e números.
    static let textPrimaryHex = HexPair(light: "#27221F", dark: "#EEE7DC")
    /// Tinta diluída: legendas e rótulos. Com Aumentar Contraste ligado, passa a usar as cores de
    /// `textPrimary` (DESIGN §3).
    static let textSecondaryHex = HexPair(
        light: "#635850", dark: "#B2A595",
        highContrastLight: "#27221F", highContrastDark: "#EEE7DC"
    )
    /// Índigo (ai): botão principal, links, seleção e o tint global.
    static let accentHex = HexPair(light: "#2B4D6B", dark: "#A4BDD6")
    /// Texto sobre `accent` (ver `PrimaryButtonStyle`).
    static let onAccentHex = HexPair(light: "#FCF9F3", dark: "#191715")
    /// Fundo de item selecionado e chips — nunca usada para texto.
    static let accentSoftHex = HexPair(light: "#DEE5EA", dark: "#27313B")
    /// Tinta 2 (nō): ícones e traços que acompanham o texto. Decorativo.
    static let inkMutedHex = HexPair(light: "#4A4139", dark: "#CFC4B5")
    /// Tinta 5 (sei): fios, divisórias, o trilho do ensō e a borda fina dos cartões. Decorativo.
    static let lineHex = HexPair(light: "#DAD1C4", dark: "#3A332D")
    /// Terra vermelha (bengara).
    static let goalHypertrophyHex = HexPair(light: "#8E3E2C", dark: "#E09A82")
    /// Chá torrado.
    static let goalStrengthHex = HexPair(light: "#6F5238", dark: "#CDAA86")
    /// Cardio: celadon profundo.
    static let goalEnduranceHex = HexPair(light: "#3A6765", dark: "#93C2BE")
    /// Verde pinheiro.
    static let goalLongevityHex = HexPair(light: "#50613F", dark: "#AFC194")
    /// Uva acinzentada.
    static let goalCombatHex = HexPair(light: "#6C4862", dark: "#CFA6C3")
    /// Folha seca: sono, HRV, VO2max e aeróbico — nunca acima do objetivo na tela Hoje (DESIGN §9).
    static let healthHex = HexPair(light: "#775816", dark: "#D7B568")
    /// Miolo da flor (areia; DESIGN §2), único tom fora da paleta de objetivo.
    static let flowerCenterHex = HexPair(light: "#E7D9C2", dark: "#CDBEA4")

    /// Tokens de texto, para `testDESIGN3_textTokensPassAA` (≥ 4,5:1 contra `background` e `surface`,
    /// claro e escuro).
    static let textTokenPairs: [(name: String, pair: HexPair)] = [
        ("textPrimary", textPrimaryHex),
        ("textSecondary", textSecondaryHex),
    ]

    /// Cores por objetivo (mais `health`), para `testDESIGN3_goalColorsPassAA` (contraste gráfico
    /// ≥ 3:1 contra `background` e `surface`, claro e escuro — DESIGN §3: "AA exige … 3:1 para
    /// gráficos").
    static let goalTokenPairs: [(name: String, pair: HexPair)] = [
        ("goalHypertrophy", goalHypertrophyHex),
        ("goalStrength", goalStrengthHex),
        ("goalEndurance", goalEnduranceHex),
        ("goalLongevity", goalLongevityHex),
        ("goalCombat", goalCombatHex),
        ("health", healthHex),
    ]

    // MARK: - `Color`s dinâmicas (o que as telas usam)

    static let background = dynamic(backgroundHex)
    static let surface = dynamic(surfaceHex)
    static let textPrimary = dynamic(textPrimaryHex)
    static let textSecondary = dynamic(textSecondaryHex)
    static let accent = dynamic(accentHex)
    static let onAccent = dynamic(onAccentHex)
    static let accentSoft = dynamic(accentSoftHex)

    // MARK: - Tons de uma tinta só (gosai; DESIGN §3 e §14) — decorativos, nunca texto

    static let inkMuted = dynamic(inkMutedHex)
    static let line = dynamic(lineHex)

    // MARK: - Cores por objetivo (DESIGN §3/§4)

    static let goalHypertrophy = dynamic(goalHypertrophyHex)
    static let goalStrength = dynamic(goalStrengthHex)
    static let goalEndurance = dynamic(goalEnduranceHex)
    static let goalLongevity = dynamic(goalLongevityHex)
    static let goalCombat = dynamic(goalCombatHex)

    static let health = dynamic(healthHex)

    /// Apagar e erro. Nunca "cor de esforço" (DESIGN §3).
    static let destructive = Color(UIColor.systemRed)

    /// Miolo da flor (areia; DESIGN §2), único tom fora da paleta de objetivo. Usado só por
    /// `FlowerView` e pela abertura, que reaproveitam a identidade do ícone dentro do app.
    static let flowerCenter = dynamic(flowerCenterHex)

    static func dynamic(_ pair: HexPair) -> Color {
        Color(UIColor { traits in
            let wantsHighContrast = traits.accessibilityContrast == .high
            if traits.userInterfaceStyle == .dark {
                return UIColor(hex: (wantsHighContrast ? pair.highContrastDark : nil) ?? pair.dark)
            } else {
                return UIColor(hex: (wantsHighContrast ? pair.highContrastLight : nil) ?? pair.light)
            }
        })
    }

    /// `Color` a partir de um hexadecimal solto — só para os degradês decorativos calculados em tempo
    /// de execução (`FlowerView`, aguada nōtan da pétala ativa: DESIGN §14). Nunca use direto numa
    /// view para texto ou fundo: os tokens acima já cobrem claro/escuro e Aumentar Contraste; esta
    /// função existe só para pintar a mistura de dois tokens já aprovados.
    static func color(hex: String) -> Color {
        Color(UIColor(hex: hex))
    }

    /// Mistura dois hexadecimais em RGB simples (não perceptual, mas determinística): o bastante para
    /// o degradê decorativo da pétala ativa (nōtan, mais escura na base e mais clara na ponta) e para
    /// a folha de conferência (`docs/design/v23-ink/render-ink-sheet.ps1`) reproduzir os mesmos
    /// números. `fraction` = 0 devolve `a`; 1 devolve `b`.
    static func mixedHex(_ a: String, _ b: String, fraction: Double) -> String {
        let t = min(1, max(0, fraction))
        let (r1, g1, b1) = components(of: a)
        let (r2, g2, b2) = components(of: b)
        func lerp(_ x: Int, _ y: Int) -> Int {
            Int((Double(x) + (Double(y) - Double(x)) * t).rounded())
        }
        return String(format: "#%02X%02X%02X", lerp(r1, r2), lerp(g1, g2), lerp(b1, b2))
    }

    private static func components(of hex: String) -> (Int, Int, Int) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(digits, radix: 16) ?? 0
        return (Int((value & 0xFF0000) >> 16), Int((value & 0x00FF00) >> 8), Int(value & 0x0000FF))
    }
}

private extension UIColor {
    /// Cor sólida e opaca a partir de um hexadecimal `#RRGGBB`. Só para os tokens fixos de `Theme`
    /// (nunca para entrada do usuário), então uma string malformada vira preto em vez de travar.
    convenience init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(digits, radix: 16) ?? 0
        let red = Double((value & 0xFF0000) >> 16) / 255
        let green = Double((value & 0x00FF00) >> 8) / 255
        let blue = Double(value & 0x0000FF) / 255
        self.init(red: red, green: green, blue: blue, alpha: 1)
    }
}
