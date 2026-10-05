import Foundation

/// O estado visual da abertura num instante `t` (SPEC RF-50): tudo o que `LaunchOverlay` precisa para
/// desenhar aquele quadro, sem saber nada de tempo — só números prontos. Ver `LaunchTimeline.frame`.
struct LaunchFrame: Equatable {
    /// Estado de uma pétala (índice = `ProgramGoal.petalIndex`).
    struct Petal: Equatable {
        /// Escala a partir da própria base (1 = tamanho normal; cresce até `1 + TL.open.grow`).
        var grow: Double
        /// Quanto a pétala deslizou para fora pelo próprio eixo, em fração do raio externo da flor.
        var slide: Double
        var opacity: Double
    }

    /// Giro da flor inteira, em graus (protótipo: sentido anti-horário é negativo).
    var turn: Double
    /// Escala do respiro (1 = normal; encolhe um pouco antes de abrir).
    var breathe: Double
    /// Escala do halo atrás da flor (o mesmo halo do ícone).
    var halo: Double
    /// Uma por pétala, na ordem de `ProgramGoal.petalIndex`.
    var petals: [Petal]
    var coreScale: Double
    var coreOpacity: Double
    /// 0 = azul da tela de lançamento; 1 = fundo claro da tela Início.
    var dawn: Double
    /// Opacidade do véu de areia do amanhecer quente (0 no escuro).
    var warm: Double
    /// Quanto a pétala do objetivo principal deve corar com a cor dele (0 sem objetivo).
    var goalTint: Double
    /// Opacidade da florzinha que chega antes da tela Início, no lugar da flor do cabeçalho.
    var goalHeader: Double
    /// 0 = conteúdo da tela Início escondido; 1 = livre (a camada da abertura já não cobre nada).
    var content: Double
    /// Escala de assentamento da tela Início (começa perto de 0,985 e chega a 1).
    var todayScale: Double
    var statusBarVisible: Bool
    /// Os 8 grãos de pólen, na mesma ordem de `LaunchPollen.grains`.
    var pollen: [LaunchPollenFrame]
}

/// A linha do tempo da abertura (SPEC RF-50; DESIGN §10), com os números do protótipo aprovado
/// (`docs/design/v23-animation/launch.html`, tabela "Quadro a quadro" e o objeto `TL`/`D`). Função
/// pura do tempo: sem `Date()`, sem estado, mesmo quadro sempre para o mesmo `t` (AGENTS R3, por
/// analogia — o motor não é o único lugar do app que não pode depender do relógio de verdade para o
/// resultado).
enum LaunchTimeline {
    /// Duração total (`TL.end`/`TL.endRM`).
    static let duration: Double = 0.92
    static let durationReduceMotion: Double = 0.60
    /// Quanto um toque durante a abertura antecipa o fim (`TL.skip`).
    static let skipDuration: Double = 0.15

    // MARK: - Janelas (início, fim/duração) em segundos, como no protótipo (`TL`)

    private static let breatheWindow = (t0: 0.04, t1: 0.24)
    private static let breatheAmount = 0.03
    private static let turnWindow = (t0: 0.04, t1: 0.84)
    private static let turnDegrees = -10.0
    private static let openStart = 0.16
    private static let openDuration = 0.46
    private static let openStagger = 0.035
    private static let openGrow = 0.22
    private static let fadeStart = 0.33
    private static let fadeStagger = 0.015
    private static let fadeDuration = 0.22
    private static let coreWindow = (t0: 0.32, t1: 0.60)
    private static let coreGrow = 0.08
    private static let dawnWindow = (t0: 0.24, t1: 0.60)
    private static let contentWindow = (t0: 0.58, t1: 0.92)
    private static let contentFrom = 0.985
    private static let statusAt = 0.45
    private static let warmWindow = (t0: 0.30, peak: 0.45, t1: 0.58)
    private static let warmWindowReduceMotion = (t0: 0.16, peak: 0.26, t1: 0.34)
    private static let handoffAmount = 0.24
    private static let handoffTintWindow = (t0: 0.30, t1: 0.46)
    private static let handoffHeaderWindow = (t0: 0.53, t1: 0.68)
    private static let handoffOutWindow = (t0: 0.82, t1: 0.92)
    private static let handoffOthersWindowReduceMotion = (t0: 0.04, t1: 0.26)
    private static let handoffActiveWindowReduceMotion = (t0: 0.10, t1: 0.32)
    private static let handoffTintWindowReduceMotion = (t0: 0.04, t1: 0.20)
    private static let handoffHeaderWindowReduceMotion = (t0: 0.29, t1: 0.44)
    private static let handoffOutWindowReduceMotion = (t0: 0.52, t1: 0.60)
    private static let rmFlowerWindow = (t0: 0.04, t1: 0.28)
    private static let rmDawnWindow = (t0: 0.12, t1: 0.40)
    private static let rmContentWindow = (t0: 0.34, t1: 0.60)
    private static let rmStatusAt = 0.30

    /// A `LaunchTimeline` só recebe `hasGoal` (assinatura congelada, docs/V23-UI-CONTRACT.md §4.2):
    /// internamente ela sempre trata esta pétala como "a do objetivo" (a que, com `hasGoal`, cora e é
    /// adiada para sair por último). `LaunchOverlay`, que conhece o objetivo de verdade, troca os
    /// números desta pétala com os da pétala realmente ativa antes de desenhar — ver o comentário lá.
    /// De propósito, **não** é `LaunchFlowerGeometry.openOrder.last` (que já sai por último de qualquer
    /// jeito): precisa ser uma pétala que normalmente NÃO é a última, para o adiamento com `hasGoal`
    /// ser uma mudança de verdade (e o teste `testRF50_goalPetalFadesLast` testar algo real).
    static let designatedGoalPetalIndex = 0

    // MARK: - Curvas (Bézier cúbica, protótipo `TL.*.c`)

    private static let breatheCurve = LaunchCurve(0.37, 0, 0.63, 1)
    private static let turnCurve = LaunchCurve(0.45, 0, 0.35, 1)
    private static let openCurve = LaunchCurve(0.33, 0, 0.13, 1)
    private static let fadeCurve = LaunchCurve(0.42, 0, 0.58, 1)
    /// A curva de entrada/saída compartilhada por quase tudo (protótipo `ED.io`): miolo, amanhecer,
    /// véu de areia, pétala do objetivo e, no modo Reduzir Movimento, tudo.
    private static let easeInOut = LaunchCurve(0.42, 0, 0.58, 1)
    private static let contentCurve = LaunchCurve(0.2, 0, 0, 1)

    /// `seg(t, a, b)` do protótipo: fração de `t` entre `a` e `b`, sempre grampeada em 0...1.
    static func fraction(_ t: Double, _ a: Double, _ b: Double) -> Double {
        guard b != a else { return t < a ? 0 : 1 }
        return min(1, max(0, (t - a) / (b - a)))
    }

    /// Sobe até `m` e desce até `b`, os dois pela mesma curva (protótipo `bump`): usado pelo véu de
    /// areia, que sobe e desce sem ficar constante no pico.
    private static func bump(_ t: Double, _ a: Double, _ m: Double, _ b: Double) -> Double {
        if t <= m { return easeInOut.value(at: fraction(t, a, m)) }
        return 1 - easeInOut.value(at: fraction(t, m, b))
    }

    /// A ordem de desvanecer: igual à de abrir, exceto que, com objetivo, a pétala designada vai para
    /// o fim (protótipo `fadeOrder`).
    private static func fadeOrder(hasGoal: Bool) -> [Int] {
        guard hasGoal else { return LaunchFlowerGeometry.openOrder }
        var order = LaunchFlowerGeometry.openOrder
        order.removeAll { $0 == designatedGoalPetalIndex }
        order.append(designatedGoalPetalIndex)
        return order
    }

    private static func slot(of petalIndex: Int, in order: [Int]) -> Int {
        order.firstIndex(of: petalIndex) ?? 0
    }

    /// O quadro no instante `t` (segundos desde o primeiro quadro do app; SPEC RF-50).
    ///
    /// - Parameters:
    ///   - reduceMotion: `@Environment(\.accessibilityReduceMotion)`; troca giro/crescimento por
    ///     esmaecimento e tira o pólen (é movimento).
    ///   - dark: `@Environment(\.colorScheme) == .dark`; desliga o véu de areia.
    ///   - hasGoal: há um objetivo ativo (`!goals.isEmpty`); sem ele, nenhuma pétala cora.
    static func frame(at t: Double, reduceMotion: Bool, dark: Bool, hasGoal: Bool) -> LaunchFrame {
        if reduceMotion {
            return reducedMotionFrame(at: t, dark: dark, hasGoal: hasGoal)
        }

        let order = fadeOrder(hasGoal: hasGoal)
        var openProgressByPetal = [Double](repeating: 0, count: 5)
        var petals = [LaunchFrame.Petal]()
        petals.reserveCapacity(5)
        for petalIndex in 0..<5 {
            let openBegins = openStart + Double(slot(of: petalIndex, in: LaunchFlowerGeometry.openOrder)) * openStagger
            let openProgress = openCurve.value(at: fraction(t, openBegins, openBegins + openDuration))
            openProgressByPetal[petalIndex] = openProgress

            let fadeBegins = fadeStart + Double(slot(of: petalIndex, in: order)) * fadeStagger
            let fadeProgress = fadeCurve.value(at: fraction(t, fadeBegins, fadeBegins + fadeDuration))

            petals.append(LaunchFrame.Petal(
                grow: 1 + openGrow * openProgress,
                slide: openProgress * LaunchFlowerGeometry.openSlideFraction,
                opacity: 1 - fadeProgress
            ))
        }
        let averageOpenProgress = openProgressByPetal.reduce(0, +) / Double(openProgressByPetal.count)

        let coreProgress = easeInOut.value(at: fraction(t, coreWindow.t0, coreWindow.t1))
        let contentProgress = contentCurve.value(at: fraction(t, contentWindow.t0, contentWindow.t1))
        let warm = dark ? 0 : bump(t, warmWindow.t0, warmWindow.peak, warmWindow.t1)
        let tint = hasGoal ? handoffAmount * easeInOut.value(at: fraction(t, handoffTintWindow.t0, handoffTintWindow.t1)) : 0
        let header = hasGoal ? headerOpacity(at: t, headerWindow: handoffHeaderWindow, outWindow: handoffOutWindow) : 0

        return LaunchFrame(
            turn: turnDegrees * turnCurve.value(at: fraction(t, turnWindow.t0, turnWindow.t1)),
            breathe: 1 - breatheAmount * breatheCurve.value(at: fraction(t, breatheWindow.t0, breatheWindow.t1)),
            halo: 1 + 0.15 * averageOpenProgress,
            petals: petals,
            coreScale: 1 + coreGrow * coreProgress,
            coreOpacity: 1 - coreProgress,
            dawn: easeInOut.value(at: fraction(t, dawnWindow.t0, dawnWindow.t1)),
            warm: warm,
            goalTint: tint,
            goalHeader: header,
            content: contentProgress,
            todayScale: contentFrom + (1 - contentFrom) * contentProgress,
            statusBarVisible: t >= statusAt,
            pollen: LaunchPollen.grains.map { LaunchPollen.frame(of: $0, at: t) }
        )
    }

    private static func headerOpacity(at t: Double, headerWindow: (t0: Double, t1: Double), outWindow: (t0: Double, t1: Double)) -> Double {
        easeInOut.value(at: fraction(t, headerWindow.t0, headerWindow.t1))
            * (1 - easeInOut.value(at: fraction(t, outWindow.t0, outWindow.t1)))
    }

    /// Com Reduzir Movimento (DESIGN §10; protótipo, seção "Com Reduzir Movimento"): nada gira, cresce
    /// ou desliza — só esmaecimentos, na mesma ordem (flor, depois azul, depois conteúdo), então nunca
    /// há flor ou azul por cima do texto. Sem pólen (é movimento).
    private static func reducedMotionFrame(at t: Double, dark: Bool, hasGoal: Bool) -> LaunchFrame {
        let flowerFade = 1 - easeInOut.value(at: fraction(t, rmFlowerWindow.t0, rmFlowerWindow.t1))

        let petals: [LaunchFrame.Petal]
        if hasGoal {
            petals = (0..<5).map { petalIndex in
                let window = petalIndex == designatedGoalPetalIndex ? handoffActiveWindowReduceMotion : handoffOthersWindowReduceMotion
                let opacity = 1 - easeInOut.value(at: fraction(t, window.t0, window.t1))
                return LaunchFrame.Petal(grow: 1, slide: 0, opacity: opacity)
            }
        } else {
            petals = (0..<5).map { _ in LaunchFrame.Petal(grow: 1, slide: 0, opacity: flowerFade) }
        }

        let warm = dark ? 0 : bump(t, warmWindowReduceMotion.t0, warmWindowReduceMotion.peak, warmWindowReduceMotion.t1)
        let tint = hasGoal ? handoffAmount * easeInOut.value(at: fraction(t, handoffTintWindowReduceMotion.t0, handoffTintWindowReduceMotion.t1)) : 0
        let header = hasGoal ? headerOpacity(at: t, headerWindow: handoffHeaderWindowReduceMotion, outWindow: handoffOutWindowReduceMotion) : 0

        return LaunchFrame(
            turn: 0,
            breathe: 1,
            halo: 1,
            petals: petals,
            coreScale: 1,
            coreOpacity: flowerFade,
            dawn: easeInOut.value(at: fraction(t, rmDawnWindow.t0, rmDawnWindow.t1)),
            warm: warm,
            goalTint: tint,
            goalHeader: header,
            content: easeInOut.value(at: fraction(t, rmContentWindow.t0, rmContentWindow.t1)),
            todayScale: 1,
            statusBarVisible: t >= rmStatusAt,
            pollen: Array(repeating: .hidden, count: LaunchPollen.grains.count)
        )
    }
}
