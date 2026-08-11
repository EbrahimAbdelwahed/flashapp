import Foundation

/// How an attachment appears *inside* note text.
///
/// Media are stored outside the note as blobs, but referenced inside it as text, in
/// Markdown-compatible syntax (ADR-004 §6):
///
/// ```
/// ![](flashup-media://<uuid>)          image
/// [audio](flashup-media://<uuid>)      audio
/// ```
///
/// Keeping the reference as text is what leaves `ContentFingerprint`, CSV export and the
/// backup format working untouched: two notes carrying the same picture still deduplicate,
/// because their text is identical.
public enum MediaReference {
    public static let scheme = "flashup-media"

    public struct Found: Equatable, Sendable {
        public let id: UUID
        /// Range in the source string, so a renderer can split text around it.
        public let range: Range<String.Index>

        public init(id: UUID, range: Range<String.Index>) {
            self.id = id
            self.range = range
        }
    }

    public static func markup(for asset: MediaAsset) -> String {
        switch asset.kind {
        case .image: "![](\(scheme)://\(asset.id.uuidString))"
        case .audio: "[audio](\(scheme)://\(asset.id.uuidString))"
        }
    }

    /// Every reference in `text`, in order of appearance.
    public static func references(in text: String) -> [Found] {
        var found: [Found] = []
        var searchStart = text.startIndex
        let needle = "(\(scheme)://"

        while searchStart < text.endIndex,
              let open = text.range(of: needle, range: searchStart ..< text.endIndex) {
            guard let close = text.range(of: ")", range: open.upperBound ..< text.endIndex) else { break }

            let uuidText = String(text[open.upperBound ..< close.lowerBound])
            if let id = UUID(uuidString: uuidText) {
                // Reach back over the "![]" or "[audio]" so the whole markup is replaced.
                let start = markupStart(in: text, before: open.lowerBound)
                found.append(Found(id: id, range: start ..< close.upperBound))
            }
            searchStart = close.upperBound
        }

        return found
    }

    public static func ids(in text: String) -> [UUID] {
        references(in: text).map(\.id)
    }

    /// The text with every reference removed — for search, for CSV-facing plain text, and
    /// for the accessibility label of a card whose picture cannot be described.
    public static func stripping(_ text: String) -> String {
        var result = text
        for reference in references(in: text).reversed() {
            result.removeSubrange(reference.range)
        }
        return result
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Walks back from `(` over the label part of the Markdown link, if it is there.
    private static func markupStart(in text: String, before parenthesis: String.Index) -> String.Index {
        guard parenthesis > text.startIndex else { return parenthesis }
        var index = parenthesis

        // "…](" — step over the closing bracket of the label.
        let beforeParen = text.index(before: index)
        guard text[beforeParen] == "]" else { return parenthesis }
        index = beforeParen

        // Scan back to the matching "[".
        while index > text.startIndex {
            index = text.index(before: index)
            if text[index] == "[" {
                // "!" in front means it is an image.
                if index > text.startIndex {
                    let bang = text.index(before: index)
                    if text[bang] == "!" { return bang }
                }
                return index
            }
        }
        return parenthesis
    }
}
