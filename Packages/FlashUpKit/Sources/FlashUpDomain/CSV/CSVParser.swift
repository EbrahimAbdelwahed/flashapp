import Foundation

/// Parses the canonical Flash Up CSV (spec §A9.1) into rows the import planner can use.
///
/// File-level problems (encoding, size, row count, missing columns) throw and reject the
/// whole file. Row-level problems reject that row only, so one bad line never costs the
/// user the rest of the import.
public enum CSVParser {
    private static let typeColumn = "type"
    private static let frontColumn = "front"
    private static let backColumn = "back"
    private static let tagsColumn = "tags"
    private static let tagSeparator: Character = ";"

    /// Columns without which the file cannot be interpreted at all.
    ///
    /// `back` and `tags` are deliberately optional: row validation already requires a
    /// non-empty `back` for basic and reversed rows, and a cloze-only export legitimately
    /// carries neither column. Recorded as an interpretation in `docs/decisions/worklog.md`.
    static let requiredColumns = [typeColumn, frontColumn]

    public static func parse(_ data: Data, limits: CSVLimits = .standard) throws -> CSVParseOutcome {
        guard data.count <= limits.maxBytes else {
            throw CSVParseError.fileTooLarge(bytes: data.count, limit: limits.maxBytes)
        }
        guard let text = decodeUTF8(data) else {
            throw CSVParseError.notUTF8
        }
        return try parse(text: text, limits: limits)
    }

    static func parse(text: String, limits: CSVLimits = .standard) throws -> CSVParseOutcome {
        let records = CSVDocument.records(in: text).filter { !isBlank($0) }
        guard let header = records.first else {
            throw CSVParseError.missingHeader
        }

        let columns = header.fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let missing = requiredColumns.filter { !columns.contains($0) }
        guard missing.isEmpty else {
            throw CSVParseError.missingColumns(missing: missing, found: columns)
        }

        let body = records.dropFirst()
        guard body.count <= limits.maxRows else {
            throw CSVParseError.tooManyRows(rows: body.count, limit: limits.maxRows)
        }

        let index = ColumnIndex(columns: columns)
        var rows: [ParsedRow] = []
        var rejected: [RowRejection] = []

        for record in body {
            switch validate(record, index: index, limits: limits) {
            case let .success(row): rows.append(row)
            case let .failure(rejection): rejected.append(rejection)
            }
        }

        return CSVParseOutcome(rows: rows, rejected: rejected, ignoredColumns: index.ignored)
    }

    // MARK: - Row validation

    private enum RowOutcome {
        case success(ParsedRow)
        case failure(RowRejection)
    }

    private static func validate(
        _ record: CSVDocument.Record,
        index: ColumnIndex,
        limits: CSVLimits
    ) -> RowOutcome {
        let raw = record.fields.joined(separator: ",")

        func reject(_ reason: RowRejection.Reason) -> RowOutcome {
            .failure(RowRejection(line: record.line, reason: reason, raw: raw))
        }

        // Over-long fields are caught before anything reads them.
        for (column, value) in index.namedValues(in: record.fields) where value.count > limits.maxFieldCharacters {
            return reject(.fieldTooLong(column: column, characters: value.count))
        }

        let rawType = index.value(of: typeColumn, in: record.fields)
        guard let type = NoteType(csvValue: rawType) else {
            return reject(.unknownType(rawType.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        let front = index.value(of: frontColumn, in: record.fields).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !front.isEmpty else {
            return reject(.emptyFront)
        }

        let rawBack = index.value(of: backColumn, in: record.fields).trimmingCharacters(in: .whitespacesAndNewlines)
        let back = rawBack.isEmpty ? nil : rawBack
        if type.requiresBack, back == nil {
            return reject(.missingBack(type))
        }

        if type == .cloze, !ClozeParser.hasValidDeletion(front) {
            return reject(.noClozeDeletion)
        }

        return .success(
            ParsedRow(
                line: record.line,
                type: type,
                front: front,
                back: back,
                tags: tags(from: index.value(of: tagsColumn, in: record.fields))
            )
        )
    }

    private static func tags(from value: String) -> [String] {
        value
            .split(separator: tagSeparator, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Helpers

    /// Strips a UTF-8 BOM and rejects anything that is not valid UTF-8.
    private static func decodeUTF8(_ data: Data) -> String? {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let payload = data.starts(with: bom) ? data.dropFirst(bom.count) : data
        return String(data: payload, encoding: .utf8)
    }

    private static func isBlank(_ record: CSVDocument.Record) -> Bool {
        record.fields.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// Maps canonical column names to positions, case-insensitively, and remembers which
    /// header columns are not part of the canonical set.
    private struct ColumnIndex {
        private let positions: [String: Int]
        let ignored: [String]

        init(columns: [String]) {
            let canonical = [typeColumn, frontColumn, backColumn, tagsColumn]
            var positions: [String: Int] = [:]
            for (offset, name) in columns.enumerated() where canonical.contains(name) {
                // A duplicated column keeps its first occurrence.
                if positions[name] == nil { positions[name] = offset }
            }
            self.positions = positions
            self.ignored = columns.filter { !canonical.contains($0) }
        }

        /// Empty string when the column is absent or the row is short — both mean
        /// "no value", and row validation decides whether that is acceptable.
        func value(of column: String, in fields: [String]) -> String {
            guard let offset = positions[column], offset < fields.count else { return "" }
            return fields[offset]
        }

        func namedValues(in fields: [String]) -> [(String, String)] {
            positions
                .sorted { $0.value < $1.value }
                .compactMap { name, offset in
                    offset < fields.count ? (name, fields[offset]) : nil
                }
        }
    }
}
