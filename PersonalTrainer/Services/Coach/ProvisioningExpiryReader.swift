import Foundation
import TrainerCore

/// Lê a validade da instalação (SPEC §7.11 C4) no `embedded.mobileprovision` que a ferramenta de
/// sideload coloca na raiz do app. O parse do plist fica no core
/// (`ProvisioningProfileParser.expirationDate`); aqui só se acha e se lê o arquivo.
///
/// Devolve `nil` no simulador e em builds sem assinatura (não há perfil embutido) e quando o
/// arquivo não pôde ser lido: sem data, a mensagem C4 simplesmente não aparece.
struct ProvisioningExpiryReader: Sendable {
    private let readData: @Sendable () -> Data?

    /// Leitor de teste ou de preview: `readData` devolve o conteúdo do perfil (ou `nil`).
    init(readData: @escaping @Sendable () -> Data?) {
        self.readData = readData
    }

    /// Leitor real sobre o bundle do app (`Bundle.main` no app).
    init(bundle: Bundle) {
        // Só a URL (Sendable) entra no fechamento; o `Bundle` fica de fora.
        let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision")
        self.readData = {
            guard let url else {
                return nil
            }
            return try? Data(contentsOf: url)
        }
    }

    /// Sem perfil: previews e testes que não tratam de C4.
    static let unavailable = ProvisioningExpiryReader(readData: { nil })

    /// `ExpirationDate` do perfil, ou `nil`.
    func expirationDate() -> Date? {
        guard let data = readData() else {
            return nil
        }
        return ProvisioningProfileParser.expirationDate(from: data)
    }
}
