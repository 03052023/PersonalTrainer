import Foundation
import SwiftData
import os

/// Único lugar do app que constrói `ModelContainer` (ARCHITECTURE §5, decisão 5).
///
/// - `.persistent`: store em `Application Support/PersonalTrainer/PersonalTrainer.store`,
///   incluído no backup do iCloud do iPhone (ARCHITECTURE §15, "Store corrompido"). Antes da
///   primeira abertura com o esquema atual, o store é copiado ao lado (ver
///   `copyStoreBeforeOpeningIfNeeded`): uma migração com defeito deixa de ser irreversível.
/// - `.inMemory`: previews e testes; nada toca o disco.
///
/// CloudKit fica desligado: `@Attribute(.unique)` é incompatível com ele e sync em nuvem
/// está fora de escopo (ADR 001). O app não tem entitlement iCloud, então o padrão de
/// `ModelConfiguration` já não ativa CloudKit; usam-se as formas mínimas documentadas
/// dos inicializadores (`schema:url:` e `schema:isStoredInMemoryOnly:`), sem argumentos
/// opcionais, porque este código é escrito sem compilador local (AGENTS R11).
enum ModelContainerFactory {
    enum Mode {
        case persistent
        case inMemory
    }

    /// Nome da cópia feita antes da primeira abertura com o esquema atual. Atualizar junto com
    /// `CurrentSchema` a cada esquema novo (AGENTS R6): cada versão ganha a própria cópia, e a
    /// anterior continua no disco.
    static let preMigrationCopyName = "PersonalTrainer.before-schema-v2.store"

    private static let storeFileName = "PersonalTrainer.store"
    /// Arquivos auxiliares do SQLite em modo WAL, que o SwiftData cria ao lado do store.
    private static let sqliteSidecarSuffixes = ["-wal", "-shm"]

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "PersonalTrainer",
        category: "Persistence"
    )

    static func make(_ mode: Mode) throws -> ModelContainer {
        // `CurrentSchema`, e não `SchemaV1`: quando `SchemaV2` entrar no plano, o container
        // precisa abrir com a última versão sem que alguém lembre de editar esta linha.
        let schema = Schema(versionedSchema: CurrentSchema.self)
        let configuration: ModelConfiguration

        switch mode {
        case .persistent:
            let url = try persistentStoreURL()
            copyStoreBeforeOpeningIfNeeded(storeURL: url)
            configuration = ModelConfiguration(schema: schema, url: url)
        case .inMemory:
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }

        return try ModelContainer(
            for: schema,
            migrationPlan: PersonalTrainerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Arquivos do store persistente que existem no disco (store, `-wal`, `-shm` e a cópia feita
    /// antes da migração), para a tela de erro oferecer a exportação quando o store não abre.
    /// Vazio se nada existe ou se a pasta não pode ser lida.
    static func existingPersistentStoreFiles() -> [URL] {
        guard let storeURL = try? persistentStoreURL() else {
            return []
        }
        let copyURL = storeURL.deletingLastPathComponent().appendingPathComponent(preMigrationCopyName, isDirectory: false)
        let candidates = storeFileSet(for: storeURL) + storeFileSet(for: copyURL)
        return candidates.filter { fileExists($0) }
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
        return directory.appendingPathComponent(storeFileName, isDirectory: false)
    }

    /// Copia o store e seus arquivos WAL para `preMigrationCopyName` (+ `-wal`, `-shm`) uma única
    /// vez, antes de o SwiftData abrir o store com o esquema atual (e migrá-lo, se ele for de uma
    /// versão anterior). Nesse instante nada tem o SQLite aberto, então os três arquivos juntos são
    /// uma cópia consistente, que abre com o esquema antigo.
    ///
    /// - Instalação limpa (sem store): nada a copiar.
    /// - Cópia já existe: não sobrescreve (a primeira é a de antes da migração).
    /// - Em quem instalou já nesta versão, a cópia do 2º launch é só um retrato inofensivo.
    /// - O store principal é copiado por último: a presença dele marca uma cópia completa. Em falha,
    ///   o que foi copiado é removido (para tentar de novo no próximo launch) e o erro só vai para o
    ///   log: a cópia é um seguro e nunca impede abrir os dados.
    private static func copyStoreBeforeOpeningIfNeeded(storeURL: URL) {
        guard fileExists(storeURL) else {
            return
        }
        let copyURL = storeURL.deletingLastPathComponent().appendingPathComponent(preMigrationCopyName, isDirectory: false)
        guard !fileExists(copyURL) else {
            return
        }
        let fileManager = FileManager.default
        let sources = storeFileSet(for: storeURL)
        let destinations = storeFileSet(for: copyURL)
        do {
            for (source, destination) in zip(sources, destinations) where fileExists(source) {
                if fileExists(destination) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: source, to: destination)
            }
            logger.info("Cópia do store feita antes de abrir com o esquema atual: \(copyURL.lastPathComponent, privacy: .public)")
        } catch {
            for destination in destinations where fileExists(destination) {
                try? fileManager.removeItem(at: destination)
            }
            logger.error("Não foi possível copiar o store antes de abrir: \(String(describing: error), privacy: .public)")
        }
    }

    /// `[<store>-wal, <store>-shm, <store>]`: os auxiliares primeiro, o principal por último.
    private static func storeFileSet(for storeURL: URL) -> [URL] {
        let directory = storeURL.deletingLastPathComponent()
        let name = storeURL.lastPathComponent
        let sidecars = sqliteSidecarSuffixes.map { suffix in
            directory.appendingPathComponent(name + suffix, isDirectory: false)
        }
        return sidecars + [storeURL]
    }

    private static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}
