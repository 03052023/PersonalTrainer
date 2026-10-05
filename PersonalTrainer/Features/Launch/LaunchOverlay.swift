import SwiftUI
import TrainerCore

extension View {
    /// Abertura a frio (SPEC RF-50). `goals`: objetivos ativos, o principal primeiro (tinge a pétala
    /// dele). Com `isEnabled` falso, devolve o conteúdo sem nada por cima e com a barra de status
    /// visível.
    func launchOverlay(goals: [ProgramGoal], isEnabled: Bool, onFinished: @escaping () -> Void) -> some View {
        modifier(LaunchOverlayModifier(goals: goals, isEnabled: isEnabled, onFinished: onFinished))
    }
}

/// A camada da abertura por cima da raiz do app (SPEC RF-50; DESIGN §10). Uma `TimelineView` dá o
/// relógio e uma `Canvas` desenha fundo, amanhecer, véu, flor grande e pólen a partir de
/// `LaunchTimeline.frame`, a mesma função pura testada em `LaunchTimelineTests`. O conteúdo de baixo
/// (a raiz do app) já está montado e aceitando toques desde o primeiro quadro.
private struct LaunchOverlayModifier: ViewModifier {
    let goals: [ProgramGoal]
    let isEnabled: Bool
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Capturado uma vez, quando esta view nasce — o "primeiro quadro do app" da SPEC RF-50. Nunca
    /// `Date()` dentro do cálculo do quadro (`LaunchTimeline.frame` é pura); só aqui, para converter o
    /// relógio de verdade em segundos decorridos, como qualquer animação normal da UI.
    @State private var startDate = Date()
    @State private var finished = false
    /// Quando a pessoa toca durante a abertura: o instante (segundos decorridos) do toque, e o quadro
    /// que estava na tela naquela hora — congelado, só a opacidade dele desce até sair (SPEC RF-50:
    /// "tocar adianta para o fim em 0,15 s").
    @State private var skipStartElapsed: Double?
    @State private var frozenFrameAtSkip: LaunchFrame?

    private var goalPetalIndex: Int? {
        goals.first?.petalIndex
    }

    private var effectiveDuration: Double {
        reduceMotion ? LaunchTimeline.durationReduceMotion : LaunchTimeline.duration
    }

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !isEnabled || finished)) { timeline in
            let elapsedTime = elapsed(at: timeline.date)
            let liveFrame = LaunchTimeline.frame(
                at: min(elapsedTime, effectiveDuration),
                reduceMotion: reduceMotion,
                dark: colorScheme == .dark,
                goalPetalIndex: goalPetalIndex
            )

            let displayFrame = frozenFrameAtSkip ?? liveFrame
            let canvasOpacity = skipOpacity(at: elapsedTime)
            let scale = displayFrame.todayScale + (1 - displayFrame.todayScale) * (1 - canvasOpacity)
            let showsOverlay = isEnabled && !finished

            content
                .scaleEffect(showsOverlay ? scale : 1)
                .overlay {
                    if showsOverlay {
                        LaunchCanvasView(
                            frame: displayFrame,
                            isDark: colorScheme == .dark,
                            goalColor: goals.first?.color,
                            goalPetalIndex: goalPetalIndex
                        )
                        .opacity(canvasOpacity)
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                    }
                }
                .overlayPreferenceValue(GoalFlowerAnchorKey.self) { anchor in
                    if showsOverlay, displayFrame.goalHeader > 0.001, let anchor {
                        GeometryReader { proxy in
                            let rect = proxy[anchor]
                            FlowerView(activeGoals: goals, size: rect.width)
                                .position(x: rect.midX, y: rect.midY)
                                .opacity(displayFrame.goalHeader * canvasOpacity)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .statusBar(hidden: showsOverlay && !displayFrame.statusBarVisible)
                // O toque só existe enquanto a abertura está na tela: depois dela, `.subviews` desliga
                // este gesto (e só ele), para a raiz do app não carregar um toque extra por cima de
                // listas, campos e botões pelo resto da vida do processo.
                .simultaneousGesture(
                    TapGesture().onEnded {
                        requestSkip(elapsedTime: elapsedTime, frame: liveFrame)
                    },
                    including: showsOverlay ? .all : .subviews
                )
                .onChange(of: elapsedTime) { _, newValue in
                    checkFinished(elapsedTime: newValue)
                }
        }
    }

    private func elapsed(at date: Date) -> Double {
        max(0, date.timeIntervalSince(startDate))
    }

    /// 1 até o toque; desce a 0 ao longo de `LaunchTimeline.skipDuration` depois dele (protótipo
    /// `extra`). Sem toque, sempre 1.
    private func skipOpacity(at elapsedTime: Double) -> Double {
        guard let skipStartElapsed else { return 1 }
        return 1 - LaunchTimeline.fraction(elapsedTime, skipStartElapsed, skipStartElapsed + LaunchTimeline.skipDuration)
    }

    private func requestSkip(elapsedTime: Double, frame: LaunchFrame) {
        guard isEnabled, !finished, skipStartElapsed == nil else { return }
        skipStartElapsed = elapsedTime
        frozenFrameAtSkip = frame
    }

    private func checkFinished(elapsedTime: Double) {
        guard isEnabled, !finished else { return }
        if let skipStartElapsed, elapsedTime >= skipStartElapsed + LaunchTimeline.skipDuration {
            finished = true
            onFinished()
        } else if skipStartElapsed == nil, elapsedTime >= effectiveDuration {
            finished = true
            onFinished()
        }
    }
}

/// O desenho de um quadro: fundo (azul-marinho → papel), halo, a flor grande (pétalas + miolo) e o
/// pólen — tudo a partir dos caminhos unitários de `BrisaGeometry`/`LaunchFlowerGeometry`, montados uma
/// vez e só transformados a cada quadro (nada de recalcular a geometria da flor 60×/s).
private struct LaunchCanvasView: View {
    let frame: LaunchFrame
    /// `colorScheme == .dark`, lido pelo modificador (a `Canvas` não tem `@Environment` de graça: os
    /// fechamentos de desenho não são `View`s). Controla a cor do fundo, da flor e do halo — o `warm`
    /// já vem zerado de `LaunchTimeline.frame(dark:)` quando escuro, mas as CORES em si (fundo azul
    /// escuro, pétala clara, sem halo) dependem deste mesmo booleano.
    let isDark: Bool
    let goalColor: Color?
    let goalPetalIndex: Int?

    /// Diâmetro de referência (ponta a ponta das pétalas) em pontos: o da flor de `LaunchFlower.imageset`
    /// (docs/V23-UI-CONTRACT.md §4.2), para o primeiro quadro da `Canvas` bater com a tela de
    /// lançamento sem salto. A imagem em si tem 312 pt de lado (A7 da 2.4: o halo, de raio ~153,6 pt,
    /// precisa caber inteiro), mas a flor continua com 256 pt, a mesma escala de sempre.
    private static let flowerDiameter: CGFloat = 256
    private static let haloRadiusFraction: CGFloat = 430.0 / 358.24

    private static let petalPaths = BrisaGeometry.unitPetalOutlines.map(LaunchFlowerGeometry.path)
    private static let corePath = LaunchFlowerGeometry.path(BrisaGeometry.unitCenterOutline)

    var body: some View {
        Canvas { context, size in
            let scale = Self.flowerDiameter / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let fullRect = Path(CGRect(origin: .zero, size: size))

            drawBackground(context: context, fullRect: fullRect, size: size, center: center, scale: scale)
            drawPetals(context: context, center: center, scale: scale)
            drawCore(context: context, center: center, scale: scale)
            drawPollen(context: context, center: center, scale: scale)
        }
    }

    private func drawBackground(context: GraphicsContext, fullRect: Path, size: CGSize, center: CGPoint, scale: CGFloat) {
        var backgroundLayer = context
        backgroundLayer.opacity = 1 - frame.content
        backgroundLayer.drawLayer { layer in
            layer.fill(fullRect, with: .color(Theme.background))

            var night = layer
            night.opacity = 1 - frame.dawn
            night.fill(fullRect, with: .color(LaunchPalette.background(dark: isDark)))
            if frame.halo > 0, let haloColor = LaunchPalette.halo(dark: isDark) {
                let radius = Self.haloRadiusFraction * scale * CGFloat(frame.halo)
                let haloRect = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
                night.fill(
                    Path(ellipseIn: haloRect),
                    with: .radialGradient(
                        Gradient(colors: [haloColor.opacity(LaunchPalette.haloAlpha), haloColor.opacity(0)]),
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }

            if frame.warm > 0 {
                var warmLayer = layer
                warmLayer.opacity = frame.warm
                warmLayer.fill(
                    fullRect,
                    with: .linearGradient(
                        Gradient(colors: [
                            LaunchPalette.warm.opacity(0.30),
                            LaunchPalette.warm.opacity(0.24),
                            LaunchPalette.warm.opacity(0.18),
                        ]),
                        startPoint: CGPoint(x: center.x, y: 0),
                        endPoint: CGPoint(x: center.x, y: size.height)
                    )
                )
            }
        }
    }

    /// Cada pétala leva o degradê da base para a ponta (B6; as mesmas misturas do script que gera a
    /// tela de lançamento, em `LaunchPalette.petalRamp`). O caminho e os dois pontos do eixo são
    /// transformados juntos, aqui, e o desenho vai para um contexto sem transformação: assim o degradê
    /// acompanha a pétala (cresce, desliza e gira com ela) sem depender de em que espaço o SwiftUI lê
    /// os pontos de um degradê dentro de um contexto transformado (não dá para conferir sem o CI).
    private func drawPetals(context: GraphicsContext, center: CGPoint, scale: CGFloat) {
        let turnRadians = frame.turn * .pi / 180
        let gradient = LaunchPalette.petalRamp(dark: isDark).gradient
        for petalIndex in 0..<5 {
            let petal = frame.petals[petalIndex]
            guard petal.opacity > 0.001 else { continue }

            let transform = petalTransform(for: petalIndex, petal: petal, turnRadians: turnRadians, center: center, scale: scale)
            let axis = LaunchFlowerGeometry.petalAxes[petalIndex]
            let path = Self.petalPaths[petalIndex].applying(transform)

            var layer = context
            layer.opacity = petal.opacity
            layer.fill(
                path,
                with: .linearGradient(
                    gradient,
                    startPoint: axis.base.applying(transform),
                    endPoint: axis.tip.applying(transform)
                )
            )

            if petalIndex == goalPetalIndex, let goalColor, frame.goalTint > 0 {
                layer.fill(path, with: .color(goalColor.opacity(frame.goalTint)))
            }
        }
    }

    private func petalTransform(for petalIndex: Int, petal: LaunchFrame.Petal, turnRadians: Double, center: CGPoint, scale: CGFloat) -> CGAffineTransform {
        let axis = LaunchFlowerGeometry.petalAxes[petalIndex]
        let base = axis.base
        let slideOffset = CGPoint(x: axis.direction.x * petal.slide, y: axis.direction.y * petal.slide)

        var transform = CGAffineTransform(translationX: -base.x, y: -base.y)
        transform = transform.concatenating(CGAffineTransform(scaleX: petal.grow, y: petal.grow))
        transform = transform.concatenating(CGAffineTransform(translationX: base.x + slideOffset.x, y: base.y + slideOffset.y))
        transform = transform.concatenating(CGAffineTransform(rotationAngle: turnRadians))
        transform = transform.concatenating(CGAffineTransform(scaleX: frame.breathe, y: frame.breathe))
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        return transform
    }

    private func drawCore(context: GraphicsContext, center: CGPoint, scale: CGFloat) {
        guard frame.coreOpacity > 0.001 else { return }
        let turnRadians = frame.turn * .pi / 180
        var transform = CGAffineTransform(scaleX: frame.coreScale, y: frame.coreScale)
        transform = transform.concatenating(CGAffineTransform(rotationAngle: turnRadians))
        transform = transform.concatenating(CGAffineTransform(scaleX: frame.breathe, y: frame.breathe))
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(CGAffineTransform(translationX: center.x, y: center.y))

        // Degradê vertical do miolo (B6), de cima para baixo no espaço do miolo; transformado junto com
        // o caminho, como nas pétalas (ver `drawPetals`).
        let halfHeight = LaunchFlowerGeometry.coreGradientHalfHeight
        var layer = context
        layer.opacity = frame.coreOpacity
        layer.fill(
            Self.corePath.applying(transform),
            with: .linearGradient(
                LaunchPalette.coreRamp(dark: isDark).gradient,
                startPoint: CGPoint(x: 0, y: -halfHeight).applying(transform),
                endPoint: CGPoint(x: 0, y: halfHeight).applying(transform)
            )
        )
    }

    private func drawPollen(context: GraphicsContext, center: CGPoint, scale: CGFloat) {
        guard !frame.pollen.isEmpty else { return }
        let turnRadians = frame.turn * .pi / 180
        let rotateAndBreathe = CGAffineTransform(rotationAngle: turnRadians)
            .concatenating(CGAffineTransform(scaleX: frame.breathe, y: frame.breathe))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
        let pollenColor = LaunchPalette.pollen(dark: isDark)

        for grain in frame.pollen where grain.opacity > 0.001 {
            let point = CGPoint(x: grain.x, y: grain.y).applying(rotateAndBreathe)
            let radius = grain.radius * scale * frame.breathe
            let rect = CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
            var layer = context
            layer.opacity = grain.opacity
            layer.fill(Path(ellipseIn: rect), with: .color(pollenColor))
        }
    }
}
