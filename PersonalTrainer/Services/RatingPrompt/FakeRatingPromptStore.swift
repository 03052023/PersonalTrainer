import Foundation

/// `RatingPromptStoring` em memória (AGENTS R9), para testes e previews. Nada vai ao `UserDefaults`.
/// O padrão é "fora da loja": um preview ou um teste que não trata da avaliação nunca pede.
final class FakeRatingPromptStore: RatingPromptStoring {
    let isStoreInstall: Bool
    let currentVersion: String
    /// O que `lastRequest()` devolve; muda só por `recordRequest(_:)` ou pelo `init`. Não se chama
    /// `lastRequest` para não conflitar com o método do protocolo.
    private(set) var storedRequest: RatingPromptRecord?
    /// Pedidos gravados, na ordem, para os testes conferirem.
    private(set) var recorded: [RatingPromptRecord] = []

    init(isStoreInstall: Bool = false, currentVersion: String = "1.0.0", lastRequest: RatingPromptRecord? = nil) {
        self.isStoreInstall = isStoreInstall
        self.currentVersion = currentVersion
        self.storedRequest = lastRequest
    }

    func lastRequest() -> RatingPromptRecord? {
        storedRequest
    }

    func recordRequest(_ record: RatingPromptRecord) {
        storedRequest = record
        recorded.append(record)
    }
}
