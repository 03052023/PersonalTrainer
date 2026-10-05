import Foundation

/// Um grão de pólen do protótipo aprovado (`docs/design/v23-animation/launch.html`, `D.pollen.grains`;
/// SPEC RF-50, owner notes item 14: "Pólen: entra, discreto, na abertura"). Números fixos, copiados
/// um a um do protótipo — nada sorteado, a mesma abertura sempre (AGENTS R3, nada de `Date()`/aleatório
/// no motor; aqui vale o mesmo espírito para a UI).
///
/// `radiusStart`/`radiusEnd`/`size` estão em px do ícone de 1024 (o mesmo referencial do protótipo e
/// de `docs/design/render-app-icon.ps1`); `LaunchPollen.frame(of:at:)` converte para a fração do raio
/// externo da flor antes de devolver.
struct LaunchPollenGrain: Sendable {
    /// Ângulo no referencial da flor, em graus, sentido horário a partir do topo (protótipo: `a`).
    let angle: Double
    /// Início da vida do grão, em segundos desde o primeiro quadro da abertura (`t0`).
    let start: Double
    /// Duração da vida do grão, em segundos (`life`).
    let life: Double
    /// Raio inicial e final (px do ícone de 1024; `r0`/`r1`).
    let radiusStart: Double
    let radiusEnd: Double
    /// Tamanho do grão (px do ícone de 1024; `s`).
    let size: Double
    /// Opacidade de pico (`o`).
    let opacity: Double
    /// Curvatura do ângulo ao longo da vida, em graus (`curl`).
    let curl: Double
}

/// Posição, raio e opacidade de um grão de pólen num instante — tudo em fração do raio externo da
/// flor (1 = ponta das pétalas), pronto para desenhar na mesma `Canvas`/escala da flor grande.
struct LaunchPollenFrame: Equatable {
    let x: Double
    let y: Double
    let radius: Double
    let opacity: Double

    static let hidden = LaunchPollenFrame(x: 0, y: 0, radius: 0, opacity: 0)
}

enum LaunchPollen {
    /// Raio externo da flor Brisa (`docs/design/render-app-icon.ps1`, `Get-Bounds`), em px do ícone de
    /// 1024 — o mesmo referencial dos números abaixo. Confirmado por
    /// `docs/design/v23-animation/render-launch-assets.ps1` ("geometria Brisa: raio externo 358,24 px").
    static let iconMaxRadius: Double = 358.24

    /// Os 8 grãos do protótipo aprovado, na ordem dele. Cor: `#F5EBD7` claro / `#E6DAC3` escuro
    /// (aplicada por quem desenha; aqui só o movimento).
    static let grains: [LaunchPollenGrain] = [
        LaunchPollenGrain(angle: 316, start: 0.190, life: 0.33, radiusStart: 40, radiusEnd: 150, size: 6.4, opacity: 0.78, curl: -6),
        LaunchPollenGrain(angle: 306, start: 0.250, life: 0.30, radiusStart: 34, radiusEnd: 186, size: 4.8, opacity: 0.56, curl: -9),
        LaunchPollenGrain(angle: 240, start: 0.220, life: 0.32, radiusStart: 42, radiusEnd: 128, size: 5.2, opacity: 0.68, curl: -5),
        LaunchPollenGrain(angle: 174, start: 0.245, life: 0.31, radiusStart: 44, radiusEnd: 168, size: 6.8, opacity: 0.72, curl: -7),
        LaunchPollenGrain(angle: 163, start: 0.290, life: 0.27, radiusStart: 36, radiusEnd: 106, size: 4.2, opacity: 0.54, curl: -3),
        LaunchPollenGrain(angle: 100, start: 0.265, life: 0.30, radiusStart: 40, radiusEnd: 122, size: 4.6, opacity: 0.62, curl: -4),
        LaunchPollenGrain(angle: 33, start: 0.280, life: 0.28, radiusStart: 44, radiusEnd: 144, size: 5.8, opacity: 0.70, curl: -6),
        LaunchPollenGrain(angle: 22, start: 0.232, life: 0.32, radiusStart: 36, radiusEnd: 196, size: 4.0, opacity: 0.50, curl: -8),
    ]

    /// Curva do avanço radial (protótipo `D.pollen.c`).
    private static let advance = LaunchCurve(0.18, 0.5, 0.36, 1)
    /// A mesma curva de entrada/saída usada por quase tudo na abertura (protótipo `ED.io`).
    private static let easeInOut = LaunchCurve(0.42, 0, 0.58, 1)

    /// Cada grão nasce sem opacidade, sobe até o pico em 16% da própria vida e esmaece só a partir de
    /// 38% dela — por isso a maior parte da vida ele está com a opacidade de pico (protótipo `grainAt`).
    private static let fadeInFraction = 0.16
    private static let fadeOutStart = 0.38

    static func frame(of grain: LaunchPollenGrain, at t: Double) -> LaunchPollenFrame {
        let u = LaunchTimeline.fraction(t, grain.start, grain.start + grain.life)
        guard u > 0, u < 1 else { return .hidden }

        let eased = advance.value(at: u)
        let distance = (grain.radiusStart + (grain.radiusEnd - grain.radiusStart) * eased) / iconMaxRadius
        let angleRadians = (grain.angle + grain.curl * eased) * .pi / 180
        let radius = (grain.size * (1 - 0.25 * u)) / iconMaxRadius
        let fadeIn = min(1, u / fadeInFraction)
        let fadeOut = 1 - easeInOut.value(at: LaunchTimeline.fraction(u, fadeOutStart, 1))
        let opacity = grain.opacity * fadeIn * fadeOut

        return LaunchPollenFrame(
            x: distance * sin(angleRadians),
            y: -distance * cos(angleRadians),
            radius: radius,
            opacity: opacity
        )
    }
}
