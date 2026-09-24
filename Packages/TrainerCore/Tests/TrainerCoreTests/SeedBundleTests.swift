import Foundation
import Testing
@testable import TrainerCore

// MARK: - Real seed files (PersonalTrainer/Resources/Seed), catalog

// SPEC 7.9 (decisão 8, 2026-09-23): o Completo de hipertrofia virou corpo todo (cada grande
// grupo 2×/semana), substituindo o antigo A/B/C empurrar/inferior/puxar. `SeedLoader` nunca
// sobrescreve um programa já instalado (upsert por uuid ausente), então quem já tem o A/B/C
// antigo no store (id `26262EE7…`, o usuário real da M1) continua com ele intacto; o seed só
// muda o que instalações NOVAS recebem. Por isso o Completo corpo todo ganha um id NOVO e o
// A/B/C antigo continua no arquivo (renomeado e inativo — renomear é seguro porque o loader
// nunca reescreve a cópia já instalada do usuário).

@Test("Seed arquivos reais v2 decodificam e passam no SeedValidator")
func seedFilesDecodeAndValidate() throws {
    let bundle = try loadSeedBundle()

    try SeedValidator.validate(bundle)
    #expect(bundle.catalog.version == 2)
    #expect(bundle.programs.version == 2)
}

@Test("Seed catálogo tem pelo menos 70 exercícios com slugs kebab-case únicos")
func seedCatalogHasUniqueKebabCaseSlugs() throws {
    let catalog = try loadSeedBundle().catalog

    #expect(catalog.exercises.count >= 70)
    let slugs = catalog.exercises.map(\.slug)
    #expect(Set(slugs).count == slugs.count)
    for slug in slugs {
        #expect(isKebabCase(slug), "slug fora do padrão kebab-case: \(slug)")
    }
}

@Test("Seed catálogo tem ids únicos e campos coerentes em cada exercício, com padrão de movimento")
func seedCatalogEntriesAreComplete() throws {
    let catalog = try loadSeedBundle().catalog

    let ids = catalog.exercises.map(\.id)
    #expect(Set(ids).count == ids.count)
    for exercise in catalog.exercises {
        #expect(!exercise.name.isEmpty, "\(exercise.slug)")
        #expect(!exercise.primaryMuscles.isEmpty, "\(exercise.slug)")
        #expect(exercise.machineNotes == nil, "\(exercise.slug)")
        #expect(exercise.loadUnit == .kilograms, "\(exercise.slug)")
        // RF-34: "Trocar" matches substitutes by pattern; the seed never ships user exercises.
        #expect(exercise.movementPattern != nil, "sem padrão de movimento: \(exercise.slug)")
        #expect(!exercise.isCustom, "\(exercise.slug)")
        #expect(
            Set(exercise.primaryMuscles).isDisjoint(with: exercise.secondaryMuscles),
            "grupo repetido entre primário e secundário: \(exercise.slug)"
        )
    }
}

@Test("SPEC 7.1 incremento é 5 kg em máquina de placas e 2,5 kg nos demais equipamentos")
func seedCatalogIncrementsFollowEquipment() throws {
    let catalog = try loadSeedBundle().catalog

    for exercise in catalog.exercises {
        let expected: Double = exercise.equipment == .machine ? 5 : 2.5
        #expect(exercise.loadIncrement == expected, "\(exercise.slug)")
    }
}

@Test("Seed catálogo cobre todos os equipamentos e marca unilaterais")
func seedCatalogCoversEquipmentAndUnilateral() throws {
    let catalog = try loadSeedBundle().catalog

    let equipment = Set(catalog.exercises.map(\.equipment))
    #expect(equipment == [.barbell, .dumbbell, .machine, .cable, .bodyweight, .smith, .kettlebell])
    #expect(catalog.exercises.contains { $0.isUnilateral })
}

@Test("Seed v2 mantém os 45 exercícios do v1 com o mesmo id, slug e nome (histórico depende disso)")
func seedCatalogKeepsEveryV1Exercise() throws {
    let catalog = try loadSeedBundle().catalog
    let exercisesByID = Dictionary(
        catalog.exercises.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    #expect(v1CatalogEntries.count == 45)
    for entry in v1CatalogEntries {
        let id = try #require(UUID(uuidString: entry.id), "\(entry.slug)")
        let exercise = try #require(exercisesByID[id], "exercício v1 ausente: \(entry.slug)")
        #expect(exercise.slug == entry.slug, "\(entry.id)")
        #expect(exercise.name == entry.name, "\(entry.slug)")
    }
}

@Test("RF-34 todo exercício do catálogo tem ao menos 2 substitutos com o mesmo padrão e o mesmo grupo primário")
func seedCatalogExercisesHaveSubstitutes() throws {
    let catalog = try loadSeedBundle().catalog

    // Comparing the *first* primary group is stricter than "share any primary group":
    // the guarantee holds whichever of the two readings of RF-34 the substitution
    // ranking uses. Covers every exercise used by the programs (≥ 3 options per pattern)
    // and every other catalog entry the user may add to a day (RF-33) and then swap.
    for exercise in catalog.exercises {
        let pattern = try #require(exercise.movementPattern, "\(exercise.slug)")
        let mainGroup = try #require(exercise.primaryMuscles.first, "\(exercise.slug)")
        let options = catalog.exercises.filter {
            $0.movementPattern == pattern && $0.primaryMuscles.first == mainGroup
        }
        #expect(
            options.count >= 3,
            "\(exercise.slug): só \(options.count) opções com \(pattern.rawValue)/\(mainGroup.rawValue)"
        )
    }
}

@Test("RF-11/RF-34 no catálogo real, todo substituto sugerido compartilha um grupo primário e há ao menos 2")
func seedCatalogSubstitutesShareAPrimaryGroup() throws {
    let catalog = try loadSeedBundle().catalog.exercises

    for exercise in catalog {
        let candidates = ExerciseSubstitution.candidates(for: exercise, in: catalog)
        #expect(candidates.count >= 2, "\(exercise.slug): \(candidates.count) substitutos")
        for candidate in candidates {
            #expect(candidate.movementPattern == exercise.movementPattern, "\(exercise.slug) → \(candidate.slug)")
            #expect(
                !Set(candidate.primaryMuscles).isDisjoint(with: exercise.primaryMuscles),
                "\(exercise.slug) → \(candidate.slug) sem grupo primário em comum"
            )
        }
    }
}

@Test("RF-34 todo padrão usado nos programas tem ≥ 3 exercícios que compartilham um grupo primário")
func seedProgramPatternsHaveThreeOptions() throws {
    let bundle = try loadSeedBundle()
    let catalog = bundle.catalog.exercises
    let exercisesByID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    for program in bundle.programs.programs {
        for day in program.days {
            for target in day.exercises {
                let label = "\(program.name) / \(day.name) ordem \(target.order)"
                let exercise = try #require(exercisesByID[target.exerciseID], "\(label)")
                let pattern = try #require(exercise.movementPattern, "\(label)")
                let options = catalog.filter {
                    $0.movementPattern == pattern
                        && !Set($0.primaryMuscles).isDisjoint(with: exercise.primaryMuscles)
                }
                #expect(options.count >= 3, "\(label): \(exercise.slug) tem \(options.count) opções")
            }
        }
    }
}

@Test("T2.16/T2.17 catálogo tem os exercícios de longevidade e de combate")
func seedCatalogHasGoalSpecificExercises() throws {
    let slugs = Set(try loadSeedBundle().catalog.exercises.map(\.slug))
    let longevity = [
        "box-squat", "dumbbell-step-up", "glute-bridge", "dead-bug", "bird-dog", "side-plank",
        "kettlebell-farmers-walk",
    ]
    let combat = [
        "medicine-ball-chest-pass", "medicine-ball-rotational-throw", "kettlebell-swing", "box-jump",
        "dumbbell-farmers-walk", "suitcase-carry", "pallof-press", "neck-isometric-band",
        "hex-bar-deadlift", "pull-up", "push-up", "inverted-row",
    ]

    for slug in longevity + combat {
        #expect(slugs.contains(slug), "ausente: \(slug)")
    }
}

// MARK: - Real seed files, programs

@Test("S1 arquivo de programas tem 8 programas, só o Completo ativo, todos com objetivo e resumo")
func seedProgramFileHasEightProgramsWithOneActive() throws {
    let programs = try loadSeedBundle().programs.programs

    #expect(programs.count == 8)
    let active = programs.filter(\.isActive)
    #expect(active.count == 1)
    #expect(active.first?.id == UUID(uuidString: completoProgramID))
    #expect(Set(programs.map(\.name)).count == programs.count)
    for program in programs {
        #expect(program.goal != nil, "\(program.name)")
        let summary = try #require(program.summary, "\(program.name) sem resumo")
        #expect(!summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(program.name)")
    }
}

@Test("SPEC 7.9 os programas cobrem todos os objetivos")
func seedProgramsCoverAllGoals() throws {
    let programs = try loadSeedBundle().programs.programs

    #expect(Set(programs.compactMap(\.goal)) == Set(ProgramGoal.allCases))
}

@Test("SPEC 7.9 todo dia de todo programa tem exatamente 5 exercícios em ordem 0..4")
func seedEveryDayHasFiveOrderedExercises() throws {
    let programs = try loadSeedBundle().programs.programs

    for program in programs {
        #expect(program.days.map(\.order) == Array(0..<program.days.count), "\(program.name)")
        for day in program.days {
            #expect(day.exercises.count == 5, "\(program.name) / \(day.name)")
            #expect(day.exercises.map(\.order) == Array(0..<5), "\(program.name) / \(day.name)")
        }
    }
}

@Test("Seed todo exerciseID dos programas existe no catálogo")
func seedProgramsReferenceCatalogExercises() throws {
    let bundle = try loadSeedBundle()
    let catalogIDs = Set(bundle.catalog.exercises.map(\.id))

    for program in bundle.programs.programs {
        for day in program.days {
            for target in day.exercises {
                #expect(
                    catalogIDs.contains(target.exerciseID),
                    "\(program.name) / \(day.name) ordem \(target.order): \(target.exerciseID)"
                )
            }
        }
    }
}

@Test("Seed ids de programa, dias e alvos são únicos no arquivo de programas inteiro")
func seedProgramFileIdentifiersAreUnique() throws {
    let file = try loadSeedBundle().programs

    var ids: [UUID] = []
    for program in file.programs {
        ids.append(program.id)
        for day in program.days {
            ids.append(day.id)
            ids.append(contentsOf: day.exercises.map(\.id))
        }
    }
    #expect(Set(ids).count == ids.count)
}

@Test("S2 o A/B/C legado (id antigo do Completo) mantém o id, os dias e os alvos do programa padrão v1, agora inativo")
func seedLegacyProgramKeepsV1Identifiers() throws {
    let program = try legacyProgram()

    #expect(program.name == legacyPushLegsPullName)
    #expect(program.goal == .hypertrophy)
    // SeedLoader nunca sobrescreve um programa já instalado (upsert por uuid ausente): o
    // usuário real da M1 continua com o A/B/C ativo no store dele mesmo com isActive=false
    // aqui. Esta flag só decide o que uma instalação NOVA recebe (SPEC S1: um único ativo).
    #expect(!program.isActive)
    #expect(program.days.count == legacyProgramV1Days.count)
    for (day, expected) in zip(program.days, legacyProgramV1Days) {
        #expect(day.id == UUID(uuidString: expected.day), "\(day.name)")
        #expect(day.exercises.map(\.id) == expected.targets.compactMap(UUID.init(uuidString:)), "\(day.name)")
    }
}

@Test("SPEC 7.2 o A/B/C legado usa S = 3, T = 2, startingLoad nulo e faixas/descansos previstos")
func seedLegacyProgramUsesSpecificationParameters() throws {
    let program = try legacyProgram()
    // 6–10 for heavy compounds, 8–12 default, 12–15 for calves/core (TASKS.md T0.6).
    let allowedRepRanges: Set<[Int]> = [[6, 10], [8, 12], [12, 15]]

    for day in program.days {
        for target in day.exercises {
            let label = "\(day.name) ordem \(target.order)"
            #expect(target.sets == 3, "\(label)")
            #expect(target.targetRIR == 2, "\(label)")
            #expect(target.startingLoad == nil, "\(label)")
            #expect(allowedRepRanges.contains([target.repMin, target.repMax]), "\(label)")
            #expect([120, 180].contains(target.restSeconds), "\(label)")
        }
    }
}

@Test("SPEC 7.9 decisão 8: Completo corpo todo usa 4 séries nos compostos e 3 nos isolados, RIR 2, startingLoad nulo e descanso 150/90 s")
func seedCompletoUsesFullBodySpecificationParameters() throws {
    let bundle = try loadSeedBundle()
    let program = try completoProgram(in: bundle)
    let exercisesByID = Dictionary(
        bundle.catalog.exercises.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    for day in program.days {
        for target in day.exercises {
            let label = "\(day.name) ordem \(target.order)"
            let exercise = try #require(exercisesByID[target.exerciseID], "\(label)")
            let pattern = try #require(exercise.movementPattern, "\(label)")
            let isCompound = compoundPatterns.contains(pattern)

            #expect(target.targetRIR == 2, "\(label)")
            #expect(target.startingLoad == nil, "\(label)")
            #expect(target.sets == (isCompound ? 4 : 3), "\(label): \(pattern.rawValue)")
            #expect(target.restSeconds == (isCompound ? 150 : 90), "\(label): \(pattern.rawValue)")
        }
    }
}

@Test("SPEC 7.4 Completo treina os 10 grupos musculares como primário")
func seedCompletoCoversAllMuscleGroups() throws {
    let bundle = try loadSeedBundle()
    let program = try completoProgram(in: bundle)

    let trained = try primaryMuscles(of: program, catalog: bundle.catalog)
    #expect(trained == Set(MuscleGroup.allCases))
}

@Test("SPEC 7.9 decisão 8: cada dia do Completo corpo todo mistura superior e inferior")
func seedCompletoDaysMixUpperAndLowerBody() throws {
    let bundle = try loadSeedBundle()
    let program = try completoProgram(in: bundle)
    let upperBody: Set<MuscleGroup> = [.chest, .back, .shoulders, .biceps, .triceps]
    let lowerBody: Set<MuscleGroup> = [.quads, .hamstrings, .glutes, .calves]

    for day in program.days {
        let trained = try primaryMuscles(of: day, catalog: bundle.catalog)
        #expect(!trained.isDisjoint(with: upperBody), "\(day.name) sem superior: \(trained)")
        #expect(!trained.isDisjoint(with: lowerBody), "\(day.name) sem inferior: \(trained)")
    }
}

@Test("SPEC 7.9 decisão 8: no Completo corpo todo, cada grande grupo é treinado em pelo menos 2 dos 3 dias")
func seedCompletoTrainsEveryGroupTwiceAWeek() throws {
    let bundle = try loadSeedBundle()
    let program = try completoProgram(in: bundle)
    #expect(program.days.count == 3)

    var daysByGroup: [MuscleGroup: Int] = [:]
    for day in program.days {
        for group in try primaryMuscles(of: day, catalog: bundle.catalog) {
            daysByGroup[group, default: 0] += 1
        }
    }

    for group in MuscleGroup.allCases {
        #expect(daysByGroup[group, default: 0] >= 2, "\(group.rawValue): \(daysByGroup[group, default: 0]) dias")
    }
}

@Test("RF-35 hipertrofia tem o Completo corpo todo, o A/B/C legado, foco inferior e foco superior, todos com os 10 grupos")
func seedHypertrophyFormatsCoverAllGroups() throws {
    let bundle = try loadSeedBundle()
    let hypertrophy = bundle.programs.programs.filter { $0.goal == .hypertrophy }

    #expect(Set(hypertrophy.map(\.name)) == [completoName, legacyPushLegsPullName, lowerFocusName, upperFocusName])
    for program in hypertrophy {
        let trained = try primaryMuscles(of: program, catalog: bundle.catalog)
        #expect(trained == Set(MuscleGroup.allCases), "\(program.name) treina \(trained)")
    }
}

@Test("RF-35 foco inferior: 2 dias de pernas com 4 séries, superior em manutenção com 2 e mais volume semanal no foco")
func seedLowerFocusProgramPrioritizesLegs() throws {
    try expectFocusFormat(
        programName: lowerFocusName,
        focusGroups: [.quads, .hamstrings, .glutes, .calves],
        maintenanceGroups: [.chest, .back, .shoulders, .biceps, .triceps]
    )
}

@Test("RF-35 foco superior: 2 dias de superior com 4 séries, pernas em manutenção com 2 e mais volume semanal no foco")
func seedUpperFocusProgramPrioritizesUpperBody() throws {
    try expectFocusFormat(
        programName: upperFocusName,
        focusGroups: [.chest, .back, .shoulders, .biceps, .triceps],
        maintenanceGroups: [.quads, .hamstrings, .glutes, .calves]
    )
}

@Test("SPEC 7.9 séries, faixas, RIR e descanso de cada programa seguem a tabela do objetivo")
func seedProgramParametersFollowGoalTable() throws {
    let bundle = try loadSeedBundle()
    let exercisesByID = Dictionary(
        bundle.catalog.exercises.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    for program in bundle.programs.programs {
        // Combat has its own components (SPEC 7.9 "Combate"), checked separately.
        guard let rule = goalParameterRules[program.effectiveGoal] else { continue }
        for day in program.days {
            for target in day.exercises {
                let label = "\(program.name) / \(day.name) ordem \(target.order)"
                let exercise = try #require(exercisesByID[target.exerciseID], "\(label)")
                let pattern = try #require(exercise.movementPattern, "\(label)")
                #expect(target.startingLoad == nil, "\(label)")
                #expect(rule.sets.contains(target.sets), "\(label): \(target.sets) séries")
                #expect(rule.repsInReserve.contains(target.targetRIR), "\(label): RIR \(target.targetRIR)")
                #expect(rule.restSeconds.contains(target.restSeconds), "\(label): \(target.restSeconds) s")
                // Carries and neck isometrics count steps/seconds in the reps field.
                guard !countedInStepsOrSeconds.contains(pattern) else { continue }
                let reps = compoundPatterns.contains(pattern) ? rule.compoundReps : rule.isolationReps
                #expect(
                    target.repMin >= reps.lowerBound && target.repMax <= reps.upperBound,
                    "\(label): \(target.repMin)–\(target.repMax) fora de \(reps)"
                )
            }
        }
    }
}

@Test("SPEC 7.9 Força: 3 dias de corpo inteiro só com exercícios compostos")
func seedStrengthProgramUsesOnlyCompounds() throws {
    let bundle = try loadSeedBundle()
    let program = try requireProgram(goal: .strength, in: bundle)

    #expect(program.days.count == 3)
    for day in program.days {
        for exercise in try exercises(of: day, catalog: bundle.catalog) {
            let pattern = try #require(exercise.movementPattern, "\(exercise.slug)")
            #expect(compoundPatterns.contains(pattern), "\(day.name): \(exercise.slug) não é composto")
        }
    }
}

@Test("SPEC 7.9 Longevidade: 2–3 dias, cada um com agachar, empurrar, puxar, dobradiça e carregar/estabilidade")
func seedLongevityProgramCoversBasicPatterns() throws {
    let bundle = try loadSeedBundle()
    let program = try requireProgram(goal: .longevity, in: bundle)
    let slots: [(name: String, patterns: Set<MovementPattern>)] = [
        ("agachar", [.squat, .lunge]),
        ("empurrar", [.horizontalPush, .verticalPush]),
        ("puxar", [.horizontalPull, .verticalPull]),
        ("dobradiça", [.hinge]),
        ("carregar/estabilidade", [.carry, .coreStability]),
    ]

    #expect((2...3).contains(program.days.count))
    for day in program.days {
        let dayExercises = try exercises(of: day, catalog: bundle.catalog)
        let patterns = Set(dayExercises.compactMap(\.movementPattern))
        for slot in slots {
            #expect(!patterns.isDisjoint(with: slot.patterns), "\(day.name) sem \(slot.name)")
        }
    }
}

@Test("SPEC 7.9 Combate: potência com 3–5 reps e descanso completo, força 3–6 reps, pegada/tronco todo dia, pescoço 2×")
func seedCombatProgramFollowsComponents() throws {
    let bundle = try loadSeedBundle()
    let program = try requireProgram(goal: .combat, in: bundle)
    let exercisesByID = Dictionary(
        bundle.catalog.exercises.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    #expect(program.days.count == 3)
    var neckDays = 0
    for day in program.days {
        var patterns: [MovementPattern] = []
        for target in day.exercises {
            let label = "\(day.name) ordem \(target.order)"
            let exercise = try #require(exercisesByID[target.exerciseID], "\(label)")
            let pattern = try #require(exercise.movementPattern, "\(label)")
            patterns.append(pattern)
            #expect(target.startingLoad == nil, "\(label)")
            if pattern == .explosive {
                // Power: 3–5 sets of 3–5 reps, full rest (Cormie 2011).
                #expect(target.repMin >= 3 && target.repMax <= 5, "\(label)")
                #expect((3...5).contains(target.sets), "\(label)")
                #expect(target.restSeconds >= 180, "\(label)")
            } else if compoundPatterns.contains(pattern), pattern != .carry {
                // Maximal strength: compounds 3–6 reps, RIR 2–3 (Suchomel 2016).
                #expect(target.repMin >= 3 && target.repMax <= 6, "\(label)")
                #expect((2...3).contains(target.targetRIR), "\(label)")
                #expect(target.restSeconds >= 180, "\(label)")
            }
        }
        let explosiveCount = patterns.filter { $0 == .explosive }.count
        #expect((1...2).contains(explosiveCount), "\(day.name): \(explosiveCount) explosivos")
        #expect(patterns.contains(.carry) || patterns.contains(.coreStability), "\(day.name) sem pegada/tronco")
        if patterns.contains(.neck) { neckDays += 1 }
    }
    #expect(neckDays >= 2)
}

@Test("Seed SeedBundle faz round-trip Codable")
func seedBundleCodableRoundTrip() throws {
    let bundle = try loadSeedBundle()

    let data = try JSONEncoder().encode(bundle)
    let decoded = try JSONDecoder().decode(SeedBundle.self, from: data)
    #expect(decoded == bundle)
}

@Test("Seed SeedBundle.decode propaga JSON malformado ou com formato trocado")
func seedBundleDecodeRejectsMalformedJSON() throws {
    let catalogData = try Data(contentsOf: seedFileURL(catalogFileName))
    let programData = try Data(contentsOf: seedFileURL(programFileName))
    let broken = Data("{ not json".utf8)

    #expect(throws: (any Error).self) {
        try SeedBundle.decode(catalogData: broken, programData: programData)
    }
    #expect(throws: (any Error).self) {
        try SeedBundle.decode(catalogData: catalogData, programData: broken)
    }
    #expect(throws: (any Error).self) {
        try SeedBundle.decode(catalogData: programData, programData: catalogData)
    }
}

// MARK: - SeedValidator, positive cases

@Test("Seed validador aceita bundle mínimo válido")
func validatorAcceptsMinimalBundle() throws {
    try SeedValidator.validate(Fixture.bundle())
}

@Test("S1 validador aceita programas inativos ao lado do único ativo")
func validatorAcceptsInactiveProgramsBesideTheActiveOne() throws {
    let bundle = Fixture.bundle(programs: [
        Fixture.program(),
        Fixture.program(isActive: false, name: "Reserva"),
    ])

    try SeedValidator.validate(bundle)
}

@Test("Seed validador aceita RIR alvo nos limites 0 e 5")
func validatorAcceptsBoundaryRepsInReserve() throws {
    for rir in [0, 5] {
        let bundle = Fixture.bundle(programs: [
            Fixture.program(days: [Fixture.day([Fixture.target(targetRIR: rir)])]),
        ])
        try SeedValidator.validate(bundle)
    }
}

@Test("RF-34 validador aceita catálogo v2 com padrão em todos e catálogo v1 sem padrão")
func validatorAcceptsMovementPatternByCatalogVersion() throws {
    let withPatterns = Fixture.bundle(
        exercises: [
            Fixture.exercise(movementPattern: .horizontalPush),
            Fixture.exercise(id: Fixture.squatID, slug: "barbell-back-squat", movementPattern: .squat),
        ],
        catalogVersion: 2
    )

    try SeedValidator.validate(withPatterns)
    try SeedValidator.validate(Fixture.bundle(catalogVersion: 1))
}

// MARK: - SeedValidator, one defect per bundle

@Test("Seed validador rejeita slug duplicado no catálogo")
func validatorRejectsDuplicateSlug() {
    let bundle = Fixture.bundle(exercises: [
        Fixture.exercise(),
        Fixture.exercise(id: Fixture.spareID, slug: Fixture.benchSlug),
    ])

    #expect(throws: SeedValidationError.duplicateSlug(Fixture.benchSlug)) {
        try SeedValidator.validate(bundle)
    }
}

@Test("Seed validador rejeita id duplicado no catálogo")
func validatorRejectsDuplicateExerciseID() {
    let bundle = Fixture.bundle(exercises: [
        Fixture.exercise(),
        Fixture.exercise(id: Fixture.benchID, slug: "incline-bench-press"),
    ])

    #expect(throws: SeedValidationError.duplicateExerciseID(Fixture.benchID)) {
        try SeedValidator.validate(bundle)
    }
}

@Test("P8 validador rejeita incremento zero ou negativo")
func validatorRejectsNonPositiveIncrement() {
    for increment in [0.0, -2.5] {
        let bundle = Fixture.bundle(exercises: [Fixture.exercise(loadIncrement: increment)])

        #expect(throws: SeedValidationError.invalidIncrement(slug: Fixture.benchSlug)) {
            try SeedValidator.validate(bundle)
        }
    }
}

@Test("P8 validador exige incremento positivo também em peso corporal")
func validatorRejectsZeroIncrementForBodyweight() {
    let pullUp = Fixture.exercise(
        id: Fixture.benchID,
        slug: "pull-up",
        equipment: .bodyweight,
        loadIncrement: 0
    )
    let bundle = Fixture.bundle(exercises: [pullUp])

    #expect(throws: SeedValidationError.invalidIncrement(slug: "pull-up")) {
        try SeedValidator.validate(bundle)
    }
}

@Test("RF-34 validador exige movementPattern em todos os exercícios do catálogo v2")
func validatorRejectsMissingMovementPatternFromVersionTwo() {
    let bundle = Fixture.bundle(
        exercises: [
            Fixture.exercise(movementPattern: .horizontalPush),
            Fixture.exercise(id: Fixture.squatID, slug: "barbell-back-squat"),
        ],
        catalogVersion: 2
    )

    #expect(throws: SeedValidationError.missingMovementPattern(slug: "barbell-back-squat")) {
        try SeedValidator.validate(bundle)
    }
}

@Test("Seed validador rejeita exerciseID ausente do catálogo")
func validatorRejectsUnknownExerciseID() {
    let bundle = Fixture.bundle(programs: [
        Fixture.program(days: [Fixture.day([Fixture.target(exerciseID: Fixture.unknownID)])]),
    ])

    #expect(
        throws: SeedValidationError.unknownExerciseID(Fixture.unknownID, inProgram: Fixture.programName)
    ) {
        try SeedValidator.validate(bundle)
    }
}

@Test("P4 validador rejeita faixa de reps com repMin >= repMax ou repMin < 1")
func validatorRejectsInvalidRepRange() {
    let invalidRanges: [(repMin: Int, repMax: Int)] = [(10, 10), (12, 8), (0, 12)]

    for range in invalidRanges {
        let target = Fixture.target(repMin: range.repMin, repMax: range.repMax)
        let bundle = Fixture.bundle(programs: [Fixture.program(days: [Fixture.day([target])])])

        #expect(
            throws: SeedValidationError.invalidRepRange(
                exerciseSlug: Fixture.benchSlug,
                program: Fixture.programName
            ),
            "faixa \(range.repMin)–\(range.repMax)"
        ) {
            try SeedValidator.validate(bundle)
        }
    }
}

@Test("P4 validador rejeita sets menor que 1")
func validatorRejectsInvalidSets() {
    for sets in [0, -1] {
        let bundle = Fixture.bundle(programs: [
            Fixture.program(days: [Fixture.day([Fixture.target(sets: sets)])]),
        ])

        #expect(
            throws: SeedValidationError.invalidSets(
                exerciseSlug: Fixture.benchSlug,
                program: Fixture.programName
            )
        ) {
            try SeedValidator.validate(bundle)
        }
    }
}

@Test("Seed validador rejeita RIR alvo fora de 0...5")
func validatorRejectsInvalidRepsInReserve() {
    for rir in [-1, 6] {
        let bundle = Fixture.bundle(programs: [
            Fixture.program(days: [Fixture.day([Fixture.target(targetRIR: rir)])]),
        ])

        #expect(
            throws: SeedValidationError.invalidRIR(
                exerciseSlug: Fixture.benchSlug,
                program: Fixture.programName
            ),
            "RIR \(rir)"
        ) {
            try SeedValidator.validate(bundle)
        }
    }
}

@Test("Seed validador rejeita descanso não positivo")
func validatorRejectsInvalidRest() {
    for rest in [0, -30] {
        let bundle = Fixture.bundle(programs: [
            Fixture.program(days: [Fixture.day([Fixture.target(restSeconds: rest)])]),
        ])

        #expect(
            throws: SeedValidationError.invalidRest(
                exerciseSlug: Fixture.benchSlug,
                program: Fixture.programName
            ),
            "descanso \(rest)"
        ) {
            try SeedValidator.validate(bundle)
        }
    }
}

@Test("S1 validador rejeita programa sem dias")
func validatorRejectsEmptyProgram() {
    let bundle = Fixture.bundle(programs: [Fixture.program(days: [])])

    #expect(throws: SeedValidationError.emptyProgram(Fixture.programName)) {
        try SeedValidator.validate(bundle)
    }
}

@Test("Seed validador rejeita dia sem exercícios")
func validatorRejectsEmptyDay() {
    let bundle = Fixture.bundle(programs: [Fixture.program(days: [Fixture.day([])])])

    #expect(throws: SeedValidationError.emptyDay(program: Fixture.programName, day: Fixture.dayName)) {
        try SeedValidator.validate(bundle)
    }
}

@Test("S1 validador rejeita ausência de programa ativo")
func validatorRejectsNoActiveProgram() {
    let inactiveOnly = Fixture.bundle(programs: [Fixture.program(isActive: false)])
    let noPrograms = Fixture.bundle(programs: [])

    #expect(throws: SeedValidationError.noActiveProgram) {
        try SeedValidator.validate(inactiveOnly)
    }
    #expect(throws: SeedValidationError.noActiveProgram) {
        try SeedValidator.validate(noPrograms)
    }
}

@Test("S1 validador rejeita mais de um programa ativo")
func validatorRejectsMultipleActivePrograms() {
    let bundle = Fixture.bundle(programs: [
        Fixture.program(),
        Fixture.program(name: "Segundo ativo"),
    ])

    #expect(throws: SeedValidationError.multipleActivePrograms) {
        try SeedValidator.validate(bundle)
    }
}

@Test("S2 validador rejeita dias com a mesma ordem no programa")
func validatorRejectsDuplicateDayOrder() {
    let bundle = Fixture.bundle(programs: [
        Fixture.program(days: [
            Fixture.day(order: 0),
            Fixture.day([Fixture.target(exerciseID: Fixture.squatID)], order: 0, name: "Dia B"),
        ]),
    ])

    #expect(throws: SeedValidationError.duplicateDayOrder(program: Fixture.programName, order: 0)) {
        try SeedValidator.validate(bundle)
    }
}

@Test("Seed validador rejeita exercícios com a mesma ordem no dia")
func validatorRejectsDuplicateExerciseOrder() {
    let bundle = Fixture.bundle(programs: [
        Fixture.program(days: [
            Fixture.day([
                Fixture.target(order: 0),
                Fixture.target(exerciseID: Fixture.squatID, order: 0),
            ]),
        ]),
    ])

    #expect(
        throws: SeedValidationError.duplicateExerciseOrder(
            program: Fixture.programName,
            day: Fixture.dayName,
            order: 0
        )
    ) {
        try SeedValidator.validate(bundle)
    }
}

@Test("P2 validador aceita startingLoad zero ou positivo")
func validatorAcceptsNonNegativeStartingLoad() throws {
    for startingLoad in [0.0, 40.0] {
        let bundle = Fixture.bundle(programs: [
            Fixture.program(days: [Fixture.day([Fixture.target(startingLoad: startingLoad)])]),
        ])
        try SeedValidator.validate(bundle)
    }
}

@Test("P2/P8 validador rejeita startingLoad negativo ou não finito")
func validatorRejectsInvalidStartingLoad() {
    for startingLoad in [-40.0, .nan, .infinity] {
        let bundle = Fixture.bundle(programs: [
            Fixture.program(days: [Fixture.day([Fixture.target(startingLoad: startingLoad)])]),
        ])

        #expect(
            throws: SeedValidationError.invalidStartingLoad(
                exerciseSlug: Fixture.benchSlug,
                program: Fixture.programName
            ),
            "startingLoad \(startingLoad)"
        ) {
            try SeedValidator.validate(bundle)
        }
    }
}

@Test("Seed validador rejeita version < 1 em qualquer dos arquivos")
func validatorRejectsInvalidVersion() {
    #expect(throws: SeedValidationError.invalidVersion(0)) {
        try SeedValidator.validate(Fixture.bundle(catalogVersion: 0))
    }
    #expect(throws: SeedValidationError.invalidVersion(-1)) {
        try SeedValidator.validate(Fixture.bundle(programVersion: -1))
    }
}

@Test("Seed validador rejeita id de programa duplicado")
func validatorRejectsDuplicateProgramID() {
    let bundle = Fixture.bundle(programs: [
        Fixture.program(id: Fixture.spareID),
        Fixture.program(id: Fixture.spareID, isActive: false, name: "Reserva"),
    ])

    #expect(throws: SeedValidationError.duplicateProgramID(Fixture.spareID)) {
        try SeedValidator.validate(bundle)
    }
}

@Test("S2 validador rejeita id de dia duplicado, mesmo com ordens distintas")
func validatorRejectsDuplicateDayID() {
    let bundle = Fixture.bundle(programs: [
        Fixture.program(days: [
            Fixture.day(id: Fixture.spareID, order: 0),
            Fixture.day([Fixture.target(exerciseID: Fixture.squatID)], id: Fixture.spareID, order: 1, name: "Dia B"),
        ]),
    ])

    #expect(throws: SeedValidationError.duplicateDayID(Fixture.spareID)) {
        try SeedValidator.validate(bundle)
    }
}

@Test("Seed validador rejeita id de alvo duplicado, mesmo em dias diferentes")
func validatorRejectsDuplicateTargetID() {
    let bundle = Fixture.bundle(programs: [
        Fixture.program(days: [
            Fixture.day([Fixture.target(id: Fixture.spareID)], order: 0),
            Fixture.day([Fixture.target(id: Fixture.spareID, exerciseID: Fixture.squatID)], order: 1, name: "Dia B"),
        ]),
    ])

    #expect(throws: SeedValidationError.duplicateTargetID(Fixture.spareID)) {
        try SeedValidator.validate(bundle)
    }
}

@Test("S2 validador rejeita id de dia ou de alvo repetido em programas diferentes")
func validatorRejectsIdentifiersRepeatedAcrossPrograms() {
    let sharedDay = Fixture.bundle(programs: [
        Fixture.program(days: [Fixture.day(id: Fixture.spareID)]),
        Fixture.program(days: [Fixture.day(id: Fixture.spareID)], isActive: false, name: "Reserva"),
    ])
    let sharedTarget = Fixture.bundle(programs: [
        Fixture.program(days: [Fixture.day([Fixture.target(id: Fixture.spareID)])]),
        Fixture.program(
            days: [Fixture.day([Fixture.target(id: Fixture.spareID)])],
            isActive: false,
            name: "Reserva"
        ),
    ])

    #expect(throws: SeedValidationError.duplicateDayID(Fixture.spareID)) {
        try SeedValidator.validate(sharedDay)
    }
    #expect(throws: SeedValidationError.duplicateTargetID(Fixture.spareID)) {
        try SeedValidator.validate(sharedTarget)
    }
}

// MARK: - Fixed data copied from the v1 seed (removed in M2)

private let catalogFileName = "exercises.v2.json"
private let programFileName = "programs.v2.json"

private let completoProgramID = "14E3FAC0-8424-4360-AF9D-20D18DCB0E45"
private let completoName = "Hipertrofia — Completo"
/// Id do Completo até a M1 (A empurrar / B inferior / C puxar, decisão 8 original). Mantido
/// no seed, inativo e renomeado, porque `SeedLoader` nunca sobrescreve o programa que o
/// usuário real já tem instalado sob este id (ARCHITECTURE §11, docs/V2-FINAL-CONTRACT.md §1.3).
private let legacyPushLegsPullProgramID = "26262EE7-89B0-4048-93F9-1720FD9CBE40"
private let legacyPushLegsPullName = "Hipertrofia — Empurrar/Inferior/Puxar"
private let lowerFocusName = "Hipertrofia — Foco inferior"
private let upperFocusName = "Hipertrofia — Foco superior"

/// Every exercise of the M1 (version 1) catalog (id, slug, name). Session history and the
/// SwiftData upsert (by slug) point at these, so v2 must keep all of them unchanged.
private let v1CatalogEntries: [(id: String, slug: String, name: String)] = [
    ("44979BE9-E276-42B9-AC77-76C831062888", "barbell-bench-press", "Supino reto com barra"),
    ("79DD67B9-B416-4492-9080-ECF151567891", "incline-dumbbell-bench-press", "Supino inclinado com halteres"),
    ("86FB8489-CBBA-47B3-9CA9-F36F9CAD85FC", "smith-machine-incline-bench-press", "Supino inclinado no smith"),
    ("B595BDE8-25AC-46D2-B014-062F77009243", "chest-press-machine", "Supino na máquina (chest press)"),
    ("ACC5492D-0E98-45D7-A0BC-41C974C15FB2", "pec-deck-machine", "Voador peitoral (peck deck)"),
    ("DE3EAC26-D3C6-417E-97C6-69E9189CEB2A", "dumbbell-fly", "Crucifixo com halteres"),
    ("DCAD9528-7927-42F2-AF9C-2964E6F0DA7C", "cable-crossover", "Crossover na polia"),
    ("DE1793B2-82AE-4470-80D2-AA4EFC9A35A3", "push-up", "Flexão de braço"),
    ("A6C1ABFC-0F95-409B-A5B4-A67AB0A17B00", "dumbbell-shoulder-press", "Desenvolvimento com halteres"),
    ("96A1DEEA-9736-41D3-AF26-37DE762B45DC", "shoulder-press-machine", "Desenvolvimento na máquina"),
    ("DA046A61-1335-48A4-A255-7E3940965DD2", "dumbbell-lateral-raise", "Elevação lateral com halteres"),
    ("8ABD6299-A192-42DB-A513-307F202F1953", "cable-lateral-raise", "Elevação lateral na polia"),
    ("23B9FF60-D908-43CB-9F32-9BEF99AF3855", "cable-face-pull", "Face pull na polia"),
    ("F334C89D-BA40-42DB-971F-5582A84259B5", "cable-triceps-pushdown", "Tríceps na polia"),
    ("C6C9FDF2-F4D2-40BF-8790-80D8B6C21DF3", "overhead-dumbbell-triceps-extension", "Tríceps francês com halter"),
    ("4FF0C96D-CB72-498D-80FA-24F30666FF82", "lying-barbell-triceps-extension", "Tríceps testa com barra"),
    ("176896E8-C175-4902-AFCF-C10A2E56B97D", "parallel-bar-dip", "Paralelas (mergulho)"),
    ("0112D559-1B6C-4E1B-A568-FAD5B05239CB", "lat-pulldown", "Puxada frontal na polia"),
    ("35CE0A33-0152-47EC-AFF7-A5930B5A2926", "seated-cable-row", "Remada baixa"),
    ("3C4F420D-2967-4986-ABB6-E6611E0FCC9C", "barbell-row", "Remada curvada com barra"),
    ("ADAD475E-985C-41D3-83EA-A900195BA27C", "one-arm-dumbbell-row", "Remada unilateral com halter (serrote)"),
    ("7DBBF98E-7765-4E47-9FA5-0D19FCB505DD", "machine-row", "Remada na máquina"),
    ("45402028-C3DD-4D96-BD2C-AC4C77CC9B5D", "pull-up", "Barra fixa"),
    ("285A095F-8121-40DA-97C2-93503C480183", "barbell-deadlift", "Levantamento terra"),
    ("FD32CC7D-93CC-4A77-B683-E5810E6586A8", "barbell-curl", "Rosca direta"),
    ("70BAF913-FCD1-40EE-8292-D4A142F6EA50", "alternating-dumbbell-curl", "Rosca alternada com halteres"),
    ("D226D440-66D5-4172-9C82-462DBE23132E", "hammer-curl", "Rosca martelo"),
    ("91036E1B-1044-421A-A0C2-4F3EC86C5E91", "machine-preacher-curl", "Rosca Scott na máquina"),
    ("DDA2E060-ADD5-4505-B4F1-067B7A451951", "barbell-back-squat", "Agachamento livre"),
    ("E4A32243-EAC3-47F6-B149-BD29570E13D1", "leg-press-45", "Leg press 45°"),
    ("BE906DB6-73DC-4ACD-8AE6-5E8CE8DD9910", "leg-extension", "Cadeira extensora"),
    ("8E0895C3-6DDB-491F-AB4C-680506700965", "hack-squat", "Agachamento no hack"),
    ("EF83BF17-6B10-45B9-A8DC-92EA6C6100DD", "dumbbell-bulgarian-split-squat", "Agachamento búlgaro com halteres"),
    ("AF5E71FF-6E05-4EBF-B1EB-C69E2C5FA4FE", "lying-leg-curl", "Mesa flexora"),
    ("2504D370-CB55-47C7-9D2A-52A32272EE10", "seated-leg-curl", "Cadeira flexora"),
    ("7B3A13B1-8A31-4CE0-AAC3-F5429C1D1530", "barbell-romanian-deadlift", "Stiff com barra"),
    ("2CE74B2F-3292-4289-8346-76F17F60AE56", "barbell-hip-thrust", "Elevação pélvica"),
    ("DC290FE8-CBE3-49F1-AD95-0CA2E9865EEF", "hip-abduction-machine", "Cadeira abdutora"),
    ("CDB2EF4F-1DA1-4CF8-8998-5F59262AFB22", "cable-glute-kickback", "Coice na polia"),
    ("14526083-CF3D-4B2F-81E3-A5B98D514922", "kettlebell-swing", "Swing com kettlebell"),
    ("84822646-546B-4E54-9673-A868A06AA70D", "standing-calf-raise", "Panturrilha em pé"),
    ("672FE619-A847-46B6-A25A-D25744FC607F", "seated-calf-raise", "Panturrilha sentado"),
    ("A24FF85F-C910-4AEA-B04E-08AF9FFC8832", "plank", "Prancha"),
    ("D41B575D-CE48-4ED6-9A79-6103D648370D", "cable-crunch", "Abdominal na polia"),
    ("6525301A-2D1D-4626-A921-D40DF056735E", "hanging-leg-raise", "Elevação de pernas suspenso"),
]

/// Day and target ids of the M1 (version 1) default program, in order. `SessionSummary.programDayID`
/// and the rotation (SPEC S2) resolve days by id, so the legacy A/B/C program (old id of
/// "Completo", now renamed and inactive — see `legacyPushLegsPullProgramID`) keeps them.
private let legacyProgramV1Days: [(day: String, targets: [String])] = [
    ("72FC489D-1D0A-444D-91E6-A1C161E537FB", [
        "29E8A320-A3CC-4B24-B76F-15D07D47C0A9", "CF34FDDD-96FE-4263-BEE3-D1970C270190",
        "4B71B8AE-A1EC-4F02-BA69-9723C798F44B", "43121DAC-CB10-482E-950E-CB364D72010A",
        "CA50F13D-FA57-4ADE-AAA5-A07A51E4A27F",
    ]),
    ("9591928D-FB3E-4BD6-B2FA-5D9804DF930A", [
        "0729C57D-D98B-43AE-BB41-6BAF50CE6DD0", "51CE191C-7BC9-47DD-A1E1-502E6062ECC1",
        "43028EE9-EC46-44CF-B873-53626FB37E49", "B412850B-1AB2-46D6-AF95-9EC4AA36B350",
        "B658BAA1-01BF-4364-9FBA-B91D255B9042",
    ]),
    ("795BFEE6-B683-4DCB-844C-4609F6C21400", [
        "8BD865BB-78A2-4089-A9BC-1154A6233D34", "4C7F48C5-C6CC-406C-89D3-ADCD82A99239",
        "9E331624-0068-4106-9A9C-9F66A6200698", "71B7E870-700B-45AE-ACFA-866A82E38D40",
        "216B1AD6-477C-4DC9-9C05-21272E649195",
    ]),
]

// MARK: - SPEC 7.9 table, as the tests read it

/// Compound patterns (docs/M2-CONTRACT.md, `MovementPattern.isCompound`). Kept here so
/// the seed tests do not depend on `GoalDefaults`, which another M2 task delivers.
private let compoundPatterns: Set<MovementPattern> = [
    .horizontalPush, .verticalPush, .horizontalPull, .verticalPull,
    .squat, .lunge, .hinge, .hipThrust, .carry, .explosive,
]

/// Patterns whose "reps" are steps (carries) or seconds (neck isometrics): the app logs
/// every set as reps, so their windows are not comparable with the goal's rep ranges.
private let countedInStepsOrSeconds: Set<MovementPattern> = [.carry, .neck]

private struct GoalParameterRule: Sendable {
    let compoundReps: ClosedRange<Int>
    let isolationReps: ClosedRange<Int>
    let repsInReserve: ClosedRange<Int>
    let restSeconds: ClosedRange<Int>
    let sets: ClosedRange<Int>
}

/// SPEC 7.9 table (combat has components instead of a single row). Sets: hypertrophy
/// ranges from 2 (foco maintenance days, RF-35) to 4 (foco focus days, RF-35; Completo corpo
/// todo compostos, decisão 8 — `seedCompletoUsesFullBodySpecificationParameters` pins the
/// exact 4/3 split); longevity uses 2 (TASKS T2.16).
private let goalParameterRules: [ProgramGoal: GoalParameterRule] = [
    .hypertrophy: GoalParameterRule(
        compoundReps: 6...12, isolationReps: 8...15, repsInReserve: 1...3, restSeconds: 90...180, sets: 2...4
    ),
    .strength: GoalParameterRule(
        compoundReps: 3...6, isolationReps: 3...6, repsInReserve: 1...3, restSeconds: 180...300, sets: 3...5
    ),
    .endurance: GoalParameterRule(
        compoundReps: 12...20, isolationReps: 12...20, repsInReserve: 2...4, restSeconds: 60...90, sets: 2...4
    ),
    .longevity: GoalParameterRule(
        compoundReps: 8...15, isolationReps: 8...15, repsInReserve: 3...3, restSeconds: 90...120, sets: 2...2
    ),
]

// MARK: - Helpers

/// Repository root derived from this file's location:
/// `Packages/TrainerCore/Tests/TrainerCoreTests/SeedBundleTests.swift` is five
/// components below it. `URL(fileURLWithPath:)` normalizes the backslashes that
/// `#filePath` carries on Windows, so the same code runs on every platform.
private func repositoryRootURL() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        url.deleteLastPathComponent()
    }
    return url
}

private func seedFileURL(_ fileName: String) -> URL {
    repositoryRootURL()
        .appendingPathComponent("PersonalTrainer", isDirectory: true)
        .appendingPathComponent("Resources", isDirectory: true)
        .appendingPathComponent("Seed", isDirectory: true)
        .appendingPathComponent(fileName, isDirectory: false)
}

private func loadSeedBundle() throws -> SeedBundle {
    let catalogData = try Data(contentsOf: seedFileURL(catalogFileName))
    let programData = try Data(contentsOf: seedFileURL(programFileName))
    return try SeedBundle.decode(catalogData: catalogData, programData: programData)
}

private func completoProgram(in bundle: SeedBundle? = nil) throws -> ProgramTemplate {
    let programs = try (bundle ?? loadSeedBundle()).programs.programs
    let id = try #require(UUID(uuidString: completoProgramID))
    return try #require(programs.first { $0.id == id }, "programa Completo ausente")
}

private func legacyProgram(in bundle: SeedBundle? = nil) throws -> ProgramTemplate {
    let programs = try (bundle ?? loadSeedBundle()).programs.programs
    let id = try #require(UUID(uuidString: legacyPushLegsPullProgramID))
    return try #require(programs.first { $0.id == id }, "programa legado (A/B/C) ausente")
}

private func requireProgram(named name: String, in bundle: SeedBundle) throws -> ProgramTemplate {
    try #require(bundle.programs.programs.first { $0.name == name }, "programa ausente: \(name)")
}

/// The single seed program of `goal`; hypertrophy has three and is looked up by name.
private func requireProgram(goal: ProgramGoal, in bundle: SeedBundle) throws -> ProgramTemplate {
    let matches = bundle.programs.programs.filter { $0.goal == goal }
    #expect(matches.count == 1, "\(goal.rawValue): \(matches.count) programas")
    return try #require(matches.first, "sem programa de \(goal.rawValue)")
}

private func exercises(
    of day: ProgramDayTemplate,
    catalog: SeedExerciseCatalog
) throws -> [ExerciseDefinition] {
    let exercisesByID = Dictionary(
        catalog.exercises.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )
    return try day.exercises.map { target in
        try #require(exercisesByID[target.exerciseID], "\(day.name) ordem \(target.order)")
    }
}

private func primaryMuscles(
    of program: ProgramTemplate,
    catalog: SeedExerciseCatalog
) throws -> Set<MuscleGroup> {
    var trained = Set<MuscleGroup>()
    for day in program.days {
        trained.formUnion(try primaryMuscles(of: day, catalog: catalog))
    }
    return trained
}

private func primaryMuscles(
    of day: ProgramDayTemplate,
    catalog: SeedExerciseCatalog
) throws -> Set<MuscleGroup> {
    var trained = Set<MuscleGroup>()
    for exercise in try exercises(of: day, catalog: catalog) {
        trained.formUnion(exercise.primaryMuscles)
    }
    return trained
}

/// Working sets per primary group over one pass of the rotation (one week), counting
/// an exercise for each of its primary groups (SPEC 7.8 R3, SPEC 7.4).
private func weeklyPrimarySets(
    of program: ProgramTemplate,
    catalog: SeedExerciseCatalog
) throws -> [MuscleGroup: Int] {
    var sets: [MuscleGroup: Int] = [:]
    for day in program.days {
        let dayExercises = try exercises(of: day, catalog: catalog)
        for (target, exercise) in zip(day.exercises, dayExercises) {
            for group in exercise.primaryMuscles {
                sets[group, default: 0] += target.sets
            }
        }
    }
    return sets
}

/// RF-35: four days, two focus days (every primary group in `focusGroups`, 4 sets per
/// exercise) and two maintenance days (2 sets per exercise); every focus group gets more
/// weekly sets than any maintenance group.
private func expectFocusFormat(
    programName: String,
    focusGroups: Set<MuscleGroup>,
    maintenanceGroups: Set<MuscleGroup>
) throws {
    let bundle = try loadSeedBundle()
    let program = try requireProgram(named: programName, in: bundle)

    #expect(program.goal == .hypertrophy)
    #expect(program.days.count == 4)
    var focusDays = 0
    var maintenanceDays = 0
    for day in program.days {
        let isFocusDay = try primaryMuscles(of: day, catalog: bundle.catalog).isSubset(of: focusGroups)
        let expectedSets = isFocusDay ? 4 : 2
        if isFocusDay { focusDays += 1 } else { maintenanceDays += 1 }
        for target in day.exercises {
            #expect(target.sets == expectedSets, "\(day.name) ordem \(target.order)")
        }
    }
    #expect(focusDays == 2)
    #expect(maintenanceDays == 2)

    let weekly = try weeklyPrimarySets(of: program, catalog: bundle.catalog)
    let leastFocused = focusGroups.map { weekly[$0, default: 0] }.min() ?? 0
    let mostMaintained = maintenanceGroups.map { weekly[$0, default: 0] }.max() ?? 0
    #expect(leastFocused > mostMaintained, "séries semanais: \(weekly)")
}

/// Lowercase ASCII letters and digits separated by single hyphens, e.g. `leg-press-45`.
private func isKebabCase(_ slug: String) -> Bool {
    guard let first = slug.first, let last = slug.last,
          first != "-", last != "-", !slug.contains("--") else {
        return false
    }
    return slug.unicodeScalars.allSatisfy { scalar in
        ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
    }
}

/// In-memory bundles for the validator. Defaults produce a valid bundle with two
/// exercises and one active program of one day; each negative test changes one thing.
private enum Fixture {
    static let benchID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let squatID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
    static let spareID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
    static let unknownID = UUID(uuidString: "00000000-0000-4000-8000-0000000000FF")!
    static let benchSlug = "barbell-bench-press"
    static let programName = "Programa de teste"
    static let dayName = "Dia único"

    static func exercise(
        id: UUID = benchID,
        slug: String = benchSlug,
        equipment: Equipment = .barbell,
        loadIncrement: Double = 2.5,
        movementPattern: MovementPattern? = nil
    ) -> ExerciseDefinition {
        ExerciseDefinition(
            id: id,
            slug: slug,
            name: "Exercício \(slug)",
            primaryMuscles: [.chest],
            equipment: equipment,
            loadUnit: .kilograms,
            loadIncrement: loadIncrement,
            movementPattern: movementPattern
        )
    }

    static func target(
        id: UUID = UUID(),
        exerciseID: UUID = benchID,
        order: Int = 0,
        sets: Int = 3,
        repMin: Int = 8,
        repMax: Int = 12,
        targetRIR: Int = 2,
        restSeconds: Int = 120,
        startingLoad: Double? = nil
    ) -> ExerciseTarget {
        ExerciseTarget(
            id: id,
            exerciseID: exerciseID,
            order: order,
            sets: sets,
            repMin: repMin,
            repMax: repMax,
            targetRIR: targetRIR,
            restSeconds: restSeconds,
            startingLoad: startingLoad
        )
    }

    static func day(
        _ exercises: [ExerciseTarget] = [target()],
        id: UUID = UUID(),
        order: Int = 0,
        name: String = dayName
    ) -> ProgramDayTemplate {
        ProgramDayTemplate(id: id, name: name, order: order, exercises: exercises)
    }

    static func program(
        id: UUID = UUID(),
        days: [ProgramDayTemplate] = [day()],
        isActive: Bool = true,
        name: String = programName
    ) -> ProgramTemplate {
        ProgramTemplate(id: id, name: name, days: days, isActive: isActive)
    }

    static func bundle(
        exercises: [ExerciseDefinition] = [exercise(), exercise(id: squatID, slug: "barbell-back-squat")],
        programs: [ProgramTemplate] = [program()],
        catalogVersion: Int = 1,
        programVersion: Int = 1
    ) -> SeedBundle {
        SeedBundle(
            catalog: SeedExerciseCatalog(version: catalogVersion, exercises: exercises),
            programs: SeedProgramFile(version: programVersion, programs: programs)
        )
    }
}
