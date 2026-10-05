import SwiftUI
import TrainerCore
import XCTest
@testable import PersonalTrainer

/// Tinta e papel (T9.1; DESIGN §3 e §14; docs/V23-UI-CONTRACT.md §4.1): os hexadecimais da paleta
/// passam AA (WCAG) contra `background` e `surface`, claro e escuro, e os componentes decorativos
/// (`FlowerView`, `EnsoRingView`, `InkMarkView`) ficam dentro do que prometem.
///
/// O cálculo de contraste é local a este arquivo (não depende de nada do app): pura função sobre os
/// hexadecimais de `Theme` (`Theme.HexPair`), a mesma fórmula da WCAG 2 usada por
/// `docs/design/render-app-icon.ps1` e por `docs/design/v23-ink/render-ink-sheet.ps1` — os três
/// concordam (a folha de conferência imprime os mesmos números que este teste verifica).
///
/// `@MainActor` porque `FlowerView`/`EnsoRingView`/`InkMarkView` são `View`s (mesma convenção de
/// `FlowerAndGoalStyleTests`).
@MainActor
final class InkDesignTests: XCTestCase {

    // MARK: - DESIGN §3: paleta e contraste (WCAG AA)

    /// Texto (`textPrimary`, `textSecondary`) exige 4,5:1 contra `background` e `surface`, claro e
    /// escuro — o menor dos dois, como a tabela do DESIGN §3 documenta ("vale o menor valor").
    func testDESIGN3_textTokensPassAA() {
        for (name, pair) in Theme.textTokenPairs {
            assertPassesAA(name: name, pair: pair, minimumRatio: 4.5, kind: "texto")
        }
    }

    /// Cores por objetivo (mais `health`) são gráficas, não texto: 3:1 basta (DESIGN §3: "3:1 para
    /// gráficos"). Todas já passam de sobra pelo texto também (DESIGN §3), mas o teste segue a regra.
    func testDESIGN3_goalColorsPassAA() {
        for (name, pair) in Theme.goalTokenPairs {
            assertPassesAA(name: name, pair: pair, minimumRatio: 3, kind: "gráfico")
        }
    }

    /// A pílula "Trocar ›" (DESIGN §9.1) é `accentSoft` com texto `accent`: 4,5:1, claro e escuro.
    func testDESIGN3_accentOnAccentSoftPassesAA() {
        let lightRatio = Self.contrastRatio(Theme.accentHex.light, Theme.accentSoftHex.light)
        let darkRatio = Self.contrastRatio(Theme.accentHex.dark, Theme.accentSoftHex.dark)
        XCTAssertGreaterThanOrEqual(lightRatio, 4.5, "accent sobre accentSoft (claro) abaixo de AA: \(lightRatio)")
        XCTAssertGreaterThanOrEqual(darkRatio, 4.5, "accent sobre accentSoft (escuro) abaixo de AA: \(darkRatio)")
    }

    // MARK: - Flor em aguada (FlowerView, docs/V23-UI-CONTRACT.md §3.2)

    func testFlower_activeGoalsOrder() {
        let none = FlowerView(activeGoal: nil, size: 56)
        XCTAssertNil(none.activeGoal, "sem objetivo, activeGoal é nil")
        XCTAssertTrue(none.activeGoals.isEmpty)

        let single = FlowerView(activeGoal: .strength, size: 56)
        XCTAssertEqual(single.activeGoal, .strength)
        XCTAssertEqual(single.activeGoals, [.strength])

        let multi = FlowerView(activeGoals: [.hypertrophy, .endurance], size: 56)
        XCTAssertEqual(multi.activeGoal, .hypertrophy, "o principal é sempre o primeiro de activeGoals")
        XCTAssertEqual(multi.activeGoals, [.hypertrophy, .endurance])
    }

    // MARK: - Ensō (EnsoRingView) e marca de tinta (InkMarkView)

    func testEnso_progressIsClamped() {
        XCTAssertEqual(EnsoRingView(progress: -0.4).clampedProgress, 0)
        XCTAssertEqual(EnsoRingView(progress: 0).clampedProgress, 0)
        XCTAssertEqual(EnsoRingView(progress: 0.5).clampedProgress, 0.5)
        XCTAssertEqual(EnsoRingView(progress: 1).clampedProgress, 1)
        XCTAssertEqual(EnsoRingView(progress: 1.4).clampedProgress, 1)
    }

    func testInkMark_progressIsClamped() {
        XCTAssertEqual(InkMarkView(progress: -0.2).clampedProgress, 0)
        XCTAssertEqual(InkMarkView(progress: 0).clampedProgress, 0)
        XCTAssertEqual(InkMarkView(progress: 0.6).clampedProgress, 0.6)
        XCTAssertEqual(InkMarkView(progress: 1).clampedProgress, 1)
        XCTAssertEqual(InkMarkView(progress: 1.8).clampedProgress, 1)
    }

    // MARK: - WCAG 2 (função local, só para este arquivo de teste)

    private func assertPassesAA(name: String, pair: Theme.HexPair, minimumRatio: Double, kind: String, line: UInt = #line) {
        let lightBg = Self.contrastRatio(pair.light, Theme.backgroundHex.light)
        let lightSurface = Self.contrastRatio(pair.light, Theme.surfaceHex.light)
        let darkBg = Self.contrastRatio(pair.dark, Theme.backgroundHex.dark)
        let darkSurface = Self.contrastRatio(pair.dark, Theme.surfaceHex.dark)
        XCTAssertGreaterThanOrEqual(
            min(lightBg, lightSurface), minimumRatio,
            "\(name) (claro) abaixo de AA (\(kind)): fundo \(lightBg), cartão \(lightSurface)", line: line
        )
        XCTAssertGreaterThanOrEqual(
            min(darkBg, darkSurface), minimumRatio,
            "\(name) (escuro) abaixo de AA (\(kind)): fundo \(darkBg), cartão \(darkSurface)", line: line
        )
    }

    /// WCAG 2: contraste = (L_claro + 0,05) / (L_escuro + 0,05), L = luminância relativa.
    private static func contrastRatio(_ hexA: String, _ hexB: String) -> Double {
        let luminanceA = relativeLuminance(of: hexA)
        let luminanceB = relativeLuminance(of: hexB)
        let lighter = max(luminanceA, luminanceB)
        let darker = min(luminanceA, luminanceB)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(of hex: String) -> Double {
        let (r, g, b) = components(of: hex)
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    private static func linearize(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func components(of hex: String) -> (Double, Double, Double) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(digits, radix: 16) ?? 0
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        return (r, g, b)
    }
}
