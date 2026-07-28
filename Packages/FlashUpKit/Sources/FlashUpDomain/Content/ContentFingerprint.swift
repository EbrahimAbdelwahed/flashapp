import CryptoKit
import Foundation

/// Duplicate detection (spec §A3.5).
///
/// Two notes are "the same" when their normalised content matches, so an import that
/// repeats a row the user already has is caught even if the casing or spacing differs.
public enum ContentFingerprint {
    /// Unit separator: cannot appear in normalised text, so field boundaries are
    /// unambiguous and `("ab", "c")` never collides with `("a", "bc")`.
    private static let separator = "\u{1F}"

    public static func hash(type: NoteType, front: String, back: String?) -> String {
        let payload = [type.rawValue, normalize(front), normalize(back ?? "")]
            .joined(separator: separator)
        return SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// NFC, trimmed, internal whitespace runs collapsed, casefolded.
    public static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }
}

/// Tag naming (spec §A3.6): lookup is by normalised name, display keeps the authored casing.
public enum TagNormalizer {
    public static func normalize(_ name: String) -> String {
        ContentFingerprint.normalize(name)
    }

    /// De-duplicates a list of authored tags, keeping the first spelling of each.
    public static func canonicalize(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalize(trimmed)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}
