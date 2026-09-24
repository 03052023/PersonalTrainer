import Foundation
import Testing
@testable import TrainerCore

// SPEC RF-42 e §7.13 H1–H3: cada exercício do dia vira o equivalente de casa (mesmo padrão e um grupo
// primário em comum, na ordem do RF-34; senão, o mesmo grupo primário; senão, sai da sessão), sem
// repetir exercício no mesmo dia.

struct HomeSubstitutionTests {
    // MARK: - H1

    @Test("H1 exercício de casa fica como está")
    func homeExerciseStays() {
        let swaps = HomeSubstitution.swaps(for: [HF.pushUp], catalog: HF.catalog, traits: HF.traits)

        #expect(swaps == [HomeSwap(originalID: HF.pushUp.id, replacement: HF.pushUp)])
        #expect(swaps.first?.isUnchanged == true)
    }

    @Test("H1 exercício personalizado nunca é de casa, mesmo com o slug de um exercício de casa")
    func customExerciseIsNeverAtHome() {
        let customPushUp = HF.exercise(40, "Minha flexão", slug: HF.pushUp.slug, equipment: .bodyweight, custom: true)
        let catalog = HF.catalog + [customPushUp]

        let swaps = HomeSubstitution.swaps(for: [customPushUp], catalog: catalog, traits: HF.traits)

        #expect(swaps == [HomeSwap(originalID: customPushUp.id, replacement: HF.pushUp)])
        #expect(swaps.first?.isUnchanged == false)
        let offered = HomeSubstitution.candidates(for: HF.barbellBench, catalog: catalog, traits: HF.traits, excluding: [], limit: 10)
        #expect(!offered.contains(customPushUp))
    }

    @Test("H1 sem catálogo de marcas ninguém é de casa: todo exercício sai da sessão")
    func withoutTraitsNothingIsAtHome() {
        let day = [HF.barbellBench, HF.pushUp]

        let swaps = HomeSubstitution.swaps(for: day, catalog: HF.catalog, traits: .empty)

        #expect(swaps.map(\.originalID) == day.map(\.id))
        #expect(swaps.allSatisfy { $0.replacement == nil })
    }

    // MARK: - H2

    @Test("H2 equivalente: mesmo padrão e grupo em comum, só de casa, na ordem do RF-34")
    func equivalentFollowsSubstitutionOrder() {
        let swaps = HomeSubstitution.swaps(for: [HF.barbellBench], catalog: HF.catalog, traits: HF.traits)

        // Supino com halteres pontua mais, mas não é de casa; entre as flexões, decide o nome.
        #expect(swaps == [HomeSwap(originalID: HF.barbellBench.id, replacement: HF.pushUp)])
        #expect(
            HomeSubstitution.equivalents(for: HF.barbellBench, in: HF.homeCatalog)
                == [HF.pushUp, HF.kneePushUp, HF.plyometricPushUp]
        )
    }

    @Test("H2 mesmo padrão sem grupo em comum não conta: vale o mesmo grupo primário")
    func samePatternWithoutSharedGroupIsSkipped() {
        // Explosivo de peito: o agachamento com salto é explosivo, mas de pernas.
        let swaps = HomeSubstitution.swaps(for: [HF.chestThrow], catalog: HF.catalog, traits: HF.traits)

        #expect(swaps.first?.replacement == HF.plyometricPushUp)
        #expect(!HomeSubstitution.equivalents(for: HF.chestThrow, in: HF.homeCatalog).contains(HF.jumpSquat))
    }

    @Test("H2 sem candidato do mesmo padrão, vale o melhor de casa com o mesmo grupo primário")
    func fallsBackToSamePrimaryGroup() {
        let rows: [(label: String, exercise: ExerciseDefinition, expected: ExerciseDefinition)] = [
            ("puxada na polia", HF.latPulldown, HF.backpackRow),
            ("barra fixa", HF.pullUp, HF.backpackRow),
            ("mesa flexora → ponte unilateral, que tem posteriores como primário", HF.legCurl, HF.singleLegBridge),
        ]

        for row in rows {
            let swaps = HomeSubstitution.swaps(for: [row.exercise], catalog: HF.catalog, traits: HF.traits)
            #expect(swaps.first?.replacement == row.expected, "\(row.label)")
        }
    }

    @Test("H2 pescoço só troca por pescoço, e nada troca por pescoço pelo grupo costas")
    func neckIsOnlyEquivalentToNeck() {
        let onlyNeckAtHome = [HF.latPulldown, HF.neckBand, HF.neckIsometric]
        let noNeckAtHome = [HF.neckBand, HF.backpackRow]

        #expect(HomeSubstitution.swaps(for: [HF.neckBand], catalog: HF.catalog, traits: HF.traits).first?.replacement == HF.neckIsometric)
        #expect(HomeSubstitution.swaps(for: [HF.latPulldown], catalog: onlyNeckAtHome, traits: HF.traits).first?.replacement == nil)
        #expect(HomeSubstitution.swaps(for: [HF.neckBand], catalog: noNeckAtHome, traits: HF.traits).first?.replacement == nil)
    }

    @Test("H2 sem nenhum equivalente, o exercício sai da sessão")
    func noEquivalentRemovesTheExercise() {
        let calfRaise = HF.exercise(50, "Panturrilha em pé", primary: [.calves], equipment: .machine, pattern: .calfRaise)
        let noGroup = HF.exercise(51, "Exercício sem grupo", primary: [], pattern: .horizontalPush)

        let swaps = HomeSubstitution.swaps(for: [calfRaise, noGroup], catalog: HF.catalog + [calfRaise, noGroup], traits: HF.traits)

        #expect(swaps == [
            HomeSwap(originalID: calfRaise.id, replacement: nil),
            HomeSwap(originalID: noGroup.id, replacement: nil),
        ])
        #expect(swaps.allSatisfy { !$0.isUnchanged })
    }

    @Test("H2 exercício sem padrão de movimento usa o mesmo grupo primário")
    func exerciseWithoutPatternUsesPrimaryGroup() {
        let customRow = HF.exercise(52, "Remada da minha academia", primary: [.back], equipment: .machine, pattern: nil, custom: true)

        let swaps = HomeSubstitution.swaps(for: [customRow], catalog: HF.catalog + [customRow], traits: HF.traits)

        #expect(swaps.first?.replacement == HF.backpackRow)
    }

    // MARK: - H3

    @Test("H3 dois exercícios do mesmo dia não viram o mesmo exercício de casa")
    func sameDayNeverRepeatsAHomeExercise() {
        let swaps = HomeSubstitution.swaps(for: [HF.barbellBench, HF.dumbbellBench], catalog: HF.catalog, traits: HF.traits)

        let expected: [ExerciseDefinition?] = [HF.pushUp, HF.kneePushUp]
        #expect(swaps.map(\.replacement) == expected)
    }

    @Test("H3 exercício de casa que já está no dia fica reservado, mesmo vindo depois")
    func homeExerciseLaterInTheDayIsReserved() {
        let swaps = HomeSubstitution.swaps(for: [HF.barbellBench, HF.pushUp], catalog: HF.catalog, traits: HF.traits)

        #expect(swaps == [
            HomeSwap(originalID: HF.barbellBench.id, replacement: HF.kneePushUp),
            HomeSwap(originalID: HF.pushUp.id, replacement: HF.pushUp),
        ])
    }

    @Test("H3 esgotados os do mesmo padrão, vale o próximo do mesmo grupo; esgotados todos, sai")
    func exhaustedPatternFallsBackThenRemoves() {
        let chestPress = HF.exercise(53, "Supino na máquina", equipment: .machine)
        let inclineBench = HF.exercise(54, "Supino inclinado com halteres", equipment: .dumbbell)
        let day = [HF.barbellBench, HF.dumbbellBench, chestPress, inclineBench]

        let swaps = HomeSubstitution.swaps(for: day, catalog: HF.catalog + [chestPress, inclineBench], traits: HF.traits)

        // Flexão explosiva é explosiva: só entra depois das duas do mesmo padrão.
        let expected: [ExerciseDefinition?] = [HF.pushUp, HF.kneePushUp, HF.plyometricPushUp, nil]
        #expect(swaps.map(\.replacement) == expected)
    }

    @Test("H2/H3 o catálogo em qualquer ordem dá as mesmas trocas")
    func resultDoesNotDependOnCatalogOrder() {
        let day = [HF.barbellBench, HF.latPulldown, HF.squat, HF.dumbbellBench, HF.pushUp, HF.legCurl]
        let baseline = HomeSubstitution.swaps(for: day, catalog: HF.catalog, traits: HF.traits)

        for shift in 1..<HF.catalog.count {
            let rotated = Array(HF.catalog.dropFirst(shift) + HF.catalog.prefix(shift))
            #expect(HomeSubstitution.swaps(for: day, catalog: rotated, traits: HF.traits) == baseline, "shift \(shift)")
            #expect(
                HomeSubstitution.swaps(for: day, catalog: Array(rotated.reversed()), traits: HF.traits) == baseline,
                "reversed shift \(shift)"
            )
        }
    }

    // MARK: - HomeSwap

    @Test("H2 isUnchanged só quando o substituto é o próprio exercício")
    func isUnchangedOnlyForTheSameExercise() {
        #expect(HomeSwap(originalID: HF.pushUp.id, replacement: HF.pushUp).isUnchanged)
        #expect(!HomeSwap(originalID: HF.barbellBench.id, replacement: HF.pushUp).isUnchanged)
        #expect(!HomeSwap(originalID: HF.barbellBench.id, replacement: nil).isUnchanged)
    }

    // MARK: - Trocar no modo casa

    @Test("RF-42 Trocar no modo casa oferece só exercícios de casa do mesmo padrão e grupo (RF-34)")
    func candidatesAreHomeOnly() {
        let all = HomeSubstitution.candidates(for: HF.barbellBench, catalog: HF.catalog, traits: HF.traits, excluding: [], limit: 10)

        #expect(all == [HF.pushUp, HF.kneePushUp])
        #expect(HomeSubstitution.candidates(for: HF.barbellBench, catalog: HF.catalog, traits: HF.traits, excluding: [HF.pushUp.id], limit: 10) == [HF.kneePushUp])
        #expect(HomeSubstitution.candidates(for: HF.barbellBench, catalog: HF.catalog, traits: HF.traits, excluding: [], limit: 1) == [HF.pushUp])
        #expect(HomeSubstitution.candidates(for: HF.barbellBench, catalog: HF.catalog, traits: HF.traits, excluding: [], limit: 0).isEmpty)
        #expect(HomeSubstitution.candidates(for: HF.pushUp, catalog: HF.catalog, traits: HF.traits, excluding: [], limit: 10) == [HF.kneePushUp])
        // Trocar segue o RF-34: sem o passo por grupo do H2.
        #expect(HomeSubstitution.candidates(for: HF.latPulldown, catalog: HF.catalog, traits: HF.traits, excluding: [], limit: 10).isEmpty)
    }

    @Test("RF-34 afinidade: objetos de casa ficam na família do peso corporal")
    func householdAffinity() {
        let rows: [(Equipment, Equipment, Int)] = [
            (.household, .household, 2),
            (.household, .bodyweight, 2),
            (.household, .barbell, 0),
            (.household, .dumbbell, 0),
            (.household, .machine, 0),
            (.household, .cable, 0),
            (.household, .kettlebell, 0),
            (.household, .smith, 0),
        ]

        for (lhs, rhs, affinity) in rows {
            #expect(ExerciseSubstitution.equipmentAffinity(lhs, rhs) == affinity, "\(lhs) × \(rhs)")
            #expect(ExerciseSubstitution.equipmentAffinity(rhs, lhs) == affinity, "\(rhs) × \(lhs)")
        }
    }

    // MARK: - Real seed files

    @Test("RF-42 cobertura: todo exercício de programs.v2.json tem equivalente de casa (H2)")
    func everyProgramExerciseHasAHomeEquivalent() throws {
        let bundle = try SeedTestFiles.bundle()
        let traits = try SeedTestFiles.traits()
        let catalog = bundle.catalog.exercises
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for program in bundle.programs.programs {
            for day in program.days {
                for target in day.exercises {
                    let label = "\(program.name) / \(day.name) ordem \(target.order)"
                    let exercise = try #require(byID[target.exerciseID], "\(label)")
                    let swap = try #require(HomeSubstitution.swaps(for: [exercise], catalog: catalog, traits: traits).first)
                    let replacement = try #require(swap.replacement, "\(label): sem opção em casa para \(exercise.slug)")
                    #expect(traits.traits(for: replacement).atHome, "\(label): \(replacement.slug)")
                }
            }
        }
    }

    @Test("H3 no seed, todo dia de todo programa fica completo em casa, sem repetir exercício")
    func everyProgramDayIsCompleteAtHome() throws {
        let bundle = try SeedTestFiles.bundle()
        let traits = try SeedTestFiles.traits()
        let catalog = bundle.catalog.exercises
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for program in bundle.programs.programs {
            for day in program.days {
                let label = "\(program.name) / \(day.name)"
                let dayExercises = try day.exercises.sorted { $0.order < $1.order }.map { target in
                    try #require(byID[target.exerciseID], "\(label) ordem \(target.order)")
                }

                let swaps = HomeSubstitution.swaps(for: dayExercises, catalog: catalog, traits: traits)

                #expect(swaps.map(\.originalID) == dayExercises.map(\.id), "\(label)")
                let replacements = swaps.compactMap(\.replacement)
                #expect(replacements.count == dayExercises.count, "\(label): \(replacements.map(\.slug))")
                #expect(Set(replacements.map(\.id)).count == replacements.count, "\(label): \(replacements.map(\.slug))")
                #expect(replacements.allSatisfy { traits.traits(for: $0).atHome }, "\(label)")
            }
        }
    }

    struct SeedSwapCase: Sendable, CustomTestStringConvertible {
        let original: String
        let replacement: String

        var testDescription: String { "\(original) → \(replacement)" }
    }

    static let seedSwapCases: [SeedSwapCase] = [
        SeedSwapCase(original: "barbell-bench-press", replacement: "push-up"),
        SeedSwapCase(original: "lat-pulldown", replacement: "backpack-pullover"),
        SeedSwapCase(original: "pull-up", replacement: "backpack-pullover"),
        SeedSwapCase(original: "barbell-row", replacement: "backpack-bent-over-row"),
        SeedSwapCase(original: "one-arm-dumbbell-row", replacement: "one-arm-backpack-row"),
        SeedSwapCase(original: "barbell-back-squat", replacement: "bodyweight-squat"),
        SeedSwapCase(original: "dumbbell-bulgarian-split-squat", replacement: "bodyweight-lunge"),
        SeedSwapCase(original: "barbell-romanian-deadlift", replacement: "single-leg-romanian-deadlift"),
        SeedSwapCase(original: "barbell-hip-thrust", replacement: "glute-bridge"),
        SeedSwapCase(original: "lying-leg-curl", replacement: "towel-leg-curl"),
        SeedSwapCase(original: "standing-calf-raise", replacement: "step-calf-raise"),
        SeedSwapCase(original: "dumbbell-shoulder-press", replacement: "water-bottle-shoulder-press"),
        SeedSwapCase(original: "dumbbell-lateral-raise", replacement: "water-bottle-lateral-raise"),
        SeedSwapCase(original: "barbell-curl", replacement: "backpack-curl"),
        SeedSwapCase(original: "cable-triceps-pushdown", replacement: "chair-dip"),
        SeedSwapCase(original: "cable-crunch", replacement: "floor-crunch"),
        SeedSwapCase(original: "dumbbell-farmers-walk", replacement: "grocery-bag-carry"),
        SeedSwapCase(original: "neck-isometric-band", replacement: "manual-neck-isometric"),
        SeedSwapCase(original: "pallof-press", replacement: "side-plank"),
        SeedSwapCase(original: "box-jump", replacement: "jump-squat"),
    ]

    @Test("RF-42 no seed, cada exercício da academia vira o equivalente de casa esperado", arguments: HomeSubstitutionTests.seedSwapCases)
    func seedSwapsAreTheExpectedOnes(_ testCase: SeedSwapCase) throws {
        let bundle = try SeedTestFiles.bundle()
        let traits = try SeedTestFiles.traits()
        let catalog = bundle.catalog.exercises
        let original = try #require(catalog.first { $0.slug == testCase.original })

        let swap = try #require(HomeSubstitution.swaps(for: [original], catalog: catalog, traits: traits).first)

        #expect(swap.replacement?.slug == testCase.replacement)
    }
}

/// Catálogo pequeno com as marcas de casa explícitas. Padrões: peito, barra, bilateral, kg, empurrar
/// na horizontal. Ids `00000000-0000-4000-8000-<número>`, então a ordem do `uuidString` segue o número.
private enum HF {
    static let barbellBench = exercise(1, "Supino reto com barra")
    static let dumbbellBench = exercise(2, "Supino reto com halteres", equipment: .dumbbell)
    static let pushUp = exercise(3, "Flexão de braço", equipment: .bodyweight)
    static let kneePushUp = exercise(4, "Flexão de braço com joelhos no chão", equipment: .bodyweight)
    static let plyometricPushUp = exercise(5, "Flexão explosiva", equipment: .bodyweight, pattern: .explosive)
    static let chestThrow = exercise(6, "Arremesso de medicine ball no peito", equipment: .dumbbell, pattern: .explosive)
    static let jumpSquat = exercise(7, "Agachamento com salto", primary: [.quads, .glutes], equipment: .bodyweight, pattern: .explosive)
    static let squat = exercise(8, "Agachamento livre", primary: [.quads, .glutes], pattern: .squat)
    static let bodyweightSquat = exercise(9, "Agachamento com peso do corpo", primary: [.quads, .glutes], equipment: .bodyweight, pattern: .squat)
    static let latPulldown = exercise(10, "Puxada frontal na polia", primary: [.back], equipment: .cable, pattern: .verticalPull)
    static let pullUp = exercise(11, "Barra fixa", primary: [.back], equipment: .bodyweight, pattern: .verticalPull)
    static let backpackRow = exercise(12, "Remada curvada com mochila", primary: [.back], equipment: .household, pattern: .horizontalPull)
    static let neckBand = exercise(13, "Isometria de pescoço com faixa", primary: [.back], equipment: .bodyweight, pattern: .neck)
    static let neckIsometric = exercise(14, "Isometria de pescoço com resistência manual", primary: [.back], equipment: .bodyweight, pattern: .neck)
    static let legCurl = exercise(15, "Mesa flexora", primary: [.hamstrings], equipment: .machine, pattern: .kneeFlexion)
    static let singleLegBridge = exercise(
        16, "Ponte de glúteo unilateral", primary: [.glutes, .hamstrings], equipment: .bodyweight, unilateral: true, pattern: .hipThrust
    )

    static let catalog: [ExerciseDefinition] = [
        neckBand, pushUp, latPulldown, barbellBench, jumpSquat, squat, singleLegBridge, dumbbellBench,
        backpackRow, legCurl, plyometricPushUp, neckIsometric, chestThrow, pullUp, kneePushUp, bodyweightSquat,
    ]

    static let homeSlugs: Set<String> = [
        pushUp.slug, kneePushUp.slug, plyometricPushUp.slug, jumpSquat.slug, bodyweightSquat.slug,
        backpackRow.slug, neckIsometric.slug, singleLegBridge.slug,
    ]

    static let traits = ExerciseTraitsCatalog(
        traitsBySlug: Dictionary(uniqueKeysWithValues: homeSlugs.map { ($0, ExerciseTraits(measure: .reps, atHome: true)) })
    )

    static var homeCatalog: [ExerciseDefinition] {
        catalog.filter { homeSlugs.contains($0.slug) }
    }

    static func id(_ number: Int) -> UUID {
        let hex = String(number, radix: 16, uppercase: true)
        let node = String(repeating: "0", count: max(0, 12 - hex.count)) + hex
        return UUID(uuidString: "00000000-0000-4000-8000-" + node)!
    }

    static func exercise(
        _ number: Int,
        _ name: String,
        slug: String? = nil,
        primary: [MuscleGroup] = [.chest],
        equipment: Equipment = .barbell,
        unilateral: Bool = false,
        pattern: MovementPattern? = .horizontalPush,
        custom: Bool = false
    ) -> ExerciseDefinition {
        ExerciseDefinition(
            id: id(number),
            slug: slug ?? "exercise-\(number)",
            name: name,
            primaryMuscles: primary,
            secondaryMuscles: [],
            equipment: equipment,
            loadUnit: .kilograms,
            loadIncrement: 2.5,
            isUnilateral: unilateral,
            movementPattern: pattern,
            isCustom: custom
        )
    }
}
