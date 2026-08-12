import Foundation

/// Failures that reject a whole `.apkg`, mirroring `CSVParseError`'s role for CSV.
///
/// Every case names a structural fact about the file and never its content: card text must
/// not reach diagnostics or logs (`AGENTS.md`, spec §A2).
public enum ApkgError: Error, Equatable, Sendable {
    /// Not a ZIP at all, or its central directory is unreadable.
    case notAZipArchive
    /// ZIP64 records are not supported; the size caps make them unreachable for real decks.
    case unsupportedZipFormat
    /// A ZIP entry uses a compression method other than stored or deflate.
    case unsupportedCompression(method: UInt16)
    /// A named entry is missing or its bytes could not be recovered.
    case missingEntry(name: String)
    /// The archive contains no Anki collection database.
    case noCollection
    /// Decompression failed, or produced something other than the declared size.
    case corruptedData(entry: String)
    /// `col.ver` is a schema this reader does not understand.
    case unsupportedSchema(version: Int)
    /// SQLite refused the collection database.
    case databaseUnreadable
    case fileTooLarge(bytes: Int, limit: Int)
    /// A decompression would exceed the cap. Both deflate and zstd can expand enormously,
    /// so this is the zip-bomb defence, not a nicety (ADR-004 §8).
    case expandedTooLarge(bytes: Int, limit: Int)
    case tooManyNotes(notes: Int, limit: Int)
}

/// Hard caps for `.apkg` import (spec §A9.5), the twin of `CSVLimits`. Injectable so tests
/// can exercise each limit without building a huge file.
public struct ApkgLimits: Equatable, Sendable {
    /// Matches `CSVLimits.maxRows`: the same deck should not import differently by format.
    public let maxNotes: Int
    public let maxFileBytes: Int
    /// Applies to every decompression individually — the collection and each media blob.
    public let maxExpandedBytes: Int
    public let maxMediaCount: Int
    public let maxMediaBytes: Int

    public static let standard = ApkgLimits(
        maxNotes: 10_000,
        // The archive is read into memory, so this is a memory budget as much as a
        // file-size one. Real shared decks sit far below it.
        maxFileBytes: 200 * 1024 * 1024,
        maxExpandedBytes: 1024 * 1024 * 1024,
        maxMediaCount: 20_000,
        maxMediaBytes: 32 * 1024 * 1024
    )

    public init(
        maxNotes: Int,
        maxFileBytes: Int,
        maxExpandedBytes: Int,
        maxMediaCount: Int,
        maxMediaBytes: Int
    ) {
        self.maxNotes = maxNotes
        self.maxFileBytes = maxFileBytes
        self.maxExpandedBytes = maxExpandedBytes
        self.maxMediaCount = maxMediaCount
        self.maxMediaBytes = maxMediaBytes
    }
}
