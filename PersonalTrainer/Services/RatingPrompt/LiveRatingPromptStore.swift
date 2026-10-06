import Foundation

/// `RatingPromptStoring` do app (SPEC §7.18 L3, AGENTS R9).
///
/// - Grava só duas chaves no `UserDefaults`: `ratingPromptLastVersion` (String) e
///   `ratingPromptLastRequestAt` (Double, segundos desde 1970). O uso do `UserDefaults` já está declarado
///   no manifesto de privacidade (`CA92.1`, L1).
/// - A versão vem de `CFBundleShortVersionString` (L7).
/// - "Veio da loja" é calculado uma vez, no `init`: sem `embedded.mobileprovision` no bundle e fora do
///   simulador. A cópia de teste do dono e os builds de desenvolvimento têm o perfil e nunca pedem; no
///   TestFlight não há perfil, mas lá o iOS ignora o pedido. Não é API documentada da Apple, só a prática
///   comum; o `AppTransaction` do StoreKit 2 ficou de fora porque pode ir à rede e, em casos raros, pedir
///   login (contrato `docs/V25-CONTRACT.md` §9).
final class LiveRatingPromptStore: RatingPromptStoring {
    static let lastVersionKey = "ratingPromptLastVersion"
    static let lastRequestAtKey = "ratingPromptLastRequestAt"

    let isStoreInstall: Bool
    let currentVersion: String

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        self.currentVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let hasEmbeddedProfile = bundle.url(forResource: "embedded", withExtension: "mobileprovision") != nil
        self.isStoreInstall = LiveRatingPromptStore.isStoreInstall(
            hasEmbeddedProfile: hasEmbeddedProfile,
            isSimulator: LiveRatingPromptStore.isRunningInSimulator
        )
    }

    /// A regra de "veio da loja", pura para os testes: sem perfil embutido e fora do simulador.
    static func isStoreInstall(hasEmbeddedProfile: Bool, isSimulator: Bool) -> Bool {
        !hasEmbeddedProfile && !isSimulator
    }

    private static var isRunningInSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    func lastRequest() -> RatingPromptRecord? {
        guard let version = defaults.string(forKey: Self.lastVersionKey),
              defaults.object(forKey: Self.lastRequestAtKey) != nil
        else {
            return nil
        }
        let seconds = defaults.double(forKey: Self.lastRequestAtKey)
        return RatingPromptRecord(version: version, date: Date(timeIntervalSince1970: seconds))
    }

    func recordRequest(_ record: RatingPromptRecord) {
        defaults.set(record.version, forKey: Self.lastVersionKey)
        defaults.set(record.date.timeIntervalSince1970, forKey: Self.lastRequestAtKey)
    }
}
