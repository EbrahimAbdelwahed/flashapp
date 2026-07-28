import Foundation

/// Hard caps from spec §A9.1. Injectable so tests can exercise the limits cheaply.
public struct CSVLimits: Equatable, Sendable {
    public let maxRows: Int
    public let maxBytes: Int
    public let maxFieldCharacters: Int

    public static let standard = CSVLimits(maxRows: 10_000, maxBytes: 2 * 1024 * 1024, maxFieldCharacters: 20_000)

    public init(maxRows: Int, maxBytes: Int, maxFieldCharacters: Int) {
        self.maxRows = maxRows
        self.maxBytes = maxBytes
        self.maxFieldCharacters = maxFieldCharacters
    }
}

/// A row that passed validation and is ready for the import planner.
public struct ParsedRow: Equatable, Sendable {
    /// 1-based line number in the source file, header included, for the preview UI.
    public let line: Int
    public let type: NoteType
    public let front: String
    /// Always non-empty when present; `nil` for a cloze row that carried no back.
    public let back: String?
    public let tags: [String]

    public init(line: Int, type: NoteType, front: String, back: String?, tags: [String]) {
        self.line = line
        self.type = type
        self.front = front
        self.back = back
        self.tags = tags
    }
}

/// A row the parser refused, with the reason shown in the import preview.
public struct RowRejection: Equatable, Sendable {
    public enum Reason: Equatable, Sendable {
        /// `type` was not basic, reversed or cloze.
        case unknownType(String)
        /// `front` was empty after trimming.
        case emptyFront
        /// `back` was empty on a basic or reversed row.
        case missingBack(NoteType)
        /// A cloze row whose front carries no well-formed `{{cN::…}}` deletion.
        case noClozeDeletion
        /// A single field exceeded `CSVLimits.maxFieldCharacters`.
        case fieldTooLong(column: String, characters: Int)
    }

    public let line: Int
    public let reason: Reason
    /// The raw row, kept for the on-device preview only. Spec §A2 forbids it from ever
    /// reaching diagnostics or logs.
    public let raw: String

    public init(line: Int, reason: Reason, raw: String) {
        self.line = line
        self.reason = reason
        self.raw = raw
    }
}

/// Failures that reject the whole file rather than a row.
public enum CSVParseError: Error, Equatable, Sendable {
    case notUTF8
    case fileTooLarge(bytes: Int, limit: Int)
    case tooManyRows(rows: Int, limit: Int)
    case missingHeader
    /// Required columns absent. `found` lists what the header did contain, so the message
    /// can tell the user what to fix.
    case missingColumns(missing: [String], found: [String])
}

/// Everything one parse produced.
public struct CSVParseOutcome: Equatable, Sendable {
    public let rows: [ParsedRow]
    public let rejected: [RowRejection]
    /// Header columns that are not part of the canonical set; ignored, but surfaced as a
    /// preview notice (spec §A9.1).
    public let ignoredColumns: [String]

    public init(rows: [ParsedRow], rejected: [RowRejection], ignoredColumns: [String]) {
        self.rows = rows
        self.rejected = rejected
        self.ignoredColumns = ignoredColumns
    }
}
