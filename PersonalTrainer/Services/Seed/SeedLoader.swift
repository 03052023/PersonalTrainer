import Foundation
import SwiftData
import TrainerCore

/// Falhas próprias do `SeedLoader`. Erros de decodificação (`DecodingError`), de validação
/// (`SeedValidationError`), de mapeamento (`MappingError`) e do SwiftData sobem sem tradução.
///
/// Compartilha o arquivo com `SeedLoader` porque TASKS.md T1.10 limita o escopo a
/// `SeedLoader.swift` (mesmo arranjo de `SeedValidator.swift` em TrainerCore).
enum SeedLoaderError: Error, Equatable {
    /// Um dos JSON do seed não está na raiz do bundle. Carrega o nome do arquivo com extensão.
    case resourceMissing(String)
}

/// Instala o catálogo e o programa padrão a partir de `Resources/Seed/*.json` no primeiro
/// launch e reaplica o catálogo quando o seed do bundle é mais novo que o instalado
/// (ARCHITECTURE §11).
///
/// Regras:
/// - Exercícios: upsert por `slug`. Existente → copia campo a campo os dados de catálogo,
///   preservando `isArchived` e `machineNotes` (edições do usuário). Inexistente → insere via
///   `ExerciseMapper.model(from:)`. Nunca faz `insert` de um modelo com `uuid`/`slug` já
///   usados: ambos são `.unique` e o insert duplicado vira upsert silencioso que zeraria
///   `isArchived`/`machineNotes` (ARCHITECTURE §15).
/// - Programas: inseridos só quando o store não tem NENHUM `ProgramModel`. Se já existe algum,
///   o seed não mexe: na M1 o programa se edita no JSON e o que está no store prevalece.
/// - `UserSettingsModel`: criado na primeira execução com os padrões de ARCHITECTURE §5;
///   `schemaSeedVersion` recebe `currentSeedVersion` ao final, no mesmo `save()`.
/// - Tudo em `@MainActor` (ARCHITECTURE §10). Datas vêm de `now` (SPEC P11); nada de `Date()`.
enum SeedLoader {
    /// Versão do seed embutido no app. Ao mudar o conteúdo dos JSON de forma que exija
    /// reaplicar o catálogo, incrementar aqui (e o campo `version` dos arquivos).
    /// `SeedValidator` só exige `version >= 1` nos arquivos; a comparação com o store é feita
    /// contra esta constante, não contra o campo do JSON.
    static let currentSeedVersion = 1

    /// Nomes dos recursos sem extensão. Os JSON ficam na RAIZ do bundle (o `project.yml`
    /// copia `Resources/Seed/*.json` sem preservar a pasta), por isso `url(forResource:
    /// withExtension:)` sem `subdirectory:` (ARCHITECTURE §11).
    static let catalogResourceName = "exercises.v1"
    static let programResourceName = "program-default.v1"

    @MainActor
    static func loadIfNeeded(context: ModelContext, bundle: Bundle, now: Date) throws -> SeedLoadReport {
        let existingSettings = try fetchSettings(in: context)
        if let existingSettings, existingSettings.schemaSeedVersion >= currentSeedVersion {
            return SeedLoadReport(insertedExercises: 0, updatedExercises: 0, insertedPrograms: 0, skipped: true)
        }

        // Ler e validar antes de gravar qualquer coisa: um JSON quebrado não deixa nem o
        // `UserSettingsModel` pela metade no store (o `mainContext` do app tem autosave).
        let seed = try decodeSeed(from: bundle)
        try SeedValidator.validate(seed)

        let settings: UserSettingsModel
        if let existingSettings {
            settings = existingSettings
        } else {
            settings = makeDefaultSettings()
            context.insert(settings)
        }

        var insertedExercises = 0
        var updatedExercises = 0
        // Chave = id do exercício NO SEED, que é o que `ExerciseTarget.exerciseID` referencia.
        // Em instalação limpa coincide com `ExerciseModel.uuid`; se um seed futuro trocasse o
        // id de um slug já instalado, o programa continuaria ligado ao modelo certo.
        var exercisesBySeedID: [UUID: ExerciseModel] = [:]
        exercisesBySeedID.reserveCapacity(seed.catalog.exercises.count)

        for definition in seed.catalog.exercises {
            if let existing = try fetchExercise(slug: definition.slug, in: context) {
                apply(definition, to: existing)
                updatedExercises += 1
                exercisesBySeedID[definition.id] = existing
            } else {
                let model = ExerciseMapper.model(from: definition)
                context.insert(model)
                insertedExercises += 1
                exercisesBySeedID[definition.id] = model
            }
        }

        var insertedPrograms = 0
        let programCount = try context.fetchCount(FetchDescriptor<ProgramModel>())
        if programCount == 0 {
            for template in seed.programs.programs {
                let program = try ProgramMapper.model(
                    from: template,
                    exercises: exercisesBySeedID,
                    createdAt: now
                )
                // O mapper devolve o grafo (dias e exercícios do programa) sem contexto; inserir
                // a raiz faz o SwiftData inserir os modelos relacionados junto com o pai. Os
                // `ExerciseModel` já estão neste contexto (inseridos ou buscados acima).
                context.insert(program)
                insertedPrograms += 1
            }
        }

        settings.schemaSeedVersion = currentSeedVersion
        try context.save()

        return SeedLoadReport(
            insertedExercises: insertedExercises,
            updatedExercises: updatedExercises,
            insertedPrograms: insertedPrograms,
            skipped: false
        )
    }

    // MARK: - Store

    @MainActor
    private static func fetchSettings(in context: ModelContext) throws -> UserSettingsModel? {
        var descriptor = FetchDescriptor<UserSettingsModel>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @MainActor
    private static func fetchExercise(slug: String, in context: ModelContext) throws -> ExerciseModel? {
        var descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate<ExerciseModel> { $0.slug == slug }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Copia só os campos de catálogo. `uuid` e `slug` são a identidade; `isArchived` e
    /// `machineNotes` são do usuário e o seed nunca os toca (ARCHITECTURE §11).
    @MainActor
    private static func apply(_ definition: ExerciseDefinition, to model: ExerciseModel) {
        model.name = definition.name
        model.primaryMusclesRaw = SchemaV1.encodeMuscleGroups(definition.primaryMuscles)
        model.secondaryMusclesRaw = SchemaV1.encodeMuscleGroups(definition.secondaryMuscles)
        model.equipmentRaw = definition.equipment.rawValue
        model.loadUnitRaw = definition.loadUnit.rawValue
        model.loadIncrement = definition.loadIncrement
        model.isUnilateral = definition.isUnilateral
    }

    /// Linha única de configuração (ARCHITECTURE §5). `schemaSeedVersion` nasce 0 e é
    /// promovido a `currentSeedVersion` no fim de `loadIfNeeded`.
    @MainActor
    private static func makeDefaultSettings() -> UserSettingsModel {
        UserSettingsModel(
            uuid: UUID(),
            weekStartsOnMonday: true,
            weeklyTargetsRaw: "{}",
            healthKitEnabled: false,
            defaultRestSeconds: 120,
            schemaSeedVersion: 0
        )
    }

    // MARK: - Bundle

    private static func decodeSeed(from bundle: Bundle) throws -> SeedBundle {
        let catalogData = try data(forResource: catalogResourceName, in: bundle)
        let programData = try data(forResource: programResourceName, in: bundle)
        return try SeedBundle.decode(catalogData: catalogData, programData: programData)
    }

    private static func data(forResource name: String, in bundle: Bundle) throws -> Data {
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw SeedLoaderError.resourceMissing("\(name).json")
        }
        return try Data(contentsOf: url)
    }
}
