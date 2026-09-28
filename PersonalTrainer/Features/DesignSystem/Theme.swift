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
    /// Washi: fundo das telas.
    static let background = dynamic(light: "#F4EEE4", dark: "#191715")
    /// Papel novo: cartões, folhas, listas.
    static let surface = dynamic(light: "#FCF9F3", dark: "#25211E")
    /// Sumi: texto e números.
    static let textPrimary = dynamic(light: "#27221F", dark: "#EEE7DC")

    /// Tinta diluída: legendas e rótulos. Com Aumentar Contraste ligado, passa a usar as cores de
    /// `textPrimary` (DESIGN §3).
    static let textSecondary = dynamic(
        light: "#635850", dark: "#B2A595",
        highContrastLight: "#27221F", highContrastDark: "#EEE7DC"
    )

    /// Índigo (ai): botão principal, links, seleção e o tint global.
    static let accent = dynamic(light: "#2B4D6B", dark: "#A4BDD6")
    /// Texto sobre `accent` (ver `PrimaryButtonStyle`).
    static let onAccent = dynamic(light: "#FCF9F3", dark: "#191715")
    /// Fundo de item selecionado e chips — nunca usada para texto.
    static let accentSoft = dynamic(light: "#DEE5EA", dark: "#27313B")

    // MARK: - Tons de uma tinta só (gosai; DESIGN §3 e §14) — decorativos, nunca texto

    /// Tinta 2 (nō): ícones e traços que acompanham o texto. Decorativo.
    static let inkMuted = dynamic(light: "#4A4139", dark: "#CFC4B5")
    /// Tinta 5 (sei): fios, divisórias, o trilho do ensō e a borda fina dos cartões. Decorativo.
    static let line = dynamic(light: "#DAD1C4", dark: "#3A332D")

    // MARK: - Cores por objetivo (DESIGN §3/§4)

    /// Terra vermelha (bengara).
    static let goalHypertrophy = dynamic(light: "#8E3E2C", dark: "#E09A82")
    /// Chá torrado.
    static let goalStrength = dynamic(light: "#6F5238", dark: "#CDAA86")
    /// Cardio: celadon profundo.
    static let goalEndurance = dynamic(light: "#3A6765", dark: "#93C2BE")
    /// Verde pinheiro.
    static let goalLongevity = dynamic(light: "#50613F", dark: "#AFC194")
    /// Uva acinzentada.
    static let goalCombat = dynamic(light: "#6C4862", dark: "#CFA6C3")

    /// Folha seca: sono, HRV, VO2max e aeróbico — nunca acima do objetivo na tela Hoje (DESIGN §9).
    static let health = dynamic(light: "#775816", dark: "#D7B568")

    /// Apagar e erro. Nunca "cor de esforço" (DESIGN §3).
    static let destructive = Color(UIColor.systemRed)

    /// Miolo da flor (areia; DESIGN §2), único tom fora da paleta de objetivo. Usado só por
    /// `FlowerView` e pela abertura, que reaproveitam a identidade do ícone dentro do app.
    static let flowerCenter = dynamic(light: "#E7D9C2", dark: "#CDBEA4")

    private static func dynamic(
        light: String,
        dark: String,
        highContrastLight: String? = nil,
        highContrastDark: String? = nil
    ) -> Color {
        Color(UIColor { traits in
            let wantsHighContrast = traits.accessibilityContrast == .high
            if traits.userInterfaceStyle == .dark {
                return UIColor(hex: (wantsHighContrast ? highContrastDark : nil) ?? dark)
            } else {
                return UIColor(hex: (wantsHighContrast ? highContrastLight : nil) ?? light)
            }
        })
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
