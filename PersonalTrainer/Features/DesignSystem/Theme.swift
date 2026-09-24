import SwiftUI
import UIKit

/// Paleta do Magister (DESIGN.md §3): superfícies claras e quentes, um azul-profundo como cor de
/// ação e tons terrosos por objetivo. Cada token é uma `Color` dinâmica clara/escura — nunca um
/// hexadecimal solto pelas views — para telas e previews acompanharem a aparência do sistema.
enum Theme {
    static let background = dynamic(light: "#F2EBE0", dark: "#1C1714")
    static let surface = dynamic(light: "#FAF6F0", dark: "#29221C")
    static let textPrimary = dynamic(light: "#33281F", dark: "#F0E7DA")

    /// Com Aumentar Contraste ligado, passa a usar as cores de `textPrimary` (DESIGN §3).
    static let textSecondary = dynamic(
        light: "#6B5A4C", dark: "#BCAB98",
        highContrastLight: "#33281F", highContrastDark: "#F0E7DA"
    )

    /// Botão principal, links, seleção e o tint global da aba Hoje.
    static let accent = dynamic(light: "#355A7C", dark: "#9DBAD6")
    /// Texto sobre `accent` (ver `PrimaryButtonStyle`).
    static let onAccent = dynamic(light: "#FAF6F0", dark: "#1C1714")
    /// Fundo de item selecionado e chips — nunca usada para texto.
    static let accentSoft = dynamic(light: "#DDE5EC", dark: "#26323E")

    // MARK: - Cores por objetivo (DESIGN §3/§4)

    static let goalHypertrophy = dynamic(light: "#904C36", dark: "#E0927A")
    static let goalStrength = dynamic(light: "#7A583C", dark: "#C9A27F")
    static let goalEndurance = dynamic(light: "#4F6170", dark: "#9FB2C2")
    static let goalLongevity = dynamic(light: "#56654A", dark: "#A9B98F")
    static let goalCombat = dynamic(light: "#74506A", dark: "#C9A0BC")

    /// Sono, HRV, VO2max e aeróbico — nunca acima do objetivo na Home (DESIGN §9).
    static let health = dynamic(light: "#7A5B1A", dark: "#D4B062")

    /// Apagar e erro. Nunca "cor de esforço" (DESIGN §3).
    static let destructive = Color(UIColor.systemRed)

    /// Miolo da flor do ícone (DESIGN §2), único tom fora da paleta de objetivo. Usado só por
    /// `FlowerView`, que reaproveita a identidade do ícone dentro do app.
    static let flowerCenter = dynamic(light: "#E9DCC6", dark: "#D3C4AB")

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
