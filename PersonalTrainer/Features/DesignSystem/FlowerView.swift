import SwiftUI
import TrainerCore

/// A flor de cinco pétalas do ícone, reaproveitada como identidade visual dentro do app
/// (DESIGN.md §2/§4). A pétala do objetivo ativo fica preenchida com a cor dele; as outras ficam
/// em contorno, porque a flor inteira é a pessoa inteira e todos os objetivos têm espaço.
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
    /// 2 × 52 px de raio do miolo, sobre 676 px (2 × os 338 px de raio externo) no ícone de 1024 px.
    private static let centerDiameterRatio: CGFloat = 104.0 / 676.0

    var body: some View {
        ZStack {
            ForEach(ProgramGoal.allCases, id: \.self) { goal in
                petal(for: goal)
            }
            Circle()
                .fill(Theme.flowerCenter)
                .frame(width: size * Self.centerDiameterRatio, height: size * Self.centerDiameterRatio)
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
        return PetalShape()
            .fill(isActive ? goal.color : Color.clear)
            .overlay(
                PetalShape()
                    .stroke(Theme.textSecondary, lineWidth: Self.outlineWidth)
                    .opacity(isActive ? 0 : 1)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(Double(goal.petalIndex) * 72))
    }

    private var accessibilityLabel: Text {
        if let activeGoal {
            Text("Objetivo ativo: \(activeGoal.displayName)")
        } else {
            Text("Objetivo ainda não escolhido")
        }
    }
}

/// Uma pétala em gota, igual à do ícone (`docs/design/render-app-icon.ps1`): estreita junto ao
/// miolo e aberta para fora, a direção do crescimento. Desenhada apontando para cima, em torno do
/// centro do retângulo recebido; `FlowerView` gira cada cópia para posicioná-la.
private struct PetalShape: Shape {
    /// Mesmas proporções do gerador do ícone (raio de referência 338 px de 1024 px): posição da
    /// largura máxima ao longo do comprimento e curvatura da base junto ao miolo.
    private let widthPosition = 0.66
    private let baseControl = 0.40
    /// Constante de Kappa da aproximação de um quarto de círculo por Bézier cúbica.
    private let bezierKappa = 0.5523

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let r0 = radius * (68.0 / 338.0)
        let halfWidth = radius * (98.0 / 338.0)
        let length = radius - r0
        let widestY = r0 + widthPosition * length
        let center = CGPoint(x: rect.midX, y: rect.midY)

        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: center.x + x, y: center.y + y)
        }

        var path = Path()
        path.move(to: point(0, -r0))
        path.addCurve(
            to: point(halfWidth, -widestY),
            control1: point(halfWidth * baseControl, -r0),
            control2: point(halfWidth, -(r0 + 0.26 * length))
        )
        path.addCurve(
            to: point(0, -radius),
            control1: point(halfWidth, -(widestY + bezierKappa * (radius - widestY))),
            control2: point(bezierKappa * halfWidth, -radius)
        )
        path.addCurve(
            to: point(-halfWidth, -widestY),
            control1: point(-bezierKappa * halfWidth, -radius),
            control2: point(-halfWidth, -(widestY + bezierKappa * (radius - widestY)))
        )
        path.addCurve(
            to: point(0, -r0),
            control1: point(-halfWidth, -(r0 + 0.26 * length)),
            control2: point(-halfWidth * baseControl, -r0)
        )
        path.closeSubpath()
        return path
    }
}
