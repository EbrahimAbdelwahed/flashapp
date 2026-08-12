import Foundation

/// Converts an Anki field, which is HTML, into the Markdown-ish plain text Flash Up stores.
///
/// Hand-written scanner in the style of `ClozeParser`, deliberately not `NSAttributedString`:
/// that lives in AppKit/UIKit, and `FlashUpDomain` has to stay pure and portable so its tests
/// run on the host without a simulator (`AGENTS.md`).
///
/// The one rule that must not be broken: **cloze syntax passes through untouched**. Anki's
/// `{{cN::text}}` is already exactly what `ClozeParser` accepts, which is why an Anki cloze
/// note needs no conversion at all.
public enum HTMLTextExtractor {
    /// Tags that end a line rather than merely ending a span.
    private static let breakingTags: Set<String> = ["br", "div", "p", "tr", "li", "blockquote", "h1", "h2", "h3"]
    private static let boldTags: Set<String> = ["b", "strong"]
    private static let italicTags: Set<String> = ["i", "em"]

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "mdash": "—", "ndash": "–", "hellip": "…", "laquo": "«", "raquo": "»",
        "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’", "times": "×", "deg": "°"
    ]

    /// What one field yielded: its text, plus the media it referenced.
    public struct Extraction: Equatable, Sendable {
        public let text: String
        /// Filenames in `<img src="…">`, in order of appearance.
        public let imageFilenames: [String]
        /// Filenames in `[sound:…]`, in order of appearance.
        public let audioFilenames: [String]

        public init(text: String, imageFilenames: [String] = [], audioFilenames: [String] = []) {
            self.text = text
            self.imageFilenames = imageFilenames
            self.audioFilenames = audioFilenames
        }

        public var mediaFilenames: [String] { imageFilenames + audioFilenames }
        public var hasMedia: Bool { !imageFilenames.isEmpty || !audioFilenames.isEmpty }
    }

    public static func extract(_ html: String) -> Extraction {
        var output = ""
        var images: [String] = []
        var audio: [String] = []

        var index = html.startIndex
        while index < html.endIndex {
            let character = html[index]

            switch character {
            case "<":
                guard let close = html[index...].firstIndex(of: ">") else {
                    // An unterminated '<' is literal text, which is how a browser reads it.
                    output.append(contentsOf: html[index...])
                    index = html.endIndex
                    continue
                }
                let tag = String(html[html.index(after: index) ..< close])
                appendTag(tag, to: &output, images: &images)
                index = html.index(after: close)

            case "&":
                let (replacement, next) = entity(in: html, from: index)
                output.append(replacement)
                index = next

            case "[":
                // `[sound:file.mp3]` is Anki's audio reference — not HTML, but it lives in
                // the same field and has to come out here too.
                if let (filename, next) = soundReference(in: html, from: index) {
                    audio.append(filename)
                    index = next
                } else {
                    output.append(character)
                    index = html.index(after: index)
                }

            default:
                output.append(character)
                index = html.index(after: index)
            }
        }

        return Extraction(text: collapse(output), imageFilenames: images, audioFilenames: audio)
    }

    /// Convenience for the common case of wanting only the text.
    public static func text(_ html: String) -> String {
        extract(html).text
    }

    // MARK: - Tags

    private static func appendTag(_ tag: String, to output: inout String, images: inout [String]) {
        let isClosing = tag.hasPrefix("/")
        let body = isClosing ? String(tag.dropFirst()) : tag
        let name = body
            .prefix { !$0.isWhitespace && $0 != "/" }
            .lowercased()

        if name == "img" {
            if let source = attribute("src", in: body) { images.append(source) }
            return
        }

        if breakingTags.contains(name) {
            // Both `<div>` and `</div>` break: Anki wraps each line in its own div, so
            // breaking only on the close tag would glue the first two lines together.
            if !output.hasSuffix("\n") { output.append("\n") }
            return
        }

        // Emphasis survives as Markdown, everything else is dropped: the tag carried
        // styling we do not keep, not content.
        if boldTags.contains(name) {
            output.append("**")
        } else if italicTags.contains(name) {
            output.append("*")
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let range = tag.range(of: "\(name)=", options: .caseInsensitive) else { return nil }
        let rest = tag[range.upperBound...]
        guard let quote = rest.first else { return nil }

        if quote == "\"" || quote == "'" {
            let afterQuote = rest.dropFirst()
            guard let end = afterQuote.firstIndex(of: quote) else { return nil }
            return String(afterQuote[..<end])
        }
        // Unquoted attribute values are legal HTML and Anki has been known to emit them.
        let value = rest.prefix { !$0.isWhitespace && $0 != ">" && $0 != "/" }
        return value.isEmpty ? nil : String(value)
    }

    // MARK: - Entities

    private static func entity(in html: String, from index: String.Index) -> (String, String.Index) {
        let afterAmpersand = html.index(after: index)
        // An entity is short; scanning the whole rest of the string for a ';' would turn a
        // stray '&' into a swallowed paragraph.
        let horizon = html.index(afterAmpersand, offsetBy: 10, limitedBy: html.endIndex) ?? html.endIndex
        guard let semicolon = html[afterAmpersand ..< horizon].firstIndex(of: ";") else {
            return ("&", afterAmpersand)
        }

        let name = String(html[afterAmpersand ..< semicolon])
        let next = html.index(after: semicolon)

        if let mapped = namedEntities[name.lowercased()] {
            return (mapped, next)
        }
        if name.hasPrefix("#"), let scalar = numericScalar(name.dropFirst()) {
            return (String(scalar), next)
        }
        // Unknown entity: keep it verbatim rather than silently deleting content.
        return ("&\(name);", next)
    }

    private static func numericScalar(_ digits: Substring) -> Unicode.Scalar? {
        let isHex = digits.first == "x" || digits.first == "X"
        let body = isHex ? digits.dropFirst() : digits
        guard let value = UInt32(body, radix: isHex ? 16 : 10) else { return nil }
        return Unicode.Scalar(value)
    }

    // MARK: - Sound references

    private static func soundReference(in html: String, from index: String.Index) -> (String, String.Index)? {
        let prefix = "[sound:"
        guard html[index...].hasPrefix(prefix) else { return nil }
        let start = html.index(index, offsetBy: prefix.count)
        guard let end = html[start...].firstIndex(of: "]") else { return nil }
        let filename = String(html[start ..< end])
        guard !filename.isEmpty else { return nil }
        return (filename, html.index(after: end))
    }

    // MARK: - Whitespace

    /// Collapses runs of spaces and blank lines, then trims. Anki fields are full of
    /// incidental whitespace from the editor that would otherwise show up on the card.
    private static func collapse(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: "\n")
            .map { line in
                line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }

        var result: [String] = []
        for line in lines {
            // At most one blank line survives, and never at the start.
            if line.isEmpty, result.last?.isEmpty ?? true { continue }
            result.append(line)
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
    }
}
