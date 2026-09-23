import Foundation

/// Failures when decoding data received from the other device.
///
/// AGENTS §4: one `enum XError` per service, and a WatchConnectivity failure
/// never interrupts the session flow — the receiver keeps its last known state.
public enum SyncError: Error, Equatable, Sendable {
    /// The payload was produced by a newer `SyncSchema`. The Watch should keep
    /// what it has and show "Atualize o app do iPhone" (ARCHITECTURE §9).
    case unsupportedSchemaVersion(found: Int, supported: Int)
    /// The payload is not a valid document of a supported schema version:
    /// malformed JSON, missing or mistyped keys, an unknown `SessionEvent.Kind`
    /// tag, or a `schemaVersion` below 1. The underlying `DecodingError` is not
    /// surfaced on purpose: the DTO layer has no logger (AGENTS R1, Foundation
    /// only) and the only sane reaction is to discard the payload.
    case corrupted
}

/// Single entry point for encoding and decoding sync DTOs (ARCHITECTURE §9, AR-3).
///
/// Both devices must use it so the bytes agree: dates as ISO 8601 (UTC,
/// whole-second precision — fractional seconds are dropped, see
/// `SessionEvent.occurredAt`) and keys sorted, which makes `encode` a pure
/// function of the value (SPEC P11 spirit: same input, same bytes).
public enum SyncCodec {
    /// Encodes any sync DTO. Throws `EncodingError` only for values that cannot
    /// be represented (e.g. a non-finite `Double`), which is a producer bug.
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        try makeEncoder().encode(value)
    }

    /// Decodes an `ActiveSessionSnapshot`, checking `schemaVersion` **before**
    /// decoding the rest: a newer iPhone may have added fields or cases that
    /// would otherwise fail as `.corrupted`, hiding the real cause.
    public static func decodeSnapshot(_ data: Data) throws -> ActiveSessionSnapshot {
        let envelope = try decode(SchemaVersionEnvelope.self, from: data)
        try requireSupported(schemaVersion: envelope.schemaVersion)
        return try decode(ActiveSessionSnapshot.self, from: data)
    }

    /// Decodes one event (one `transferUserInfo` payload, ARCHITECTURE §9).
    /// Events carry no `schemaVersion`; an unknown `Kind` tag is `.corrupted`.
    public static func decodeEvent(_ data: Data) throws -> SessionEvent {
        try decode(SessionEvent.self, from: data)
    }

    /// Decodes a JSON array of events (e.g. the Watch's persisted pending queue).
    public static func decodeEvents(_ data: Data) throws -> [SessionEvent] {
        try decode([SessionEvent].self, from: data)
    }

    // MARK: - Private

    /// Minimal projection used to read the version without decoding the payload.
    private struct SchemaVersionEnvelope: Decodable {
        let schemaVersion: Int
    }

    private static func requireSupported(schemaVersion: Int) throws {
        guard schemaVersion <= SyncSchema.currentVersion else {
            throw SyncError.unsupportedSchemaVersion(
                found: schemaVersion,
                supported: SyncSchema.currentVersion
            )
        }
        // No schema below 1 was ever published; such a value can only come from
        // a damaged payload, so it is not an "update your app" situation.
        guard schemaVersion >= 1 else {
            throw SyncError.corrupted
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try makeDecoder().decode(type, from: data)
        } catch let error as SyncError {
            throw error
        } catch {
            throw SyncError.corrupted
        }
    }

    // JSONEncoder/JSONDecoder are not Sendable, so they cannot be cached in a
    // static property under Swift 6; building them per call is cheap.
    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
