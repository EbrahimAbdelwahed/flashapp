import Foundation
import Testing
@testable import FlashUpDomain

/// Bead fu-04a (source B4.1): RFC 4180 dialect plus the row rules of spec §A9.1.
@Suite("CSV parser")
struct CSVParserTests {
    private let header = "type,front,back,tags\n"

    private func parse(_ body: String, limits: CSVLimits = .standard) throws -> CSVParseOutcome {
        try CSVParser.parse(text: header + body, limits: limits)
    }

    // MARK: - Dialect

    @Test("A minimal file parses into one row")
    func minimalFile() throws {
        let outcome = try parse("basic,Ciao,Hello,saluti\n")

        #expect(outcome.rejected.isEmpty)
        #expect(outcome.rows.count == 1)
        #expect(outcome.rows.first?.type == .basic)
        #expect(outcome.rows.first?.front == "Ciao")
        #expect(outcome.rows.first?.back == "Hello")
        #expect(outcome.rows.first?.tags == ["saluti"])
        #expect(outcome.rows.first?.line == 2)
    }

    @Test("Quoted fields keep their commas")
    func quotedCommas() throws {
        let outcome = try parse("basic,\"uno, due\",tre,\n")

        #expect(outcome.rows.first?.front == "uno, due")
    }

    @Test("Doubled quotes decode to a single quote")
    func escapedQuotes() throws {
        let outcome = try parse("basic,\"dice \"\"ciao\"\"\",hello,\n")

        #expect(outcome.rows.first?.front == "dice \"ciao\"")
    }

    @Test("A newline inside a quoted field stays in the value")
    func newlineInsideQuotes() throws {
        let outcome = try parse("basic,\"riga uno\nriga due\",back,\n")

        #expect(outcome.rows.count == 1)
        #expect(outcome.rows.first?.front == "riga uno\nriga due")
    }

    @Test("A row after a quoted newline reports its real physical line")
    func lineNumbersSurviveQuotedNewlines() throws {
        let outcome = try parse("basic,\"a\nb\",back,\nbasic,secondo,back,\n")

        #expect(outcome.rows.count == 2)
        #expect(outcome.rows.first?.line == 2)
        #expect(outcome.rows.last?.line == 4)
    }

    @Test("CRLF and LF line endings are both accepted")
    func lineEndings() throws {
        let windows = try CSVParser.parse(text: "type,front,back,tags\r\nbasic,Ciao,Hello,\r\n")
        let unix = try parse("basic,Ciao,Hello,\n")

        #expect(windows.rows.count == 1)
        #expect(windows.rows.first?.front == unix.rows.first?.front)
    }

    @Test("A file that does not end with a newline keeps its last row")
    func missingTrailingNewline() throws {
        let outcome = try parse("basic,Ciao,Hello,")

        #expect(outcome.rows.count == 1)
    }

    @Test("Blank lines are skipped rather than rejected")
    func blankLinesAreSkipped() throws {
        let outcome = try parse("basic,Ciao,Hello,\n\nbasic,Ciao2,Hello2,\n")

        #expect(outcome.rows.count == 2)
        #expect(outcome.rejected.isEmpty)
    }

    // MARK: - Encoding

    @Test("A UTF-8 BOM is stripped instead of corrupting the first column name")
    func bomIsStripped() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: Array((header + "basic,Ciao,Hello,\n").utf8))

        let outcome = try CSVParser.parse(data)

        #expect(outcome.rows.count == 1)
    }

    @Test("A non-UTF-8 file is rejected as a whole")
    func nonUTF8IsRejected() {
        let latin1 = Data([0x74, 0x79, 0x70, 0x65, 0x0A, 0xFF, 0xFE, 0x41])

        #expect(throws: CSVParseError.notUTF8) {
            _ = try CSVParser.parse(latin1)
        }
    }

    // MARK: - Header

    @Test("Column names match case-insensitively and ignore surrounding spaces")
    func headerIsCaseInsensitive() throws {
        let outcome = try CSVParser.parse(text: " TYPE , Front ,BACK,Tags\nbasic,Ciao,Hello,\n")

        #expect(outcome.rows.first?.front == "Ciao")
    }

    @Test("Extra columns are ignored and reported")
    func extraColumnsAreReported() throws {
        let outcome = try CSVParser.parse(text: "type,front,back,tags,note\nbasic,Ciao,Hello,,x\n")

        #expect(outcome.rows.count == 1)
        #expect(outcome.ignoredColumns == ["note"])
    }

    @Test("A missing required column fails the whole file and lists what was found")
    func missingRequiredColumnFailsTheFile() {
        #expect(throws: CSVParseError.missingColumns(missing: ["front"], found: ["type", "back", "tags"])) {
            _ = try CSVParser.parse(text: "type,back,tags\nbasic,Hello,\n")
        }
    }

    @Test("back and tags are optional columns, so a cloze-only file imports")
    func optionalColumnsMayBeAbsent() throws {
        let outcome = try CSVParser.parse(text: "type,front\ncloze,Il cuore ha {{c1::quattro}} camere.\n")

        #expect(outcome.rows.count == 1)
        #expect(outcome.rows.first?.back == nil)
        #expect(outcome.rows.first?.tags.isEmpty == true)
    }

    @Test("An empty file is rejected")
    func emptyFileIsRejected() {
        #expect(throws: CSVParseError.missingHeader) {
            _ = try CSVParser.parse(text: "")
        }
    }

    // MARK: - Row validation

    @Test("An unknown type rejects only its own row")
    func unknownTypeRejectsOneRow() throws {
        let outcome = try parse("sconosciuto,Ciao,Hello,\nbasic,Ciao,Hello,\n")

        #expect(outcome.rows.count == 1)
        #expect(outcome.rejected.count == 1)
        #expect(outcome.rejected.first?.reason == .unknownType("sconosciuto"))
        #expect(outcome.rejected.first?.line == 2)
    }

    @Test("Type matching is case-insensitive")
    func typeIsCaseInsensitive() throws {
        let outcome = try parse("BASIC,Ciao,Hello,\nReversed,Ciao,Hello,\n")

        #expect(outcome.rows.map(\.type) == [.basic, .reversed])
    }

    @Test("An empty front is rejected")
    func emptyFrontIsRejected() throws {
        let outcome = try parse("basic,   ,Hello,\n")

        #expect(outcome.rejected.first?.reason == .emptyFront)
    }

    @Test("basic and reversed rows require a back")
    func backIsRequiredForBasicAndReversed() throws {
        let outcome = try parse("basic,Ciao,,\nreversed,Ciao,,\n")

        #expect(outcome.rows.isEmpty)
        #expect(outcome.rejected.map(\.reason) == [.missingBack(.basic), .missingBack(.reversed)])
    }

    @Test("A cloze row needs at least one valid deletion")
    func clozeRowNeedsADeletion() throws {
        let outcome = try parse("cloze,Nessuna cancellazione,,\n")

        #expect(outcome.rejected.first?.reason == .noClozeDeletion)
    }

    @Test("A malformed cloze deletion does not count as valid")
    func malformedClozeIsRejected() throws {
        let outcome = try parse("cloze,{{c0::x}},,\n")

        #expect(outcome.rejected.first?.reason == .noClozeDeletion)
    }

    @Test("A cloze row keeps an optional back when one is present")
    func clozeMayCarryABack() throws {
        let outcome = try parse("cloze,{{c1::Roma}} è la capitale,nota,\n")

        #expect(outcome.rows.first?.back == "nota")
    }

    @Test("Tags split on semicolons, trim, and drop empties")
    func tagsAreNormalized() throws {
        let outcome = try parse("basic,Ciao,Hello,\" anatomia ; ;cuore \"\n")

        #expect(outcome.rows.first?.tags == ["anatomia", "cuore"])
    }

    @Test("A short row is treated as having empty trailing values")
    func shortRowsAreTolerated() throws {
        let outcome = try parse("basic,Ciao,Hello\n")

        #expect(outcome.rows.count == 1)
        #expect(outcome.rows.first?.tags.isEmpty == true)
    }

    // MARK: - Caps

    @Test("A file over the byte cap is rejected before decoding")
    func fileSizeCap() {
        let limits = CSVLimits(maxRows: 10, maxBytes: 8, maxFieldCharacters: 100)
        let data = Data((header + "basic,Ciao,Hello,\n").utf8)

        #expect(throws: CSVParseError.fileTooLarge(bytes: data.count, limit: 8)) {
            _ = try CSVParser.parse(data, limits: limits)
        }
    }

    @Test("Too many rows rejects the whole file")
    func rowCountCap() {
        let limits = CSVLimits(maxRows: 2, maxBytes: .max, maxFieldCharacters: 100)
        let body = String(repeating: "basic,Ciao,Hello,\n", count: 3)

        #expect(throws: CSVParseError.tooManyRows(rows: 3, limit: 2)) {
            _ = try parse(body, limits: limits)
        }
    }

    @Test("An over-long field rejects only its own row")
    func fieldLengthCap() throws {
        let limits = CSVLimits(maxRows: 10, maxBytes: .max, maxFieldCharacters: 5)
        let outcome = try parse("basic,dodici caratteri,Hello,\nbasic,ok,Hello,\n", limits: limits)

        #expect(outcome.rows.count == 1)
        #expect(outcome.rejected.first?.reason == .fieldTooLong(column: "front", characters: 16))
    }

    @Test("The rejected row keeps its raw text for the on-device preview")
    func rejectionsKeepRawText() throws {
        let outcome = try parse("sconosciuto,Ciao,Hello,tag\n")

        #expect(outcome.rejected.first?.raw == "sconosciuto,Ciao,Hello,tag")
    }
}
