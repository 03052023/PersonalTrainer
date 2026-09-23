import SwiftUI
import UniformTypeIdentifiers

/// Envelope do JSON de backup para o `fileExporter` (T2.4). Só carrega os bytes já gerados pelo
/// `BackupServicing`; não interpreta nada. A leitura (`init(configuration:)`) existe porque o
/// protocolo exige, mas a importação usa `fileImporter` + `BackupServicing.importBackup`.
struct BackupFileDocument: FileDocument {
    // Propriedade computada, não armazenada: `static var` armazenada é estado global mutável,
    // proibido em Swift 6 strict concurrency.
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
