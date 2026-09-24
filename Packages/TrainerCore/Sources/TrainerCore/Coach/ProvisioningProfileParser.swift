import Foundation

/// Reads the expiry of the app's installation (SPEC §7.11 C4). A sideloaded app signed
/// with a free Apple account carries an `embedded.mobileprovision`: a CMS (PKCS #7)
/// envelope whose payload is an XML property list with `ExpirationDate`. Decoding the
/// CMS itself would need Security.framework, which TrainerCore cannot import (AGENTS
/// R1); the XML payload sits in the file as plain bytes, so it is cut out directly.
public enum ProvisioningProfileParser: Sendable {
    private static let xmlStart = Array("<?xml".utf8)
    private static let plistEnd = Array("</plist>".utf8)

    /// Extrai `ExpirationDate` do plist XML embutido no CMS do `embedded.mobileprovision`.
    /// Procura "<?xml" … "</plist>" nos bytes e usa PropertyListSerialization. nil se não achar.
    public static func expirationDate(from data: Data) -> Date? {
        guard let plist = embeddedPlist(in: data) else {
            return nil
        }
        if let object = try? PropertyListSerialization.propertyList(from: plist, options: [], format: nil),
           let dictionary = object as? [String: Any],
           let expiry = dictionary["ExpirationDate"] as? Date {
            return expiry
        }
        // The same payload through the typed decoder: the untyped result above relies on
        // Foundation bridging, which differs on Linux (CI); the Codable path does not.
        return (try? PropertyListDecoder().decode(ExpiryPayload.self, from: plist))?.expirationDate
    }

    /// The bytes from the first "<?xml" to the first "</plist>" after it, inclusive.
    static func embeddedPlist(in data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard let start = firstIndex(of: xmlStart, in: bytes, from: 0),
              let end = firstIndex(of: plistEnd, in: bytes, from: start + xmlStart.count)
        else {
            return nil
        }
        return Data(bytes[start..<(end + plistEnd.count)])
    }

    /// Naive byte search; a profile is a few kilobytes, so nothing smarter is needed.
    static func firstIndex(of pattern: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        guard !pattern.isEmpty, start >= 0, bytes.count >= pattern.count else {
            return nil
        }
        let last = bytes.count - pattern.count
        guard start <= last else {
            return nil
        }
        for index in start...last {
            var matched = 0
            while matched < pattern.count, bytes[index + matched] == pattern[matched] {
                matched += 1
            }
            if matched == pattern.count {
                return index
            }
        }
        return nil
    }
}

/// The only key of the profile the app needs.
private struct ExpiryPayload: Decodable {
    let expirationDate: Date

    enum CodingKeys: String, CodingKey {
        case expirationDate = "ExpirationDate"
    }
}
