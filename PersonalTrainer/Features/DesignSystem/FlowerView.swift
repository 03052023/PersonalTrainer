import SwiftUI
import TrainerCore

/// A flor de cinco pétalas do ícone, reaproveitada como identidade visual dentro do app
/// (DESIGN.md §2/§4). A pétala do objetivo ativo fica preenchida com a cor dele; as outras ficam
/// em contorno, porque a flor inteira é a pessoa inteira e todos os objetivos têm espaço.
///
/// Desde a 2.2 (SPEC decisão 18), a geometria é a Brisa: cada pétala nasce de uma espinha levemente
/// curva, com giro, inclinação e ondulação próprios — como uma flor mexida pelo vento —, o mesmo
/// desenho do ícone (`docs/design/render-app-icon.ps1`, portado de
/// `docs/design/icon-v22/render-icon-v22.ps1`, candidato 6 · Brisa). Ver `BrisaGeometry` abaixo.
///
/// `size` é o diâmetro total da flor, ponta a ponta das pétalas (na Home, cerca de 56 pt).
struct FlowerView: View {
    let activeGoal: ProgramGoal?
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Init explícito (integração onda 3): com a propriedade `private` acima, o init sintetizado
    /// poderia ficar privado e a Home, em outro arquivo, não conseguiria criar a flor.
    init(activeGoal: ProgramGoal?, size: CGFloat) {
        self.activeGoal = activeGoal
        self.size = size
    }

    private static let outlineWidth: CGFloat = 1.5

    var body: some View {
        ZStack {
            ForEach(ProgramGoal.allCases, id: \.self) { goal in
                petal(for: goal)
            }
            BrisaCenterShape()
                .fill(Theme.flowerCenter)
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
        // Reduzir Movimento: troca a transição suave por uma mudança direta (DESIGN §10).
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: activeGoal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Mesma forma sempre (mesma identidade de view), só muda preenchimento e contorno — para o
    /// preenchimento poder ser animado em vez de trocado abruptamente quando o objetivo ativo muda.
    private func petal(for goal: ProgramGoal) -> some View {
        let isActive = goal == activeGoal
        return BrisaPetalShape(petalIndex: goal.petalIndex)
            .fill(isActive ? goal.color : Color.clear)
            .overlay(
                BrisaPetalShape(petalIndex: goal.petalIndex)
                    .stroke(Theme.textSecondary, lineWidth: Self.outlineWidth)
                    .opacity(isActive ? 0 : 1)
            )
            .frame(width: size, height: size)
    }

    private var accessibilityLabel: Text {
        if let activeGoal {
            Text("Objetivo ativo: \(activeGoal.displayName)")
        } else {
            Text("Objetivo ainda não escolhido")
        }
    }
}

/// Uma pétala da flor Brisa (DESIGN §2), na posição do objetivo de índice `petalIndex`
/// (`ProgramGoal.petalIndex`: 0 = topo, sentido horário). O contorno vem pronto de `BrisaGeometry`,
/// calculado uma única vez em coordenadas unitárias (raio externo da flor inteira = 1) e só
/// escalado e centralizado aqui para o `rect` pedido — nada de `Date()` nem de números aleatórios.
struct BrisaPetalShape: Shape {
    let petalIndex: Int

    func path(in rect: CGRect) -> Path {
        // `petalIndex` só deveria vir de `ProgramGoal.petalIndex` (sempre 0–4); um índice fora da
        // faixa não deve derrubar a tela, só não desenhar nada (R11: sem força-unwrap/crash na UI).
        guard BrisaGeometry.unitPetalOutlines.indices.contains(petalIndex) else { return Path() }
        return BrisaGeometry.path(for: BrisaGeometry.unitPetalOutlines[petalIndex], in: rect)
    }
}

/// O miolo levemente irregular da flor Brisa (harmônicos fixos), normalizado na mesma escala das
/// pétalas (`BrisaGeometry.unitCenterOutline`).
struct BrisaCenterShape: Shape {
    func path(in rect: CGRect) -> Path {
        BrisaGeometry.path(for: BrisaGeometry.unitCenterOutline, in: rect)
    }
}

/// Modelo da pétala Brisa, portado de `docs/design/icon-v22/render-icon-v22.ps1`
/// (`$Candidates['brisa']`) e usado igual pelo ícone (`docs/design/render-app-icon.ps1`): mesmos
/// números, para o ícone e a `FlowerView` serem a mesma flor.
///
/// Coordenadas locais (u, v): u = para fora, a partir da base da pétala (a `r0` do centro da flor);
/// v = sentido horário. Cada pétala nasce de uma espinha em Bézier cúbica com desvio lateral (`b2`,
/// `b3`), um perfil de largura que sobe até `tm` e fecha num quarto de elipse (a ponta redonda da
/// gota), giro (`tilt`), assimetria de cabeça (`lean`) e de flanco (`asym`, crescendo para a ponta) e
/// ondulação de borda feita à mão (`wobP`/`wobM`); a flor inteira gira `rotation` e cada pétala soma
/// o próprio `dAngle`. A Brisa não usa base alargada (`w0 = 0`), torção nem riscos, então só o
/// contorno importa (sem holes, sem "fold").
private enum BrisaGeometry {
    /// Termo de ondulação: `amplitude · sen(2π · cycles · t + phase)`.
    struct Wobble {
        let amplitude: Double
        let cycles: Double
        let phase: Double
    }

    private struct PetalParameters {
        let length: Double
        let halfWidth: Double
        let dAngle: Double
        let tilt: Double
        let b2: Double
        let b3: Double
        let lean: Double
        let asym: Double
        let wobP: [Wobble]
        let wobM: [Wobble]
    }

    /// Giro geral da flor (graus); cada pétala soma o próprio `dAngle`.
    private static let rotation: Double = -5
    /// Comuns às 5 pétalas.
    private static let r0: Double = 70
    private static let tm: Double = 0.62
    private static let alpha: Double = 0.68
    private static let w0: Double = 0.0
    private static let b1: Double = 0.0
    private static let asymK: Double = 1.3
    /// Miolo: raio e harmônicos da irregularidade.
    private static let centerRadius: Double = 52
    private static let centerHarmonics: [Wobble] = [
        Wobble(amplitude: 0.025, cycles: 2, phase: 0.6),
        Wobble(amplitude: 0.018, cycles: 3, phase: 2.1),
    ]
    /// Amostras por flanco: modesto (a curva não tem cantos vivos e a flor nunca é grande o bastante
    /// para expor a poligonal), mas o bastante para a ondulação (até ~2,4 ciclos) sair lisa.
    private static let samplesPerFlank = 56

    /// Um item por pétala, índice = `ProgramGoal.petalIndex` (0 = topo, sentido horário).
    private static let perPetal: [PetalParameters] = [
        PetalParameters(length: 270, halfWidth: 97, dAngle: 0.0, tilt: -11, b2: 0.10, b3: 0.26, lean: 0.06, asym: 0.12,
                        wobP: [Wobble(amplitude: 0.020, cycles: 1.6, phase: 0.4)],
                        wobM: [Wobble(amplitude: 0.016, cycles: 2.1, phase: 2.2)]),
        PetalParameters(length: 252, halfWidth: 103, dAngle: 2.5, tilt: -7, b2: 0.07, b3: 0.18, lean: 0.03, asym: 0.09,
                        wobP: [Wobble(amplitude: 0.018, cycles: 1.9, phase: 1.1)],
                        wobM: [Wobble(amplitude: 0.020, cycles: 1.4, phase: 4.0)]),
        PetalParameters(length: 275, halfWidth: 95, dAngle: 1.0, tilt: -14, b2: 0.12, b3: 0.30, lean: 0.07, asym: 0.14,
                        wobP: [Wobble(amplitude: 0.016, cycles: 2.3, phase: 5.0)],
                        wobM: [Wobble(amplitude: 0.018, cycles: 1.7, phase: 0.9)]),
        PetalParameters(length: 257, halfWidth: 101, dAngle: -1.0, tilt: -8, b2: 0.08, b3: 0.20, lean: 0.04, asym: 0.10,
                        wobP: [Wobble(amplitude: 0.020, cycles: 1.5, phase: 3.3)],
                        wobM: [Wobble(amplitude: 0.015, cycles: 2.4, phase: 1.8)]),
        PetalParameters(length: 264, halfWidth: 97, dAngle: -2.5, tilt: -12, b2: 0.10, b3: 0.25, lean: 0.06, asym: 0.12,
                        wobP: [Wobble(amplitude: 0.018, cycles: 2.0, phase: 2.7)],
                        wobM: [Wobble(amplitude: 0.019, cycles: 1.8, phase: 5.6)]),
    ]

    /// As 5 pétalas em coordenadas de tela (origem no centro da flor, escala 1 = px de referência do
    /// ícone de 1024) e o maior raio entre todos os pontos delas — igual ao `Get-Bounds`/`maxR` do
    /// gerador, usado para normalizar tudo a seguir.
    private static let rawFlower: (petals: [[CGPoint]], maxRadius: Double) = {
        let petals = perPetal.enumerated().map { index, parameters in
            outline(for: parameters, angle: rotation + 72 * Double(index) + parameters.dAngle)
        }
        let maxRadius = petals.reduce(0.0) { partial, points in
            points.reduce(partial) { farthest, point in
                max(farthest, (point.x * point.x + point.y * point.y).squareRoot())
            }
        }
        return (petals, maxRadius)
    }()

    /// Caminhos unitários das 5 pétalas (índice = `ProgramGoal.petalIndex`), normalizados para o raio
    /// externo da flor inteira = 1 — como `Draw-AppFlower` do gerador, que escala pelo mesmo `k` para
    /// as pétalas e o miolo.
    static let unitPetalOutlines: [[CGPoint]] = {
        let (petals, maxRadius) = rawFlower
        return petals.map { points in points.map { CGPoint(x: $0.x / maxRadius, y: $0.y / maxRadius) } }
    }()

    /// O miolo, normalizado pelo mesmo `maxRadius` das pétalas (não pelo próprio raio dele).
    static let unitCenterOutline: [CGPoint] = {
        centerOutline().map { CGPoint(x: $0.x / rawFlower.maxRadius, y: $0.y / rawFlower.maxRadius) }
    }()

    /// Converte um caminho unitário (raio externo da flor = 1) num `Path` escalado e centralizado em
    /// `rect`, com o raio externo = `min(rect.width, rect.height) / 2`.
    static func path(for unitPoints: [CGPoint], in rect: CGRect) -> Path {
        var path = Path()
        guard let first = unitPoints.first else { return path }
        let scale = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func place(_ point: CGPoint) -> CGPoint {
            CGPoint(x: center.x + point.x * scale, y: center.y + point.y * scale)
        }
        path.move(to: place(first))
        for point in unitPoints.dropFirst() {
            path.addLine(to: place(point))
        }
        path.closeSubpath()
        return path
    }

    // MARK: - Matemática da espinha (Bézier cúbica escalar) e do perfil de largura

    private static func bezier(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ t: Double) -> Double {
        let m = 1 - t
        return m * m * m * a + 3 * m * m * t * b + 3 * m * t * t * c + t * t * t * d
    }

    private static func bezierDerivative(_ a: Double, _ b: Double, _ c: Double, _ d: Double, _ t: Double) -> Double {
        let m = 1 - t
        return 3 * m * m * (b - a) + 6 * m * t * (c - b) + 3 * t * t * (d - c)
    }

    private static func wobble(_ terms: [Wobble], _ t: Double) -> Double {
        terms.reduce(0.0) { $0 + $1.amplitude * sin(2 * .pi * $1.cycles * t + $1.phase) }
    }

    /// Sobe em seno até a largura máxima em `tm` e fecha num quarto de elipse (a ponta redonda da gota).
    private static func widthProfile(_ t: Double, _ tm: Double, _ alpha: Double, _ w0: Double) -> Double {
        if t <= tm {
            let s = t / tm
            return w0 + (1 - w0) * pow(sin(.pi / 2 * s), alpha)
        }
        let s = (t - tm) / (1 - tm)
        return (max(0.0, 1 - s * s)).squareRoot()
    }

    /// O contorno de uma pétala (sem holes/fold/riscos: a Brisa não usa nenhum), em coordenadas de
    /// tela com origem no centro da flor.
    private static func outline(for p: PetalParameters, angle: Double) -> [CGPoint] {
        let cnt = samplesPerFlank
        let tau = p.tilt * .pi / 180
        let (ct, st) = (cos(tau), sin(tau))
        let angleR = angle * .pi / 180
        let (ca, sa) = (cos(angleR), sin(angleR))
        let (q1, q2, q3) = (b1 * p.length, p.b2 * p.length, p.b3 * p.length)

        var u = [Double](repeating: 0, count: cnt + 1)
        var v = [Double](repeating: 0, count: cnt + 1)
        var normalU = [Double](repeating: 0, count: cnt + 1)
        var normalV = [Double](repeating: 0, count: cnt + 1)
        var widthP = [Double](repeating: 0, count: cnt + 1)
        var widthM = [Double](repeating: 0, count: cnt + 1)

        for j in 0...cnt {
            // Mais amostras nas duas pontas, onde a largura muda rápido.
            let t = (1 - cos(.pi * Double(j) / Double(cnt))) / 2
            let su = bezier(0, p.length / 3, 2 * p.length / 3, p.length, t)
            let sv = bezier(0, q1, q2, q3, t)
            let du = bezierDerivative(0, p.length / 3, 2 * p.length / 3, p.length, t)
            let dv = bezierDerivative(0, q1, q2, q3, t)
            let dl = (du * du + dv * dv).squareRoot()
            let asymT = pow(t, asymK)
            u[j] = su
            v[j] = sv
            normalU[j] = -dv / dl
            normalV[j] = du / dl
            widthP[j] = p.halfWidth * widthProfile(t, tm + p.lean, alpha, w0) * (1 + p.asym * asymT) * (1 + wobble(p.wobP, t))
            widthM[j] = p.halfWidth * widthProfile(t, tm - p.lean, alpha, w0) * (1 - p.asym * asymT) * (1 + wobble(p.wobM, t))
        }

        // (u, v) → tela: inclina (tilt) em torno da base da pétala, afasta `r0` do centro e gira pelo
        // ângulo total da pétala (giro geral + 72°×índice + `dAngle`).
        func toScreen(_ pu: Double, _ pv: Double) -> CGPoint {
            let u2 = pu * ct - pv * st
            let v2 = pu * st + pv * ct
            let x = v2
            let y = -(r0 + u2)
            return CGPoint(x: x * ca - y * sa, y: x * sa + y * ca)
        }

        var points: [CGPoint] = []
        points.reserveCapacity(2 * (cnt + 1))
        for j in 0...cnt {
            points.append(toScreen(u[j] + normalU[j] * widthP[j], v[j] + normalV[j] * widthP[j]))
        }
        for j in stride(from: cnt - 1, through: 0, by: -1) {
            points.append(toScreen(u[j] - normalU[j] * widthM[j], v[j] - normalV[j] * widthM[j]))
        }
        return points
    }

    /// O miolo: um disco levemente irregular (harmônicos fixos), não um círculo perfeito.
    private static func centerOutline(samples: Int = 64) -> [CGPoint] {
        (0..<samples).map { j in
            let theta = 2 * Double.pi * Double(j) / Double(samples)
            let radius = centerHarmonics.reduce(centerRadius) { partial, harmonic in
                partial + centerRadius * harmonic.amplitude * sin(harmonic.cycles * theta + harmonic.phase)
            }
            return CGPoint(x: radius * sin(theta), y: -radius * cos(theta))
        }
    }
}
