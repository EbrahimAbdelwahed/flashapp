import Foundation

/// One Anki note type, as found in the file.
///
/// These types describe *Anki*, not Flash Up, which is why they live in `FlashUpData`:
/// translating them into Flash Up notes is `FlashUpDomain`'s job (ADR-004 §4).
public struct ApkgNoteType: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let name: String
    /// Field names in `flds` order — this is what the mapping screen offers the user.
    public let fieldNames: [String]
    /// Anki's notetype kind 1. A cloze note type maps to `NoteType.cloze`.
    public let isCloze: Bool
    /// Two or more templates is Anki's way of saying "and reversed card".
    public let templateCount: Int

    public init(id: Int64, name: String, fieldNames: [String], isCloze: Bool, templateCount: Int) {
        self.id = id
        self.name = name
        self.fieldNames = fieldNames
        self.isCloze = isCloze
        self.templateCount = templateCount
    }
}

public struct ApkgNote: Equatable, Sendable {
    public let noteTypeID: Int64
    /// From the note's first card. `nil` when the note has no card, which Anki allows for a
    /// cloze note whose text lost its deletions.
    public let deckName: String?
    /// Raw HTML, already split on the `0x1F` unit separator.
    public let fields: [String]
    public let tags: [String]

    public init(noteTypeID: Int64, deckName: String?, fields: [String], tags: [String]) {
        self.noteTypeID = noteTypeID
        self.deckName = deckName
        self.fields = fields
        self.tags = tags
    }
}

/// Everything one `.apkg` yielded, before any Flash Up decision has been made about it.
public struct ApkgCollection: Equatable, Sendable {
    public let noteTypes: [ApkgNoteType]
    public let notes: [ApkgNote]
    /// Logical media filenames present in the archive, for resolving `<img src>` and
    /// `[sound:…]` references. The bytes stay in the archive until an import commits.
    public let mediaFilenames: Set<String>

    public init(noteTypes: [ApkgNoteType], notes: [ApkgNote], mediaFilenames: Set<String>) {
        self.noteTypes = noteTypes
        self.notes = notes
        self.mediaFilenames = mediaFilenames
    }

    public func noteType(id: Int64) -> ApkgNoteType? {
        noteTypes.first { $0.id == id }
    }

    /// Note types that at least one note actually uses. An Anki collection ships every
    /// stock note type whether or not the deck uses it, and offering the user a mapping
    /// screen full of empty note types would be noise.
    public var usedNoteTypes: [ApkgNoteType] {
        let used = Set(notes.map(\.noteTypeID))
        return noteTypes.filter { used.contains($0.id) }
    }

    public func noteCount(forNoteType id: Int64) -> Int {
        notes.filter { $0.noteTypeID == id }.count
    }
}
