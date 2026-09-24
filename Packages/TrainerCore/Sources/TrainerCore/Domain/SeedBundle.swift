import Foundation

// Seed files (ARCHITECTURE §11): `Resources/Seed/exercises.v2.json` and
// `Resources/Seed/programs.v2.json` (seed v2, M2) ship in the iPhone bundle and use
// the synthesized `Codable` of the domain structs — the same encoding as the backup —
// so the JSON stays readable and editable by hand. The three seed types live
// together in this file because TASKS.md T0.6 scopes them to `SeedBundle.swift`.

/// Contents of `exercises.v2.json`: the exercise catalog (SPEC §7.1 "Exercício").
public struct SeedExerciseCatalog: Codable, Sendable, Hashable {
    /// Seed format version; `SeedLoader` (T1.10) compares it with
    /// `UserSettingsModel.schemaSeedVersion` to decide whether to upsert.
    public let version: Int
    public let exercises: [ExerciseDefinition]

    public init(version: Int, exercises: [ExerciseDefinition]) {
        self.version = version
        self.exercises = exercises
    }
}

/// Contents of `programs.v2.json`: the programs installed by the seed (SPEC §7.1
/// "Programa"). Exactly one of them is `isActive` (SPEC S1).
public struct SeedProgramFile: Codable, Sendable, Hashable {
    public let version: Int
    public let programs: [ProgramTemplate]

    public init(version: Int, programs: [ProgramTemplate]) {
        self.version = version
        self.programs = programs
    }
}

/// The two seed files decoded together. Decoding is separate from validation
/// (`SeedValidator`) so callers can report a malformed file and an inconsistent
/// bundle as different failures.
public struct SeedBundle: Codable, Sendable, Hashable {
    public let catalog: SeedExerciseCatalog
    public let programs: SeedProgramFile

    public init(catalog: SeedExerciseCatalog, programs: SeedProgramFile) {
        self.catalog = catalog
        self.programs = programs
    }

    /// Decodes the raw bytes of both seed files with a plain `JSONDecoder`
    /// (no key or date strategies: the files carry no dates and use the
    /// struct property names as keys). Throws the decoder's error unchanged.
    public static func decode(catalogData: Data, programData: Data) throws -> SeedBundle {
        let decoder = JSONDecoder()
        let catalog = try decoder.decode(SeedExerciseCatalog.self, from: catalogData)
        let programs = try decoder.decode(SeedProgramFile.self, from: programData)
        return SeedBundle(catalog: catalog, programs: programs)
    }
}
