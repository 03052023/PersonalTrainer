import Foundation
import Testing
@testable import TrainerCore

// SPEC RF-43 (medida do exercício) e §7.13 H1 (quem é de casa): marcas lidas do catálogo do seed pelo
// slug, sem campo no esquema de dados.

struct ExerciseTraitsTests {
    // MARK: - ExerciseTraits

    @Test("RF-43 padrão: repetições e fora do modo casa")
    func defaultTraits() {
        #expect(ExerciseTraits.default == ExerciseTraits(measure: .reps, atHome: false))
        #expect(ExerciseTraits() == .default)
    }

    @Test("RF-43 raw values da medida são estáveis (ficam no JSON do seed)")
    func measureRawValues() {
        #expect(ExerciseMeasure.allCases.map(\.rawValue) == ["reps", "seconds", "steps"])
    }

    struct DecodeCase: Sendable, CustomTestStringConvertible {
        let json: String
        let expected: ExerciseTraits

        var testDescription: String { json }
    }

    static let decodeCases: [DecodeCase] = [
        DecodeCase(json: "{}", expected: ExerciseTraits(measure: .reps, atHome: false)),
        DecodeCase(json: #"{"atHome": true}"#, expected: ExerciseTraits(measure: .reps, atHome: true)),
        DecodeCase(json: #"{"measure": "seconds"}"#, expected: ExerciseTraits(measure: .seconds, atHome: false)),
        DecodeCase(json: #"{"measure": "steps", "atHome": true}"#, expected: ExerciseTraits(measure: .steps, atHome: true)),
        DecodeCase(json: #"{"measure": null, "atHome": null}"#, expected: ExerciseTraits(measure: .reps, atHome: false)),
        DecodeCase(json: #"{"slug": "plank", "measure": "seconds", "atHome": true}"#, expected: ExerciseTraits(measure: .seconds, atHome: true)),
    ]

    @Test("RF-43/H1 chave ausente ou nula vale o padrão (reps, fora de casa)", arguments: ExerciseTraitsTests.decodeCases)
    func decodeIsTolerant(_ testCase: DecodeCase) throws {
        let decoded = try JSONDecoder().decode(ExerciseTraits.self, from: Data(testCase.json.utf8))

        #expect(decoded == testCase.expected)
    }

    @Test("RF-43 ExerciseTraits faz round-trip Codable")
    func traitsCodableRoundTrip() throws {
        let values: [ExerciseTraits] = [.default, ExerciseTraits(measure: .steps, atHome: true)]

        for value in values {
            let data = try JSONEncoder().encode(value)
            #expect(try JSONDecoder().decode(ExerciseTraits.self, from: data) == value)
        }
    }

    // MARK: - ExerciseTraitsCatalog

    @Test("RF-43 catálogo lê medida e casa por slug; slug desconhecido vale o padrão")
    func catalogDecodesBySlug() throws {
        let json = """
        {"version": 3, "exercises": [
          {"slug": "plank", "name": "Prancha", "measure": "seconds", "atHome": true},
          {"slug": "farmers-walk", "measure": "steps", "atHome": false},
          {"slug": "push-up", "atHome": true},
          {"slug": "barbell-bench-press"}
        ]}
        """

        let catalog = try ExerciseTraitsCatalog.decode(seedCatalogJSON: Data(json.utf8))

        #expect(catalog.traits(forSlug: "plank") == ExerciseTraits(measure: .seconds, atHome: true))
        #expect(catalog.traits(forSlug: "farmers-walk") == ExerciseTraits(measure: .steps, atHome: false))
        #expect(catalog.traits(forSlug: "push-up") == ExerciseTraits(measure: .reps, atHome: true))
        #expect(catalog.traits(forSlug: "barbell-bench-press") == .default)
        #expect(catalog.traits(forSlug: "nao-existe") == .default)
    }

    @Test("RF-43 slug repetido: vale a primeira ocorrência")
    func catalogKeepsFirstOccurrence() throws {
        let json = #"{"exercises": [{"slug": "plank", "measure": "seconds"}, {"slug": "plank", "measure": "steps"}]}"#

        let catalog = try ExerciseTraitsCatalog.decode(seedCatalogJSON: Data(json.utf8))

        #expect(catalog.traits(forSlug: "plank").measure == .seconds)
    }

    @Test("RF-43 exercício personalizado usa reps e não entra no modo casa, mesmo com slug do seed")
    func customExerciseAlwaysUsesDefaults() {
        let catalog = ExerciseTraitsCatalog(traitsBySlug: ["plank": ExerciseTraits(measure: .seconds, atHome: true)])
        let seedPlank = Self.exercise(slug: "plank", isCustom: false)
        let customPlank = Self.exercise(slug: "plank", isCustom: true)

        #expect(catalog.traits(for: seedPlank) == ExerciseTraits(measure: .seconds, atHome: true))
        #expect(catalog.traits(for: customPlank) == .default)
    }

    @Test("RF-43 catálogo vazio: tudo em repetições e ninguém em casa")
    func emptyCatalogUsesDefaults() {
        #expect(ExerciseTraitsCatalog.empty.traits(forSlug: "plank") == .default)
        #expect(ExerciseTraitsCatalog.empty.traits(for: Self.exercise(slug: "plank", isCustom: false)) == .default)
        #expect(ExerciseTraitsCatalog.empty == ExerciseTraitsCatalog(traitsBySlug: [:]))
    }

    static let malformedCatalogs: [String] = [
        "{ not json",
        #"{"version": 3}"#,
        #"{"exercises": [{"name": "Sem slug"}]}"#,
        #"{"exercises": [{"slug": "plank", "measure": "minutes"}]}"#,
        #"{"exercises": [{"slug": "plank", "atHome": "sim"}]}"#,
    ]

    @Test("RF-43 JSON malformado, sem slug ou com medida desconhecida lança erro", arguments: ExerciseTraitsTests.malformedCatalogs)
    func catalogDecodeRejectsMalformedJSON(_ json: String) {
        #expect(throws: (any Error).self) {
            try ExerciseTraitsCatalog.decode(seedCatalogJSON: Data(json.utf8))
        }
    }

    // MARK: - Real seed file

    @Test("RF-43/H1 o seed traz atHome em todo exercício e measure só quando não é reps")
    func seedWritesTraitsExplicitly() throws {
        let file = try JSONDecoder().decode(RawSeedFile.self, from: SeedTestFiles.catalogData())

        #expect(!file.exercises.isEmpty)
        for entry in file.exercises {
            if let measure = entry.measure {
                #expect(measure != ExerciseMeasure.reps.rawValue, "\(entry.slug): reps não precisa ser escrito")
                #expect(ExerciseMeasure(rawValue: measure) != nil, "\(entry.slug): medida \(measure)")
            }
        }
    }

    @Test("RF-43 no seed, carregadas medem em passos, pranchas e isometrias em segundos, o resto em repetições")
    func seedMeasuresFollowTheExerciseKind() throws {
        let bundle = try SeedTestFiles.bundle()
        let traits = try SeedTestFiles.traits()
        let isometrics: Set<String> = ["plank", "side-plank", "neck-isometric-band", "manual-neck-isometric"]

        for exercise in bundle.catalog.exercises {
            let expected: ExerciseMeasure
            if exercise.movementPattern == .carry {
                expected = .steps
            } else if isometrics.contains(exercise.slug) {
                expected = .seconds
            } else {
                expected = .reps
            }
            #expect(traits.traits(for: exercise).measure == expected, "\(exercise.slug)")
        }
    }

    @Test("H1 no seed, equipamento de academia nunca é de casa e objeto de casa sempre é")
    func seedAtHomeFollowsEquipment() throws {
        let bundle = try SeedTestFiles.bundle()
        let traits = try SeedTestFiles.traits()
        let gymEquipment: Set<Equipment> = [.barbell, .dumbbell, .machine, .cable, .smith, .kettlebell]
        let homeEquipment: Set<Equipment> = [.bodyweight, .household]

        for exercise in bundle.catalog.exercises {
            let atHome = traits.traits(for: exercise).atHome
            if gymEquipment.contains(exercise.equipment) {
                #expect(!atHome, "\(exercise.slug) usa \(exercise.equipment.rawValue)")
            }
            if exercise.equipment == .household {
                #expect(atHome, "\(exercise.slug) é objeto de casa")
            }
            if atHome {
                #expect(homeEquipment.contains(exercise.equipment), "\(exercise.slug)")
            }
        }
    }

    @Test("H1 no seed, peso do corpo que exige aparelho não é de casa; sem aparelho, é")
    func seedBodyweightNeedingApparatusIsNotAtHome() throws {
        let traits = try SeedTestFiles.traits()
        // Barra fixa, paralelas, banco 45°, caixa de salto, apoio para os pés e faixa elástica.
        let needsApparatus = [
            "pull-up", "chin-up", "parallel-bar-dip", "inverted-row", "back-extension-45", "box-jump",
            "hanging-leg-raise", "nordic-hamstring-curl", "neck-isometric-band",
        ]
        let noApparatus = [
            "push-up", "plank", "side-plank", "dead-bug", "bird-dog", "glute-bridge", "floor-crunch",
            "box-squat", "jump-squat", "manual-neck-isometric",
        ]

        for slug in needsApparatus {
            #expect(!traits.traits(forSlug: slug).atHome, "\(slug)")
        }
        for slug in noApparatus {
            #expect(traits.traits(forSlug: slug).atHome, "\(slug)")
        }
    }

    @Test("RF-42 o seed traz os exercícios novos de casa, todos marcados atHome")
    func seedHasNewHomeExercises() throws {
        let bundle = try SeedTestFiles.bundle()
        let traits = try SeedTestFiles.traits()
        let bySlug = Dictionary(bundle.catalog.exercises.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })

        for slug in SeedTestFiles.newHomeSlugs {
            let exercise = try #require(bySlug[slug], "ausente: \(slug)")
            #expect(traits.traits(for: exercise).atHome, "\(slug)")
            #expect(exercise.movementPattern != nil, "\(slug)")
        }
    }

    @Test("RF-43 o catálogo de marcas do seed cobre todos os slugs do catálogo")
    func seedTraitsCoverEverySlug() throws {
        let file = try JSONDecoder().decode(RawSeedFile.self, from: SeedTestFiles.catalogData())
        let bundle = try SeedTestFiles.bundle()

        #expect(file.exercises.map(\.slug) == bundle.catalog.exercises.map(\.slug))
    }

    // MARK: - Helpers

    static func exercise(slug: String, isCustom: Bool) -> ExerciseDefinition {
        ExerciseDefinition(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
            slug: slug,
            name: "Prancha",
            primaryMuscles: [.core],
            equipment: .bodyweight,
            loadUnit: .kilograms,
            loadIncrement: 2.5,
            movementPattern: .coreStability,
            isCustom: isCustom
        )
    }
}

/// O JSON do seed como está escrito: `atHome` obrigatório (falha se faltar) e `measure` opcional.
private struct RawSeedFile: Decodable {
    struct Entry: Decodable {
        let slug: String
        let atHome: Bool
        let measure: String?
    }

    let exercises: [Entry]
}

/// Arquivos reais do seed (`PersonalTrainer/Resources/Seed`), lidos pelo caminho deste arquivo.
enum SeedTestFiles {
    /// Exercícios de casa acrescentados na versão 2.1 (RF-42).
    static let newHomeSlugs: [String] = [
        "chair-incline-push-up", "knee-push-up", "pike-push-up", "water-bottle-shoulder-press", "chair-dip",
        "water-bottle-overhead-triceps-extension", "bodyweight-squat", "chair-bulgarian-split-squat",
        "bodyweight-lunge", "bodyweight-reverse-lunge", "single-leg-romanian-deadlift", "single-leg-glute-bridge",
        "step-calf-raise", "single-leg-step-calf-raise", "backpack-bent-over-row", "one-arm-backpack-row",
        "prone-ytw-raise", "backpack-pullover", "backpack-curl", "water-bottle-lateral-raise", "grocery-bag-carry",
        "superman", "towel-leg-curl", "lying-leg-raise",
    ]

    /// `Packages/TrainerCore/Tests/TrainerCoreTests/ExerciseTraitsTests.swift` fica cinco componentes
    /// abaixo da raiz do repositório.
    static func url(_ fileName: String) -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
            .appendingPathComponent("PersonalTrainer", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Seed", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func catalogData() throws -> Data {
        try Data(contentsOf: url("exercises.v2.json"))
    }

    static func bundle() throws -> SeedBundle {
        try SeedBundle.decode(catalogData: catalogData(), programData: Data(contentsOf: url("programs.v2.json")))
    }

    static func traits() throws -> ExerciseTraitsCatalog {
        try ExerciseTraitsCatalog.decode(seedCatalogJSON: catalogData())
    }
}
