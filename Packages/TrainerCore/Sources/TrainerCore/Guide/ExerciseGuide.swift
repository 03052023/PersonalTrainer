import Foundation

/// Guia "Como fazer" de um exercício do catálogo (SPEC RF-40 e §7.12): a figura em dados, o ritmo e os textos. O app
/// desenha e anima a figura a partir destes números (`GuideKinematics`, `GuideMotion`, `GuideTiming`); o formato
/// está congelado em docs/V23-CORE-CONTRACT.md §2.5.
///
/// A decodificação só lê: exige as chaves sem as quais não há guia (`slug`, `view`, `anchor`, `scene`, `props`,
/// `frames`, `a11y`, `steps`, `mistakes`), ignora chaves desconhecidas e deixa as regras que dependem do contexto
/// (ritmo e seta obrigatórios em `loop`, chaves da pose, referências) para o `ExerciseGuideValidator`.
public struct ExerciseGuide: Codable, Sendable, Hashable, Identifiable {
    public enum Viewpoint: String, Codable, Sendable, Hashable, CaseIterable {
        /// De lado, virado para a direita.
        case side
        /// De frente; o lado de lá é o espelho do de cá.
        case front
    }

    public enum Playback: String, Codable, Sendable, Hashable, CaseIterable {
        /// Anima em loop entre os quadros (padrão).
        case loop
        /// `"static"`: não anima nem desenha o fantasma; os quadros ficam lado a lado, com setas (SPEC E7).
        case still = "static"
    }

    public var id: String { slug }

    public let slug: String
    public let view: Viewpoint
    public let motion: Playback
    public let anchor: GuideAnchor
    public let timing: GuideRhythm?
    public let scene: [GuideSceneItem]
    public let props: [GuideProp]
    public let arms: GuideArms?
    public let frames: [GuideFrame]
    public let cue: GuideCue?
    /// Substitui o cálculo das partes em acento forte (SPEC E9); uma chave do lado de cá vale também para o de lá.
    public let moving: [String]?
    /// Substitui o "Trabalha: …" tirado do catálogo; obrigatório nos aeróbicos e no pescoço (SPEC E2).
    public let works: String?
    /// Descrição do movimento para o VoiceOver.
    public let a11y: String
    public let steps: [String]
    public let mistakes: [String]

    public init(
        slug: String,
        view: Viewpoint,
        motion: Playback = .loop,
        anchor: GuideAnchor,
        timing: GuideRhythm? = nil,
        scene: [GuideSceneItem] = [],
        props: [GuideProp] = [],
        arms: GuideArms? = nil,
        frames: [GuideFrame],
        cue: GuideCue? = nil,
        moving: [String]? = nil,
        works: String? = nil,
        a11y: String,
        steps: [String],
        mistakes: [String]
    ) {
        self.slug = slug
        self.view = view
        self.motion = motion
        self.anchor = anchor
        self.timing = timing
        self.scene = scene
        self.props = props
        self.arms = arms
        self.frames = frames
        self.cue = cue
        self.moving = moving
        self.works = works
        self.a11y = a11y
        self.steps = steps
        self.mistakes = mistakes
    }

    private enum CodingKeys: String, CodingKey {
        case slug, view, motion, anchor, timing, scene, props, arms, frames, cue, moving, works, a11y, steps, mistakes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.slug = try container.decode(String.self, forKey: .slug)
        self.view = try container.decode(Viewpoint.self, forKey: .view)
        self.motion = try container.decodeIfPresent(Playback.self, forKey: .motion) ?? .loop
        self.anchor = try container.decode(GuideAnchor.self, forKey: .anchor)
        self.timing = try container.decodeIfPresent(GuideRhythm.self, forKey: .timing)
        self.scene = try container.decode([GuideSceneItem].self, forKey: .scene)
        self.props = try container.decode([GuideProp].self, forKey: .props)
        self.arms = try container.decodeIfPresent(GuideArms.self, forKey: .arms)
        self.frames = try container.decode([GuideFrame].self, forKey: .frames)
        self.cue = try container.decodeIfPresent(GuideCue.self, forKey: .cue)
        self.moving = try container.decodeIfPresent([String].self, forKey: .moving)
        self.works = try container.decodeIfPresent(String.self, forKey: .works)
        self.a11y = try container.decode(String.self, forKey: .a11y)
        self.steps = try container.decode([String].self, forKey: .steps)
        self.mistakes = try container.decode([String].self, forKey: .mistakes)
    }
}
