import Foundation
import SwiftData

/// Plano de migração do store do iPhone (ARCHITECTURE §5, decisão 4).
///
/// Cada versão nova de esquema vira um item em `schemas` e um `MigrationStage` em `stages`,
/// mais um teste que abre um store da versão anterior (AGENTS R6). Nunca se edita uma versão
/// já publicada para isso.
///
/// - V1 → V2 (T2.11): leve. V2 só acrescenta atributos com valor padrão na declaração
///   (`movementPatternRaw`, `isCustom`, `goalRaw`, `summary`, `prescribedTargetReps`); não
///   renomeia nem remove nada, então o SwiftData migra sem código próprio.
enum PersonalTrainerMigrationPlan: SchemaMigrationPlan {
    // Propriedades computadas para não criar estado global mutável (Swift 6):
    // `MigrationStage` não é `Sendable`, então nem poderia ser um `static let`.
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static var migrateV1toV2: MigrationStage {
        .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
    }
}
