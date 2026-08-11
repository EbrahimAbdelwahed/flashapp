import Compression
import Foundation

/// A minimal read-only ZIP reader: exactly the two compression methods an `.apkg` uses
/// (stored and deflate) and nothing else.
///
/// Hand-written rather than taken from a package because the alternative carries writing,
/// encryption and format variants we will never use, and this is ~150 lines (ADR-004 §3).
/// Deflate goes through Apple's `Compression`, whose `COMPRESSION_ZLIB` is raw deflate —
/// exactly the ZIP payload format.
struct ZipArchive {
    struct Entry: Equatable {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        /// Offset of the *local* header, which is where the payload actually lives. The
        /// central directory's copy of the sizes is the one to trust.
        let localHeaderOffset: Int
    }

    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4B50
    private static let centralFileHeaderSignature: UInt32 = 0x0201_4B50
    private static let localFileHeaderSignature: UInt32 = 0x0403_4B50
    private static let zip64LocatorSignature: UInt32 = 0x0706_4B50
    private static let methodStored: UInt16 = 0
    private static let methodDeflate: UInt16 = 8
    /// The end-of-central-directory record is followed by a comment of up to 65 535 bytes.
    private static let maxCommentLength = 65_535

    private let reader: ByteReader
    private let limits: ApkgLimits
    let entries: [String: Entry]

    init(data: Data, limits: ApkgLimits = .standard) throws {
        guard data.count <= limits.maxFileBytes else {
            throw ApkgError.fileTooLarge(bytes: data.count, limit: limits.maxFileBytes)
        }
        self.limits = limits
        reader = ByteReader(data)
        entries = try Self.readCentralDirectory(reader)
    }

    var entryNames: [String] { Array(entries.keys) }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    /// Decompresses one entry. Every entry is read on demand: a deck with 200 MB of media
    /// must never be resident all at once.
    func data(for name: String) throws -> Data {
        guard let entry = entries[name] else { throw ApkgError.missingEntry(name: name) }
        return try data(for: entry)
    }

    func data(for entry: Entry) throws -> Data {
        guard entry.uncompressedSize <= limits.maxExpandedBytes else {
            throw ApkgError.expandedTooLarge(bytes: entry.uncompressedSize, limit: limits.maxExpandedBytes)
        }

        // The local header repeats the name and extra fields, at its own lengths: the
        // central directory's extra-field length does not apply here.
        guard reader.uint32(at: entry.localHeaderOffset) == Self.localFileHeaderSignature,
              let nameLength = reader.uint16(at: entry.localHeaderOffset + 26),
              let extraLength = reader.uint16(at: entry.localHeaderOffset + 28) else {
            throw ApkgError.corruptedData(entry: entry.name)
        }

        let payloadOffset = entry.localHeaderOffset + 30 + Int(nameLength) + Int(extraLength)
        guard let payload = reader.slice(at: payloadOffset, count: entry.compressedSize) else {
            throw ApkgError.corruptedData(entry: entry.name)
        }

        switch entry.method {
        case Self.methodStored:
            return payload
        case Self.methodDeflate:
            return try Self.inflate(payload, expectedSize: entry.uncompressedSize, entry: entry.name)
        default:
            throw ApkgError.unsupportedCompression(method: entry.method)
        }
    }

    // MARK: - Central directory

    private static func readCentralDirectory(_ reader: ByteReader) throws -> [String: Entry] {
        let searchFloor = reader.count - maxCommentLength - 22
        guard let eocd = reader.lastIndex(of: endOfCentralDirectorySignature, notBefore: searchFloor) else {
            throw ApkgError.notAZipArchive
        }

        // A ZIP64 locator immediately precedes the EOCD when the archive needs 64-bit
        // offsets. Refusing it outright beats mis-reading a truncated 32-bit view.
        if eocd >= 20, reader.uint32(at: eocd - 20) == zip64LocatorSignature {
            throw ApkgError.unsupportedZipFormat
        }

        guard let entryCount = reader.uint16(at: eocd + 10),
              let directoryOffset = reader.uint32(at: eocd + 16) else {
            throw ApkgError.notAZipArchive
        }
        guard directoryOffset != UInt32.max else { throw ApkgError.unsupportedZipFormat }

        var entries: [String: Entry] = [:]
        var offset = Int(directoryOffset)

        for _ in 0 ..< Int(entryCount) {
            guard reader.uint32(at: offset) == centralFileHeaderSignature,
                  let method = reader.uint16(at: offset + 10),
                  let compressedSize = reader.uint32(at: offset + 20),
                  let uncompressedSize = reader.uint32(at: offset + 24),
                  let nameLength = reader.uint16(at: offset + 28),
                  let extraLength = reader.uint16(at: offset + 30),
                  let commentLength = reader.uint16(at: offset + 32),
                  let localOffset = reader.uint32(at: offset + 42),
                  let nameData = reader.slice(at: offset + 46, count: Int(nameLength)) else {
                throw ApkgError.notAZipArchive
            }
            guard compressedSize != UInt32.max, uncompressedSize != UInt32.max,
                  localOffset != UInt32.max else {
                throw ApkgError.unsupportedZipFormat
            }

            // Entry names in an .apkg are ASCII ("collection.anki21b", "media", "0", "1"…),
            // but a hostile file can put anything here, so decoding must be allowed to fail.
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw ApkgError.notAZipArchive
            }
            entries[name] = Entry(
                name: name,
                method: method,
                compressedSize: Int(compressedSize),
                uncompressedSize: Int(uncompressedSize),
                localHeaderOffset: Int(localOffset)
            )
            offset += 46 + Int(nameLength) + Int(extraLength) + Int(commentLength)
        }

        return entries
    }

    // MARK: - Deflate

    private static func inflate(_ payload: Data, expectedSize: Int, entry: String) throws -> Data {
        guard expectedSize > 0 else { return Data() }

        var destination = Data(count: expectedSize)
        let written: Int = destination.withUnsafeMutableBytes { destinationBuffer in
            payload.withUnsafeBytes { sourceBuffer in
                guard let destinationBase = destinationBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let sourceBase = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                    return 0
                }
                return compression_decode_buffer(
                    destinationBase, expectedSize,
                    sourceBase, payload.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }

        // A short read means the entry lied about its size or the stream is damaged. Either
        // way the bytes cannot be trusted, so this is a failure rather than a partial result.
        guard written == expectedSize else { throw ApkgError.corruptedData(entry: entry) }
        return destination
    }
}
