import Foundation

/// A row that duplicates a note already in the destination deck (spec §A3.5, §A9.2).
public struct DuplicateRow: Equatable, Sendable {
    public let row: ParsedRow
    public let matchedNoteID: UUID
    /// Duplicates are skipped by default; the preview lets the user import one anyway.
    public var isSelected: Bool

    public init(row: ParsedRow, matchedNoteID: UUID, isSelected: Bool = false) {
        self.row = row
        self.matchedNoteID = matchedNoteID
        self.isSelected = isSelected
    }
}

/// What the import preview shows and the committer acts on.
public struct ImportPlan: Equatable, Sendable {
    public var valid: [ParsedRow]
    public var duplicates: [DuplicateRow]
    public var rejected: [RowRejection]
    public var ignoredColumns: [String]

    public init(
        valid: [ParsedRow] = [],
        duplicates: [DuplicateRow] = [],
        rejected: [RowRejection] = [],
        ignoredColumns: [String] = []
    ) {
        self.valid = valid
        self.duplicates = duplicates
        self.rejected = rejected
        self.ignoredColumns = ignoredColumns
    }

    /// Rows that will actually be created: the clean ones plus any duplicate the user
    /// explicitly kept.
    public var rowsToImport: [ParsedRow] {
        valid + duplicates.filter(\.isSelected).map(\.row)
    }

    public var isEmpty: Bool { rowsToImport.isEmpty }

    /// Swaps provisional attachment ids for the ids the media store assigned.
    ///
    /// Applied between storing the blobs and creating the notes: the store deduplicates by
    /// content, so an attachment already on disk comes back with the id it already had,
    /// not the one the mapper guessed (ADR-004 §6).
    public func replacingMediaIDs(_ replacements: [UUID: UUID]) -> ImportPlan {
        guard !replacements.isEmpty else { return self }
        return ImportPlan(
            valid: valid.map { $0.replacingMediaIDs(replacements) },
            duplicates: duplicates.map {
                DuplicateRow(
                    row: $0.row.replacingMediaIDs(replacements),
                    matchedNoteID: $0.matchedNoteID,
                    isSelected: $0.isSelected
                )
            },
            rejected: rejected,
            ignoredColumns: ignoredColumns
        )
    }
}

/// Marks duplicates against the destination deck (spec §A9.2 step 2).
public enum ImportPlanner {
    /// - Parameter existingHashes: content fingerprints of the destination deck's
    ///   non-trashed notes, keyed by note id. Comparing only against the destination is
    ///   deliberate: the same fact may legitimately live in two different decks.
    public static func plan(
        _ outcome: CSVParseOutcome,
        existingHashes: [UUID: String]
    ) -> ImportPlan {
        var byHash: [String: UUID] = [:]
        for (noteID, hash) in existingHashes where byHash[hash] == nil {
            byHash[hash] = noteID
        }

        var valid: [ParsedRow] = []
        var duplicates: [DuplicateRow] = []
        // A file that repeats a row internally must not import it twice either.
        var seenInFile: [String: UUID] = [:]

        for row in outcome.rows {
            let hash = ContentFingerprint.hash(type: row.type, front: row.front, back: row.back)
            if let matched = byHash[hash] ?? seenInFile[hash] {
                duplicates.append(DuplicateRow(row: row, matchedNoteID: matched))
            } else {
                valid.append(row)
                seenInFile[hash] = UUID()
            }
        }

        return ImportPlan(
            valid: valid,
            duplicates: duplicates,
            rejected: outcome.rejected,
            ignoredColumns: outcome.ignoredColumns
        )
    }
}
