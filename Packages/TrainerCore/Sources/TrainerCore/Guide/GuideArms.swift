import Foundation

/// Como os braços são resolvidos (docs/V23-CORE-CONTRACT.md §2.5). Sem `reach`, por ângulos (`upperArm` e `forearm`
/// da pose). Com `reach`, por IK de dois ossos até a pegada do quadro (`"grip"`) ou até um acessório nas costas, no
/// peito ou no quadril; `forearm` trava o antebraço num ângulo (supino: vertical sob a barra).
public struct GuideArms: Codable, Sendable, Hashable {
    public enum FarArm: String, Codable, Sendable, Hashable, CaseIterable {
        /// O braço de lá repete o de cá (padrão).
        case mirror
        /// O braço de lá segue `upperArmFar` e `forearmFar` dos quadros, por ângulos, enquanto o de cá usa IK.
        case pose
    }

    public static let gripReach = "grip"

    public let reach: String?
    public let depth: GuideDepth?
    /// Dica padrão do lado do cotovelo no IK, em graus; sem ela, −90.
    public let elbow: Double?
    public let forearm: Double?
    public let farArm: FarArm?

    public init(reach: String? = nil, depth: GuideDepth? = nil, elbow: Double? = nil, forearm: Double? = nil, farArm: FarArm? = nil) {
        self.reach = reach
        self.depth = depth
        self.elbow = elbow
        self.forearm = forearm
        self.farArm = farArm
    }
}
