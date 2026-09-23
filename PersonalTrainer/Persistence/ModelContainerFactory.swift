import Foundation
import SwiftData

/// Único lugar do app que constrói `ModelContainer` (ARCHITECTURE §5, decisão 5).
///
/// - `.persistent`: store em `Application Support/PersonalTrainer/PersonalTrainer.store`,
///   incluído no backup do iCloud do iPhone (ARCHITECTURE §15, "Store corrompido").
/// - `.inMemory`: previews e testes; nada toca o disco.
///
/// CloudKit fica explicitamente desligado: `@Attribute(.unique)` é incompatível com ele
/// e sync em nuvem está fora de escopo (ADR 001).
enum ModelContainerFactory {
    enum Mode {
        case persistent
        case inMemory
    }

    static func make(_ mode: Mode) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration: ModelConfiguration

        switch mode {
        case .persistent:
            let url = try persistentStoreURL()
            configuration = ModelConfiguration(
                "PersonalTrainer",
                schema: schema,
                url: url,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        case .inMemory:
            configuration = ModelConfiguration(
                "PersonalTrainer",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none
            )
        }

        return try ModelContainer(
            for: schema,
            migrationPlan: PersonalTrainerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Cria o diretório se preciso; `Application Support` não existe por padrão em
    /// instalação limpa e SwiftData não cria pastas intermediárias.
    private static func persistentStoreURL() throws -> URL {
        let fileManager = FileManager.default
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent("PersonalTrainer", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("PersonalTrainer.store", isDirectory: false)
    }
}
