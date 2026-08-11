import Foundation

/// How one Anki note type becomes Flash Up notes.
///
/// An Anki collection can hold any number of note types with any number of fields, and no
/// heuristic gets that right every time. So this is a *decision*, presented to the user with
/// a sensible proposal already filled in (spec §A9.5) — never applied silently.
public struct FieldMapping: Identifiable, Equatable, Sendable {
    public let noteTypeID: Int64
    public let noteTypeName: String
    public let fieldNames: [String]
    /// How many notes in the file use this note type, for the mapping screen.
    public let noteCount: Int

    public var target: NoteType
    public var frontIndex: Int
    /// `nil` means "no back field", which is only valid for cloze.
    public var backIndex: Int?
    /// Lets the user drop an entire note type without dropping the import.
    public var isEnabled: Bool

    public var id: Int64 { noteTypeID }

    public init(
        noteTypeID: Int64,
        noteTypeName: String,
        fieldNames: [String],
        noteCount: Int,
        target: NoteType,
        frontIndex: Int,
        backIndex: Int?,
        isEnabled: Bool = true
    ) {
        self.noteTypeID = noteTypeID
        self.noteTypeName = noteTypeName
        self.fieldNames = fieldNames
        self.noteCount = noteCount
        self.target = target
        self.frontIndex = frontIndex
        self.backIndex = backIndex
        self.isEnabled = isEnabled
    }

    /// Field names this mapping does not use. Surfaced in the preview as ignored columns,
    /// reusing the notice the CSV importer already shows (spec §A9.1).
    public var ignoredFieldNames: [String] {
        fieldNames.enumerated()
            .filter { index, _ in index != frontIndex && index != backIndex }
            .map(\.element)
    }

    public func name(at index: Int?) -> String? {
        guard let index, fieldNames.indices.contains(index) else { return nil }
        return fieldNames[index]
    }
}
