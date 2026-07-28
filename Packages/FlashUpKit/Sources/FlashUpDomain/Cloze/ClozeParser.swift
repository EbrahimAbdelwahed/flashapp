import Foundation

/// Hand-written scanner for the Anki-compatible cloze grammar (spec §A3.4):
///
/// ```
/// deletion := "{{c" INT "::" text ( "::" hint )? "}}"
/// ```
///
/// Deliberately not a regular expression: the grammar has to take nested braces inside
/// `text` literally up to the first `}}`, and malformed input must survive as plain text
/// rather than failing the whole note.
public enum ClozeParser {
    /// Text substituted for a masked deletion that carries no hint.
    public static let maskPlaceholder = "[...]"

    private static let openToken = "{{c"
    private static let closeToken = "}}"
    private static let separator = "::"

    // MARK: - Scanning

    public static func parse(_ source: String) -> ClozeParseResult {
        var deletions: [ClozeDeletion] = []
        var issues: [ClozeParseIssue] = []
        var cursor = source.startIndex

        while let open = source.range(of: openToken, range: cursor..<source.endIndex) {
            guard let close = source.range(of: closeToken, range: open.upperBound..<source.endIndex) else {
                // Anki keeps an unclosed deletion as literal text; report it once and stop.
                issues.append(ClozeParseIssue(kind: .unclosedDeletion, range: open.lowerBound..<source.endIndex))
                break
            }

            let token = open.lowerBound..<close.upperBound
            let body = String(source[open.upperBound..<close.lowerBound])

            switch parseBody(body) {
            case let .success(group, text, hint):
                deletions.append(ClozeDeletion(group: group, text: text, hint: hint, range: token))
            case let .failure(kind):
                issues.append(ClozeParseIssue(kind: kind, range: token))
            }

            cursor = close.upperBound
        }

        return ClozeParseResult(deletions: deletions, issues: issues)
    }

    /// Distinct group numbers in `source`; each one generates a card.
    public static func groups(in source: String) -> Set<Int> {
        parse(source).groups
    }

    /// True when the text carries at least one well-formed deletion — the condition a
    /// cloze note and a cloze CSV row must satisfy.
    public static func hasValidDeletion(_ source: String) -> Bool {
        !parse(source).deletions.isEmpty
    }

    // MARK: - Rendering

    /// Study-ready text.
    ///
    /// - Parameter maskGroup: the group to hide. Deletions in that group become their hint
    ///   or `[...]`; every other deletion is replaced by its own text, so the rest of the
    ///   sentence reads normally. Passing `nil` reveals everything, which is what the
    ///   answer side and the editor preview show.
    ///
    /// Malformed deletions are left untouched, exactly as the author typed them.
    public static func render(_ source: String, maskGroup: Int?) -> String {
        let result = parse(source)
        guard !result.deletions.isEmpty else { return source }

        var rendered = ""
        var cursor = source.startIndex

        for deletion in result.deletions {
            rendered += source[cursor..<deletion.range.lowerBound]
            if let maskGroup, deletion.group == maskGroup {
                rendered += deletion.hint.map { "[\($0)]" } ?? maskPlaceholder
            } else {
                rendered += deletion.text
            }
            cursor = deletion.range.upperBound
        }
        rendered += source[cursor...]

        return rendered
    }

    // MARK: - Body grammar

    private enum BodyParse {
        case success(group: Int, text: String, hint: String?)
        case failure(ClozeParseIssue.Kind)
    }

    /// Parses what sits between `{{c` and `}}`: `INT "::" text ( "::" hint )?`.
    private static func parseBody(_ body: String) -> BodyParse {
        let digits = body.prefix(while: \.isASCIIDigit)
        guard !digits.isEmpty else { return .failure(.missingGroupNumber) }
        guard let group = Int(digits) else { return .failure(.missingGroupNumber) }
        guard group >= 1 else { return .failure(.invalidGroupNumber(group)) }

        let remainder = body[digits.endIndex...]
        guard remainder.hasPrefix(separator) else { return .failure(.missingSeparator) }

        let payload = remainder.dropFirst(separator.count)
        // Only the first `::` separates text from hint; later ones belong to the hint.
        let text: String
        let hint: String?
        if let hintSeparator = payload.range(of: separator) {
            text = String(payload[payload.startIndex..<hintSeparator.lowerBound])
            hint = String(payload[hintSeparator.upperBound...])
        } else {
            text = String(payload)
            hint = nil
        }

        guard !text.isEmpty else { return .failure(.emptyText) }

        return .success(group: group, text: text, hint: hint)
    }
}

private extension Character {
    /// Restricted to ASCII on purpose: `Character.isNumber` accepts digits from other
    /// scripts, which `Int(_:)` then rejects, turning a typo into a confusing failure.
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}
