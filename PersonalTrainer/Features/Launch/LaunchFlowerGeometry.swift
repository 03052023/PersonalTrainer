import SwiftUI

/// Deriva, a partir dos contornos unitários da `BrisaGeometry` (congelados, docs/V23-UI-CONTRACT.md
/// §3.2 — mesma flor do ícone e da `FlowerView`), o que a abertura precisa para animar cada pétala por
/// conta própria: o ponto onde ela nasce (a base, perto do miolo) e o eixo pelo qual ela cresce e
/// desliza para fora — o centroide de área da própria pétala, como no protótipo aprovado
/// (`docs/design/v23-animation/launch.html`, "cresce a partir da própria base e desliza pelo eixo do
/// centroide"). Números derivados da mesma geometria que o resto do app usa, nunca duplicados à mão:
/// a abertura e a `FlowerView` nunca podem desenhar flores diferentes.
enum LaunchFlowerGeometry {
    /// Ordem de abertura das pétalas (SPEC RF-50; protótipo, `ORDER`): de cima (índice 0), no sentido
    /// anti-horário — o mesmo sentido do giro. Índice = `ProgramGoal.petalIndex`.
    static let openOrder: [Int] = [0, 4, 3, 2, 1]

    /// Fração do raio externo da flor que cada pétala percorre no desabrochar (80 px do ícone de
    /// 1024, protótipo `TL.open.dist`, sobre o raio externo de 358,24 px que
    /// `docs/design/render-app-icon.ps1 -CheckDir` confirma para a mesma geometria Brisa).
    static let openSlideFraction: Double = 80.0 / 358.24

    struct PetalAxis {
        /// Onde a pétala nasce (perto do miolo), em coordenadas unitárias (raio externo da flor
        /// inteira = 1, origem no centro) — o ponto ao redor do qual ela cresce.
        let base: CGPoint
        /// Direção unitária (comprimento 1), do centro da flor até o centroide de área da pétala: o
        /// eixo pelo qual ela desliza para fora ao abrir.
        let direction: CGPoint
        /// A ponta da espinha da pétala (largura 0), em coordenadas unitárias: o fim do degradê da base
        /// para a ponta (o `Tip` que `Get-Petal` devolve em `render-launch-assets.ps1`; B6 da 2.3).
        let tip: CGPoint
    }

    /// Um item por pétala, na ordem de `ProgramGoal.petalIndex` (0 = topo, sentido horário).
    static let petalAxes: [PetalAxis] = BrisaGeometry.unitPetalOutlines.map(axis(for:))

    /// Meia altura do degradê vertical do miolo, em coordenadas unitárias: o raio do miolo (52 px do
    /// ícone de 1024) mais 4 px de folga, como o `LinearGradientBrush` do script (`render-launch-assets.ps1`,
    /// `Render-Flower`) e o protótipo (`s-ca`/`s-cb`, de `-centerR - 4` a `centerR + 4`).
    static let coreGradientHalfHeight: CGFloat = CGFloat((52.0 + 4.0) / LaunchPollen.iconMaxRadius)

    private static func axis(for outline: [CGPoint]) -> PetalAxis {
        // O primeiro ponto do contorno (`BrisaGeometry.outline`, j = 0, largura 0 na base) é a base da
        // pétala — mesmo ponto que o protótipo chama de `base` (`S(0,0)`). Um contorno vazio não
        // deveria acontecer (a Brisa sempre tem 5 pétalas não vazias, cobertas pelos testes de
        // `FlowerAndGoalStyleTests`), mas isto nunca derruba a tela (R11): sem pontos, a pétala fica
        // parada no centro, apontando para cima.
        guard let base = outline.first else {
            return PetalAxis(base: .zero, direction: CGPoint(x: 0, y: -1), tip: CGPoint(x: 0, y: -1))
        }
        // O contorno tem `2 * cnt + 1` pontos: o flanco de ida (j = 0...cnt), cujo último ponto (j = cnt,
        // índice `count / 2`) é a ponta da espinha, com largura 0, e o flanco de volta (j = cnt - 1...0).
        // `count / 2` é sempre um índice válido de um array não vazio.
        let tip = outline[outline.count / 2]
        let centroid = areaCentroid(of: outline)
        let length = (centroid.x * centroid.x + centroid.y * centroid.y).squareRoot()
        guard length > 0.0001 else {
            return PetalAxis(base: base, direction: CGPoint(x: 0, y: -1), tip: tip)
        }
        return PetalAxis(base: base, direction: CGPoint(x: centroid.x / length, y: centroid.y / length), tip: tip)
    }

    /// Centroide de área de um polígono fechado (fórmula do sapateiro), a mesma conta do protótipo
    /// (`getPetal`, JS): dá a direção para onde a pétala "pesa" mais, que é por onde ela desliza.
    private static func areaCentroid(of points: [CGPoint]) -> CGPoint {
        guard points.count > 2 else { return points.first ?? .zero }
        var area = 0.0
        var cx = 0.0
        var cy = 0.0
        for index in points.indices {
            let p0 = points[index]
            let p1 = points[(index + 1) % points.count]
            let cross = Double(p0.x) * Double(p1.y) - Double(p1.x) * Double(p0.y)
            area += cross
            cx += (Double(p0.x) + Double(p1.x)) * cross
            cy += (Double(p0.y) + Double(p1.y)) * cross
        }
        area /= 2
        guard abs(area) > 0.0000001 else { return points.first ?? .zero }
        return CGPoint(x: cx / (6 * area), y: cy / (6 * area))
    }

    /// Um `Path` fechado a partir de pontos unitários, sem centralizar nem escalar — ao contrário de
    /// `BrisaGeometry.path(for:in:)`, que já assume uma única transformação para a flor inteira. Aqui
    /// quem chama aplica a própria transformação por pétala (crescer a partir da base, deslizar, girar
    /// a flor inteira), então o `Path` fica cru, em coordenadas unitárias.
    static func path(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}
