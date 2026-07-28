import Foundation

/// RFC 4180 tokenizer: comma separator, `"` quoting, `""` escape, CRLF or LF line
/// endings, and newlines allowed inside quoted fields.
///
/// Split from `CSVParser` so the dialect can be tested independently of Flash Up's
/// column and row rules.
enum CSVDocument {
    /// One record plus the 1-based physical line it starts on. The two differ as soon as a
    /// quoted field contains a newline, and the import preview reports physical lines
    /// because that is what the user sees in their file.
    struct Record: Equatable {
        let line: Int
        let fields: [String]
    }

    /// Splits `text` into records of fields. An unterminated quote is tolerated: the
    /// field simply runs to the end of the input, which keeps a truncated file
    /// importable up to its last complete row.
    static func records(in text: String) -> [Record] {
        var scanner = Scanner()
        for character in text {
            scanner.consume(character)
        }
        return scanner.finish()
    }

    /// Character-at-a-time state machine.
    ///
    /// Swift treats CRLF as a single grapheme cluster, so CR, LF and CRLF all arrive as
    /// one `Character` and the scanner never needs to look ahead.
    private struct Scanner {
        private var records: [Record] = []
        private var fields: [String] = []
        private var field = ""
        private var insideQuotes = false
        private var pendingQuote = false
        private var currentLine = 1
        private var recordStartLine = 1

        mutating func consume(_ character: Character) {
            if pendingQuote {
                pendingQuote = false
                if character == "\"" {
                    field.append("\"")   // "" is an escaped quote
                    return
                }
                insideQuotes = false
            }

            if insideQuotes {
                consumeQuoted(character)
            } else {
                consumeUnquoted(character)
            }
        }

        mutating func finish() -> [Record] {
            // A file that does not end with a newline still has a final record.
            if !field.isEmpty || !fields.isEmpty {
                endRecord()
            }
            return records
        }

        private mutating func consumeQuoted(_ character: Character) {
            if character == "\"" {
                pendingQuote = true
            } else {
                if character.isNewline { currentLine += 1 }
                field.append(character)
            }
        }

        private mutating func consumeUnquoted(_ character: Character) {
            switch character {
            case "\"":
                insideQuotes = true
            case ",":
                endField()
            default:
                if character.isNewline {
                    currentLine += 1
                    endRecord()
                } else {
                    field.append(character)
                }
            }
        }

        private mutating func endField() {
            fields.append(field)
            field = ""
        }

        private mutating func endRecord() {
            endField()
            records.append(Record(line: recordStartLine, fields: fields))
            fields = []
            recordStartLine = currentLine
        }
    }
}
