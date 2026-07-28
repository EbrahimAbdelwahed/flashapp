import Foundation

/// The three note shapes Flash Up can import and create.
///
/// Raw values are the canonical CSV spelling (spec §A9.1); matching is case-insensitive
/// at the boundary, never here.
public enum NoteType: String, CaseIterable, Codable, Sendable {
    case basic
    case reversed
    case cloze

    /// Parses a CSV `type` cell. Returns `nil` for anything unrecognised.
    public init?(csvValue: String) {
        self.init(rawValue: csvValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    /// Whether a non-empty `back` is required (spec §A9.1 row validation).
    public var requiresBack: Bool {
        switch self {
        case .basic, .reversed: true
        case .cloze: false
        }
    }
}
