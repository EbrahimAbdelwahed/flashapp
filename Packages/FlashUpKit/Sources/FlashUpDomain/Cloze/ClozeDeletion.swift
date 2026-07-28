import Foundation

/// One well-formed `{{cN::text}}` or `{{cN::text::hint}}` deletion found in a note.
public struct ClozeDeletion: Equatable, Sendable {
    /// The group number `N`. Always >= 1; several deletions may share a group.
    public let group: Int
    /// The text hidden on the card for this group.
    public let text: String
    /// Optional replacement shown in place of the masked text.
    public let hint: String?
    /// Range of the whole `{{...}}` token in the source string.
    public let range: Range<String.Index>

    public init(group: Int, text: String, hint: String?, range: Range<String.Index>) {
        self.group = group
        self.text = text
        self.hint = hint
        self.range = range
    }
}

/// A malformed deletion. The offending text is left in place as literal characters
/// (Anki behaviour); the issue is surfaced in the editor and the import preview.
public struct ClozeParseIssue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A `{{c…` was opened but never closed with `}}`.
        case unclosedDeletion
        /// `{{c` was not followed by digits, e.g. `{{cX::a}}`.
        case missingGroupNumber
        /// The group number was zero or negative, e.g. `{{c0::a}}`.
        case invalidGroupNumber(Int)
        /// The `::` separator between group and text is missing, e.g. `{{c1 a}}`.
        case missingSeparator
        /// The deletion closed with no text to hide, e.g. `{{c1::}}`.
        case emptyText
    }

    public let kind: Kind
    /// Range of the offending token in the source string.
    public let range: Range<String.Index>

    public init(kind: Kind, range: Range<String.Index>) {
        self.kind = kind
        self.range = range
    }
}

/// Everything the parser found in one pass.
public struct ClozeParseResult: Equatable, Sendable {
    public let deletions: [ClozeDeletion]
    public let issues: [ClozeParseIssue]

    public init(deletions: [ClozeDeletion], issues: [ClozeParseIssue]) {
        self.deletions = deletions
        self.issues = issues
    }

    /// Distinct group numbers, each of which generates one card.
    public var groups: Set<Int> {
        Set(deletions.map(\.group))
    }
}

/// One piece of a cloze sentence as it is shown to the learner.
///
/// Splitting the sentence into segments lets the study screen keep one single sentence on
/// screen and swap only the hidden part when the card is flipped, instead of repeating the
/// whole sentence underneath.
public struct ClozeSegment: Equatable, Sendable {
    public let text: String
    /// True for the piece that is hidden before the flip and filled in after it.
    public let isAnswer: Bool

    public init(text: String, isAnswer: Bool) {
        self.text = text
        self.isAnswer = isAnswer
    }
}

/// Where a cloze card came from, so the study screen can re-render it in either state.
public struct ClozeContext: Equatable, Sendable {
    public let source: String
    public let group: Int

    public init(source: String, group: Int) {
        self.source = source
        self.group = group
    }
}
