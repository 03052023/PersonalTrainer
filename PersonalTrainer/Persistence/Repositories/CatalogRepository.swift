import Foundation
import SwiftData
import TrainerCore

/// Implementação de `CatalogRepositoring` sobre SwiftData (T2.5, RF-15; AGENTS R4): depois do seed,
/// o único lugar do app que cria ou altera `ExerciseModel`.
///
/// - Exercício nunca é apagado, só arquivado: o histórico e os programas apontam para ele
///   (ARCHITECTURE §5).
/// - `uuid` e `slug` são a identidade e nunca mudam depois de criados. Os dois são `.unique`: um
///   `insert` com valor repetido vira upsert silencioso (ARCHITECTURE §15), por isso o slug de um
///   exercício novo é conferido no store antes do `insert`.
/// - Cada mutação valida antes de tocar o store e salva no fim; falha no `save()` faz `rollback()`.
/// - `@MainActor` porque `@Model` não é `Sendable` (ARCHITECTURE §10).
@MainActor
final class CatalogRepository: CatalogRepositoring {
    private let modelContext: ModelContext

    /// Prefixo dos slugs criados pelo usuário: nunca colide com os slugs do seed, que não o usam.
    private static let customSlugPrefix = "custom-"
    /// Teto do trecho do nome no slug; o sufixo do UUID é que garante a unicidade.
    private static let maxSlugNameLength = 40

    /// Ordenação e dobra de acentos independentes do idioma do aparelho (SPEC P11).
    private static let ptBR = Locale(identifier: "pt_BR")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Leitura

    func allExercises(includeArchived: Bool) throws -> [ExerciseDefinition] {
        let descriptor: FetchDescriptor<ExerciseModel>
        if includeArchived {
            descriptor = FetchDescriptor<ExerciseModel>()
        } else {
            descriptor = FetchDescriptor<ExerciseModel>(
                predicate: #Predicate<ExerciseModel> { $0.isArchived == false }
            )
        }

        return try modelContext.fetch(descriptor)
            .map { try definition(from: $0) }
            .sorted { Self.nameOrder($0, $1) }
    }

    func exercise(id: UUID) throws -> ExerciseDefinition? {
        guard let model = try fetchExercise(uuid: id) else {
            return nil
        }
        return try definition(from: model)
    }

    // MARK: - Escrita

    func createExercise(_ draft: ExerciseDraft) throws -> UUID {
        guard draft.isValid else {
            throw CatalogRepositoryError.invalidDraft
        }

        let id = UUID()
        let name = Self.normalizedName(draft.name)
        let slug = try uniqueSlug(forName: name, id: id)
        let definition = ExerciseDefinition(
            id: id,
            slug: slug,
            name: name,
            primaryMuscles: draft.primaryMuscles,
            secondaryMuscles: draft.secondaryMuscles,
            equipment: draft.equipment,
            loadUnit: draft.loadUnit,
            loadIncrement: draft.loadIncrement,
            isUnilateral: draft.isUnilateral,
            machineNotes: Self.normalizedNotes(draft.machineNotes),
            movementPattern: draft.movementPattern,
            isCustom: true
        )

        let model = ExerciseMapper.model(from: definition)
        // Gravados explicitamente: garantem os campos do SchemaV2 qualquer que seja a versão do
        // mapper. `isCustom` protege o exercício do upsert do seed (M2-CONTRACT §2).
        model.movementPatternRaw = draft.movementPattern?.rawValue
        model.isCustom = true
        modelContext.insert(model)

        try save()
        return id
    }

    func updateExercise(id: UUID, with draft: ExerciseDraft) throws {
        guard let model = try fetchExercise(uuid: id) else {
            throw CatalogRepositoryError.exerciseNotFound(id)
        }
        guard draft.isValid else {
            throw CatalogRepositoryError.invalidDraft
        }

        // `uuid`, `slug`, `isCustom` e `isArchived` não mudam aqui: identidade, origem e
        // arquivamento têm caminhos próprios.
        model.name = Self.normalizedName(draft.name)
        model.primaryMusclesRaw = SchemaV1.encodeMuscleGroups(draft.primaryMuscles)
        model.secondaryMusclesRaw = SchemaV1.encodeMuscleGroups(draft.secondaryMuscles)
        model.equipmentRaw = draft.equipment.rawValue
        model.loadUnitRaw = draft.loadUnit.rawValue
        model.loadIncrement = draft.loadIncrement
        model.isUnilateral = draft.isUnilateral
        model.machineNotes = Self.normalizedNotes(draft.machineNotes)
        model.movementPatternRaw = draft.movementPattern?.rawValue

        try save()
    }

    func setArchived(id: UUID, _ archived: Bool) throws {
        guard let model = try fetchExercise(uuid: id) else {
            throw CatalogRepositoryError.exerciseNotFound(id)
        }
        if model.isArchived != archived {
            model.isArchived = archived
        }
        try save()
    }

    // MARK: - Slug

    /// "Supino Inclinado c/ Halteres" → "supino-inclinado-c-halteres": minúsculas, sem acentos, só
    /// `[a-z0-9]` separados por um hífen, no formato dos slugs do seed. Pode voltar vazio (nome só
    /// com símbolos); quem chama trata.
    static func kebabCase(_ name: String) -> String {
        let folded = name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: ptBR)
            .lowercased()

        var result = ""
        var pendingHyphen = false
        for character in folded {
            if character.isASCII && (character.isLetter || character.isNumber) {
                if pendingHyphen && !result.isEmpty {
                    result.append("-")
                }
                pendingHyphen = false
                result.append(character)
            } else {
                pendingHyphen = true
            }
        }

        var truncated = String(result.prefix(maxSlugNameLength))
        while truncated.hasSuffix("-") {
            truncated.removeLast()
        }
        return truncated
    }

    /// `custom-<nome>-<8 hex do UUID>`. Os 8 hex separam dois exercícios de mesmo nome; na colisão
    /// improvável com um slug já gravado, usa o UUID inteiro, único por construção.
    private func uniqueSlug(forName name: String, id: UUID) throws -> String {
        let base = Self.kebabCase(name)
        let prefix = base.isEmpty ? Self.customSlugPrefix : "\(Self.customSlugPrefix)\(base)-"
        let fullSuffix = id.uuidString.lowercased()

        let candidate = prefix + String(fullSuffix.prefix(8))
        if try fetchExercise(slug: candidate) == nil {
            return candidate
        }
        return prefix + fullSuffix
    }

    // MARK: - Mapeamento

    /// `ExerciseMapper` converte os campos de V1. Padrão de movimento e origem são lidos aqui direto
    /// do modelo para o DTO sempre carregá-los, qualquer que seja a versão do mapper.
    private func definition(from model: ExerciseModel) throws -> ExerciseDefinition {
        let mapped = try ExerciseMapper.definition(from: model)
        return ExerciseDefinition(
            id: mapped.id,
            slug: mapped.slug,
            name: mapped.name,
            primaryMuscles: mapped.primaryMuscles,
            secondaryMuscles: mapped.secondaryMuscles,
            equipment: mapped.equipment,
            loadUnit: mapped.loadUnit,
            loadIncrement: mapped.loadIncrement,
            isUnilateral: mapped.isUnilateral,
            machineNotes: mapped.machineNotes,
            movementPattern: model.movementPatternRaw.flatMap { MovementPattern(rawValue: $0) },
            isCustom: model.isCustom
        )
    }

    // MARK: - Regras auxiliares

    /// Nome em pt-BR sem diferenciar maiúsculas; empate pelo slug, que é único (SPEC P11).
    private static func nameOrder(_ lhs: ExerciseDefinition, _ rhs: ExerciseDefinition) -> Bool {
        let byName = lhs.name.compare(rhs.name, options: [.caseInsensitive], locale: ptBR)
        if byName != .orderedSame {
            return byName == .orderedAscending
        }
        return lhs.slug < rhs.slug
    }

    private static func normalizedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Notas só com espaços viram `nil`: a UI mostra "sem anotação" em vez de uma linha vazia.
    private static func normalizedNotes(_ notes: String?) -> String? {
        guard let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    // MARK: - Store

    private func save() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func fetchExercise(uuid: UUID) throws -> ExerciseModel? {
        var descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate<ExerciseModel> { $0.uuid == uuid }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchExercise(slug: String) throws -> ExerciseModel? {
        var descriptor = FetchDescriptor<ExerciseModel>(
            predicate: #Predicate<ExerciseModel> { $0.slug == slug }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
