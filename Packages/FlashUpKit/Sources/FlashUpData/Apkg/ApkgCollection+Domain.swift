import FlashUpDomain
import Foundation

/// The seam between the archive and the domain.
///
/// `FlashUpDomain` must not know what an `.apkg` is (ADR-004 §4), so the translation into
/// the pure types it does understand happens here, in one place.
extension ApkgCollection {
    /// One descriptor per note type that some note actually uses, carrying a sample note so
    /// `FieldMappingDefaults` can propose a mapping that fits the real content.
    public func noteTypeDescriptors() -> [NoteTypeDescriptor] {
        usedNoteTypes.map { noteType in
            NoteTypeDescriptor(
                id: noteType.id,
                name: noteType.name,
                fieldNames: noteType.fieldNames,
                isCloze: noteType.isCloze,
                templateCount: noteType.templateCount,
                noteCount: noteCount(forNoteType: noteType.id),
                sampleFields: sampleFields(forNoteType: noteType.id)
            )
        }
    }

    public func sourceNotes() -> [SourceNote] {
        notes.map {
            SourceNote(noteTypeID: $0.noteTypeID, fields: $0.fields, tags: $0.tags)
        }
    }

    /// The first note of this type that has any content at all. A note type's first note can
    /// be a half-finished one, and proposing a mapping from empty fields would put the front
    /// on whichever field happened to be filled in that one.
    private func sampleFields(forNoteType id: Int64) -> [String] {
        let candidates = notes.filter { $0.noteTypeID == id }
        let populated = candidates.first { note in
            note.fields.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return (populated ?? candidates.first)?.fields ?? []
    }
}
