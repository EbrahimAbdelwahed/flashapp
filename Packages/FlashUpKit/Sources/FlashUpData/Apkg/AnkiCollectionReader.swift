import Foundation
import SQLite3

/// Reads an Anki collection database.
///
/// Two schema generations must both work, discriminated on `col.ver` (ADR-004 §2):
///
/// - **schema 11** keeps note types and decks as JSON blobs in `col.models` / `col.decks`;
/// - **schema 18** keeps them in real `notetypes` / `fields` / `templates` / `decks` tables.
///
/// A legacy export produces the first, a modern one the second, and both are current in the
/// wild — the same deck exported twice by today's Anki gives one of each.
final class AnkiCollectionReader {
    /// The lowest and highest `col.ver` this reader understands. Anything outside is
    /// refused loudly rather than misread.
    private static let schemaJSON = 11
    private static let schemaTables = 18

    private var database: OpaquePointer?
    private let limits: ApkgLimits

    init(databaseURL: URL, limits: ApkgLimits) throws {
        self.limits = limits

        // `immutable=1` is not an optimisation, it is what makes this work at all: a
        // schema-18 collection is left in WAL mode, and opening one read-only without its
        // companion `-wal`/`-shm` files fails with SQLITE_CANTOPEN at the first prepare.
        // The flag promises the file cannot change, so SQLite reads the main database
        // directly — correct here, because the archive carries no separate WAL to lose.
        //
        // Read-only, and on our own extracted copy: the user's file is never touched.
        let uri = "\(databaseURL.absoluteString)?immutable=1"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &database, flags, nil) == SQLITE_OK, database != nil else {
            throw ApkgError.databaseUnreadable
        }
    }

    func close() {
        if let database { sqlite3_close(database) }
        database = nil
    }

    deinit { close() }

    func read(mediaFilenames: Set<String>) throws -> ApkgCollection {
        let version = try schemaVersion()
        let noteTypes: [ApkgNoteType]
        let deckNames: [Int64: String]

        switch version {
        case Self.schemaJSON:
            noteTypes = try readNoteTypesFromJSON()
            deckNames = try readDeckNamesFromJSON()
        case Self.schemaTables...:
            noteTypes = try readNoteTypesFromTables()
            deckNames = try readDeckNamesFromTables()
        default:
            throw ApkgError.unsupportedSchema(version: version)
        }

        let notes = try readNotes(deckNames: deckNames)
        return ApkgCollection(noteTypes: noteTypes, notes: notes, mediaFilenames: mediaFilenames)
    }

    // MARK: - Schema discrimination

    private func schemaVersion() throws -> Int {
        guard let value = try queryFirstRow("SELECT ver FROM col", column: { statement in
            Int(sqlite3_column_int64(statement, 0))
        }) else {
            throw ApkgError.databaseUnreadable
        }
        return value
    }

    // MARK: - Note types

    /// Schema 18: `notetypes` + `fields` + `templates`.
    private func readNoteTypesFromTables() throws -> [ApkgNoteType] {
        var fieldsByNoteType: [Int64: [String]] = [:]
        try forEachRow("SELECT ntid, name FROM fields ORDER BY ntid, ord") { statement in
            let id = sqlite3_column_int64(statement, 0)
            fieldsByNoteType[id, default: []].append(Self.text(statement, 1))
        }

        var templateCounts: [Int64: Int] = [:]
        try forEachRow("SELECT ntid, COUNT(*) FROM templates GROUP BY ntid") { statement in
            templateCounts[sqlite3_column_int64(statement, 0)] = Int(sqlite3_column_int64(statement, 1))
        }

        var noteTypes: [ApkgNoteType] = []
        try forEachRow("SELECT id, name, config FROM notetypes ORDER BY id") { statement in
            let id = sqlite3_column_int64(statement, 0)
            // The kind lives inside the protobuf `config` blob: field 1, varint, 1 = cloze.
            let config = Self.blob(statement, 2)
            let isCloze = ProtobufScanner.varintValue(1, in: config) == 1
            noteTypes.append(
                ApkgNoteType(
                    id: id,
                    name: Self.text(statement, 1),
                    fieldNames: fieldsByNoteType[id] ?? [],
                    isCloze: isCloze,
                    templateCount: templateCounts[id] ?? 1
                )
            )
        }
        return noteTypes
    }

    /// Schema 11: one JSON object in `col.models`, keyed by note type id.
    private func readNoteTypesFromJSON() throws -> [ApkgNoteType] {
        guard let raw = try queryFirstRow("SELECT models FROM col", column: { Self.text($0, 0) }),
              let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)),
              let models = object as? [String: Any] else {
            return []
        }

        return models.compactMap { key, value -> ApkgNoteType? in
            guard let model = value as? [String: Any], let id = Int64(key) else { return nil }
            let rawFields = model["flds"] as? [[String: Any]] ?? []
            let fieldNames = rawFields
                .sorted { ($0["ord"] as? Int ?? 0) < ($1["ord"] as? Int ?? 0) }
                .compactMap { $0["name"] as? String }
            return ApkgNoteType(
                id: id,
                name: model["name"] as? String ?? "",
                fieldNames: fieldNames,
                isCloze: (model["type"] as? Int) == 1,
                templateCount: (model["tmpls"] as? [Any])?.count ?? 1
            )
        }
        .sorted { $0.id < $1.id }
    }

    // MARK: - Decks

    private func readDeckNamesFromTables() throws -> [Int64: String] {
        var names: [Int64: String] = [:]
        try forEachRow("SELECT id, name FROM decks") { statement in
            names[sqlite3_column_int64(statement, 0)] = Self.deckName(Self.text(statement, 1))
        }
        return names
    }

    private func readDeckNamesFromJSON() throws -> [Int64: String] {
        guard let raw = try queryFirstRow("SELECT decks FROM col", column: { Self.text($0, 0) }),
              let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)),
              let decks = object as? [String: Any] else {
            return [:]
        }

        return decks.reduce(into: [:]) { result, pair in
            guard let id = Int64(pair.key),
                  let deck = pair.value as? [String: Any],
                  let name = deck["name"] as? String else { return }
            result[id] = Self.deckName(name)
        }
    }

    /// Schema 18 separates nested deck components with `0x1F`; schema 11 uses `::`.
    /// Flash Up has no nested decks, so the full path becomes the name.
    private static func deckName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{1F}", with: "::")
    }

    // MARK: - Notes

    private func readNotes(deckNames: [Int64: String]) throws -> [ApkgNote] {
        var deckByNote: [Int64: Int64] = [:]
        try forEachRow("SELECT nid, did FROM cards ORDER BY nid, ord") { statement in
            let noteID = sqlite3_column_int64(statement, 0)
            // First card wins: a reversed note's two cards live in the same deck anyway.
            if deckByNote[noteID] == nil {
                deckByNote[noteID] = sqlite3_column_int64(statement, 1)
            }
        }

        var notes: [ApkgNote] = []
        try forEachRow("SELECT id, mid, tags, flds FROM notes ORDER BY id") { statement in
            let noteID = sqlite3_column_int64(statement, 0)
            let deckID = deckByNote[noteID]
            notes.append(
                ApkgNote(
                    noteTypeID: sqlite3_column_int64(statement, 1),
                    deckName: deckID.flatMap { deckNames[$0] },
                    // Fields are concatenated with the unit separator, never escaped.
                    fields: Self.text(statement, 3).components(separatedBy: "\u{1F}"),
                    // Tags are space-separated and padded with a leading and trailing space.
                    tags: Self.text(statement, 2)
                        .split(whereSeparator: \.isWhitespace)
                        .map(String.init)
                )
            )
        }

        guard notes.count <= limits.maxNotes else {
            throw ApkgError.tooManyNotes(notes: notes.count, limit: limits.maxNotes)
        }
        return notes
    }

    // MARK: - SQLite plumbing

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: pointer)
    }

    private static func blob(_ statement: OpaquePointer?, _ column: Int32) -> Data {
        let length = Int(sqlite3_column_bytes(statement, column))
        guard length > 0, let pointer = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: pointer, count: length)
    }

    /// All queries are literal strings with no interpolation — there is no user input in
    /// any of them, and there never should be.
    private func forEachRow(_ sql: String, body: (OpaquePointer?) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ApkgError.databaseUnreadable
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            body(statement)
        }
    }

    private func queryFirstRow<T>(_ sql: String, column: (OpaquePointer?) -> T) throws -> T? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ApkgError.databaseUnreadable
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return column(statement)
    }
}
