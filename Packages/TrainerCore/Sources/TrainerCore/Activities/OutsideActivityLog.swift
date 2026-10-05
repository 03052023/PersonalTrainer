import Foundation

/// Tudo o que a pessoa registrou fora do app (SPEC §7.17 X8): os registros e as fixas. O app grava num JSON
/// em Application Support (sem SchemaV3) e leva no backup, no campo opcional `outsideActivities`.
///
/// Decodificação tolerante: chave ausente vale lista vazia, e `version` ausente vale 1.
public struct OutsideActivityLog: Codable, Sendable, Hashable {
    /// Versão do formato que este app grava.
    public static let currentVersion = 1

    public var version: Int
    public var entries: [OutsideActivityEntry]
    public var fixed: [FixedOutsideActivity]

    public init(
        version: Int = OutsideActivityLog.currentVersion,
        entries: [OutsideActivityEntry] = [],
        fixed: [FixedOutsideActivity] = []
    ) {
        self.version = version
        self.entries = entries
        self.fixed = fixed
    }

    /// Nada registrado.
    public static let empty = OutsideActivityLog()

    private enum CodingKeys: String, CodingKey {
        case version, entries, fixed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.entries = try container.decodeIfPresent([OutsideActivityEntry].self, forKey: .entries) ?? []
        self.fixed = try container.decodeIfPresent([FixedOutsideActivity].self, forKey: .fixed) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(entries, forKey: .entries)
        try container.encode(fixed, forKey: .fixed)
    }
}
