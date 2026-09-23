import Foundation
import Testing
@testable import TrainerCore

// MARK: - Real seed files (PersonalTrainer/Resources/Seed)

@Test("Seed arquivos reais decodificam e passam no SeedValidator")
func seedFilesDecodeAndValidate() throws {
    let bundle = try loadSeedBundle()

    try SeedValidator.validate(bundle)
    #expect(bundle.catalog.version == 1)
    #expect(bundle.programs.version == 1)
}

@Test("Seed catálogo tem pelo menos 30 exercícios com slugs kebab-case únicos")
func seedCatalogHasUniqueKebabCaseSlugs() throws {
    let catalog = try loadSeedBundle().catalog

    #expect(catalog.exercises.count >= 30)
    let slugs = catalog.exercises.map(\.slug)
    #expect(Set(slugs).count == slugs.count)
    for slug in slugs {
        #expect(isKebabCase(slug), "slug fora do padrão kebab-case: \(slug)")
    }
}

@Test("Seed catálogo tem ids únicos e campos coerentes em cada exercício")
func seedCatalogEntriesAreComplete() throws {
    let catalog = try loadSeedBundle().catalog

    let ids = catalog.exercises.map(\.id)
    #expect(Set(ids).count == ids.count)
    for exercise in catalog.exercises {
        #expect(!exercise.name.isEmpty, "\(exercise.slug)")
        #expect(!exercise.primaryMuscles.isEmpty, "\(exercise.slug)")
        #expect(exercise.machineNotes == nil, "\(exercise.slug)")
        #expect(exercise.loadUnit == .kilograms, "\(exercise.slug)")
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

@Test("S1 programa padrão é o único programa e está ativo, com 3 dias em ordem 0..2")
func seedDefaultProgramHasThreeOrderedDays() throws {
    let bundle = try loadSeedBundle()

    #expect(bundle.programs.programs.count == 1)
    let program = try #require(bundle.programs.programs.first)
    #expect(program.name == "Programa ABC")
    #expect(program.isActive)
    #expect(program.days.count == 3)
    #expect(program.days.map(\.order) == [0, 1, 2])
}

@Test("Seed cada dia do programa padrão tem 5 a 6 exercícios em ordem 0..n-1")
func seedDefaultProgramDaysHaveFiveToSixExercises() throws {
    let program = try #require(loadSeedBundle().programs.programs.first)

    for day in program.days {
        #expect((5...6).contains(day.exercises.count), "\(day.name)")
        #expect(day.exercises.map(\.order) == Array(0..<day.exercises.count), "\(day.name)")
    }
}

@Test("Seed todo exerciseID do programa padrão existe no catálogo")
func seedDefaultProgramReferencesCatalogExercises() throws {
    let bundle = try loadSeedBundle()
    let catalogIDs = Set(bundle.catalog.exercises.map(\.id))

    for program in bundle.programs.programs {
        for day in program.days {
            for target in day.exercises {
                #expect(
                    catalogIDs.contains(target.exerciseID),
                    "\(day.name) ordem \(target.order): \(target.exerciseID)"
                )
            }
        }
    }
}

@Test("Seed ids de programa, dias e alvos são únicos no arquivo de programas")
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

@Test("SPEC 7.2 programa padrão usa S = 3, T = 2, startingLoad nulo e faixas/descansos previstos")
func seedDefaultProgramUsesSpecificationParameters() throws {
    let program = try #require(loadSeedBundle().programs.programs.first)
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

@Test("SPEC 7.4 programa padrão treina os 10 grupos musculares como primário")
func seedDefaultProgramCoversAllMuscleGroups() throws {
    let bundle = try loadSeedBundle()
    let program = try #require(bundle.programs.programs.first)

    let trained = try primaryMuscles(of: program, catalog: bundle.catalog)
    #expect(trained == Set(MuscleGroup.allCases))
}

@Test("Seed dias do programa padrão cobrem os grupos anunciados no nome")
func seedDefaultProgramDaysMatchTheirSplit() throws {
    let bundle = try loadSeedBundle()
    let program = try #require(bundle.programs.programs.first)
    let expectedBySplit: [Int: Set<MuscleGroup>] = [
        0: [.chest, .shoulders, .triceps],
        1: [.quads, .hamstrings, .glutes, .calves],
        2: [.back, .biceps, .core],
    ]

    for day in program.days {
        let expected = try #require(expectedBySplit[day.order], "dia inesperado: \(day.name)")
        let trained = try primaryMuscles(of: day, catalog: bundle.catalog)
        #expect(expected.isSubset(of: trained), "\(day.name) treina \(trained)")
    }
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
    let catalogData = try Data(contentsOf: seedFileURL("exercises.v1.json"))
    let programData = try Data(contentsOf: seedFileURL("program-default.v1.json"))
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
    let catalogData = try Data(contentsOf: seedFileURL("exercises.v1.json"))
    let programData = try Data(contentsOf: seedFileURL("program-default.v1.json"))
    return try SeedBundle.decode(catalogData: catalogData, programData: programData)
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
    let exercisesByID = Dictionary(
        catalog.exercises.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )
    var trained = Set<MuscleGroup>()
    for target in day.exercises {
        let exercise = try #require(exercisesByID[target.exerciseID], "\(day.name) ordem \(target.order)")
        trained.formUnion(exercise.primaryMuscles)
    }
    return trained
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
        loadIncrement: Double = 2.5
    ) -> ExerciseDefinition {
        ExerciseDefinition(
            id: id,
            slug: slug,
            name: "Exercício \(slug)",
            primaryMuscles: [.chest],
            equipment: equipment,
            loadUnit: .kilograms,
            loadIncrement: loadIncrement
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
