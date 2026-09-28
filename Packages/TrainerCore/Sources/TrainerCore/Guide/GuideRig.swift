import Foundation

/// O manequim único do "Como fazer" (SPEC E3), em estaturas (H = 1). Comprimentos de Drillis e Contini (1966),
/// reproduzidos em Winter, *Biomechanics and Motor Control of Human Movement*: braço 0,186 H, antebraço 0,146 H,
/// mão 0,108 H, coxa 0,245 H e perna 0,246 H; tronco (quadril → ombro) 0,288 H e pescoço e cabeça 0,122 H. São as
/// constantes `$Rig`, `$GripAt`, `$FistAt` e `$Rad` de docs/design/exercise-guides/render-exercise-guides.ps1.
public enum GuideRig {
    public static let name = "mannequin-v2"

    public static let trunk = 0.288
    public static let neck = 0.122
    public static let thigh = 0.245
    public static let shin = 0.246
    public static let foot = 0.125
    public static let upperArm = 0.186
    public static let forearm = 0.146
    public static let hand = 0.108

    /// A pegada fica no meio da palma: 40% da mão depois do punho.
    public static let gripAt = 0.40
    /// A mão fechada vai do punho até 55% do comprimento da mão.
    public static let fistAt = 0.55

    /// Do cotovelo até a pegada, sem escorço.
    public static var reach: Double {
        forearm + gripAt * hand
    }

    /// Calcanhar a partir do tornozelo, girado pelo ângulo do pé (vista lateral).
    public static let heelOffset = GuidePoint(x: -0.035, y: -0.026)
    /// Vista frontal: meia largura dos ombros, queda do ombro abaixo da base do pescoço e meia largura do quadril.
    public static let frontShoulderHalfWidth = 0.118
    public static let frontShoulderDrop = 0.012
    public static let frontHipHalfWidth = 0.085
    /// Vista frontal: ponta do pé a partir do tornozelo (x espelhado no lado de lá).
    public static let frontToeOffset = GuidePoint(x: 0.03, y: -0.026)
    /// Deslocamento do desenho do lado de lá na vista lateral (a câmera fica um pouco acima e à frente).
    public static let farShift = GuidePoint(x: -0.016, y: 0.013)

    /// Dica padrão do lado do cotovelo no IK, em graus.
    public static let defaultElbowHint = -90.0

    /// E9: um segmento se move quando gira pelo menos 12° ou o meio dele anda pelo menos 0,04 H.
    public static let movingAngle = 12.0
    public static let movingShift = 0.04

    /// E5: a âncora não sai do lugar mais que 0,001 H.
    public static let anchorTolerance = 0.001
    /// E6: a mão chega ao alvo alcançável com 0,005 H, e o braço não estica mais que isso.
    public static let reachTolerance = 0.005

    /// Raios do desenho (o casco de cada segmento), em estaturas.
    public enum Radius {
        public static let hip = 0.062
        public static let chest = 0.067
        public static let neck = 0.024
        public static let head = 0.064
        public static let thighTop = 0.055
        public static let knee = 0.038
        public static let kneeLow = 0.034
        public static let ankle = 0.024
        public static let heel = 0.019
        public static let toe = 0.013
        public static let shoulder = 0.034
        public static let elbow = 0.029
        public static let elbowLow = 0.027
        public static let wrist = 0.021
        public static let hand = 0.025
        /// Anilha da barra vista de frente.
        public static let plate = 0.074
        /// Rolo acolchoado sem `radius`.
        public static let roller = 0.035
        /// Medicine ball.
        public static let ball = 0.07
    }

    /// Espessuras padrão da cena sem `thick`.
    public static let padThickness = 0.042
    public static let postThickness = 0.024
}
