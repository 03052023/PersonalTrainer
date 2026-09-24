import Foundation
import Testing
@testable import TrainerCore

// SPEC §7.11 C4: "Lê a data de expiração do perfil de assinatura embutido no app".

@Suite("Coach — C4 perfil de assinatura")
struct CoachProvisioningProfileParserTests {
    /// 2026-09-30T14:05:00Z.
    static let expiry = Date(timeIntervalSince1970: 1_790_777_100)

    /// Bytes that look like the start of a CMS (DER) envelope, including 0x00 and 0xFF.
    static let cmsPrefix: [UInt8] = [0x30, 0x82, 0x1F, 0x3A, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x07, 0x02, 0xA0, 0x00, 0xFF]
    /// Bytes that look like the signer certificates after the payload.
    static let cmsSuffix: [UInt8] = [0xA0, 0x82, 0x0D, 0x00, 0xFF, 0x3C, 0x31, 0x00]

    static func plist(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        \(body)
        </plist>
        """
    }

    static let fullDictionary = """
        <dict>
            <key>AppIDName</key>
            <string>Magister</string>
            <key>CreationDate</key>
            <date>2026-09-23T14:05:00Z</date>
            <key>DeveloperCertificates</key>
            <array>
                <data>MIIFxjCCBK6gAwIBAgIQ</data>
            </array>
            <key>Entitlements</key>
            <dict>
                <key>com.apple.developer.healthkit</key>
                <true/>
            </dict>
            <key>ExpirationDate</key>
            <date>2026-09-30T14:05:00Z</date>
            <key>TimeToLive</key>
            <integer>7</integer>
        </dict>
        """

    static func profile(_ text: String, prefix: [UInt8] = cmsPrefix, suffix: [UInt8] = cmsSuffix) -> Data {
        Data(prefix + Array(text.utf8) + suffix)
    }

    @Test("C4 lê ExpirationDate do plist dentro do envelope CMS")
    func readsTheExpirationDate() {
        let data = Self.profile(Self.plist(Self.fullDictionary))

        #expect(ProvisioningProfileParser.expirationDate(from: data) == Self.expiry)
    }

    @Test("C4 um </plist> antes do <?xml não atrapalha")
    func ignoresPlistEndBeforeTheStart() {
        let data = Self.profile(Self.plist(Self.fullDictionary), prefix: Self.cmsPrefix + Array("</plist>".utf8))

        #expect(ProvisioningProfileParser.expirationDate(from: data) == Self.expiry)
    }

    struct MissingCase: Sendable, CustomTestStringConvertible {
        let text: String
        let label: String

        var testDescription: String { label }
    }

    static let missingCases: [MissingCase] = [
        MissingCase(text: "", label: "arquivo vazio"),
        MissingCase(text: "sem plist nenhum", label: "sem <?xml"),
        MissingCase(
            text: "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>ExpirationDate</key>",
            label: "plist cortado, sem </plist>"
        ),
        MissingCase(
            text: CoachProvisioningProfileParserTests.plist("<dict><key>AppIDName</key><string>Magister</string></dict>"),
            label: "sem ExpirationDate"
        ),
        MissingCase(
            text: CoachProvisioningProfileParserTests.plist(
                "<dict><key>ExpirationDate</key><string>2026-09-30T14:05:00Z</string></dict>"
            ),
            label: "ExpirationDate como texto"
        ),
        MissingCase(
            text: CoachProvisioningProfileParserTests.plist("<array><date>2026-09-30T14:05:00Z</date></array>"),
            label: "raiz não é dicionário"
        ),
    ]

    @Test("C4 sem data de expiração legível, devolve nil", arguments: CoachProvisioningProfileParserTests.missingCases)
    func missingExpirationGivesNil(_ testCase: MissingCase) {
        #expect(ProvisioningProfileParser.expirationDate(from: Self.profile(testCase.text)) == nil)
    }

    @Test("C4 recorta exatamente de <?xml até </plist>")
    func cutsThePayloadExactly() throws {
        let text = Self.plist(Self.fullDictionary)

        let payload = try #require(ProvisioningProfileParser.embeddedPlist(in: Self.profile(text)))

        #expect(payload == Data(text.utf8))
    }
}
