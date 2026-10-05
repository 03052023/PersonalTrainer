import Foundation

/// Os endereços públicos do app, num lugar só (SPEC §7.18 L2 e L3). Quando o dono tiver o site e o
/// número do app na loja, só estas constantes mudam; sem o endereço, a linha correspondente não
/// aparece e nenhum texto provisório toma o lugar (contrato V25 §1, regra 7).
enum AppLinks {
    /// Política de privacidade (a loja exige o endereço). `nil` até o site existir.
    static let privacyPolicyURL: URL? = nil

    /// Página de suporte (a loja exige o endereço). `nil` até o site existir.
    static let supportURL: URL? = nil

    /// O número que o App Store Connect dá ao app (só dígitos). `nil` até o app existir na loja.
    static let appStoreID: String? = nil

    /// Página de avaliação do app na loja. Só devolve o endereço quando o ID tem apenas dígitos
    /// (0 a 9) e não é vazio; qualquer outra coisa vira `nil`, para nunca montar um link quebrado.
    static func writeReviewURL(appStoreID: String?) -> URL? {
        guard let appStoreID, !appStoreID.isEmpty else {
            return nil
        }
        // Só os dígitos ASCII: `Character.isNumber` aceitaria também algarismos de outros alfabetos.
        let onlyDigits = appStoreID.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x30 && scalar.value <= 0x39
        }
        guard onlyDigits else {
            return nil
        }
        return URL(string: "https://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }

    /// `writeReviewURL(appStoreID:)` com o ID do app. `nil` hoje: o item "Avaliar o Magister" fica
    /// escondido até o ID existir (L3).
    static var writeReviewURL: URL? {
        writeReviewURL(appStoreID: appStoreID)
    }
}
