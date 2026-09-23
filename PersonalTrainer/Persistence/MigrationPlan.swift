import Foundation
import SwiftData

/// Plano de migração do store do iPhone (ARCHITECTURE §5, decisão 4).
///
/// Existe desde a V1, mesmo sem estágios: adicionar `SchemaV2` vira um item novo em
/// `schemas` e um `MigrationStage` em `stages`, mais um teste que abre um store V1
/// gravado como fixture (AGENTS R6). Nunca se edita `SchemaV1` para isso.
enum PersonalTrainerMigrationPlan: SchemaMigrationPlan {
    // Propriedades computadas para não criar estado global mutável (Swift 6).
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
