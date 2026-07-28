import Foundation

/// Writes the canonical CSV (spec §A9.1) so an export can be re-imported without loss.
public enum CSVWriter {
    public static let header = "type,front,back,tags"

    public static func csv(for notes: [Note]) -> String {
        ([header] + notes.map(row)).joined(separator: "\n") + "\n"
    }

    public static func data(for notes: [Note]) -> Data {
        Data(csv(for: notes).utf8)
    }

    private static func row(_ note: Note) -> String {
        [
            note.type.rawValue,
            note.front,
            note.back ?? "",
            note.tags.joined(separator: ";")
        ]
        .map(escape)
        .joined(separator: ",")
    }

    /// Quotes a field only when it needs it, and doubles any embedded quote.
    private static func escape(_ field: String) -> String {
        let needsQuoting = field.contains(",")
            || field.contains("\"")
            || field.contains(where: \.isNewline)
        guard needsQuoting else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
