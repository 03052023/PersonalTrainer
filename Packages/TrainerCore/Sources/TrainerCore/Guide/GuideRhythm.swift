import Foundation

/// Ritmo do loop (`timing` no JSON; SPEC E7): pausa no início, ida, pausa no fim e volta. Ida e volta ficam entre
/// 0,8 e 3 s e a pausa entre 0,2 e 1 s; o cálculo do instante está em `GuideTiming`.
public struct GuideRhythm: Codable, Sendable, Hashable {
    public enum Easing: String, Codable, Sendable, Hashable, CaseIterable {
        case easeInOut
    }

    public let toEnd: Double
    public let toStart: Double
    public let hold: Double
    public let easing: Easing

    public init(toEnd: Double, toStart: Double, hold: Double, easing: Easing = .easeInOut) {
        self.toEnd = toEnd
        self.toStart = toStart
        self.hold = hold
        self.easing = easing
    }
}
