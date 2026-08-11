import Foundation

/// What the mapping screen needs to know about one note type in order to propose a default.
///
/// A plain description rather than the `.apkg` reader's own type: `FlashUpDomain` must not
/// depend on `FlashUpData` (ADR-004 §4), and this keeps the proposal logic pure and unit
/// testable without an archive.
public struct NoteTypeDescriptor: Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let fieldNames: [String]
    /// The source note type is a cloze type.
    public let isCloze: Bool
    /// Anki generates one card per template; two or more means "and reversed card".
    public let templateCount: Int
    public let noteCount: Int
    /// One note's fields, used only to sharpen the proposal — for instance spotting a cloze
    /// deletion in a note type that is not formally a cloze type.
    public let sampleFields: [String]

    public init(
        id: Int64,
        name: String,
        fieldNames: [String],
        isCloze: Bool,
        templateCount: Int,
        noteCount: Int,
        sampleFields: [String] = []
    ) {
        self.id = id
        self.name = name
        self.fieldNames = fieldNames
        self.isCloze = isCloze
        self.templateCount = templateCount
        self.noteCount = noteCount
        self.sampleFields = sampleFields
    }
}

/// Proposes the mapping the user sees pre-filled. Pure, so it is testable without any UI.
public enum FieldMappingDefaults {
    public static func propose(for descriptor: NoteTypeDescriptor) -> FieldMapping {
        let target = proposedType(for: descriptor)
        let frontIndex = proposedFrontIndex(for: descriptor, target: target)
        let backIndex = proposedBackIndex(for: descriptor, target: target, frontIndex: frontIndex)

        return FieldMapping(
            noteTypeID: descriptor.id,
            noteTypeName: descriptor.name,
            fieldNames: descriptor.fieldNames,
            noteCount: descriptor.noteCount,
            target: target,
            frontIndex: frontIndex,
            backIndex: backIndex
        )
    }

    public static func propose(for descriptors: [NoteTypeDescriptor]) -> [FieldMapping] {
        descriptors.map(propose(for:))
    }

    /// A cloze type is cloze. Otherwise a note type carrying a real deletion is treated as
    /// cloze anyway — people do write `{{c1::…}}` inside a Basic note, and importing that as
    /// a basic card would put the braces on the front of the card.
    private static func proposedType(for descriptor: NoteTypeDescriptor) -> NoteType {
        if descriptor.isCloze { return .cloze }
        if descriptor.sampleFields.contains(where: ClozeParser.hasValidDeletion) { return .cloze }
        return descriptor.templateCount >= 2 ? .reversed : .basic
    }

    /// For cloze, the front must be the field that actually holds the deletion — in Anki's
    /// stock Cloze note type that is field 0, but in a custom one it need not be.
    private static func proposedFrontIndex(for descriptor: NoteTypeDescriptor, target: NoteType) -> Int {
        guard !descriptor.fieldNames.isEmpty else { return 0 }

        if target == .cloze {
            let withDeletion = descriptor.sampleFields.firstIndex(where: ClozeParser.hasValidDeletion)
            if let withDeletion, descriptor.fieldNames.indices.contains(withDeletion) {
                return withDeletion
            }
        }

        let firstNonEmpty = descriptor.sampleFields.firstIndex { !$0.trimmed.isEmpty }
        if let firstNonEmpty, descriptor.fieldNames.indices.contains(firstNonEmpty) {
            return firstNonEmpty
        }
        return 0
    }

    /// The first field after the front that carries something. For cloze the back is
    /// optional — it becomes the extra explanation — so an empty one stays `nil`.
    private static func proposedBackIndex(
        for descriptor: NoteTypeDescriptor,
        target: NoteType,
        frontIndex: Int
    ) -> Int? {
        let candidates = descriptor.fieldNames.indices.filter { $0 != frontIndex }
        guard let first = candidates.first else { return nil }

        let firstWithContent = candidates.first { index in
            guard descriptor.sampleFields.indices.contains(index) else { return false }
            return !descriptor.sampleFields[index].trimmed.isEmpty
        }

        if target == .cloze {
            // Only offer a back when the sample actually has one; a stock Cloze note with an
            // empty "Back Extra" should not arrive pre-filled with a field that is blank.
            return firstWithContent
        }
        return firstWithContent ?? first
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
