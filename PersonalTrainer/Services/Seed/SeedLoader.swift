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

/// Instala o catálogo e os programas semente a partir de `Resources/Seed/*.json` no primeiro
/// launch e reaplica o seed quando o do bundle é mais novo que o instalado (ARCHITECTURE §11,
/// docs/M2-CONTRACT.md §2).
///
/// Política v2:
/// - Exercícios: upsert por `slug`. Existente → copia campo a campo os dados de catálogo
///   (inclusive `movementPatternRaw`), preservando `isArchived` e `machineNotes` (edições do
///   usuário). Exercício criado pelo usuário (`isCustom == true`) nunca é tocado, mesmo que o
///   slug colida. Sem slug igual mas com `uuid` igual (seed que renomeou um slug) → atualiza
///   esse modelo, slug incluído, em vez de inserir: ambos são `.unique` e o insert duplicado
///   vira upsert silencioso que zeraria `isArchived`/`machineNotes` (ARCHITECTURE §15).
///   Inexistente → insere via `ExerciseMapper.model(from:)` com `isCustom = false`.
/// - Store que já tem o seed 2 ou mais novo (`refreshesExistingBelowInstalledVersion`): só insere
///   os exercícios que faltam e não reescreve os existentes. O store ainda não marca um exercício
///   do seed editado pelo usuário (TASKS C11, fica para um SchemaV3), então reescrever apagaria
///   essa edição. O seed 3 (versão 2.1) só acrescenta exercícios de casa (RF-42) e não muda os
///   campos de nenhum exercício do seed 2.
/// - Programas: insere cada programa do seed cujo `uuid` ainda não existe no store; nunca
///   altera nem apaga programas existentes. Se o store já tem um programa ativo, os inseridos
///   entram inativos (SPEC S1: um único programa ativo). Primeiro launch: o programa marcado
///   `isActive` no seed fica ativo e os demais inativos.
/// - `UserSettingsModel`: criado na primeira execução com os padrões de ARCHITECTURE §5;
///   `schemaSeedVersion` recebe `currentSeedVersion` ao final, no mesmo `save()`.
/// - Tudo ou nada: ler e validar vem antes de qualquer escrita, e uma falha durante a escrita
///   descarta as mudanças pendentes (`rollback`) antes de relançar o erro — o `mainContext`
///   do app tem autosave e não pode gravar um seed pela metade.
/// - Tudo em `@MainActor` (ARCHITECTURE §10). Datas vêm de `now` (SPEC P11); nada de `Date()`.
enum SeedLoader {
    /// Versão do seed embutido no app. Ao mudar o conteúdo dos JSON de forma que exija
    /// reaplicar o catálogo ou instalar programas novos, incrementar aqui (e o campo `version`
    /// dos arquivos). `SeedValidator` só exige `version >= 1` nos arquivos; a comparação com o
    /// store é feita contra esta constante, não contra o campo do JSON.
    /// 3 = versão 2.1: exercícios de casa (RF-42) e descansos dos programas de foco (§7.9).
    static let currentSeedVersion = 3

    /// Stores com o seed abaixo desta versão (o v1 da M1, sem `movementPattern`) recebem o upsert
    /// completo do catálogo. Daqui para cima, reaplicar o seed só insere exercícios novos.
    static let refreshesExistingBelowInstalledVersion = 2

    /// Nomes dos recursos sem extensão. Os JSON ficam na RAIZ do bundle (o `project.yml`
    /// copia `Resources/Seed/*.json` sem preservar a pasta), por isso `url(forResource:
    /// withExtension:)` sem `subdirectory:` (ARCHITECTURE §11).
    static let catalogResourceName = "exercises.v2"
    static let programResourceName = "programs.v2"

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

        do {
            let settings: UserSettingsModel
            if let existingSettings {
                settings = existingSettings
            } else {
                settings = makeDefaultSettings()
                context.insert(settings)
            }

            let installedVersion = existingSettings?.schemaSeedVersion ?? 0
            let catalog = try upsertCatalog(
                seed.catalog.exercises,
                refreshingExisting: installedVersion < refreshesExistingBelowInstalledVersion,
                in: context
            )
            let programs = try insertMissingPrograms(
                seed.programs.programs,
                exercisesBySeedID: catalog.exercisesBySeedID,
                in: context,
                now: now
            )

            settings.schemaSeedVersion = currentSeedVersion
            try context.save()

            return SeedLoadReport(
                insertedExercises: catalog.inserted,
                updatedExercises: catalog.updated,
                insertedPrograms: programs.inserted,
                skipped: false,
                skippedPrograms: programs.skipped
            )
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - Catálogo

    private struct CatalogResult {
        /// Chave = id do exercício NO SEED, que é o que `ExerciseTarget.exerciseID` referencia.
        /// Em instalação limpa coincide com `ExerciseModel.uuid`; se o store já tinha o slug com
        /// outro `uuid`, o programa do seed liga ao modelo existente.
        var exercisesBySeedID: [UUID: ExerciseModel] = [:]
        var inserted = 0
        var updated = 0
    }

    /// - Parameter refreshingExisting: `false` liga os existentes aos programas do seed sem
    ///   reescrevê-los (store com seed 2 ou mais novo).
    @MainActor
    private static func upsertCatalog(
        _ definitions: [ExerciseDefinition],
        refreshingExisting: Bool,
        in context: ModelContext
    ) throws -> CatalogResult {
        // Um fetch só em vez de um por exercício. Atribuição em laço (e não
        // `Dictionary(uniqueKeysWithValues:)`) para nunca derrubar o app num store estranho.
        var existingBySlug: [String: ExerciseModel] = [:]
        var existingByUUID: [UUID: ExerciseModel] = [:]
        for model in try context.fetch(FetchDescriptor<ExerciseModel>()) {
            existingBySlug[model.slug] = model
            existingByUUID[model.uuid] = model
        }

        var result = CatalogResult()
        result.exercisesBySeedID.reserveCapacity(definitions.count)

        for definition in definitions {
            guard let existing = existingBySlug[definition.slug] ?? existingByUUID[definition.id] else {
                let model = ExerciseMapper.model(from: definition)
                // Exercício do seed nunca é "do usuário", seja o que for que o JSON diga.
                model.isCustom = false
                context.insert(model)
                existingBySlug[model.slug] = model
                existingByUUID[model.uuid] = model
                result.exercisesBySeedID[definition.id] = model
                result.inserted += 1
                continue
            }

            // Mesmo um exercício do usuário com slug igual serve de alvo para os programas do
            // seed: sem ele o `ProgramMapper` falharia e nenhum programa seria instalado.
            result.exercisesBySeedID[definition.id] = existing
            guard !existing.isCustom, refreshingExisting else { continue }

            if existing.slug != definition.slug {
                existingBySlug[existing.slug] = nil
                existingBySlug[definition.slug] = existing
            }
            apply(definition, to: existing)
            result.updated += 1
        }

        return result
    }

    /// Copia só os campos de catálogo. `uuid` é a identidade; `slug` só muda quando o seed o
    /// renomeou (casamento por `uuid`). `isArchived`, `machineNotes` e `isCustom` são do
    /// usuário e o seed nunca os toca (ARCHITECTURE §11).
    @MainActor
    private static func apply(_ definition: ExerciseDefinition, to model: ExerciseModel) {
        if model.slug != definition.slug {
            model.slug = definition.slug
        }
        model.name = definition.name
        model.primaryMusclesRaw = CurrentSchema.encodeMuscleGroups(definition.primaryMuscles)
        model.secondaryMusclesRaw = CurrentSchema.encodeMuscleGroups(definition.secondaryMuscles)
        model.equipmentRaw = definition.equipment.rawValue
        model.loadUnitRaw = definition.loadUnit.rawValue
        model.loadIncrement = definition.loadIncrement
        model.isUnilateral = definition.isUnilateral
        model.movementPatternRaw = definition.movementPattern?.rawValue
    }

    // MARK: - Programas

    @MainActor
    private static func insertMissingPrograms(
        _ templates: [ProgramTemplate],
        exercisesBySeedID: [UUID: ExerciseModel],
        in context: ModelContext,
        now: Date
    ) throws -> (inserted: Int, skipped: Int) {
        var existingIDs = Set<UUID>()
        var hasActiveProgram = false
        for program in try context.fetch(FetchDescriptor<ProgramModel>()) {
            existingIDs.insert(program.uuid)
            if program.isActive {
                hasActiveProgram = true
            }
        }

        var inserted = 0
        var skipped = 0
        for template in templates {
            // Programa já instalado (ou restaurado de backup): pode ter sido editado pelo
            // usuário; o seed nunca o reescreve.
            guard !existingIDs.contains(template.id) else {
                skipped += 1
                continue
            }

            let program = try ProgramMapper.model(
                from: template,
                exercises: exercisesBySeedID,
                createdAt: now
            )
            // SPEC S1: um único programa ativo. O que o usuário já treina continua ativo.
            if hasActiveProgram {
                program.isActive = false
            } else if program.isActive {
                hasActiveProgram = true
            }
            // O mapper devolve o grafo (dias e exercícios do programa) sem contexto; inserir
            // a raiz faz o SwiftData inserir os modelos relacionados junto com o pai. Os
            // `ExerciseModel` já estão neste contexto (inseridos ou buscados acima).
            context.insert(program)
            existingIDs.insert(template.id)
            inserted += 1
        }

        return (inserted: inserted, skipped: skipped)
    }

    // MARK: - Store

    @MainActor
    private static func fetchSettings(in context: ModelContext) throws -> UserSettingsModel? {
        var descriptor = FetchDescriptor<UserSettingsModel>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
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
