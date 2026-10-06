import Foundation
import XCTest
@testable import PersonalTrainer

/// SPEC §7.18 L2 (página "Privacidade"), L3 (item "Avaliar o Magister", só com o ID do app) e L5
/// (aviso de saúde): os textos de `PrivacyText` dizem fatos, sem promessa absoluta, e os endereços
/// de `AppLinks` só viram link quando existem.
final class PrivacyAboutTests: XCTestCase {
    // MARK: - L2: textos

    func testL2_privacyTextsHaveNoAbsolutePromises() {
        let forbidden: [String] = [
            "100%", "100 %", "seguro", "garant", "nada sai", "aprovado pela apple", "lgpd",
            "validado", "impactor", "personal", "treinador", "coach", "icloud drive",
        ]
        XCTAssertFalse(PrivacyText.all.isEmpty)
        for text in PrivacyText.all {
            let lowered = text.lowercased()
            for word in forbidden {
                XCTAssertFalse(lowered.contains(word), "\"\(word)\" não pode aparecer em: \(text)")
            }
        }
    }

    func testL2_privacyTextsStateTheFacts() {
        let joined = PrivacyText.all.joined(separator: "\n")
        let facts: [String] = [
            "não coleta dados",
            "Acesso a Dados e Dispositivos",
            "Guarde-o num lugar só seu",
            "backup do iPhone no iCloud",
            "app Saúde",
        ]
        for fact in facts {
            XCTAssertTrue(joined.contains(fact), "Falta o fato: \(fact)")
        }
    }

    /// Os itens que a página lista são os dos textos de permissão do iOS (contrato V25 §6.3).
    func testL2_healthListsMatchPermissions() {
        let reads = PrivacyText.healthReads.lowercased()
        XCTAssertTrue(PrivacyText.healthReads.hasPrefix("Lê:"))
        let readItems: [String] = [
            "treinos", "frequência cardíaca", "vo2máx", "variabilidade", "repouso", "sono", "passos",
            "data de nascimento", "sexo",
        ]
        for item in readItems {
            XCTAssertTrue(reads.contains(item), "A lista de leitura não cita: \(item)")
        }

        let writes = PrivacyText.healthWrites.lowercased()
        XCTAssertTrue(PrivacyText.healthWrites.hasPrefix("Grava:"))
        let writeItems: [String] = ["força", "aeróbico"]
        for item in writeItems {
            XCTAssertTrue(writes.contains(item), "A lista de gravação não cita: \(item)")
        }
    }

    /// Nenhuma linha provisória: o que ainda não existe não aparece (contrato V25 §1, regra 7).
    func testL2_noPlaceholderTexts() {
        let placeholders: [String] = ["em breve", "lorem", "xxx", "http", "exemplo", "provisório"]
        for text in PrivacyText.all {
            XCTAssertFalse(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let lowered = text.lowercased()
            for placeholder in placeholders {
                XCTAssertFalse(lowered.contains(placeholder), "\"\(placeholder)\" em: \(text)")
            }
        }
    }

    // MARK: - L3: endereço da avaliação

    func testL3_writeReviewURLNeedsDigits() throws {
        XCTAssertNil(AppLinks.writeReviewURL(appStoreID: nil))
        XCTAssertNil(AppLinks.writeReviewURL(appStoreID: ""))
        XCTAssertNil(AppLinks.writeReviewURL(appStoreID: "abc"))
        XCTAssertNil(AppLinks.writeReviewURL(appStoreID: "12a45"))
        XCTAssertNil(AppLinks.writeReviewURL(appStoreID: " 123"))
        XCTAssertNil(AppLinks.writeReviewURL(appStoreID: "12 3"))
        XCTAssertNil(AppLinks.writeReviewURL(appStoreID: "１２３"), "Só os dígitos de 0 a 9")

        let url = try XCTUnwrap(AppLinks.writeReviewURL(appStoreID: "1234567890"))
        XCTAssertEqual(url.absoluteString, "https://apps.apple.com/app/id1234567890?action=write-review")
    }

    /// A propriedade usa o ID guardado em `AppLinks`: sem ele, o item não aparece.
    func testL3_writeReviewURLFollowsTheStoredID() {
        let fromProperty: URL? = AppLinks.writeReviewURL
        let fromFunction: URL? = AppLinks.writeReviewURL(appStoreID: AppLinks.appStoreID)
        XCTAssertEqual(fromProperty, fromFunction)
    }

    // MARK: - L5: aviso de saúde

    func testL5_healthNoticeIsExact() {
        XCTAssertEqual(
            PrivacyText.healthNotice,
            "O Magister não substitui a orientação de um médico ou de um profissional de educação física."
        )
        XCTAssertEqual(PrivacyText.aboutPrivacy, "Privacidade")
        XCTAssertEqual(PrivacyText.rateApp, "Avaliar o Magister")
    }
}
