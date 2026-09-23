import Foundation

/// Why a `SeedBundle` cannot be installed. Each case names the offending
/// exercise (by slug or id) and program so a hand-edited JSON can be fixed
/// without a debugger. `SeedValidator` and its error share this file because
/// TASKS.md T0.6 scopes both to `SeedValidator.swift`.
public enum SeedValidationError: Error, Equatable, Sendable {
    /// Two catalog entries share a slug; `SeedLoader` upserts by slug (ARCHITECTURE §11).
    case duplicateSlug(String)
    /// Two catalog entries share an id; program targets reference exercises by id.
    case duplicateExerciseID(UUID)
    /// A program target points to an exercise that is not in the catalog.
    case unknownExerciseID(UUID, inProgram: String)
    /// `repMin` must be at least 1 and strictly below `repMax` (SPEC P4/P5 compare reps against both).
    case invalidRepRange(exerciseSlug: String, program: String)
    /// `sets` must be at least 1 (SPEC P4 needs S working sets to count a success).
    case invalidSets(exerciseSlug: String, program: String)
    /// `loadIncrement` must be a positive finite number (SPEC §7.1, P8): every
    /// prescribed load is a multiple of it, including added load on bodyweight moves.
    case invalidIncrement(slug: String)
    /// A program has no days (SPEC S1 rotates over D1…Dn).
    case emptyProgram(String)
    /// A day has no exercises; a session of it could never log a working set.
    case emptyDay(program: String, day: String)
    /// No program is `isActive` (SPEC S1: "o programa ativo").
    case noActiveProgram
    /// More than one program is `isActive`.
    case multipleActivePrograms
    /// `targetRIR` must be within 0...5 (SPEC §7.1: RIR is reps left before failure).
    case invalidRIR(exerciseSlug: String, program: String)
    /// `restSeconds` must be positive.
    case invalidRest(exerciseSlug: String, program: String)
    /// Two days of the same program share an `order`.
    case duplicateDayOrder(program: String, order: Int)
    /// Two targets of the same day share an `order`.
    case duplicateExerciseOrder(program: String, day: String, order: Int)
    /// `startingLoad`, when present, must be a finite number ≥ 0 (SPEC P2 prescribes
    /// it as-is; SPEC P8 would otherwise silently turn a negative value into `inc`).
    case invalidStartingLoad(exerciseSlug: String, program: String)
    /// A seed file `version` must be ≥ 1; `SeedLoader` compares it with the installed
    /// version to decide whether to upsert (ARCHITECTURE §11), so 0 would never install.
    case invalidVersion(Int)
    /// Two programs share an id; program ids are stable client identifiers (AGENTS R8).
    case duplicateProgramID(UUID)
    /// Two days (in any program) share an id; `SessionSummary.programDayID` and the
    /// rotation (SPEC S2) resolve a day by id, so a duplicate makes "next day" ambiguous.
    case duplicateDayID(UUID)
    /// Two targets (in any day) share an id.
    case duplicateTargetID(UUID)
}

/// Structural validation of a decoded `SeedBundle`. Pure and deterministic:
/// same bundle → same first error. Stops at the first problem found, walking the
/// catalog first and then the programs in file order, so tests build one defect
/// per bundle.
public enum SeedValidator {
    /// Inclusive range accepted for `ExerciseTarget.targetRIR`. SPEC §7.5 uses 4 for
    /// deload and P2 adds 1 to the target, so 5 is the practical ceiling.
    public static let allowedRepsInReserve: ClosedRange<Int> = 0...5

    public static func validate(_ bundle: SeedBundle) throws {
        let exercisesByID = try validateCatalog(bundle.catalog)
        try validatePrograms(bundle.programs, exercisesByID: exercisesByID)
    }

    // MARK: - Catalog

    /// Returns the catalog indexed by id for the program checks.
    private static func validateCatalog(
        _ catalog: SeedExerciseCatalog
    ) throws -> [UUID: ExerciseDefinition] {
        try validateVersion(catalog.version)

        var seenSlugs = Set<String>()
        var exercisesByID: [UUID: ExerciseDefinition] = [:]
        exercisesByID.reserveCapacity(catalog.exercises.count)

        for exercise in catalog.exercises {
            guard seenSlugs.insert(exercise.slug).inserted else {
                throw SeedValidationError.duplicateSlug(exercise.slug)
            }
            guard exercisesByID[exercise.id] == nil else {
                throw SeedValidationError.duplicateExerciseID(exercise.id)
            }
            // SPEC §7.1 + P8: the increment is the unit every prescribed load is a
            // multiple of. Bodyweight exercises keep a positive increment too — it is
            // the step for added load (vest, belt) — otherwise P4 could never progress.
            guard exercise.loadIncrement.isFinite, exercise.loadIncrement > 0 else {
                throw SeedValidationError.invalidIncrement(slug: exercise.slug)
            }
            exercisesByID[exercise.id] = exercise
        }

        return exercisesByID
    }

    /// ARCHITECTURE §11: `SeedLoader` installs a file only when its version is above
    /// the one recorded on the device, which starts at 0; a version below 1 never installs.
    private static func validateVersion(_ version: Int) throws {
        guard version >= 1 else {
            throw SeedValidationError.invalidVersion(version)
        }
    }

    // MARK: - Programs

    /// Identifiers seen so far across the whole program file. Ids are global
    /// (SwiftData `uuid` columns are unique per model), so a day id repeated in two
    /// programs is as much a defect as one repeated inside a program.
    private struct SeenIdentifiers {
        var programs = Set<UUID>()
        var days = Set<UUID>()
        var targets = Set<UUID>()
    }

    private static func validatePrograms(
        _ file: SeedProgramFile,
        exercisesByID: [UUID: ExerciseDefinition]
    ) throws {
        try validateVersion(file.version)

        // SPEC S1: the selector rotates over "the active program", so the seed must
        // define exactly one. An empty file has none.
        let activeCount = file.programs.filter(\.isActive).count
        guard activeCount > 0 else { throw SeedValidationError.noActiveProgram }
        guard activeCount == 1 else { throw SeedValidationError.multipleActivePrograms }

        var seen = SeenIdentifiers()
        for program in file.programs {
            guard seen.programs.insert(program.id).inserted else {
                throw SeedValidationError.duplicateProgramID(program.id)
            }
            try validateProgram(program, exercisesByID: exercisesByID, seen: &seen)
        }
    }

    private static func validateProgram(
        _ program: ProgramTemplate,
        exercisesByID: [UUID: ExerciseDefinition],
        seen: inout SeenIdentifiers
    ) throws {
        guard !program.days.isEmpty else {
            throw SeedValidationError.emptyProgram(program.name)
        }

        // SPEC S1/S2: days are rotated by `order`; a tie would make "next day" ambiguous.
        var seenDayOrders = Set<Int>()
        for day in program.days {
            guard seen.days.insert(day.id).inserted else {
                throw SeedValidationError.duplicateDayID(day.id)
            }
            guard seenDayOrders.insert(day.order).inserted else {
                throw SeedValidationError.duplicateDayOrder(program: program.name, order: day.order)
            }
            try validateDay(day, program: program.name, exercisesByID: exercisesByID, seen: &seen)
        }
    }

    private static func validateDay(
        _ day: ProgramDayTemplate,
        program: String,
        exercisesByID: [UUID: ExerciseDefinition],
        seen: inout SeenIdentifiers
    ) throws {
        guard !day.exercises.isEmpty else {
            throw SeedValidationError.emptyDay(program: program, day: day.name)
        }

        var seenExerciseOrders = Set<Int>()
        for target in day.exercises {
            guard seen.targets.insert(target.id).inserted else {
                throw SeedValidationError.duplicateTargetID(target.id)
            }
            guard seenExerciseOrders.insert(target.order).inserted else {
                throw SeedValidationError.duplicateExerciseOrder(
                    program: program,
                    day: day.name,
                    order: target.order
                )
            }
            guard let exercise = exercisesByID[target.exerciseID] else {
                throw SeedValidationError.unknownExerciseID(target.exerciseID, inProgram: program)
            }
            try validateTarget(target, exerciseSlug: exercise.slug, program: program)
        }
    }

    private static func validateTarget(
        _ target: ExerciseTarget,
        exerciseSlug: String,
        program: String
    ) throws {
        // SPEC P4: success needs "nº de séries de trabalho ≥ S"; S = 0 would make every
        // session a success and S < 0 is meaningless.
        guard target.sets >= 1 else {
            throw SeedValidationError.invalidSets(exerciseSlug: exerciseSlug, program: program)
        }
        // SPEC P4–P6 compare reps against repMin and repMax as a strict window
        // (reps ≥ repMax → increase; reps < repMin → failure), so repMin < repMax
        // and repMin ≥ 1 are required for the rules to be distinguishable.
        guard target.repMin >= 1, target.repMin < target.repMax else {
            throw SeedValidationError.invalidRepRange(exerciseSlug: exerciseSlug, program: program)
        }
        guard allowedRepsInReserve.contains(target.targetRIR) else {
            throw SeedValidationError.invalidRIR(exerciseSlug: exerciseSlug, program: program)
        }
        guard target.restSeconds > 0 else {
            throw SeedValidationError.invalidRest(exerciseSlug: exerciseSlug, program: program)
        }
        // SPEC P2/P8: the starting load is prescribed as typed (rounded to the grid);
        // a negative or non-finite value has no meaning as a load. 0 is allowed — it is
        // the natural start for bodyweight work, and P8 raises it to `inc` elsewhere.
        if let startingLoad = target.startingLoad {
            guard startingLoad.isFinite, startingLoad >= 0 else {
                throw SeedValidationError.invalidStartingLoad(exerciseSlug: exerciseSlug, program: program)
            }
        }
    }
}
