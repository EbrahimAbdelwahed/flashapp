import Foundation

/// The `.apkg` container: picks the right collection database out of the ZIP, decompresses
/// it if needed, and resolves media names to their entries.
///
/// The one non-obvious rule, and the one that matters most: **`collection.anki2` is a decoy**.
/// Every modern export still contains it, holding a single note that reads "Please update to
/// the latest Anki version…". Reading it instead of `collection.anki21b` would silently
/// import one junk card and drop the deck. Priority order is therefore mandatory, not a
/// preference (verified against real Anki 26.08 exports — ADR-004 §2).
public final class ApkgArchive: Sendable {
    /// Newest first. The first one present wins.
    private static let collectionEntries = ["collection.anki21b", "collection.anki21", "collection.anki2"]
    private static let mediaIndexEntry = "media"

    private let zip: ZipArchive
    private let limits: ApkgLimits
    /// Logical media filename → ZIP entry name (which is an ordinal like "0", "1", …).
    private let mediaEntries: [String: String]

    public init(data: Data, limits: ApkgLimits = .standard) throws {
        self.limits = limits
        zip = try ZipArchive(data: data, limits: limits)

        guard Self.collectionEntries.contains(where: zip.contains) else {
            throw ApkgError.noCollection
        }
        mediaEntries = try Self.readMediaIndex(zip: zip, limits: limits)
    }

    public var mediaFilenames: Set<String> { Set(mediaEntries.keys) }

    /// Writes the collection database to a temporary file, because SQLite needs a real path.
    /// The caller owns the returned URL and must remove it.
    func extractCollectionDatabase() throws -> URL {
        guard let name = Self.collectionEntries.first(where: zip.contains) else {
            throw ApkgError.noCollection
        }

        let raw = try zip.data(for: name)
        let database = ZstdDecoder.isFrame(raw)
            ? try ZstdDecoder.decompress(raw, limit: limits.maxExpandedBytes, entry: name)
            : raw

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("apkg-\(UUID().uuidString).sqlite")
        try database.write(to: url, options: .atomic)
        return url
    }

    /// Media bytes are fetched one at a time, on demand: a deck can carry hundreds of
    /// megabytes and must never be resident all at once.
    public func mediaData(named filename: String) throws -> Data {
        guard let entry = mediaEntries[filename] else {
            throw ApkgError.missingEntry(name: filename)
        }
        let raw = try zip.data(for: entry)
        let bytes = ZstdDecoder.isFrame(raw)
            ? try ZstdDecoder.decompress(raw, limit: limits.maxMediaBytes, entry: filename)
            : raw

        guard bytes.count <= limits.maxMediaBytes else {
            throw ApkgError.expandedTooLarge(bytes: bytes.count, limit: limits.maxMediaBytes)
        }
        return bytes
    }

    /// Reads the whole collection. The database file is removed before returning, on every
    /// path including failure.
    public func readCollection() throws -> ApkgCollection {
        let url = try extractCollectionDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = try AnkiCollectionReader(databaseURL: url, limits: limits)
        defer { reader.close() }
        return try reader.read(mediaFilenames: mediaFilenames)
    }

    // MARK: - Media index

    /// Legacy stores the index as JSON; modern stores it as a zstd-compressed protobuf.
    /// Both are detected from the bytes rather than from `meta`, so a file that disagrees
    /// with its own version marker still reads correctly.
    private static func readMediaIndex(zip: ZipArchive, limits: ApkgLimits) throws -> [String: String] {
        guard zip.contains(mediaIndexEntry) else { return [:] }

        let raw = try zip.data(for: mediaIndexEntry)
        guard !raw.isEmpty else { return [:] }

        let payload = ZstdDecoder.isFrame(raw)
            ? try ZstdDecoder.decompress(raw, limit: limits.maxExpandedBytes, entry: mediaIndexEntry)
            : raw

        let index = payload.first == UInt8(ascii: "{")
            ? decodeJSONMediaIndex(payload)
            : decodeProtobufMediaIndex(payload)

        guard index.count <= limits.maxMediaCount else {
            throw ApkgError.expandedTooLarge(bytes: index.count, limit: limits.maxMediaCount)
        }
        return index
    }

    /// `{"0": "photo.jpg", "1": "sound.mp3"}` — the key is the ZIP entry name.
    private static func decodeJSONMediaIndex(_ data: Data) -> [String: String] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let mapping = object as? [String: String] else {
            return [:]
        }
        return mapping.reduce(into: [:]) { result, pair in
            result[pair.value] = pair.key
        }
    }

    /// `repeated MediaEntry entries = 1`, where `MediaEntry.name = 1`. An entry's position in
    /// the list is its ZIP entry name.
    private static func decodeProtobufMediaIndex(_ data: Data) -> [String: String] {
        var mapping: [String: String] = [:]
        for (index, entry) in ProtobufScanner.byteValues(1, in: data).enumerated() {
            guard let name = ProtobufScanner.stringValue(1, in: entry) else { continue }
            mapping[name] = String(index)
        }
        return mapping
    }
}
