import Foundation

/// One Anki note, reduced to what the mapper needs. Built by the caller from the `.apkg`
/// reader, so `FlashUpDomain` never sees the archive itself.
public struct SourceNote: Equatable, Sendable {
    public let noteTypeID: Int64
    /// Raw HTML fields, in note-type field order.
    public let fields: [String]
    public let tags: [String]

    public init(noteTypeID: Int64, fields: [String], tags: [String]) {
        self.noteTypeID = noteTypeID
        self.fields = fields
        self.tags = tags
    }
}

/// Applies the user's field mappings to Anki notes and produces exactly what `CSVParser`
/// produces.
///
/// That convergence is the point (ADR-004 §5): `ImportPlanner`, duplicate detection,
/// `commitImport` and undo are shared verbatim with the CSV importer, so the `.apkg` path
/// inherits the two behaviours where a bug would destroy user data instead of reimplementing
/// them.
public enum ApkgRowMapper {
    /// A row either maps or is refused. Deliberately not `Result`: `RowRejection` is a piece
    /// of preview data shared with the CSV importer, not an error, and it should not be made
    /// to conform to `Error` just to fit a generic here.
    private enum Mapped {
        case row(ParsedRow)
        case rejected(RowRejection)
    }

    public static func map(
        notes: [SourceNote],
        mappings: [FieldMapping],
        media: MediaPlan = MediaPlan(),
        limits: CSVLimits = .standard
    ) -> CSVParseOutcome {
        let byNoteType = Dictionary(uniqueKeysWithValues: mappings.map { ($0.noteTypeID, $0) })

        var rows: [ParsedRow] = []
        var rejected: [RowRejection] = []

        for (offset, note) in notes.enumerated() {
            // 1-based, and the preview labels it "note N" rather than "row N" for `.apkg`.
            let line = offset + 1
            guard let mapping = byNoteType[note.noteTypeID], mapping.isEnabled else { continue }

            switch row(for: note, mapping: mapping, line: line, media: media, limits: limits) {
            case let .row(row): rows.append(row)
            case let .rejected(rejection): rejected.append(rejection)
            }
        }

        return CSVParseOutcome(
            rows: rows,
            rejected: rejected,
            ignoredColumns: ignoredFieldNames(mappings: mappings, notes: notes)
        )
    }

    /// Field names no enabled mapping uses. Reported through the same preview notice the CSV
    /// importer shows for extra columns, so "the Source field was ignored" needs no new UI.
    private static func ignoredFieldNames(mappings: [FieldMapping], notes: [SourceNote]) -> [String] {
        let used = Set(notes.map(\.noteTypeID))
        var seen: Set<String> = []
        var ordered: [String] = []

        for mapping in mappings where mapping.isEnabled && used.contains(mapping.noteTypeID) {
            for name in mapping.ignoredFieldNames where !name.isEmpty && !seen.contains(name) {
                seen.insert(name)
                ordered.append(name)
            }
        }
        return ordered
    }

    // MARK: - One note

    private static func row(
        for note: SourceNote,
        mapping: FieldMapping,
        line: Int,
        media: MediaPlan,
        limits: CSVLimits
    ) -> Mapped {
        let front = HTMLTextExtractor.extract(field(note, at: mapping.frontIndex))
        let back = mapping.backIndex.map { HTMLTextExtractor.extract(field(note, at: $0)) }

        // An attachment Flash Up cannot carry — video, or a file the archive does not
        // actually contain — refuses the row with a visible reason rather than importing a
        // card with a hole where the picture should be.
        let referenced = front.mediaFilenames + (back?.mediaFilenames ?? [])
        if let unsupported = referenced.first(where: { media.id(for: $0) == nil }) {
            return .rejected(RowRejection(line: line, reason: .unsupportedMedia(unsupported), raw: ""))
        }

        if let rejection = lengthRejection(front: front.text, back: back?.text, line: line, limits: limits) {
            return .rejected(rejection)
        }

        // The text must be non-empty *before* attachments are appended: a card that is only
        // a picture has nothing to ask, and would be unanswerable.
        let frontText = front.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !frontText.isEmpty else {
            return .rejected(RowRejection(line: line, reason: .emptyFront, raw: ""))
        }

        let backText = back?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBack = (backText?.isEmpty ?? true) ? nil : backText

        // Same validation rules as A9.1, so a deck behaves identically whichever format it
        // arrived in.
        if mapping.target.requiresBack, resolvedBack == nil {
            return .rejected(RowRejection(line: line, reason: .missingBack(mapping.target), raw: frontText))
        }
        if mapping.target == .cloze, !ClozeParser.hasValidDeletion(frontText) {
            return .rejected(RowRejection(line: line, reason: .noClozeDeletion, raw: frontText))
        }

        let frontIDs = attach(front.imageFilenames, front.audioFilenames, using: media)
        let backIDs = attach(back?.imageFilenames ?? [], back?.audioFilenames ?? [], using: media)

        return .row(
            ParsedRow(
                line: line,
                type: mapping.target,
                front: frontText + markup(for: frontIDs, media: media),
                back: resolvedBack.map { $0 + markup(for: backIDs, media: media) }
                    ?? (backIDs.isEmpty ? nil : markup(for: backIDs, media: media)),
                tags: note.tags,
                mediaIDs: frontIDs + backIDs
            )
        )
    }

    /// Provisional ids, in the order the attachments appeared. They become real ids once the
    /// bytes are stored (`MediaPlan.rewrite`).
    private static func attach(
        _ images: [String],
        _ audio: [String],
        using media: MediaPlan
    ) -> [UUID] {
        (images + audio).compactMap { media.id(for: $0) }
    }

    private static func markup(for ids: [UUID], media: MediaPlan) -> String {
        guard !ids.isEmpty else { return "" }
        let references = ids.map { id -> String in
            // The kind decides the syntax, and it is known from the filename.
            let filename = media.filenames(for: [id]).first ?? ""
            let kind = media.kind(for: filename) ?? .image
            return MediaReference.markup(
                for: MediaAsset(id: id, kind: kind, filename: filename, sha256: "", byteCount: 0)
            )
        }
        return "\n" + references.joined(separator: "\n")
    }

    private static func field(_ note: SourceNote, at index: Int) -> String {
        note.fields.indices.contains(index) ? note.fields[index] : ""
    }

    private static func lengthRejection(
        front: String,
        back: String?,
        line: Int,
        limits: CSVLimits
    ) -> RowRejection? {
        if front.count > limits.maxFieldCharacters {
            return RowRejection(
                line: line,
                reason: .fieldTooLong(column: "front", characters: front.count),
                raw: ""
            )
        }
        if let back, back.count > limits.maxFieldCharacters {
            return RowRejection(
                line: line,
                reason: .fieldTooLong(column: "back", characters: back.count),
                raw: ""
            )
        }
        return nil
    }
}
