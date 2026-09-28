import Foundation

/// Quadro-chave de uma guia (SPEC E2): rótulo, legenda curta em pt-BR, pose e os dados opcionais do quadro.
public struct GuideFrame: Codable, Sendable, Hashable {
    /// Com 2 quadros, Início e Fim; com 3, Início, Meio e Fim; num `static` de 1 quadro, Posição.
    public enum Label: String, Codable, Sendable, Hashable, CaseIterable {
        case start = "Início"
        case middle = "Meio"
        case end = "Fim"
        case position = "Posição"
    }

    public let label: Label
    /// De 1 a 28 caracteres, descrevendo a posição ("Coxas paralelas ao chão").
    public let caption: String
    public let pose: GuidePose
    /// Pegada (meio da palma) no mundo, com `arms.reach` = `"grip"`.
    public let grip: GuidePoint?
    public let armDepth: GuideDepth?
    public let legDepth: GuideDepth?
    /// Dica do lado do cotovelo no IK, em graus.
    public let elbow: Double?
    /// Posição do quadril com `anchor` = `"none"`.
    public let root: GuidePoint?

    public init(
        label: Label,
        caption: String,
        pose: GuidePose,
        grip: GuidePoint? = nil,
        armDepth: GuideDepth? = nil,
        legDepth: GuideDepth? = nil,
        elbow: Double? = nil,
        root: GuidePoint? = nil
    ) {
        self.label = label
        self.caption = caption
        self.pose = pose
        self.grip = grip
        self.armDepth = armDepth
        self.legDepth = legDepth
        self.elbow = elbow
        self.root = root
    }
}
