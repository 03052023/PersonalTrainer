import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.12 E1–E10 e o formato de docs/V23-CORE-CONTRACT.md §2.5. Cada regra tem um caso bom e um ruim; o arquivo
// real do bundle é lido por #filePath (E8: "os testes garantem que o arquivo do bundle passa").

/// Arquivos reais e guias de teste do "Como fazer", compartilhados pelos testes de guia.
enum GuideTestSupport {
    /// As 4 guias do protótipo (lote 0, docs/V23-CORE-CONTRACT.md §4).
    static let batchZeroSlugs: [String] = ["barbell-back-squat", "barbell-bench-press", "seated-cable-row", "dumbbell-lateral-raise"]

    /// `Packages/TrainerCore/Tests/TrainerCoreTests/ExerciseGuideTests.swift` fica cinco componentes abaixo da raiz.
    static func repositoryURL() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }

    static func seedURL(_ fileName: String) -> URL {
        repositoryURL()
            .appendingPathComponent("PersonalTrainer", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Seed", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func goldenURL() -> URL {
        repositoryURL()
            .appendingPathComponent("Packages", isDirectory: true)
            .appendingPathComponent("TrainerCore", isDirectory: true)
            .appendingPathComponent("Tests", isDirectory: true)
            .appendingPathComponent("TrainerCoreTests", isDirectory: true)
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("exercise-guides-golden.v1.json", isDirectory: false)
    }

    static func bundleCatalog() throws -> ExerciseGuideCatalog {
        try ExerciseGuideCatalog.decode(Data(contentsOf: seedURL("exercise-guides.v1.json")))
    }

    static func bundleGuide(_ slug: String) throws -> ExerciseGuide {
        let catalog = try bundleCatalog()
        return try #require(catalog.guide(forSlug: slug), "sem guia no bundle: \(slug)")
    }

    static func seedExercises() throws -> [ExerciseDefinition] {
        try JSONDecoder().decode(SeedExerciseCatalog.self, from: Data(contentsOf: seedURL("exercises.v2.json"))).exercises
    }

    static func exercise(_ slug: String, pattern: MovementPattern) -> ExerciseDefinition {
        ExerciseDefinition(
            slug: slug,
            name: "Exercício \(slug)",
            primaryMuscles: [.quads],
            equipment: .barbell,
            loadUnit: .kilograms,
            loadIncrement: 2.5,
            movementPattern: pattern
        )
    }

    /// Catálogo mínimo dos testes: o agachamento e um exercício de pescoço (padrão com `works` obrigatório).
    static func exercises() -> [ExerciseDefinition] {
        [exercise("barbell-back-squat", pattern: .squat), exercise("neck-isometric-band", pattern: .neck)]
    }

    static func guide(_ json: String) throws -> ExerciseGuide {
        try JSONDecoder().decode(ExerciseGuide.self, from: Data(json.utf8))
    }

    /// Troca um trecho do JSON de teste, exigindo que ele exista (senão o teste mudaria nada e passaria à toa).
    static func replacing(_ json: String, _ old: String, _ new: String) throws -> String {
        try #require(json.contains(old), "trecho ausente no JSON de teste: \(old)")
        return json.replacingOccurrences(of: old, with: new)
    }

    static func problems(_ guides: [ExerciseGuide]) -> [ExerciseGuideError] {
        ExerciseGuideValidator.problems(in: ExerciseGuideCatalog(guides: guides), exercises: exercises())
    }

    static func rules(_ guides: [ExerciseGuide]) -> Set<String> {
        Set(problems(guides).map(\.rule))
    }

    /// Regras violadas pela guia deste JSON.
    static func rules(ofJSON json: String) throws -> Set<String> {
        let decoded = try guide(json)
        return rules([decoded])
    }

    /// Regras violadas pela variante do JSON com um trecho trocado.
    static func rules(ofVariant json: String, _ old: String, _ new: String) throws -> Set<String> {
        let variant = try replacing(json, old, new)
        return try rules(ofJSON: variant)
    }

    /// O agachamento do protótipo, com textos curtos: válido contra `exercises()`.
    static let squatJSON = """
    {
      "slug": "barbell-back-squat",
      "view": "side",
      "anchor": { "joint": "ankle", "at": [0.0, 0.039] },
      "timing": { "toEnd": 1.6, "toStart": 1.2, "hold": 0.4, "easing": "easeInOut" },
      "scene": [],
      "props": [ { "id": "barbell", "kind": "barbell", "attach": "back", "offset": [-0.085, 0.0] } ],
      "arms": { "reach": "barbell", "depth": 0.65, "elbow": -150 },
      "frames": [
        { "label": "Início", "caption": "Em pé, barra nas costas", "pose": { "trunk": 84, "neck": 88, "thigh": -90, "shin": -88, "foot": -12 } },
        { "label": "Fim", "caption": "Coxas paralelas ao chão", "pose": { "trunk": 50, "neck": 64, "thigh": -12, "shin": -115, "foot": -12 } }
      ],
      "cue": { "track": "hip", "offset": [-0.082, 0.0], "span": [0.0, 0.97] },
      "a11y": "Pessoa em pé dobra quadril e joelhos até as coxas ficarem paralelas ao chão e volta.",
      "steps": ["Apoie a barra no alto das costas.", "Desça até as coxas ficarem paralelas ao chão.", "Suba até ficar em pé."],
      "mistakes": ["Joelhos para dentro: aponte-os para as pontas dos pés.", "Calcanhar fora do chão: apoie o pé inteiro."]
    }
    """

    static func squat() throws -> ExerciseGuide {
        try guide(squatJSON)
    }

    /// Prancha parada (`static` de 1 quadro, com `moving`), com a âncora na ponta do pé.
    static let plankJSON = """
    {
      "slug": "barbell-back-squat",
      "view": "side",
      "motion": "static",
      "anchor": { "joint": "toe", "at": [-0.45, 0.0] },
      "scene": [],
      "props": [],
      "frames": [
        { "label": "Posição", "caption": "Corpo reto, apoiado", "pose": { "trunk": 5, "neck": 3, "thigh": -175, "shin": -175, "foot": -90, "upperArm": -90, "forearm": 0 } }
      ],
      "moving": ["trunk"],
      "a11y": "Pessoa apoiada nos antebraços e nas pontas dos pés mantém o corpo reto.",
      "steps": ["Apoie os antebraços no chão.", "Estenda as pernas para trás.", "Segure o corpo reto."],
      "mistakes": ["Quadril alto: alinhe com os ombros.", "Quadril caído: firme a barriga."]
    }
    """
}

extension ExerciseGuide {
    /// A mesma guia com outros quadros (para poses que o JSON não carrega, como ângulo infinito).
    func replacingFrames(_ frames: [GuideFrame]) -> ExerciseGuide {
        ExerciseGuide(
            slug: slug, view: view, motion: motion, anchor: anchor, timing: timing, scene: scene, props: props,
            arms: arms, frames: frames, cue: cue, moving: moving, works: works, a11y: a11y, steps: steps, mistakes: mistakes
        )
    }
}

// MARK: - E8: o arquivo do bundle

@Test("E8 o arquivo de guias do bundle decodifica e passa no validador contra o catálogo do seed")
func guideBundleFilePassesValidation() throws {
    let catalog = try GuideTestSupport.bundleCatalog()
    let exercises = try GuideTestSupport.seedExercises()

    let problems = ExerciseGuideValidator.problems(in: catalog, exercises: exercises)
    #expect(problems.isEmpty, "\(problems)")
    try ExerciseGuideValidator.validate(catalog, exercises: exercises)
    #expect(catalog.version == 1)
    #expect(catalog.rig == "mannequin-v2")
    for slug in GuideTestSupport.batchZeroSlugs {
        #expect(catalog.guide(forSlug: slug) != nil, "sem guia: \(slug)")
    }
    // guias em ordem de slug (a junção grava assim; o arquivo é gerado)
    let slugs = catalog.guides.map(\.slug)
    #expect(slugs == slugs.sorted())
}

@Test("E8 catálogo vazio não tem guias e não acha slug nenhum")
func guideEmptyCatalogHasNoGuides() {
    #expect(ExerciseGuideCatalog.empty.guides.isEmpty)
    #expect(ExerciseGuideCatalog.empty.guide(forSlug: "barbell-back-squat") == nil)
}

// MARK: - E1

@Test("E1 slug do catálogo passa; slug fora do catálogo e slug repetido são recusados")
func guideE1SlugMustExistOnce() throws {
    let squat = try GuideTestSupport.squat()
    let good = GuideTestSupport.problems([squat])
    #expect(good.isEmpty, "\(good)")

    let unknownJSON = try GuideTestSupport.replacing(GuideTestSupport.squatJSON, "\"slug\": \"barbell-back-squat\"", "\"slug\": \"nao-existe\"")
    let unknown = try GuideTestSupport.guide(unknownJSON)
    #expect(GuideTestSupport.rules([unknown]) == ["E1"])
    #expect(GuideTestSupport.rules([squat, squat]) == ["E1"])

    // com o catálogo desligado (vocabulário da ferramenta), o slug de fora passa
    let vocabulary = ExerciseGuideValidator.problems(in: ExerciseGuideCatalog(guides: [unknown]), exercises: [], checkingCatalog: false)
    #expect(vocabulary.isEmpty, "\(vocabulary)")
}

// MARK: - E2

@Test("E2 três passos, dois erros no formato 'o erro: o que fazer', legendas curtas e rótulos Início/Fim")
func guideE2FixedContent() throws {
    let base = GuideTestSupport.squatJSON
    let good = try GuideTestSupport.rules(ofJSON: base)
    #expect(good.isEmpty)

    let twoSteps = try GuideTestSupport.rules(ofVariant: base, "\"steps\": [\"Apoie a barra no alto das costas.\", ", "\"steps\": [")
    #expect(twoSteps == ["E2"])

    let noColon = try GuideTestSupport.rules(ofVariant: base, "Joelhos para dentro: aponte-os", "Joelhos para dentro, aponte-os")
    #expect(noColon == ["E2"])

    let longCaption = try GuideTestSupport.rules(
        ofVariant: base,
        "\"caption\": \"Em pé, barra nas costas\"",
        "\"caption\": \"Em pé, com a barra apoiada no alto das costas\""
    )
    #expect(longCaption == ["E2"])

    let wrongLabel = try GuideTestSupport.rules(ofVariant: base, "\"label\": \"Fim\"", "\"label\": \"Meio\"")
    #expect(wrongLabel == ["E2"])

    let oneFrameLoop = try GuideTestSupport.rules(
        ofVariant: base,
        ",\n    { \"label\": \"Fim\", \"caption\": \"Coxas paralelas ao chão\", \"pose\": { \"trunk\": 50, \"neck\": 64, \"thigh\": -12, \"shin\": -115, \"foot\": -12 } }",
        ""
    )
    #expect(oneFrameLoop.contains("E2"))
}

@Test("E2 works é obrigatório no pescoço (e no aeróbico), no máximo 60 caracteres e começa com minúscula")
func guideE2WorksRequiredForNeck() throws {
    let neckJSON = try GuideTestSupport.replacing(
        GuideTestSupport.squatJSON,
        "\"slug\": \"barbell-back-squat\"",
        "\"slug\": \"neck-isometric-band\""
    )
    let withoutWorks = try GuideTestSupport.rules(ofJSON: neckJSON)
    #expect(withoutWorks == ["E2"])

    let withWorksJSON = try GuideTestSupport.replacing(neckJSON, "\"a11y\":", "\"works\": \"pescoço\",\n  \"a11y\":")
    let withWorks = try GuideTestSupport.rules(ofJSON: withWorksJSON)
    #expect(withWorks.isEmpty)

    let capitalized = try GuideTestSupport.rules(ofVariant: withWorksJSON, "\"works\": \"pescoço\"", "\"works\": \"Pescoço\"")
    #expect(capitalized == ["E2"])
}

// MARK: - E3

@Test("E3 o arquivo usa o manequim mannequin-v2; outro rig é recusado")
func guideE3SingleRig() throws {
    let squat = try GuideTestSupport.squat()
    let good = ExerciseGuideCatalog(guides: [squat])
    let goodProblems = ExerciseGuideValidator.problems(in: good, exercises: GuideTestSupport.exercises())
    #expect(goodProblems.isEmpty, "\(goodProblems)")

    let other = ExerciseGuideCatalog(version: 1, rig: "mannequin-v1", units: "stature", guides: [squat])
    let problems = ExerciseGuideValidator.problems(in: other, exercises: GuideTestSupport.exercises())
    #expect(problems.map(\.rule) == ["E3"])
    #expect(problems.first?.slug == nil)
}

// MARK: - E4

@Test("E4 pose determinística: a mesma guia e o mesmo t dão as mesmas coordenadas")
func guideE4Determinism() throws {
    let catalog = try GuideTestSupport.bundleCatalog()
    let instants: [Double] = [0, 0.13, 0.5, 0.77, 1]
    for guide in catalog.guides {
        for t in instants {
            let first = GuideKinematics.skeleton(of: guide, at: t)
            let second = GuideKinematics.skeleton(of: guide, at: t)
            #expect(first == second, "\(guide.slug) t=\(t)")
            #expect(first.points.values.allSatisfy { $0.isFinite }, "\(guide.slug) t=\(t)")
        }
    }
}

@Test("E4 coordenada não finita é recusada")
func guideE4NonFiniteIsRejected() throws {
    let squat = try GuideTestSupport.squat()
    var broken: [GuideFrame] = []
    for frame in squat.frames {
        var angles = frame.pose.angles
        angles[.trunk] = Double.infinity
        broken.append(GuideFrame(label: frame.label, caption: frame.caption, pose: GuidePose(angles: angles)))
    }
    let rules = GuideTestSupport.rules([squat.replacingFrames(broken)])
    #expect(rules == ["E4"])
}

// MARK: - E5

@Test("E5 a âncora fica parada em todas as guias do bundle")
func guideE5AnchorPassesInBundle() throws {
    let catalog = try GuideTestSupport.bundleCatalog()
    for guide in catalog.guides {
        var collector = GuideProblemCollector(slug: guide.slug)
        ExerciseGuideValidator.checkKinematics(guide, into: &collector)
        let anchorProblems = collector.problems.filter { $0.rule == "E5" }
        #expect(anchorProblems.isEmpty, "\(guide.slug): \(collector.problems)")
    }
}

@Test("E5 âncora na mão com braços por IK sai do lugar (e o formato recusa antes)")
func guideE5AnchorOnIKHandMoves() throws {
    let json = try GuideTestSupport.replacing(
        GuideTestSupport.squatJSON,
        "\"anchor\": { \"joint\": \"ankle\", \"at\": [0.0, 0.039] }",
        "\"anchor\": { \"joint\": \"hand\", \"at\": [0.3, 0.9] }"
    )
    let guide = try GuideTestSupport.guide(json)
    var collector = GuideProblemCollector(slug: guide.slug)
    ExerciseGuideValidator.checkKinematics(guide, into: &collector)
    let anchorProblems = collector.problems.filter { $0.rule == "E5" }
    #expect(anchorProblems.count == 1)
    #expect(GuideTestSupport.rules([guide]) == [ExerciseGuideError.formatRule])
}

// MARK: - E6

@Test("E6 no supino, com o antebraço travado, o braço não estica; pegada longe demais é recusada")
func guideE6LockedForearmNeverStretches() throws {
    let bench = try GuideTestSupport.bundleGuide("barbell-bench-press")
    var collector = GuideProblemCollector(slug: bench.slug)
    ExerciseGuideValidator.checkKinematics(bench, into: &collector)
    #expect(collector.problems.isEmpty, "\(collector.problems)")

    var far: [GuideFrame] = []
    for (index, frame) in bench.frames.enumerated() {
        let grip = index == 0 ? GuidePoint(x: -0.285, y: 1.2) : frame.grip
        far.append(GuideFrame(label: frame.label, caption: frame.caption, pose: frame.pose, grip: grip, armDepth: frame.armDepth))
    }
    var stretched = GuideProblemCollector(slug: bench.slug)
    ExerciseGuideValidator.checkKinematics(bench.replacingFrames(far), into: &stretched)
    #expect(stretched.problems.map(\.rule) == ["E6"])
}

// MARK: - E7

@Test("E7 ritmo calmo: ida e volta de 0,8 a 3 s e pausa de 0,2 a 1 s")
func guideE7RhythmRanges() throws {
    let base = GuideTestSupport.squatJSON
    let good = try GuideTestSupport.rules(ofJSON: base)
    #expect(good.isEmpty)

    let fast = try GuideTestSupport.rules(ofVariant: base, "\"toEnd\": 1.6", "\"toEnd\": 0.5")
    #expect(fast == ["E7"])

    let longHold = try GuideTestSupport.rules(ofVariant: base, "\"hold\": 0.4", "\"hold\": 1.5")
    #expect(longHold == ["E7"])

    // guia parada não precisa de ritmo
    let still = try GuideTestSupport.rules(ofJSON: GuideTestSupport.plankJSON)
    #expect(still.isEmpty)
}

// MARK: - E9

@Test("E9 moving com segmentos válidos passa; segmento desconhecido e static de 1 quadro sem moving são recusados")
func guideE9MovingKeys() throws {
    let base = GuideTestSupport.plankJSON
    let plank = try GuideTestSupport.guide(base)
    let good = GuideTestSupport.problems([plank])
    #expect(good.isEmpty, "\(good)")

    let unknown = try GuideTestSupport.rules(ofVariant: base, "\"moving\": [\"trunk\"]", "\"moving\": [\"wing\"]")
    #expect(unknown == ["E9"])

    let missing = try GuideTestSupport.rules(ofVariant: base, "\"moving\": [\"trunk\"],", "")
    #expect(missing == ["E9"])
}

// MARK: - E10

@Test("E10 as articulações das guias do bundle ficam nas faixas possíveis")
func guideE10BundleJointsInRange() throws {
    let catalog = try GuideTestSupport.bundleCatalog()
    for guide in catalog.guides {
        var collector = GuideProblemCollector(slug: guide.slug)
        ExerciseGuideValidator.checkKinematics(guide, into: &collector)
        let jointProblems = collector.problems.filter { $0.rule == "E10" }
        #expect(jointProblems.isEmpty, "\(guide.slug): \(collector.problems)")
    }
}

@Test("E10 joelho dobrado para trás é recusado")
func guideE10HyperextendedKneeIsRejected() throws {
    // coxa −90 e perna −60: o joelho fica em +30°, fora de −165° a 5°
    let json = try GuideTestSupport.replacing(GuideTestSupport.squatJSON, "\"shin\": -88", "\"shin\": -60")
    let guide = try GuideTestSupport.guide(json)
    let problems = GuideTestSupport.problems([guide])
    #expect(Set(problems.map(\.rule)) == ["E10"])
    #expect(problems.contains { $0.message.contains("joelho") })
}

@Test("E10 ângulo relativo normalizado para (−180°, 180°]")
func guideE10Normalization() {
    let cases: [(input: Double, expected: Double)] = [
        (input: 0, expected: 0), (input: 180, expected: 180), (input: -180, expected: 180), (input: 190, expected: -170),
        (input: -190, expected: 170), (input: 540, expected: 180), (input: -184, expected: 176),
    ]
    for entry in cases {
        let value = GuideKinematics.normalized(entry.input)
        #expect(abs(value - entry.expected) < 1e-9, "\(entry.input) → \(value)")
    }
}

// MARK: - format

@Test("format chave obrigatória ausente: sem a11y não decodifica; loop sem timing é recusado")
func guideFormatMissingRequiredKey() throws {
    let noA11y = try GuideTestSupport.replacing(
        GuideTestSupport.squatJSON,
        "\"a11y\": \"Pessoa em pé dobra quadril e joelhos até as coxas ficarem paralelas ao chão e volta.\",",
        ""
    )
    #expect(throws: DecodingError.self) {
        _ = try GuideTestSupport.guide(noA11y)
    }

    let noTiming = try GuideTestSupport.rules(
        ofVariant: GuideTestSupport.squatJSON,
        "\"timing\": { \"toEnd\": 1.6, \"toStart\": 1.2, \"hold\": 0.4, \"easing\": \"easeInOut\" },",
        ""
    )
    #expect(noTiming == [ExerciseGuideError.formatRule])
}

@Test("format arms.reach para acessório inexistente é recusado")
func guideFormatReachToMissingProp() throws {
    let json = try GuideTestSupport.replacing(GuideTestSupport.squatJSON, "\"reach\": \"barbell\"", "\"reach\": \"barra\"")
    let guide = try GuideTestSupport.guide(json)
    let problems = GuideTestSupport.problems([guide])
    #expect(problems.map(\.rule) == [ExerciseGuideError.formatRule])
    #expect(problems.first?.message.contains("barra") == true)
}

@Test("format quadros com chaves de pose diferentes são recusados")
func guideFormatPoseKeysDiffer() throws {
    let rules = try GuideTestSupport.rules(
        ofVariant: GuideTestSupport.squatJSON,
        "\"shin\": -115, \"foot\": -12 }",
        "\"shin\": -115, \"foot\": -12, \"thighFar\": -20 }"
    )
    #expect(rules == [ExerciseGuideError.formatRule])
}

@Test("format a seta precisa de caminho: static de 1 quadro com cue é recusado")
func guideFormatCueNeedsTwoFrames() throws {
    let rules = try GuideTestSupport.rules(
        ofVariant: GuideTestSupport.plankJSON,
        "\"moving\": [\"trunk\"],",
        "\"moving\": [\"trunk\"],\n  \"cue\": { \"track\": \"hip\", \"offset\": [0.0, 0.05] },"
    )
    #expect(rules == [ExerciseGuideError.formatRule])
}
