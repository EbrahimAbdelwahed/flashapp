import Foundation
import Testing
@testable import FlashUpDomain

@Suite("Field mapping defaults")
struct FieldMappingDefaultsTests {
    private func descriptor(
        isCloze: Bool = false,
        templates: Int = 1,
        fields: [String] = ["Front", "Back"],
        sample: [String] = ["domanda", "risposta"]
    ) -> NoteTypeDescriptor {
        NoteTypeDescriptor(
            id: 1, name: "T", fieldNames: fields, isCloze: isCloze,
            templateCount: templates, noteCount: 3, sampleFields: sample
        )
    }

    @Test("A one-template note type is proposed as basic")
    func basic() {
        let mapping = FieldMappingDefaults.propose(for: descriptor())
        #expect(mapping.target == .basic)
        #expect(mapping.frontIndex == 0)
        #expect(mapping.backIndex == 1)
        #expect(mapping.isEnabled)
    }

    /// Two templates is exactly how Anki expresses "and reversed card".
    @Test("A two-template note type is proposed as reversed")
    func reversed() {
        #expect(FieldMappingDefaults.propose(for: descriptor(templates: 2)).target == .reversed)
    }

    @Test("A cloze note type is proposed as cloze")
    func cloze() {
        let mapping = FieldMappingDefaults.propose(
            for: descriptor(isCloze: true, fields: ["Text", "Back Extra"],
                            sample: ["Il {{c1::sole}} splende", ""])
        )
        #expect(mapping.target == .cloze)
        #expect(mapping.frontIndex == 0)
    }

    /// People write `{{c1::…}}` inside a Basic note. Importing that as basic would put the
    /// braces on the front of the card, which is worse than guessing cloze.
    @Test("A deletion in a non-cloze note type still proposes cloze")
    func clozeByContent() {
        let mapping = FieldMappingDefaults.propose(
            for: descriptor(sample: ["La {{c1::mitosi}} produce due cellule", ""])
        )
        #expect(mapping.target == .cloze)
    }

    @Test("The cloze front is the field that actually carries the deletion")
    func clozeFrontFollowsTheDeletion() {
        let mapping = FieldMappingDefaults.propose(
            for: descriptor(isCloze: true, fields: ["Titolo", "Testo"],
                            sample: ["Biologia", "La {{c1::mitosi}} avviene"])
        )
        #expect(mapping.frontIndex == 1)
    }

    @Test("A cloze with an empty second field is proposed without a back")
    func clozeWithoutBack() {
        let mapping = FieldMappingDefaults.propose(
            for: descriptor(isCloze: true, fields: ["Text", "Back Extra"],
                            sample: ["Il {{c1::sole}}", "   "])
        )
        #expect(mapping.backIndex == nil)
    }

    @Test("With five fields the first two are proposed and the rest reported as ignored")
    func fiveFields() {
        let mapping = FieldMappingDefaults.propose(
            for: descriptor(
                fields: ["Termine", "Definizione", "Esempio", "Fonte", "Note"],
                sample: ["Entropia", "Disordine", "Ghiaccio", "Cap. 2", "Ripassare"]
            )
        )
        #expect(mapping.frontIndex == 0)
        #expect(mapping.backIndex == 1)
        #expect(mapping.ignoredFieldNames == ["Esempio", "Fonte", "Note"])
    }

    @Test("An empty leading field does not become the front")
    func skipsEmptyLeadingField() {
        let mapping = FieldMappingDefaults.propose(
            for: descriptor(fields: ["Vuoto", "Domanda", "Risposta"], sample: ["", "che ora è?", "le tre"])
        )
        #expect(mapping.frontIndex == 1)
        #expect(mapping.backIndex == 2)
    }

    @Test("A note type with no fields does not crash the proposal")
    func noFields() {
        let mapping = FieldMappingDefaults.propose(for: descriptor(fields: [], sample: []))
        #expect(mapping.frontIndex == 0)
        #expect(mapping.backIndex == nil)
    }
}

@Suite("Anki notes to import rows")
struct ApkgRowMapperTests {
    private let basicMapping = FieldMapping(
        noteTypeID: 1, noteTypeName: "Basic", fieldNames: ["Front", "Back"],
        noteCount: 1, target: .basic, frontIndex: 0, backIndex: 1
    )

    private func note(_ fields: [String], tags: [String] = [], type: Int64 = 1) -> SourceNote {
        SourceNote(noteTypeID: type, fields: fields, tags: tags)
    }

    @Test("A basic note becomes a row with its HTML converted")
    func basicRow() {
        let outcome = ApkgRowMapper.map(
            notes: [note(["Cos'è il <b>DNA</b>?", "<div>Acido</div><div>desossiribonucleico</div>"],
                         tags: ["biologia"])],
            mappings: [basicMapping]
        )
        #expect(outcome.rows.count == 1)
        #expect(outcome.rows.first?.front == "Cos'è il **DNA**?")
        #expect(outcome.rows.first?.back == "Acido\ndesossiribonucleico")
        #expect(outcome.rows.first?.tags == ["biologia"])
    }

    @Test("Rows are numbered from one, so the preview can point at a note")
    func lineNumbers() {
        let outcome = ApkgRowMapper.map(
            notes: [note(["a", "1"]), note(["b", "2"]), note(["c", "3"])],
            mappings: [basicMapping]
        )
        #expect(outcome.rows.map(\.line) == [1, 2, 3])
    }

    @Test("A note whose front is empty is refused, not imported blank")
    func emptyFront() {
        let outcome = ApkgRowMapper.map(notes: [note(["   ", "risposta"])], mappings: [basicMapping])
        #expect(outcome.rows.isEmpty)
        #expect(outcome.rejected.first?.reason == .emptyFront)
    }

    @Test("A basic note with no back is refused, exactly as in CSV")
    func missingBack() {
        let outcome = ApkgRowMapper.map(notes: [note(["domanda", ""])], mappings: [basicMapping])
        #expect(outcome.rejected.first?.reason == .missingBack(.basic))
    }

    @Test("A cloze mapping over text with no deletion is refused")
    func clozeWithoutDeletion() {
        let mapping = FieldMapping(
            noteTypeID: 1, noteTypeName: "Cloze", fieldNames: ["Text", "Extra"],
            noteCount: 1, target: .cloze, frontIndex: 0, backIndex: nil
        )
        let outcome = ApkgRowMapper.map(notes: [note(["nessuna cancellazione"])], mappings: [mapping])
        #expect(outcome.rejected.first?.reason == .noClozeDeletion)
    }

    @Test("A cloze note keeps its deletions and needs no back")
    func clozeRow() {
        let mapping = FieldMapping(
            noteTypeID: 1, noteTypeName: "Cloze", fieldNames: ["Text", "Extra"],
            noteCount: 1, target: .cloze, frontIndex: 0, backIndex: nil
        )
        let outcome = ApkgRowMapper.map(
            notes: [note(["La {{c1::glicolisi}} avviene nel {{c2::citoplasma}}"])],
            mappings: [mapping]
        )
        #expect(outcome.rows.count == 1)
        #expect(outcome.rows.first?.back == nil)
        #expect(ClozeParser.groups(in: outcome.rows.first?.front ?? "") == [1, 2])
    }

    /// Until media are carried, a note that depends on one is refused with a visible reason
    /// rather than imported as a card with a hole in it.
    @Test("A note referencing an attachment is refused, naming the file")
    func mediaRefused() {
        let outcome = ApkgRowMapper.map(
            notes: [note(["Che colore? <img src=\"rossa.png\">", "Rosso"])],
            mappings: [basicMapping]
        )
        #expect(outcome.rejected.first?.reason == .unsupportedMedia("rossa.png"))
    }

    @Test("The user's choice of front and back field is honoured")
    func customMapping() {
        let mapping = FieldMapping(
            noteTypeID: 1, noteTypeName: "Cinque", fieldNames: ["A", "B", "C"],
            noteCount: 1, target: .basic, frontIndex: 2, backIndex: 0
        )
        let outcome = ApkgRowMapper.map(notes: [note(["primo", "secondo", "terzo"])], mappings: [mapping])
        #expect(outcome.rows.first?.front == "terzo")
        #expect(outcome.rows.first?.back == "primo")
    }

    @Test("A disabled mapping drops its notes without rejecting them")
    func disabledMapping() {
        var mapping = basicMapping
        mapping.isEnabled = false
        let outcome = ApkgRowMapper.map(notes: [note(["a", "b"])], mappings: [mapping])
        #expect(outcome.rows.isEmpty)
        #expect(outcome.rejected.isEmpty)
    }

    @Test("A note whose type has no mapping is skipped silently")
    func unmappedNoteType() {
        let outcome = ApkgRowMapper.map(notes: [note(["a", "b"], type: 99)], mappings: [basicMapping])
        #expect(outcome.rows.isEmpty)
        #expect(outcome.rejected.isEmpty)
    }

    @Test("Unused fields are reported as ignored columns, reusing the CSV notice")
    func ignoredColumns() {
        let mapping = FieldMapping(
            noteTypeID: 1, noteTypeName: "Cinque", fieldNames: ["Termine", "Definizione", "Fonte"],
            noteCount: 1, target: .basic, frontIndex: 0, backIndex: 1
        )
        let outcome = ApkgRowMapper.map(notes: [note(["a", "b", "c"])], mappings: [mapping])
        #expect(outcome.ignoredColumns == ["Fonte"])
    }

    @Test("A field past the length cap is refused")
    func fieldTooLong() {
        let limits = CSVLimits(maxRows: 100, maxBytes: 1 << 20, maxFieldCharacters: 10)
        let outcome = ApkgRowMapper.map(
            notes: [note([String(repeating: "x", count: 50), "b"])],
            mappings: [basicMapping],
            limits: limits
        )
        #expect(outcome.rejected.first?.reason == .fieldTooLong(column: "front", characters: 50))
    }

    /// The output is a `CSVParseOutcome` so that `ImportPlanner`, duplicate detection, commit
    /// and undo are shared verbatim with the CSV importer (ADR-004 §5).
    @Test("The mapper's output feeds the existing import planner unchanged")
    func feedsThePlanner() {
        let outcome = ApkgRowMapper.map(notes: [note(["domanda", "risposta"])], mappings: [basicMapping])
        let plan = ImportPlanner.plan(outcome, existingHashes: [:])
        #expect(plan.rowsToImport.count == 1)
        #expect(plan.duplicates.isEmpty)
    }

    @Test("A note already in the deck is flagged as a duplicate, not imported twice")
    func duplicateDetection() {
        let outcome = ApkgRowMapper.map(notes: [note(["domanda", "risposta"])], mappings: [basicMapping])
        let hash = ContentFingerprint.hash(type: .basic, front: "domanda", back: "risposta")
        let plan = ImportPlanner.plan(outcome, existingHashes: [UUID(): hash])
        #expect(plan.duplicates.count == 1)
        #expect(plan.rowsToImport.isEmpty)
    }
}
